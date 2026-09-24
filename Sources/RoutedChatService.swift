import Foundation

struct RoutedChatReply: Sendable {
    let text: String
    let actualModelID: String
    let inputTokens: Int?
    let outputTokens: Int?
    let modelMatched: Bool
}

enum RoutedChatRecovery: Sendable {
    case recovered(RoutedChatReply)
    case running
    case unmatched
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
    static let recommendedGPT6 = RoutedModelMapping(
        economical: "openai/gpt-6-luna",
        reasoning: "openai/gpt-6-astra",
        coding: "openai/gpt-6-sol"
    )

    static func isMissingRouterMethod(_ output: String) -> Bool {
        output.range(of: "unknown method: localclaw.router.classify", options: .caseInsensitive) != nil
    }

    static func canRetryPluginReload(_ output: String) -> Bool {
        output.contains("still has active retained work") && output.contains("replacement not applied")
    }

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
        // `onnx download` verifies the pinned sizes and hashes; the separate
        // verify command would re-read the same 300 MB before the smoke probe.
        _ = try command(["onnx", "probe", "gliner2.5-small-v1"], timeout: 180)

        if existing.isEmpty {
            report("Selecting ONNX for the beta router only…")
            do {
                _ = try command(["config", "set", "agents.entries.localclaw-router.decisionModel", decisionModel], timeout: 60)
            } catch RoutedChatError.commandTimedOut {
                // OpenClaw 2026.9.6 can save this new agent and then linger
                // while resolving its inherited chat model. Verify the exact
                // write instead of making the user repeat a completed step.
                report("OpenClaw is slow to finish agent setup; checking the saved configuration…")
            }
            let updated = InstallerEngine().readOpenClawConfig()
            let agent = ((updated?["agents"] as? [String: Any])?["entries"] as? [String: Any])?["localclaw-router"] as? [String: Any]
            guard agent?["decisionModel"] as? String == decisionModel else {
                throw RoutedChatError.commandFailed("OpenClaw did not save the local decision model. Router setup stopped before loading the bridge.")
            }
            let validation = try command(["config", "validate", "--json"], timeout: 60)
            guard InstallerEngine.firstJSONObject(in: validation.output)?["valid"] as? Bool == true else {
                throw RoutedChatError.commandFailed("OpenClaw did not validate the saved router configuration. Router setup stopped before loading the bridge.")
            }
        }

        report("Installing the LocalClaw decision bridge…")
        let staged = try stageBridgePlugin()
        defer { try? FileManager.default.removeItem(at: staged) }
        _ = try command(["plugins", "install", staged.path, "--force", "--accept-capabilities"], timeout: 180)
        _ = try command(["plugins", "enable", "localclaw-router"], timeout: 60)
        report("Loading both local plugins in the running Gateway…")
        try reloadRouterPlugins(report: report)

        report("Testing a local decision…")
        let smoke = try classify(prompt: "Translate this short sentence into French.", prior: nil)
        guard smoke.status == "ok" else {
            throw RoutedChatError.routerUnavailable(smoke.reason ?? "smoke-test-failed")
        }
    }

    func classify(prompt: String, prior: String?) throws -> RoutedDecision {
        // Setup validates the OpenClaw version. Every decision still checks
        // the selected Gateway is local, and the bridge verifies ONNX itself.
        // Starting `openclaw --version` for every draft adds avoidable latency.
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

    /// Add three exact OpenAI refs to an existing OpenClaw model policy. The
    /// global default and all existing allowed models remain unchanged.
    func enableGPT6Options() throws {
        let engine = InstallerEngine()
        guard let agentID = engine.resolvedChatAgentID() else { throw RoutedChatError.noAgent }
        let desired = Self.recommendedGPT6.modelIDs
        let catalog = try command(["models", "list", "--all", "--agent", agentID,
                                   "--provider", "openai", "--json"], timeout: 45).output
        guard let catalogObject = InstallerEngine.firstJSONObject(in: catalog),
              let rows = catalogObject["models"] as? [[String: Any]],
              desired.allSatisfy({ id in rows.contains(where: {
                  ($0["key"] as? String) == id && ($0["available"] as? Bool) != false
              }) }) else {
            throw RoutedChatError.commandFailed("OpenClaw does not list all three GPT-6 models for the connected OpenAI route. No model policy was changed.")
        }
        let configURL = try OpenClawRuntimeInstallation.selectedConfig()
        guard let config = engine.readOpenClawConfig(),
              let agents = config["agents"] as? [String: Any],
              let defaults = agents["defaults"] as? [String: Any] else {
            throw RoutedChatError.commandFailed("OpenClaw's model policy could not be read. No setting was changed.")
        }
        let entries = agents["entries"] as? [String: Any] ?? [:]
        let selectedAgent = entries[agentID] as? [String: Any] ?? [:]
        let agentPolicy = selectedAgent["modelPolicy"] as? [String: Any]
        let defaultPolicy = defaults["modelPolicy"] as? [String: Any]
        let hasAgentPolicy = (agentPolicy?["allow"] as? [String])?.isEmpty == false
        let path = hasAgentPolicy ? "agents.entries.\(agentID).modelPolicy.allow"
                                  : "agents.defaults.modelPolicy.allow"
        let allowed = (hasAgentPolicy ? agentPolicy : defaultPolicy)?["allow"] as? [String] ?? []
        guard !allowed.isEmpty else {
            throw RoutedChatError.commandFailed("This agent has no explicit model allowlist to extend. Refresh the model list instead.")
        }
        let additions = desired.filter { !allowed.contains($0) }
        guard !additions.isEmpty else { return }
        let updated = allowed + additions
        func json(_ value: [String]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        }

        let backupDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalClaw/runtime-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let backup = backupDir.appendingPathComponent("openclaw-config-before-routed-gpt6-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: configURL, to: backup)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)

        _ = try command(["config", "set", path, try json(updated), "--strict-json",
                         "--expect-current-json", try json(allowed)], timeout: 120)
        let validation = try command(["config", "validate", "--json"], timeout: 60).output
        guard InstallerEngine.firstJSONObject(in: validation)?["valid"] as? Bool == true else {
            throw RoutedChatError.commandFailed("The GPT-6 model policy was saved but could not be validated. Restore the small configuration backup before using it: \(backup.path)")
        }
        for attempt in 0..<5 {
            if let models = try? availableChatModels(), desired.allSatisfy({ id in models.contains(where: { $0.id == id }) }) {
                return
            }
            if attempt < 4 { Thread.sleep(forTimeInterval: [1.0, 2.0, 3.0, 5.0][attempt]) }
        }
        throw RoutedChatError.commandFailed("GPT-6 was added to OpenClaw's model policy. Its catalog is still refreshing; click Refresh in Routed Chat shortly.")
    }

    func send(prompt: String, modelID: String, sessionID: String) throws -> RoutedChatReply {
        let engine = InstallerEngine()
        guard let agentID = engine.resolvedChatAgentID() else { throw RoutedChatError.noAgent }
        guard Self.supportsChatModel(modelID) else {
            throw RoutedChatError.commandFailed("This beta routes to explicitly chosen cloud or OAuth models only. No message was sent.")
        }

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

    /// A CLI turn may finish in the Gateway after LocalClaw's window closes.
    /// Read only the exact routed session; never replay its prompt on recovery.
    func recoverPendingReply(sessionID: String, createdAt: Date,
                             expectedModelID: String) throws -> RoutedChatRecovery {
        let prefix = "localclaw-routed-"
        guard sessionID.hasPrefix(prefix),
              UUID(uuidString: String(sessionID.dropFirst(prefix.count))) != nil else {
            return .unmatched
        }
        let engine = InstallerEngine()
        guard let agentID = engine.resolvedChatAgentID() else { throw RoutedChatError.noAgent }
        let sessionKey = "agent:\(agentID):explicit:\(sessionID.lowercased())"
        let params: [String: Any] = ["sessionKey": sessionKey, "agentId": agentID, "limit": 2]
        let data = try JSONSerialization.data(withJSONObject: params)
        let output = try command(["gateway", "call", "chat.history", "--params",
                                  String(decoding: data, as: UTF8.self), "--json", "--timeout", "15000"],
                                 timeout: 20).output
        guard let object = InstallerEngine.firstJSONObject(in: output) else {
            throw RoutedChatError.commandFailed("OpenClaw did not return the routed conversation history.")
        }
        return Self.recovery(from: object, sessionKey: sessionKey,
                             createdAt: createdAt, expectedModelID: expectedModelID)
    }

    static func recovery(from response: [String: Any], sessionKey: String, createdAt: Date,
                         expectedModelID: String) -> RoutedChatRecovery {
        guard let session = response["sessionInfo"] as? [String: Any],
              (session["key"] as? String)?.lowercased() == sessionKey.lowercased() else {
            return .unmatched
        }
        if session["hasActiveRun"] as? Bool == true { return .running }
        guard session["status"] as? String == "done",
              let lastRunID = session["lastRunId"] as? String,
              let messages = response["messages"] as? [[String: Any]], messages.count >= 2 else {
            return .unmatched
        }
        let user = messages[messages.count - 2]
        let assistant = messages[messages.count - 1]
        guard user["role"] as? String == "user", assistant["role"] as? String == "assistant",
              let userMs = (user["timestamp"] as? NSNumber)?.doubleValue,
              let assistantMs = (assistant["timestamp"] as? NSNumber)?.doubleValue,
              abs(userMs - createdAt.timeIntervalSince1970 * 1_000) <= 45_000,
              assistantMs >= userMs,
              let metadata = assistant["__openclaw"] as? [String: Any],
              metadata["runId"] as? String == lastRunID,
              let provider = assistant["provider"] as? String, !provider.isEmpty,
              let model = assistant["model"] as? String, !model.isEmpty,
              let blocks = assistant["content"] as? [[String: Any]] else {
            return .unmatched
        }
        let actual = model.hasPrefix(provider + "/") ? model : provider + "/" + model
        guard actual == expectedModelID else { return .unmatched }
        let text = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unmatched }
        let usage = assistant["usage"] as? [String: Any] ?? [:]
        return .recovered(RoutedChatReply(
            text: text, actualModelID: actual,
            inputTokens: (usage["input"] as? NSNumber)?.intValue,
            outputTokens: (usage["output"] as? NSNumber)?.intValue,
            modelMatched: true
        ))
    }

    private func reloadRouterPlugins(report: @Sendable (String) -> Void) throws {
        let arguments = ["plugins", "reload", "onnx", "localclaw-router", "--accept-capabilities", "--json"]
        for attempt in 0..<4 {
            do {
                _ = try command(arguments, timeout: 120)
                return
            } catch RoutedChatError.commandFailed(let message) {
                // OpenClaw refuses replacement while a just-installed ONNX
                // worker retains its startup/probe work. It explicitly says
                // that no generation was applied and asks for a later retry.
                guard Self.canRetryPluginReload(message), attempt < 3 else {
                    throw RoutedChatError.commandFailed(message)
                }
                report("ONNX is finishing local work; retrying the plugin load…")
                Thread.sleep(forTimeInterval: [3.0, 6.0, 10.0][attempt])
            }
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
            throw RoutedChatError.commandTimedOut
        }
        guard process.terminationStatus == 0 else {
            if arguments.starts(with: ["gateway", "call", "localclaw.router.classify"]),
               Self.isMissingRouterMethod(output) {
                throw RoutedChatError.routerSetupRequired
            }
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
