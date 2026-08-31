import Foundation

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
                for key in ["OPENCLAW_STATE_DIR", "OPENCLAW_CONFIG_PATH"] where line.hasPrefix("export \(key)=") {
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
        return try resolve(node: URL(fileURLWithPath: arguments[0]), entry: URL(fileURLWithPath: entry),
                           state: state, config: config, serviceLabel: "ai.openclaw.gateway")
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
        "OPENCLAW_STATE_DIR=\(Self.quote(state.path)) OPENCLAW_CONFIG_PATH=\(Self.quote(config.path)) "
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
        return result
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
    private let fm = FileManager.default
    private var backupPath: String?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, run: @escaping Runner,
         report: @escaping (String) -> Void = { _ in }) {
        self.home = home
        self.run = run
        self.report = report
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
        return OpenClawSchemaMismatch.detect(in: run(runtime.command("gateway status --json --timeout 5000 2>&1")).1)
    }

    func update() -> StepResult {
        guard Self.lock.try() else { return StepResult(state: .fail, message: "Another OpenClaw maintenance operation is running.") }
        defer { Self.lock.unlock() }
        do {
            let runtime = try installation()
            report("Checking the Gateway installation: \(runtime.package.path)")
            let target = try updateTarget(runtime, cli: runtime.cli, tag: "latest")
            guard let current = runtime.version, current.compare(target, options: .numeric) != .orderedDescending else {
                throw MaintenanceError("The selected release would downgrade OpenClaw. No database or runtime was replaced.")
            }
            let status = run(runtime.command("gateway status --json --timeout 5000 2>&1")).1
            var mismatch = OpenClawSchemaMismatch.detect(in: status) != nil
            let directory = home.appendingPathComponent("Library/Application Support/LocalClaw/runtime-backups")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let archive = directory.appendingPathComponent("openclaw-\(UUID().uuidString).tar.gz")
            report("Creating a recovery backup before changing OpenClaw...")
            if !mismatch {
                let backup = run(runtime.command("backup create --no-include-workspace --verify --output \(q(archive.path)) --json"))
                mismatch = OpenClawSchemaMismatch.detect(in: backup.1) != nil
                if !mismatch && backup.0 != 0 { throw MaintenanceError("State backup failed. No runtime was replaced.\n\(backup.1)") }
            }
            if mismatch {
                report("The database is newer than OpenClaw. Preserving it with an offline backup...")
                try offlineBackup(runtime, archive: archive)
            }
            guard let size = try fm.attributesOfItem(atPath: archive.path)[.size] as? NSNumber, size.intValue > 0 else {
                throw MaintenanceError("The recovery archive is missing or empty. Update stopped.")
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
            backupPath = archive.path
            report("Recovery backup: \(archive.path)")

            var updater = runtime.cli
            var staging: URL?
            defer { if let staging { try? fm.removeItem(at: staging) } }
            if mismatch {
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
                _ = try updateTarget(runtime, cli: updater, tag: target)
            }

            report("Updating the Gateway, synchronizing plugins and checking startup...")
            let output = try checked(runtime.command("update --tag \(q(target)) --yes --json", cli: updater), stage: "OpenClaw update")
            guard let result = InstallerEngine.firstJSONObject(in: output), result["status"] as? String == "ok" else {
                throw MaintenanceError("OpenClaw did not confirm a successful update.\n\(output)")
            }
            if let plugins = (result["postUpdate"] as? [String: Any])?["plugins"] as? [String: Any],
               let pluginStatus = plugins["status"] as? String, ["error", "warning"].contains(pluginStatus) {
                throw MaintenanceError("The core update finished, but plugin convergence needs attention. No task was replayed.\n\(output)")
            }
            guard runtime.version == target else { throw MaintenanceError("The Gateway package is not version \(target) after updating. No task was replayed.") }
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
            return StepResult(state: .fail, message: SecretRedactor.redactConfigText("OpenClaw maintenance stopped: \(error.localizedDescription)\(backup)\nYour database was not deleted or downgraded. No chat request was replayed."))
        }
    }

    private func updateTarget(_ runtime: OpenClawRuntimeInstallation, cli: URL, tag: String) throws -> String {
        let output = try checked(runtime.command("update --tag \(q(tag)) --dry-run --json", cli: cli), stage: "Check update target")
        guard let plan = InstallerEngine.firstJSONObject(in: output), plan["dryRun"] as? Bool == true,
              let root = plan["root"] as? String,
              URL(fileURLWithPath: root).resolvingSymlinksInPath().path == runtime.package.path,
              let version = plan["targetVersion"] as? String,
              version.range(of: #"^\d{4}\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil else {
            throw MaintenanceError("The updater could not confirm the target version and Gateway package location. No package was replaced.\n\(output)")
        }
        return version
    }

    private func offlineBackup(_ runtime: OpenClawRuntimeInstallation, archive: URL) throws {
        guard let label = runtime.serviceLabel else { throw MaintenanceError("Offline database recovery requires an identified Gateway service. No data was changed.") }
        let state = runtime.state.resolvingSymlinksInPath().path
        let config = runtime.config.resolvingSymlinksInPath().path
        guard config.hasPrefix(state + "/"), !archive.path.hasPrefix(state + "/"), fm.fileExists(atPath: state) else {
            throw MaintenanceError("The custom state/config paths need a separate verified backup. Automatic recovery stopped.")
        }
        let service = "gui/\(getuid())/\(label)"
        let loaded = run("/bin/launchctl print \(q(service)) 2>&1")
        if loaded.0 == 0 {
            _ = try checked("/bin/launchctl bootout \(q(service))", stage: "Stop incompatible Gateway")
        } else if !loaded.1.contains("Could not find service") {
            throw MaintenanceError("Could not confirm the Gateway service state.\n\(loaded.1)")
        }
        // Do not take a raw SQLite/WAL snapshot while another app or helper owns the files.
        var owners = run("/usr/sbin/lsof -t +D \(q(state)) 2>&1")
        for _ in 0..<4 where owners.0 == 0 {
            Thread.sleep(forTimeInterval: 1)
            owners = run("/usr/sbin/lsof -t +D \(q(state)) 2>&1")
        }
        guard owners.0 == 1, owners.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MaintenanceError("OpenClaw state is still open in another process. Close other OpenClaw clients and retry. No runtime was replaced.")
        }
        _ = try checked("umask 077; /usr/bin/tar -czf \(q(archive.path)) -C \(q(state)) .", stage: "Back up migrated state")
        _ = try checked("/usr/bin/tar -tzf \(q(archive.path)) >/dev/null", stage: "Verify offline recovery archive")
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
