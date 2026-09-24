import Foundation

struct RoutedChatReply: Sendable {
    let text: String
    let actualModelID: String
    let inputTokens: Int?
    let outputTokens: Int?
    let modelMatched: Bool
}

struct RoutedModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let source: String
}

/// The only decision call in this service targets the loopback Gateway. The
/// Gateway plugin refuses to evaluate unless its selected provider is ONNX.
struct RoutedChatService: Sendable {
    private let decisionModel = "onnx/gliner2.5-small-v1"

    static func supportsChatModel(_ id: String) -> Bool {
        [.cloud, .oauth].contains(RuntimeSnapshotResolver.route(for: id)) && id != "openrouter/auto"
    }

    func checkPrerequisites() throws {
        let version = try command(["--version"], timeout: 20).output
        let numbers = version.split(whereSeparator: { !$0.isNumber && $0 != "." })
            .first(where: { $0.contains(".") })?
            .split(separator: ".").compactMap { Int($0) } ?? []
        guard numbers.count >= 3, Array(numbers.prefix(3)).lexicographicallyPrecedes([2026, 9, 6]) == false else {
            throw RoutedChatError.requiresOpenClawUpdate
        }
        _ = try localGatewayPort()
    }

    func setup(report: @Sendable (String) -> Void) throws {
        try checkPrerequisites()
        guard let config = InstallerEngine().readOpenClawConfig() else {
            throw RoutedChatError.commandFailed("LocalClaw could not read the selected OpenClaw configuration. Router setup was not started.")
        }
        let entries = (config["agents"] as? [String: Any])?["entries"] as? [String: Any]
        let routerEntry = entries?["localclaw-router"] as? [String: Any]
        let existing = (routerEntry?["decisionModel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty || existing == decisionModel else {
            throw RoutedChatError.commandFailed("The localclaw-router agent already has another decision model (\(existing)). LocalClaw left that choice unchanged.")
        }

        report("Installing the local ONNX decision provider…")
        let onnxInspection = try? command(["plugins", "inspect", "onnx", "--json"], timeout: 30)
        let onnxPlugin = onnxInspection.flatMap { InstallerEngine.firstJSONObject(in: $0.output)?["plugin"] as? [String: Any] }
        if (onnxPlugin?["packageVersion"] as? String) != "2026.9.6" {
            _ = try command(["plugins", "install", "@openclaw/onnx@2026.9.6", "--pin"], timeout: 300)
        }
        _ = try command(["plugins", "enable", "onnx"], timeout: 60)

        report("Downloading and verifying the local model…")
        _ = try command(["onnx", "download", "gliner2.5-small-v1"], timeout: 900)
        _ = try command(["onnx", "verify", "gliner2.5-small-v1"], timeout: 180)
        _ = try command(["onnx", "probe", "gliner2.5-small-v1"], timeout: 180)

        if existing.isEmpty {
            report("Selecting ONNX for the beta router only…")
            _ = try command(["config", "set", "agents.entries.localclaw-router.decisionModel", decisionModel], timeout: 60)
        }

        report("Installing the LocalClaw decision bridge…")
        let staged = try stageBridgePlugin()
        defer { try? FileManager.default.removeItem(at: staged) }
        _ = try command(["plugins", "install", staged.path, "--force", "--accept-capabilities"], timeout: 180)
        _ = try command(["plugins", "enable", "localclaw-router"], timeout: 60)
        report("Loading both local plugins in the running Gateway…")
        _ = try command(["plugins", "reload", "onnx", "localclaw-router", "--accept-capabilities", "--json"], timeout: 120)

        report("Testing a local decision…")
        let smoke = try classify(prompt: "Translate this short sentence into French.", prior: nil)
        guard smoke.status == "ok" else {
            throw RoutedChatError.routerUnavailable(smoke.reason ?? "smoke-test-failed")
        }
    }

    func classify(prompt: String, prior: String?) throws -> RoutedDecision {
        try checkPrerequisites()
        let port = try localGatewayPort()
        var params: [String: String] = ["prompt": prompt]
        if let prior, !prior.isEmpty { params["prior"] = prior }
        let json = try JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])
        guard let argument = String(data: json, encoding: .utf8) else {
            throw RoutedChatError.routerUnavailable("invalid-input")
        }
        let result = try command([
            "gateway", "call", "localclaw.router.classify",
            "--port", String(port), "--params", argument,
            "--timeout", "30000", "--json"
        ], timeout: 40)
        guard let object = InstallerEngine.firstJSONObject(in: result.output) else {
            throw RoutedChatError.routerUnavailable("invalid-gateway-response")
        }
        let payload = (object["result"] as? [String: Any]) ?? object
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(RoutedDecision.self, from: payloadData)
    }

    func availableChatModels() throws -> [RoutedModelOption] {
        let engine = InstallerEngine()
        guard let agentID = engine.resolvedChatAgentID() else { throw RoutedChatError.noAgent }
        let output = try command(["models", "list", "--agent", agentID, "--json"], timeout: 45).output
        guard let object = InstallerEngine.firstJSONObject(in: output),
              let models = object["models"] as? [[String: Any]] else {
            throw RoutedChatError.commandFailed("OpenClaw did not return its available model list.")
        }
        var seen = Set<String>()
        return models.compactMap { row -> RoutedModelOption? in
            guard let id = row["key"] as? String, id.contains("/"),
                  Self.supportsChatModel(id),
                  (row["available"] as? Bool) != false,
                  seen.insert(id).inserted else { return nil }
            let source = id.hasPrefix("openrouter/") ? "OpenRouter" : "Cloud / OAuth"
            return RoutedModelOption(id: id, name: (row["name"] as? String) ?? id, source: source)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func send(prompt: String, modelID: String, sessionID: String) throws -> RoutedChatReply {
        let engine = InstallerEngine()
        guard let agentID = engine.resolvedChatAgentID() else { throw RoutedChatError.noAgent }
        try verifyAvailable(modelID: modelID, agentID: agentID)

        let messageFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("localclaw-routed-chat-\(UUID().uuidString).txt")
        try Data(prompt.utf8).write(to: messageFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: messageFile.path)
        defer { try? FileManager.default.removeItem(at: messageFile) }

        let run = try command([
            "agent", "--agent", agentID, "--session-id", sessionID,
            "--message-file", messageFile.path, "--model", modelID,
            "--json", "--timeout", "600"
        ], timeout: 650)
        let normalized = InstallerViewModel.normalizedAgentResult((run.exitCode, run.output))
        guard normalized.0 == 0 else {
            throw RoutedChatError.commandFailed("OpenClaw could not complete this routed turn. It was not retried automatically. \(SecretRedactor.redactConfigText(String(normalized.1.suffix(1_000))))")
        }
        guard let actual = InstallerViewModel.extractAgentRuntimeModel(from: normalized.1),
              !actual.isEmpty else { throw RoutedChatError.unexpectedReply }
        let text = InstallerViewModel.extractAgentReply(from: normalized.1)
        guard !text.isEmpty,
              text != normalized.1.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw RoutedChatError.unexpectedReply
        }
        let usage = InstallerViewModel.extractAgentUsage(from: normalized.1)
        return RoutedChatReply(
            text: text,
            actualModelID: actual,
            inputTokens: usage.input,
            outputTokens: usage.output,
            modelMatched: actual == modelID
        )
    }

    private func verifyAvailable(modelID: String, agentID: String) throws {
        guard Self.supportsChatModel(modelID) else {
            throw RoutedChatError.commandFailed("This beta routes to explicitly chosen cloud or OAuth models only. No message was sent.")
        }
        let output = try command(["models", "list", "--agent", agentID, "--json"], timeout: 45).output
        guard let object = InstallerEngine.firstJSONObject(in: output),
              let models = object["models"] as? [[String: Any]],
              models.contains(where: { ($0["key"] as? String) == modelID && ($0["available"] as? Bool) != false }) else {
            throw RoutedChatError.commandFailed("The selected model is not currently available to this OpenClaw agent. No message was sent.")
        }
    }

    private func localGatewayPort() throws -> Int {
        let config = InstallerEngine().readOpenClawConfig() ?? [:]
        let gateway = config["gateway"] as? [String: Any] ?? [:]
        if (gateway["mode"] as? String)?.lowercased() == "remote" {
            throw RoutedChatError.gatewayNotLocal
        }
        if let runtime = try OpenClawRuntimeInstallation.managed(), let port = runtime.port {
            return port
        }
        let port = (gateway["port"] as? NSNumber)?.intValue ?? 18_789
        guard (1...65_535).contains(port) else { throw RoutedChatError.gatewayNotLocal }
        return port
    }

    private func stageBridgePlugin() throws -> URL {
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("localclaw-router-plugin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        do {
            for (source, target) in [
                ("localclaw-router-index.mjs", "index.mjs"),
                ("localclaw-router-plugin.json", "openclaw.plugin.json"),
                ("localclaw-router-package.json", "package.json")
            ] {
                guard let url = GoalControllerResourceLocator.locate(scriptName: source) else {
                    throw RoutedChatError.commandFailed("The LocalClaw router resource \(source) is missing from this app build.")
                }
                try FileManager.default.copyItem(at: url, to: staged.appendingPathComponent(target))
            }
            return staged
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    private func command(_ arguments: [String], timeout: TimeInterval) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        var environment = ProcessInfo.processInfo.environment
        let pathPrefix = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:\(NSHomeDirectory())/.npm-global/bin:\(NSHomeDirectory())/.local/bin"
        environment["PATH"] = pathPrefix + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        try OpenClawRuntimeInstallation.configureCLIProcess(process, arguments: arguments, environment: environment)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let timeoutFlag = CommandTimeoutFlag()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            timeoutFlag.mark()
            if process.isRunning {
                process.terminate()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        timer.resume()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()

        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if timeoutFlag.didTimeout {
            throw RoutedChatError.commandFailed("The local router command timed out. Check its status before retrying.")
        }
        guard process.terminationStatus == 0 else {
            throw RoutedChatError.commandFailed("Local router command failed: \(SecretRedactor.redactConfigText(String(output.suffix(1_000))))")
        }
        return (process.terminationStatus, output)
    }
}

private final class CommandTimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var didTimeout: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func mark() { lock.lock(); value = true; lock.unlock() }
}
