import Foundation

enum OpenClawRecoveryDiagnostic {
    static func hasLegacyExecApprovals(_ text: String) -> Bool {
        let current = currentFailure(in: text).lowercased()
        return current.contains("legacy exec approvals exist") || current.contains("execapprovalsmigrationrequirederror") ||
            current.contains("migrate execution approvals failed") || current.contains("execution approvals migration was not verified")
    }

    static func currentFailure(in text: String) -> String {
        // Supplementary log history must not choose a repair for the current request.
        let markers = ["\nRecent startup log (", "\nHistorical startup log (", "\nLocalClaw Gateway diagnostic:"]
        let end = markers.compactMap { text.range(of: $0)?.lowerBound }.min() ?? text.endIndex
        return String(text[..<end])
    }

    static func hasInvalidConfiguration(_ text: String) -> Bool {
        let current = currentFailure(in: text)
        let clean = current.lowercased()
        if clean.contains("config is invalid") || clean.contains("config invalid") || clean.contains("invalid config") ||
            clean.contains("configuration validation failed") { return true }
        guard let json = InstallerEngine.firstJSONObject(in: current) else { return false }
        if json["valid"] as? Bool == false { return true }
        guard let config = json["config"] as? [String: Any] else { return false }
        return ["cli", "daemon"].contains { (config[$0] as? [String: Any])?["valid"] as? Bool == false }
    }
}

struct OpenClawSchemaMismatch: Equatable {
    let stored: Int
    let supported: Int

    static func detect(in text: String) -> Self? {
        let pattern = #"uses newer schema version\s+(\d+);\s*(?:this\s+)?(?:OpenClaw\s+)?build supports\s+(\d+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let storedRange = Range(match.range(at: 1), in: text),
              let supportedRange = Range(match.range(at: 2), in: text),
              let stored = Int(text[storedRange]), let supported = Int(text[supportedRange]),
              stored > supported else { return nil }
        return Self(stored: stored, supported: supported)
    }

    var explanation: String {
        "OpenClaw's database uses newer schema version \(stored); this build supports \(supported). Update the Gateway runtime; do not delete or downgrade the database."
    }
}

struct OpenClawRuntimeInstallation {
    let node: URL
    let package: URL
    let prefix: URL
    let state: URL
    let config: URL
    let serviceLabel: String?
    var port: Int? = nil

    var cli: URL { package.appendingPathComponent("openclaw.mjs") }
    var bin: URL { prefix.appendingPathComponent("bin") }
    var version: String? {
        guard let data = try? Data(contentsOf: package.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["name"] as? String == "openclaw" else { return nil }
        return json["version"] as? String
    }

    static func managed(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Self? {
        let plist = home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.gateway.plist")
        guard FileManager.default.fileExists(atPath: plist.path) else { return nil }
        let data = try Data(contentsOf: plist)
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["Label"] as? String == "ai.openclaw.gateway",
              var arguments = root["ProgramArguments"] as? [String], arguments.count >= 3 else {
            throw MaintenanceError("The Gateway service has an unsupported launch command. Its files were left unchanged.")
        }
        var environment = root["EnvironmentVariables"] as? [String: String] ?? [:]
        // Newer OpenClaw keeps service environment values outside the plist.
        let wrapperIndex = arguments[0] == "/bin/sh" ? 1 : 0
        if arguments[wrapperIndex].hasSuffix("/ai.openclaw.gateway-env-wrapper.sh"), arguments.count > wrapperIndex + 3 {
            let wrapper = URL(fileURLWithPath: arguments[wrapperIndex])
            let envFile = URL(fileURLWithPath: arguments[wrapperIndex + 1])
            guard wrapper.deletingLastPathComponent().lastPathComponent == "service-env",
                  envFile.deletingLastPathComponent() == wrapper.deletingLastPathComponent(),
                  envFile.lastPathComponent == "ai.openclaw.gateway.env" else {
                throw MaintenanceError("The Gateway environment wrapper has an unexpected location.")
            }
            let values = try String(contentsOf: envFile, encoding: .utf8)
            for line in values.components(separatedBy: .newlines) {
                for key in ["OPENCLAW_STATE_DIR", "OPENCLAW_CONFIG_PATH", "OPENCLAW_GATEWAY_PORT"] where line.hasPrefix("export \(key)=") {
                    let value = String(line.dropFirst("export \(key)=".count)).trimmingCharacters(in: .whitespaces)
                    guard value.hasPrefix("'"), value.hasSuffix("'") else {
                        throw MaintenanceError("The Gateway state path must be a literal in its generated environment file.")
                    }
                    let literal = String(value.dropFirst().dropLast())
                    guard !literal.replacingOccurrences(of: "'\\''", with: "").contains("'") else {
                        throw MaintenanceError("The Gateway state path could not be read safely.")
                    }
                    environment[key] = literal.replacingOccurrences(of: "'\\''", with: "'")
                }
            }
            arguments = Array(arguments.dropFirst(wrapperIndex + 2))
        }
        guard arguments.count >= 3, arguments[0].hasPrefix("/"),
              URL(fileURLWithPath: arguments[0]).lastPathComponent == "node",
              let gatewayIndex = arguments.firstIndex(of: "gateway"), gatewayIndex > 1,
              let entry = arguments[1..<gatewayIndex].first(where: { $0.hasPrefix("/") && ($0.hasSuffix("/openclaw.mjs") || $0.hasSuffix("/dist/index.js") || $0.hasSuffix("/dist/entry.js")) }) else {
            throw MaintenanceError("The Gateway service has an unsupported launch command. Its files were left unchanged.")
        }
        let state = URL(fileURLWithPath: environment["OPENCLAW_STATE_DIR"] ?? home.appendingPathComponent(".openclaw").path)
        let config = URL(fileURLWithPath: environment["OPENCLAW_CONFIG_PATH"] ?? state.appendingPathComponent("openclaw.json").path)
        var runtime = try resolve(node: URL(fileURLWithPath: arguments[0]), entry: URL(fileURLWithPath: entry),
                                  state: state, config: config, serviceLabel: "ai.openclaw.gateway")
        let portIndex = arguments.firstIndex(of: "--port").map { $0 + 1 }
        let portValue = portIndex.flatMap { arguments.indices.contains($0) ? arguments[$0] : nil }
            ?? environment["OPENCLAW_GATEWAY_PORT"]
        if let portValue {
            guard let port = Int(portValue), (1...65535).contains(port) else {
                throw MaintenanceError("The Gateway service port is invalid. Its launch configuration was left unchanged.")
            }
            runtime.port = port
        }
        return runtime
    }

    static func resolve(node: URL, entry: URL, state: URL, config: URL, serviceLabel: String?) throws -> Self {
        let resolved = entry.resolvingSymlinksInPath()
        let package = resolved.lastPathComponent == "openclaw.mjs"
            ? resolved.deletingLastPathComponent() : resolved.deletingLastPathComponent().deletingLastPathComponent()
        guard ["openclaw.mjs", "index.js", "entry.js"].contains(resolved.lastPathComponent),
              package.lastPathComponent == "openclaw", package.deletingLastPathComponent().lastPathComponent == "node_modules",
              package.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "lib" else {
            throw MaintenanceError("Cannot identify the Gateway's npm installation safely. No package was replaced.")
        }
        let installation = Self(node: node, package: package,
                                prefix: package.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
                                state: state, config: config, serviceLabel: serviceLabel)
        guard installation.version != nil, FileManager.default.isExecutableFile(atPath: node.path),
              FileManager.default.fileExists(atPath: installation.cli.path) else {
            throw MaintenanceError("The Gateway's Node or OpenClaw entry point is missing. Its launch configuration was left unchanged.")
        }
        return installation
    }

    var environmentPrefix: String {
        "env PATH=\(Self.quote(node.deletingLastPathComponent().path + ":" + bin.path)):\"$PATH\" " +
        "NPM_CONFIG_PREFIX=\(Self.quote(prefix.path)) npm_config_prefix=\(Self.quote(prefix.path)) " +
        "OPENCLAW_STATE_DIR=\(Self.quote(state.path)) OPENCLAW_CONFIG_PATH=\(Self.quote(config.path)) " +
        (port.map { "OPENCLAW_GATEWAY_PORT=\($0) " } ?? "")
    }

    func command(_ arguments: String, cli override: URL? = nil) -> String {
        environmentPrefix + Self.quote(node.path) + " " + Self.quote((override ?? cli).path) + " " + arguments
    }

    func applying(to environment: [String: String]) -> [String: String] {
        var result = environment
        result["PATH"] = node.deletingLastPathComponent().path + ":" + bin.path + ":" + (result["PATH"] ?? "")
        result["OPENCLAW_DIST_DIR"] = package.appendingPathComponent("dist").path
        result["OPENCLAW_STATE_DIR"] = state.path
        result["OPENCLAW_CONFIG_PATH"] = config.path
        if let port { result["OPENCLAW_GATEWAY_PORT"] = String(port) }
        return result
    }

    static func configureCLIProcess(_ process: Process, arguments: [String], environment: [String: String],
                                    home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        if let runtime = try managed(home: home) {
            process.executableURL = runtime.node
            process.arguments = [runtime.cli.path] + arguments
            process.environment = runtime.applying(to: environment)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["openclaw"] + arguments
            process.environment = environment
        }
    }

    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

struct MaintenanceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Keeps update ownership, backup and post-update verification in one transaction.
final class OpenClawRuntimeMaintenance {
    typealias Runner = (String) -> (Int32, String)
    private static let lock = NSLock()
    static var isActive: Bool {
        guard lock.try() else { return true }
        lock.unlock()
        return false
    }
    private let home: URL
    private let run: Runner
    private let report: (String) -> Void
    private let wait: (TimeInterval) -> Void
    private let freeBytes: (URL) throws -> UInt64
    private let fm = FileManager.default
    private var backupPath: String?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, run: @escaping Runner,
         report: @escaping (String) -> Void = { _ in }, wait: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
         freeBytes: @escaping (URL) throws -> UInt64 = OpenClawOfflineBackup.availableBytes) {
        self.home = home
        self.run = run
        self.report = report
        self.wait = wait
        self.freeBytes = freeBytes
    }

    func installation() throws -> OpenClawRuntimeInstallation {
        if let managed = try OpenClawRuntimeInstallation.managed(home: home) { return managed }
        let entry = try checked("command -v openclaw", stage: "Locate OpenClaw")
        let node = try checked("command -v node", stage: "Locate Node")
        guard entry.hasPrefix("/"), node.hasPrefix("/"), !entry.contains("\n"), !node.contains("\n") else {
            throw MaintenanceError("OpenClaw and Node must resolve to installed executables.")
        }
        let state = home.appendingPathComponent(".openclaw")
        return try .resolve(node: URL(fileURLWithPath: node), entry: URL(fileURLWithPath: entry),
                            state: state, config: state.appendingPathComponent("openclaw.json"), serviceLabel: nil)
    }

    func schemaMismatch() -> OpenClawSchemaMismatch? {
        guard let runtime = try? installation() else { return nil }
        return OpenClawSchemaMismatch.detect(in: probeGateway(runtime).1)
    }

    func configurationNeedsRepair() -> Bool {
        guard let runtime = try? installation() else { return false }
        return OpenClawRecoveryDiagnostic.hasInvalidConfiguration(validateConfiguration(runtime).1)
    }

    func execApprovalsNeedMigration() -> Bool {
        guard let runtime = try? installation(), runtime.version == "2026.8.1" else { return false }
        return hasLegacyExecApprovals(runtime)
    }

    private func hasLegacyExecApprovals(_ runtime: OpenClawRuntimeInstallation) -> Bool {
        ["exec-approvals.json", "exec-approvals.json.doctor-importing"].contains { name in
            let path = runtime.state.appendingPathComponent(name).path
            return fm.fileExists(atPath: path) || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil
        }
    }

    /// Restore connectivity only. A previous agent request must never be replayed here.
    func prepareGateway(allowRuntimeUpdate: Bool = false) -> StepResult {
        guard Self.lock.try() else { return StepResult(state: .fail, message: "Another OpenClaw maintenance operation is running. No request was sent.") }
        defer { Self.lock.unlock() }
        do {
            var runtime = try installation()
            report("Checking the Gateway used by this chat...")
            var probe = probeGateway(runtime)
            let pendingApprovals = runtime.version == "2026.8.1" && hasLegacyExecApprovals(runtime)
            if probe.0 == 0, InstallerEngine.gatewayIsHealthy(statusOutput: probe.1), !pendingApprovals {
                return StepResult(state: .ok, message: "Gateway RPC is healthy. No running task was interrupted or replayed.")
            }
            let root = InstallerEngine.firstJSONObject(in: probe.1)
            let service = root?["service"] as? [String: Any]
            let process = service?["runtime"] as? [String: Any]
            let rpc = root?["rpc"] as? [String: Any]
            if service?["targetRole"] as? String == "diagnostic-only" {
                throw MaintenanceError("The CLI targets a different Gateway. Local service recovery was not attempted.\n\(probe.1)")
            }
            if let mismatch = OpenClawSchemaMismatch.detect(in: probe.1) {
                return allowRuntimeUpdate ? updateUnlocked(requiresOfflineBackup: true)
                    : StepResult(state: .fail, message: mismatch.explanation + " No request was sent. Use Update OpenClaw to repair the runtime.")
            }

            if OpenClawRecoveryDiagnostic.hasLegacyExecApprovals(probe.1) ||
                pendingApprovals {
                return allowRuntimeUpdate ? updateUnlocked(requiresOfflineBackup: true)
                    : StepResult(state: .fail, message: "Legacy exec approvals exist and need migration. No request was sent. Use Repair Gateway to back up the state and migrate the existing permissions without resetting them.")
            }

            let validation = validateConfiguration(runtime)
            if OpenClawRecoveryDiagnostic.hasInvalidConfiguration(validation.1) {
                return configurationRecovery(runtime, evidence: validation.1, allowed: allowRuntimeUpdate)
            }

            let alreadyRunning = process?["status"] as? String == "running" || rpc?["ok"] as? Bool == true
            let markers = startupLogSizes(runtime)
            var startOutput = ""
            if !alreadyRunning {
                if runtime.serviceLabel == nil {
                    guard allowRuntimeUpdate else {
                        throw MaintenanceError("The Gateway service is missing. Use Repair Gateway to install it.\n\(probe.1)")
                    }
                    report("Installing the Gateway service from the selected runtime...")
                    _ = try checked(bounded(runtime.command("gateway install --force --json"), seconds: 90), stage: "Install Gateway service")
                    guard let installed = try OpenClawRuntimeInstallation.managed(home: home), installed.package == runtime.package else {
                        throw MaintenanceError("The Gateway service did not bind to the expected installation.")
                    }
                    runtime = installed
                }
                report("Starting the existing Gateway service...")
                let start = run(bounded(runtime.command("gateway start --json"), seconds: 45))
                startOutput = start.1
                if start.0 != 0 || InstallerEngine.firstJSONObject(in: start.1)?["ok"] as? Bool == false {
                    if let mismatch = OpenClawSchemaMismatch.detect(in: start.1) {
                        return allowRuntimeUpdate ? updateUnlocked(requiresOfflineBackup: true)
                            : StepResult(state: .fail, message: mismatch.explanation + " No request was sent.")
                    }
                    if OpenClawRecoveryDiagnostic.hasInvalidConfiguration(start.1) {
                        return configurationRecovery(runtime, evidence: start.1, allowed: allowRuntimeUpdate)
                    }
                    throw MaintenanceError("Gateway start failed (\(start.0)).\n\(start.1)\n\(gatewayFailureDetails(runtime, status: probe.1))")
                }
            } else {
                report("The Gateway process is running. Waiting for RPC without restarting it...")
            }

            // LaunchAgent success only means launchd accepted the start, not that RPC is ready.
            var healthySamples = 0
            for delay in [0.0, 1.0, 2.0, 3.0, 5.0, 5.0] {
                wait(delay)
                probe = probeGateway(runtime)
                let currentEvidence = probe.1 + "\n" + startupLogEvidence(runtime, after: markers)
                if let mismatch = OpenClawSchemaMismatch.detect(in: currentEvidence) {
                    return allowRuntimeUpdate ? updateUnlocked(requiresOfflineBackup: true)
                        : StepResult(state: .fail, message: mismatch.explanation + " No request was sent.")
                }
                if OpenClawRecoveryDiagnostic.hasInvalidConfiguration(currentEvidence) {
                    return configurationRecovery(runtime, evidence: currentEvidence, allowed: allowRuntimeUpdate)
                }
                if probe.0 == 0, InstallerEngine.gatewayIsHealthy(statusOutput: probe.1) {
                    healthySamples += 1
                    if healthySamples == 2 {
                        return StepResult(state: .ok, message: "Gateway service is running and RPC passed two health checks. No chat request was replayed.")
                    }
                } else {
                    healthySamples = 0
                }
            }
            let preservation = alreadyRunning ? "The running process was left untouched." : "The service start did not restore RPC health."
            throw MaintenanceError("\(preservation)\n\(startOutput)\n\(gatewayFailureDetails(runtime, status: probe.1))")
        } catch {
            return StepResult(state: .fail, message: SecretRedactor.redactConfigText(
                "Gateway recovery stopped: \(error.localizedDescription)\nNo chat request was replayed. Your configuration and project files were not reset."
            ))
        }
    }

    func gatewayDiagnostic() -> String {
        do {
            let runtime = try installation()
            let probe = probeGateway(runtime)
            if probe.0 == 0, InstallerEngine.gatewayIsHealthy(statusOutput: probe.1) {
                return "The Gateway is reachable now. The previous request may still be running; it was not resent."
            }
            return SecretRedactor.redactConfigText(gatewayFailureDetails(runtime, status: probe.1))
        } catch {
            return SecretRedactor.redactConfigText("Gateway diagnostic: \(error.localizedDescription)")
        }
    }

    private func probeGateway(_ runtime: OpenClawRuntimeInstallation) -> (Int32, String) {
        run(bounded(runtime.command("gateway status --json --require-rpc --timeout 5000 2>&1"), seconds: 25))
    }

    private func validateConfiguration(_ runtime: OpenClawRuntimeInstallation) -> (Int32, String) {
        run(bounded(runtime.command("config validate --json 2>&1"), seconds: 30))
    }

    private func configurationRecovery(_ runtime: OpenClawRuntimeInstallation, evidence: String, allowed: Bool) -> StepResult {
        guard allowed else {
            return StepResult(state: .fail, message: SecretRedactor.redactConfigText(
                "OpenClaw config is invalid for runtime \(runtime.version ?? "unknown"). No request was sent. Use Repair Gateway to back up the state and run current configuration migrations.\n\(evidence)"
            ))
        }
        report("Configuration blocks startup. Preparing backup-first runtime and configuration repair...")
        return updateUnlocked(requiresOfflineBackup: true, repairConfiguration: true)
    }

    private func bounded(_ command: String, seconds: Int) -> String {
        "perl -e 'alarm \(seconds); exec @ARGV' " + command
    }

    private func gatewayFailureDetails(_ runtime: OpenClawRuntimeInstallation, status: String) -> String {
        let root = InstallerEngine.firstJSONObject(in: status)
        let lastError = root?["lastError"] as? String ?? ""
        return "Gateway is not ready. Runtime: \(runtime.version ?? "unknown") at \(runtime.package.path)\n" +
            "Config: \(runtime.config.path)\n\(lastError)\n\(String(status.suffix(6_000)))\n\(startupLogEvidence(runtime))"
    }

    private func startupLogPaths(_ runtime: OpenClawRuntimeInstallation) -> [URL] {
        [runtime.state.appendingPathComponent("logs/gateway.err.log"),
         runtime.state.appendingPathComponent("logs/gateway.log"),
         home.appendingPathComponent("Library/Logs/openclaw/gateway.log"),
         home.appendingPathComponent("Library/Logs/openclaw/gateway.err.log")]
    }

    private func startupLogSizes(_ runtime: OpenClawRuntimeInstallation) -> [String: UInt64] {
        Dictionary(uniqueKeysWithValues: startupLogPaths(runtime).map {
            ($0.path, ((try? fm.attributesOfItem(atPath: $0.path)[.size]) as? NSNumber)?.uint64Value ?? 0)
        })
    }

    private func startupLogEvidence(_ runtime: OpenClawRuntimeInstallation, after markers: [String: UInt64]? = nil) -> String {
        startupLogPaths(runtime).compactMap { url -> String? in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  markers != nil || (values.contentModificationDate ?? .distantPast) >= Date().addingTimeInterval(-900),
                  let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let end = try? handle.seekToEnd() else { return nil }
            let previous = markers?[url.path] ?? 0
            let start = max(end > 32_768 ? end - 32_768 : 0, previous <= end ? previous : 0)
            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.readToEnd() else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            let errors = text.components(separatedBy: .newlines).filter {
                let line = $0.lowercased()
                return ["error", "failed", "fatal", "schema version", "refusing", "blocked", "eaddrinuse", "requires node", "config is invalid", "invalid config"].contains(where: line.contains)
            }.suffix(4)
            guard !errors.isEmpty else { return nil }
            let label = markers == nil ? "Recent startup log" : "Current startup failure"
            return "\(label) (\(url.lastPathComponent)):\n" + String(errors.joined(separator: "\n").suffix(3_000))
        }.joined(separator: "\n")
    }

    func update() -> StepResult {
        guard Self.lock.try() else { return StepResult(state: .fail, message: "Another OpenClaw maintenance operation is running.") }
        defer { Self.lock.unlock() }
        return updateUnlocked()
    }

    func clearDownloadCache(confirmed: Bool) -> StepResult {
        guard Self.lock.try() else { return StepResult(state: .fail, message: "Wait for OpenClaw maintenance to finish before cleaning the cache.") }
        defer { Self.lock.unlock() }
        do {
            try OpenClawStorageRecovery(home: home).clearCache(confirmed: confirmed, run: run)
            return StepResult(state: .ok, message: "npm download cache cleared. Models, projects, chats, credentials and backups were kept. Downloads may need to be fetched again.")
        } catch { return StepResult(state: .fail, message: SecretRedactor.redactConfigText(error.localizedDescription)) }
    }

    private func updateUnlocked(requiresOfflineBackup: Bool = false, repairConfiguration: Bool = false) -> StepResult {
        backupPath = nil
        do {
            report("Checking free disk space before contacting npm...")
            try OpenClawStorageRecovery.requireSpace(at: home, freeBytes: freeBytes)
            let runtime = try installation()
            for directory in [runtime.prefix, runtime.state] where fm.fileExists(atPath: directory.path) {
                try OpenClawStorageRecovery.requireSpace(at: directory, freeBytes: freeBytes)
            }
            report("Checking the Gateway installation: \(runtime.package.path)")
            let validation = validateConfiguration(runtime)
            var repairingConfig = repairConfiguration || OpenClawRecoveryDiagnostic.hasInvalidConfiguration(validation.1)
            let pendingApprovals = hasLegacyExecApprovals(runtime)
            let target: String
            if repairingConfig || pendingApprovals {
                // A rejected config can prevent the old CLI from even planning its update.
                target = try registryTarget(runtime)
            } else {
                do {
                    target = try updateTarget(runtime, cli: runtime.cli, tag: "latest")
                } catch {
                    guard OpenClawRecoveryDiagnostic.hasInvalidConfiguration(error.localizedDescription) else { throw error }
                    repairingConfig = true
                    target = try registryTarget(runtime)
                }
            }
            guard let current = runtime.version, current.compare(target, options: .numeric) != .orderedDescending else {
                throw MaintenanceError("The selected release would downgrade OpenClaw. No database or runtime was replaced.")
            }
            if let data = try? Data(contentsOf: runtime.config),
               let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let meta = config["meta"] as? [String: Any], let authored = meta["lastTouchedVersion"] as? String,
               Self.isReleaseVersion(authored), authored.compare(target, options: .numeric) == .orderedDescending {
                throw MaintenanceError("The configuration was written by OpenClaw \(authored), newer than available release \(target). No older Doctor was run and no configuration was changed.")
            }
            let status = probeGateway(runtime).1
            var mismatch = requiresOfflineBackup || repairingConfig || pendingApprovals || OpenClawSchemaMismatch.detect(in: status) != nil
            let directory = home.appendingPathComponent("Library/Application Support/LocalClaw/runtime-backups")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let archive = directory.appendingPathComponent("openclaw-\(UUID().uuidString).tar.gz")
            guard !fm.fileExists(atPath: archive.path) else { throw MaintenanceError("The recovery backup destination already exists.") }
            var verifiedArchive = false
            defer { if !verifiedArchive { try? fm.removeItem(at: archive) } }
            report("Creating a recovery backup before changing OpenClaw...")
            if !mismatch {
                let backup = run(runtime.command("backup create --no-include-workspace --verify --output \(q(archive.path)) --json"))
                mismatch = OpenClawSchemaMismatch.detect(in: backup.1) != nil || OpenClawRecoveryDiagnostic.hasInvalidConfiguration(backup.1)
                if !mismatch && backup.0 != 0 { throw MaintenanceError("State backup failed. No runtime was replaced.\n\(backup.1)") }
                if mismatch && fm.fileExists(atPath: archive.path) { try fm.removeItem(at: archive) }
            }
            if mismatch {
                report("The installed runtime cannot safely handle this state. Creating an offline recovery backup...")
                try offlineBackup(runtime, archive: archive)
            }
            guard let size = try fm.attributesOfItem(atPath: archive.path)[.size] as? NSNumber, size.intValue > 0 else {
                throw MaintenanceError("The recovery archive is missing or empty. Update stopped.")
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
            verifiedArchive = true
            backupPath = archive.path
            report("Recovery backup: \(archive.path)")

            var updater = runtime.cli
            var staging: URL?
            defer { if let staging { try? fm.removeItem(at: staging) } }
            if mismatch && current != target {
                // Bootstrap from new code: the old updater can itself require the incompatible DB.
                let candidate = directory.appendingPathComponent("updater-\(UUID().uuidString)")
                try fm.createDirectory(at: candidate, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                staging = candidate
                report("Preparing OpenClaw \(target) in a temporary directory...")
                let npmVersion = try checked(runtime.environmentPrefix + "npm --version", stage: "Check npm")
                let flags = Self.npmLifecycleFlags(version: npmVersion)
                _ = try checked(runtime.environmentPrefix + "npm install --global --prefix \(q(candidate.path)) openclaw@\(target)\(flags)", stage: "Prepare recovery updater")
                updater = candidate.appendingPathComponent("lib/node_modules/openclaw/openclaw.mjs")
                guard fm.fileExists(atPath: updater.path) else { throw MaintenanceError("The recovery updater is incomplete.") }
                guard try updateTarget(runtime, cli: updater, tag: target) == target else {
                    throw MaintenanceError("The recovery updater changed the requested release. No package was replaced.")
                }
            } else if mismatch {
                guard try updateTarget(runtime, cli: updater, tag: target) == target else {
                    throw MaintenanceError("The installed updater changed the requested release. No package was replaced.")
                }
            }

            if pendingApprovals && target == "2026.8.1" {
                report("Migrating legacy execution approvals with OpenClaw's verified importer...")
                guard let helper = Bundle.module.url(forResource: "exec-approvals-migration", withExtension: "mjs") else {
                    throw MaintenanceError("The approvals migration helper is missing. Existing permissions were kept.")
                }
                let package = updater.deletingLastPathComponent()
                let command = runtime.environmentPrefix + q(runtime.node.path) + " " + q(helper.path) + " " + q(package.path) + " " + q(runtime.state.path)
                let migrated = try checked(bounded(command, seconds: 120), stage: "Migrate execution approvals")
                guard let result = InstallerEngine.firstJSONObject(in: migrated), result["ok"] as? Bool == true,
                      result["version"] as? String == target,
                      let state = result["stateDir"] as? String,
                      URL(fileURLWithPath: state).resolvingSymlinksInPath() == runtime.state.resolvingSymlinksInPath(),
                      !hasLegacyExecApprovals(runtime) else {
                    throw MaintenanceError("Execution approvals migration was not verified. No permissions were reset.\n\(migrated)")
                }
            }

            report("Updating the Gateway, synchronizing plugins and checking startup...")
            let update = run(runtime.command("update --tag \(q(target)) --yes --json", cli: updater))
            guard update.0 == 0 else {
                let installed = runtime.version == target ? "OpenClaw \(target) is installed, but post-update maintenance did not finish.\n" : ""
                throw MaintenanceError("\(installed)OpenClaw update failed (\(update.0)).\n\(update.1)")
            }
            let output = update.1
            guard let result = InstallerEngine.firstJSONObject(in: output), result["status"] as? String == "ok" else {
                throw MaintenanceError("OpenClaw did not confirm a successful update.\n\(output)")
            }
            if let plugins = (result["postUpdate"] as? [String: Any])?["plugins"] as? [String: Any],
               let pluginStatus = plugins["status"] as? String, ["error", "warning"].contains(pluginStatus) {
                throw MaintenanceError("The core update finished, but plugin convergence needs attention. No task was replayed.\n\(output)")
            }
            guard runtime.version == target else { throw MaintenanceError("The Gateway package is not version \(target) after updating. No task was replayed.") }
            let configCheck = validateConfiguration(runtime)
            guard configCheck.0 == 0, InstallerEngine.firstJSONObject(in: configCheck.1)?["valid"] as? Bool == true else {
                throw MaintenanceError("Configuration validation failed after updating OpenClaw.\n\(configCheck.1)")
            }
            if runtime.serviceLabel != nil {
                guard let installed = try OpenClawRuntimeInstallation.managed(home: home), installed.package == runtime.package else {
                    throw MaintenanceError("The Gateway service points to a different installation after updating.")
                }
            }
            let verified = try checked(runtime.command("gateway status --json --require-rpc --timeout 10000"), stage: "Verify Gateway")
            guard Self.verifiedGateway(verified, expectedVersion: target) else {
                throw MaintenanceError("The Gateway is not running the expected version with healthy RPC.\n\(verified)")
            }
            return StepResult(state: .ok, message: "OpenClaw \(target) updated; Gateway version and RPC verified.\nRecovery backup: \(archive.path)")
        } catch {
            let backup = backupPath.map { "\nRecovery backup: \($0)" } ?? ""
            let guidance = OpenClawStorageRecovery.isStorageFailure(error.localizedDescription) ? "\(OpenClawStorageRecovery.explanation)\n\n" : ""
            return StepResult(state: .fail, message: SecretRedactor.redactConfigText("\(guidance)OpenClaw maintenance stopped: \(error.localizedDescription)\(backup)\nYour database was not deleted or downgraded. No chat request was replayed."))
        }
    }

    private func updateTarget(_ runtime: OpenClawRuntimeInstallation, cli: URL, tag: String) throws -> String {
        let output = try checked(bounded(runtime.command("update --tag \(q(tag)) --dry-run --json", cli: cli), seconds: 90), stage: "Check update target")
        guard let plan = InstallerEngine.firstJSONObject(in: output), plan["dryRun"] as? Bool == true,
              let root = plan["root"] as? String,
              URL(fileURLWithPath: root).resolvingSymlinksInPath().path == runtime.package.path,
              let version = plan["targetVersion"] as? String,
              Self.isReleaseVersion(version) else {
            throw MaintenanceError("The updater could not confirm the target version and Gateway package location. No package was replaced.\n\(output)")
        }
        return version
    }

    private func registryTarget(_ runtime: OpenClawRuntimeInstallation) throws -> String {
        let output = try checked(bounded(runtime.environmentPrefix + "npm view openclaw@latest version --json", seconds: 60), stage: "Resolve recovery release")
        guard let data = output.data(using: .utf8),
              let version = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String,
              Self.isReleaseVersion(version) else {
            throw MaintenanceError("The package registry did not return a valid OpenClaw release. Nothing was replaced.")
        }
        return version
    }

    private static func isReleaseVersion(_ value: String) -> Bool {
        value.range(of: #"^\d{4}\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil
    }

    private func offlineBackup(_ runtime: OpenClawRuntimeInstallation, archive: URL) throws {
        guard let label = runtime.serviceLabel else { throw MaintenanceError("Offline database recovery requires an identified Gateway service. No data was changed.") }
        let state = runtime.state.resolvingSymlinksInPath().path
        let config = runtime.config.resolvingSymlinksInPath().path
        guard config.hasPrefix(state + "/"), !archive.path.hasPrefix(state + "/"), fm.fileExists(atPath: state) else {
            throw MaintenanceError("The custom state/config paths need a separate verified backup. Automatic recovery stopped.")
        }
        report("Checking space for the offline backup before stopping the Gateway...")
        let inventory = try OpenClawOfflineBackup.inventory(state: runtime.state)
        try OpenClawStorageRecovery.requireSpace(at: archive.deletingLastPathComponent(), required: inventory.requiredBytes, freeBytes: freeBytes)
        let service = "gui/\(getuid())/\(label)"
        let loaded = run("/bin/launchctl print \(q(service)) 2>&1")
        if loaded.0 == 0 {
            _ = try checked("/bin/launchctl bootout \(q(service))", stage: "Stop incompatible Gateway")
        } else if !loaded.1.contains("Could not find service") {
            throw MaintenanceError("Could not confirm the Gateway service state.\n\(loaded.1)")
        }
        // Do not take a raw SQLite/WAL snapshot while another app or helper owns the files.
        func inspect() -> OpenClawStateInspection {
            let result = run(OpenClawStateInspection.command(state: state))
            return OpenClawStateInspection.parse(code: result.0, output: result.1)
        }
        report("Checking for processes with open OpenClaw data files...")
        var inspection = inspect()
        for _ in 0..<4 {
            guard case .busy = inspection else { break }
            wait(1)
            inspection = inspect()
        }
        switch inspection {
        case .clear:
            break
        case .busy(let owners):
            let details = owners.prefix(8).map(\.summary).joined(separator: "\n")
            let remaining = owners.count > 8 ? "\nAnd \(owners.count - 8) more open file handles." : ""
            throw MaintenanceError("OpenClaw data files are still open. Close the listed app or stop its task, then retry. No process was killed and no runtime was replaced.\n\(details)\(remaining)")
        case .failed(let diagnostic):
            throw MaintenanceError("LocalClaw could not verify whether OpenClaw data files are in use. This does not confirm a database lock. Backup and update stopped.\n\(diagnostic)")
        }
        try OpenClawOfflineBackup.create(state: URL(fileURLWithPath: state), archive: archive, run: run, report: report)
    }

    static func verifiedGateway(_ output: String, expectedVersion: String) -> Bool {
        guard OpenClawSchemaMismatch.detect(in: output) == nil,
              InstallerEngine.gatewayIsHealthy(statusOutput: output),
              let root = InstallerEngine.firstJSONObject(in: output) else { return false }
        let gateway = root["gateway"] as? [String: Any]
        let rpc = root["rpc"] as? [String: Any]
        let server = rpc?["server"] as? [String: Any]
        let version = gateway?["version"] as? String ?? server?["version"] as? String ?? rpc?["version"] as? String
        return version == expectedVersion
    }

    static func npmLifecycleFlags(version: String) -> String {
        let parts = version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return "" }
        return parts[0] >= 12 || (parts[0] == 11 && parts[1] >= 16) ? " --allow-scripts=openclaw" : ""
    }

    private func checked(_ command: String, stage: String) throws -> String {
        let (code, output) = run(command)
        guard code == 0 else { throw MaintenanceError("\(stage) failed (\(code)).\n\(output)") }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func q(_ value: String) -> String { OpenClawRuntimeInstallation.quote(value) }
}
