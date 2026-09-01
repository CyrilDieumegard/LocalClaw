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
    let selectedProfile: String?
    var port: Int? = nil

    init(node: URL, package: URL, prefix: URL, state: URL, config: URL,
         serviceLabel: String?, selectedProfile: String? = nil, port: Int? = nil) {
        self.node = node
        self.package = package
        self.prefix = prefix
        self.state = state
        self.config = config
        self.serviceLabel = serviceLabel
        self.selectedProfile = selectedProfile
        self.port = port
    }

    var profile: String? {
        if let selectedProfile = selectedProfile?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedProfile.isEmpty {
            return selectedProfile
        }
        guard let serviceLabel,
              serviceLabel != "ai.openclaw.gateway",
              serviceLabel.hasPrefix("ai.openclaw.") else { return nil }
        return String(serviceLabel.dropFirst("ai.openclaw.".count))
    }

    var cli: URL { package.appendingPathComponent("openclaw.mjs") }
    var bin: URL { prefix.appendingPathComponent("bin") }
    var version: String? {
        guard let data = try? Data(contentsOf: package.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["name"] as? String == "openclaw" else { return nil }
        return json["version"] as? String
    }

    static func managed(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self? {
        let directory = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let explicitLabel: String? = try {
            guard let raw = environment["OPENCLAW_LAUNCHD_LABEL"] else { return nil }
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, isGatewayServiceLabel(label) else {
                throw MaintenanceError("OPENCLAW_LAUNCHD_LABEL is invalid. No OpenClaw service was selected.")
            }
            return label
        }()
        let profileLabel: String? = try {
            guard let raw = environment["OPENCLAW_PROFILE"] else { return nil }
            let profile = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !profile.isEmpty else {
                throw MaintenanceError("OPENCLAW_PROFILE is empty. No OpenClaw service was selected.")
            }
            let label = profile == "default" ? "ai.openclaw.gateway" : "ai.openclaw.\(profile)"
            guard isGatewayServiceLabel(label) else {
                throw MaintenanceError("OPENCLAW_PROFILE contains unsupported characters. No OpenClaw service was selected.")
            }
            return label
        }()
        if let explicitLabel, let profileLabel, explicitLabel != profileLabel {
            throw MaintenanceError("OPENCLAW_LAUNCHD_LABEL and OPENCLAW_PROFILE select different services. No OpenClaw service was changed.")
        }
        let requestedLabel = explicitLabel ?? profileLabel

        let plists: [URL]
        if let requestedLabel {
            let requested = directory.appendingPathComponent("\(requestedLabel).plist")
            guard FileManager.default.fileExists(atPath: requested.path) else {
                if explicitLabel != nil {
                    throw MaintenanceError("The explicitly selected OpenClaw LaunchAgent is not installed. No other service was selected.")
                }
                return nil
            }
            plists = [requested]
        } else {
            plists = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ))?.filter { url in
                url.pathExtension == "plist" && isGatewayServiceLabel(url.deletingPathExtension().lastPathComponent)
            }.sorted { lhs, rhs in
                let left = lhs.deletingPathExtension().lastPathComponent
                let right = rhs.deletingPathExtension().lastPathComponent
                if left == "ai.openclaw.gateway" { return true }
                if right == "ai.openclaw.gateway" { return false }
                return left < right
            } ?? []
            guard !plists.isEmpty else { return nil }
        }

        let runtimes = try plists.map { try parseManagedService(plist: $0) }
        let requestedState = environment["OPENCLAW_STATE_DIR"].map { canonicalPath(URL(fileURLWithPath: $0)) }
        let requestedConfig = environment["OPENCLAW_CONFIG_PATH"].map { canonicalPath(URL(fileURLWithPath: $0)) }
        if requestedState != nil || requestedConfig != nil {
            let matches = runtimes.filter { runtime in
                (requestedState == nil || canonicalPath(runtime.state) == requestedState) &&
                    (requestedConfig == nil || canonicalPath(runtime.config) == requestedConfig)
            }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                throw MaintenanceError("Multiple OpenClaw Gateway services target the requested state. Select one profile before repair.")
            }
            throw MaintenanceError("The selected OpenClaw state does not match an installed Gateway service. No service was changed.")
        }
        if runtimes.count == 1 { return runtimes[0] }
        throw MaintenanceError("Multiple OpenClaw Gateway profiles are installed. Set OPENCLAW_PROFILE before using LocalClaw repair so it cannot target the wrong service.")
    }

    fileprivate static func canonicalPath(_ url: URL) -> String {
        var existingAncestor = url.standardizedFileURL
        var missingComponents: [String] = []
        while !FileManager.default.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            missingComponents.append(existingAncestor.lastPathComponent)
            existingAncestor = parent
        }
        var canonical = existingAncestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents.reversed() {
            canonical.appendPathComponent(component)
        }
        return canonical.standardizedFileURL.path
    }

    private static func isGatewayServiceLabel(_ label: String) -> Bool {
        if label == "ai.openclaw.gateway" { return true }
        guard label.hasPrefix("ai.openclaw.") else { return false }
        let suffix = String(label.dropFirst("ai.openclaw.".count))
        guard !["gateway", "node", "ssh-tunnel"].contains(suffix), !suffix.isEmpty else { return false }
        return suffix.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    static func gatewayPort(environment: [String: String]) throws -> Int? {
        guard let raw = environment["OPENCLAW_GATEWAY_PORT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        guard let port = Int(raw), (1...65535).contains(port) else {
            throw MaintenanceError("OPENCLAW_GATEWAY_PORT is invalid. No Gateway configuration was changed.")
        }
        return port
    }

    static func gatewayPortForConfiguration(
        managedPort: Int?,
        configuredPort: Int?,
        isManaged: Bool,
        environment: [String: String],
        occupiedPorts: Set<Int>
    ) throws -> Int? {
        if let managedPort { return managedPort }
        let explicitPort = try gatewayPort(environment: environment)
        if let configuredPort {
            if let explicitPort, explicitPort != configuredPort {
                throw MaintenanceError(
                    "OPENCLAW_GATEWAY_PORT does not match gateway.port in the selected profile. No configuration was written."
                )
            }
            guard isManaged || !occupiedPorts.contains(configuredPort) else {
                throw MaintenanceError(
                    "gateway.port \(configuredPort) in the selected profile is already used by another Gateway. No configuration was written."
                )
            }
            return configuredPort
        }
        guard !isManaged,
              let rawProfile = environment["OPENCLAW_PROFILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawProfile.isEmpty,
              rawProfile != "default" else {
            return explicitPort
        }
        guard let explicitPort else {
            guard occupiedPorts.isEmpty else {
                throw MaintenanceError(
                    "OPENCLAW_GATEWAY_PORT is required when creating a named profile alongside another Gateway. Choose an unused port; no configuration was written."
                )
            }
            return nil
        }
        guard !occupiedPorts.contains(explicitPort) else {
            throw MaintenanceError(
                "OPENCLAW_GATEWAY_PORT \(explicitPort) is already used by another Gateway profile. Choose an unused port; no configuration was written."
            )
        }
        return explicitPort
    }

    static func configuredGatewayPort(in config: [String: Any]) throws -> Int? {
        guard let gateway = config["gateway"] as? [String: Any],
              let rawPort = gateway["port"] else {
            return nil
        }
        guard let port = rawPort as? Int, (1...65535).contains(port) else {
            throw MaintenanceError(
                "gateway.port in the selected OpenClaw configuration is invalid. No configuration was written."
            )
        }
        return port
    }

    func gatewayPortForCollisionCheck() throws -> Int {
        if let port { return port }
        guard let data = FileManager.default.contents(atPath: config.path) else {
            return 18789
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MaintenanceError(
                "An installed Gateway has invalid JSON configuration, so LocalClaw could not prove that its port is free. No configuration was written."
            )
        }
        return try Self.configuredGatewayPort(in: root) ?? 18789
    }

    private static func parseManagedService(plist: URL) throws -> Self {
        let expectedLabel = plist.deletingPathExtension().lastPathComponent
        let home = plist.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: plist)
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["Label"] as? String == expectedLabel,
              var arguments = root["ProgramArguments"] as? [String], arguments.count >= 3 else {
            throw MaintenanceError("The Gateway service has an unsupported launch command. Its files were left unchanged.")
        }
        var environment = root["EnvironmentVariables"] as? [String: String] ?? [:]
        // Newer OpenClaw keeps service environment values outside the plist.
        let wrapperIndex = arguments[0] == "/bin/sh" ? 1 : 0
        if arguments[wrapperIndex].hasSuffix("/\(expectedLabel)-env-wrapper.sh"), arguments.count > wrapperIndex + 3 {
            let wrapper = URL(fileURLWithPath: arguments[wrapperIndex])
            let envFile = URL(fileURLWithPath: arguments[wrapperIndex + 1])
            guard wrapper.deletingLastPathComponent().lastPathComponent == "service-env",
                  envFile.deletingLastPathComponent() == wrapper.deletingLastPathComponent(),
                  envFile.lastPathComponent == "\(expectedLabel).env" else {
                throw MaintenanceError("The Gateway environment wrapper has an unexpected location.")
            }
            let values = try String(contentsOf: envFile, encoding: .utf8)
            for line in values.components(separatedBy: .newlines) {
                for key in ["OPENCLAW_STATE_DIR", "OPENCLAW_CONFIG_PATH", "OPENCLAW_GATEWAY_PORT", "OPENCLAW_PROFILE", "OPENCLAW_LAUNCHD_LABEL"] where line.hasPrefix("export \(key)=") {
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
        if let declaredLabel = environment["OPENCLAW_LAUNCHD_LABEL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !declaredLabel.isEmpty, declaredLabel != expectedLabel {
            throw MaintenanceError("The Gateway service label conflicts with its environment. No service was changed.")
        }
        let expectedProfile = expectedLabel == "ai.openclaw.gateway"
            ? "default"
            : String(expectedLabel.dropFirst("ai.openclaw.".count))
        if let declaredProfile = environment["OPENCLAW_PROFILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !declaredProfile.isEmpty, declaredProfile != expectedProfile {
            throw MaintenanceError("The Gateway service profile conflicts with its LaunchAgent label. No service was changed.")
        }
        guard arguments.count >= 3, arguments[0].hasPrefix("/"),
              URL(fileURLWithPath: arguments[0]).lastPathComponent == "node",
              let gatewayIndex = arguments.firstIndex(of: "gateway"), gatewayIndex > 1,
              let entry = arguments[1..<gatewayIndex].first(where: { $0.hasPrefix("/") && ($0.hasSuffix("/openclaw.mjs") || $0.hasSuffix("/dist/index.js") || $0.hasSuffix("/dist/entry.js")) }) else {
            throw MaintenanceError("The Gateway service has an unsupported launch command. Its files were left unchanged.")
        }
        let defaultState = expectedProfile == "default"
            ? home.appendingPathComponent(".openclaw")
            : home.appendingPathComponent(".openclaw-\(expectedProfile)")
        let state = URL(fileURLWithPath: environment["OPENCLAW_STATE_DIR"] ?? defaultState.path)
        let config = URL(fileURLWithPath: environment["OPENCLAW_CONFIG_PATH"] ?? state.appendingPathComponent("openclaw.json").path)
        var runtime = try resolve(node: URL(fileURLWithPath: arguments[0]), entry: URL(fileURLWithPath: entry),
                                  state: state, config: config, serviceLabel: expectedLabel,
                                  selectedProfile: expectedProfile)
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

    static func resolve(node: URL, entry: URL, state: URL, config: URL, serviceLabel: String?,
                        selectedProfile: String? = nil) throws -> Self {
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
                                state: state, config: config, serviceLabel: serviceLabel,
                                selectedProfile: selectedProfile)
        guard installation.version != nil, FileManager.default.isExecutableFile(atPath: node.path),
              FileManager.default.fileExists(atPath: installation.cli.path) else {
            throw MaintenanceError("The Gateway's Node or OpenClaw entry point is missing. Its launch configuration was left unchanged.")
        }
        return installation
    }

    static func installedGatewayServices(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> [Self] {
        let directory = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plists = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            $0.pathExtension == "plist" && isGatewayServiceLabel($0.deletingPathExtension().lastPathComponent)
        } ?? []
        return try plists.map { try parseManagedService(plist: $0) }
    }

    static func selectedState(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let runtime = try managed(home: home, environment: environment) { return runtime.state }
        if let explicit = environment["OPENCLAW_STATE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return URL(fileURLWithPath: explicit)
        }
        if let profile = environment["OPENCLAW_PROFILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !profile.isEmpty, profile != "default" {
            guard profile.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
                throw MaintenanceError("OPENCLAW_PROFILE contains unsupported characters. No OpenClaw state was selected.")
            }
            return home.appendingPathComponent(".openclaw-\(profile)")
        }
        return home.appendingPathComponent(".openclaw")
    }

    static func selectedConfig(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let runtime = try managed(home: home, environment: environment) { return runtime.config }
        if let explicit = environment["OPENCLAW_CONFIG_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return URL(fileURLWithPath: explicit)
        }
        return try selectedState(home: home, environment: environment).appendingPathComponent("openclaw.json")
    }

    var environmentPrefix: String {
        "env PATH=\(Self.quote(node.deletingLastPathComponent().path + ":" + bin.path)):\"$PATH\" " +
        "NPM_CONFIG_PREFIX=\(Self.quote(prefix.path)) npm_config_prefix=\(Self.quote(prefix.path)) " +
        "OPENCLAW_STATE_DIR=\(Self.quote(state.path)) OPENCLAW_CONFIG_PATH=\(Self.quote(config.path)) " +
        (serviceLabel.map { "OPENCLAW_LAUNCHD_LABEL=\(Self.quote($0)) " } ?? "") +
        (profile.map { "OPENCLAW_PROFILE=\(Self.quote($0)) " } ?? "") +
        (port.map { "OPENCLAW_GATEWAY_PORT=\($0) " } ?? "")
    }

    func command(_ arguments: String, cli override: URL? = nil,
                 externalServiceRepair: Bool = false) -> String {
        let entry = override ?? cli
        return environmentPrefix +
            (externalServiceRepair ? "OPENCLAW_SERVICE_REPAIR_POLICY=external " : "") +
            "OPENCLAW_DIST_DIR=\(Self.quote(entry.deletingLastPathComponent().appendingPathComponent("dist").path)) " +
            Self.quote(node.path) + " " + Self.quote(entry.path) + " " + arguments
    }

    func applying(to environment: [String: String]) -> [String: String] {
        var result = environment
        result["PATH"] = node.deletingLastPathComponent().path + ":" + bin.path + ":" + (result["PATH"] ?? "")
        result["OPENCLAW_DIST_DIR"] = package.appendingPathComponent("dist").path
        result["OPENCLAW_STATE_DIR"] = state.path
        result["OPENCLAW_CONFIG_PATH"] = config.path
        if let serviceLabel { result["OPENCLAW_LAUNCHD_LABEL"] = serviceLabel }
        else { result.removeValue(forKey: "OPENCLAW_LAUNCHD_LABEL") }
        if let profile { result["OPENCLAW_PROFILE"] = profile }
        else { result.removeValue(forKey: "OPENCLAW_PROFILE") }
        if let port { result["OPENCLAW_GATEWAY_PORT"] = String(port) }
        else { result.removeValue(forKey: "OPENCLAW_GATEWAY_PORT") }
        return result
    }

    static func configureCLIProcess(_ process: Process, arguments: [String], environment: [String: String],
                                    home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        if let runtime = try managed(home: home, environment: environment) {
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
    private let environment: [String: String]
    private let run: Runner
    private let report: (String) -> Void
    private let wait: (TimeInterval) -> Void
    private let freeBytes: (URL) throws -> UInt64
    private let migrationHelper: () throws -> URL
    private let fm = FileManager.default
    private var backupPath: String?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         run: @escaping Runner,
         report: @escaping (String) -> Void = { _ in }, wait: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
         freeBytes: @escaping (URL) throws -> UInt64 = OpenClawOfflineBackup.availableBytes,
         migrationHelper: @escaping () throws -> URL = { try OpenClawRecoveryResources.migrationHelper() }) {
        self.home = home
        self.environment = environment
        self.run = run
        self.report = report
        self.wait = wait
        self.freeBytes = freeBytes
        self.migrationHelper = migrationHelper
    }

    func installation() throws -> OpenClawRuntimeInstallation {
        if let managed = try OpenClawRuntimeInstallation.managed(home: home, environment: environment) { return managed }
        let entry = try checked("command -v openclaw", stage: "Locate OpenClaw")
        let node = try checked("command -v node", stage: "Locate Node")
        guard entry.hasPrefix("/"), node.hasPrefix("/"), !entry.contains("\n"), !node.contains("\n") else {
            throw MaintenanceError("OpenClaw and Node must resolve to installed executables.")
        }
        let profile = environment["OPENCLAW_PROFILE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profile, !profile.isEmpty, profile != "default",
           profile.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) == nil {
            throw MaintenanceError("OPENCLAW_PROFILE contains unsupported characters. No OpenClaw state was selected.")
        }
        let defaultState = profile.flatMap { value in
            value.isEmpty || value == "default" ? nil : home.appendingPathComponent(".openclaw-\(value)")
        } ?? home.appendingPathComponent(".openclaw")
        let state = URL(fileURLWithPath: environment["OPENCLAW_STATE_DIR"] ?? defaultState.path)
        let config = URL(fileURLWithPath: environment["OPENCLAW_CONFIG_PATH"] ?? state.appendingPathComponent("openclaw.json").path)
        var runtime = try OpenClawRuntimeInstallation.resolve(
            node: URL(fileURLWithPath: node), entry: URL(fileURLWithPath: entry),
            state: state, config: config, serviceLabel: nil,
            selectedProfile: profile?.isEmpty == false ? profile : nil
        )
        if let port = try OpenClawRuntimeInstallation.gatewayPort(environment: environment) {
            runtime.port = port
        }
        return runtime
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

    func hasPendingUpdate() -> Bool {
        guard let runtime = try? installation() else { return false }
        return OpenClawUpdateCheckpoint.load(home: home, runtime: runtime) != nil
    }

    static func supportsPostCoreRepair(_ version: String?) -> Bool {
        guard let version else { return false }
        return version.compare("2026.8.1", options: .numeric) != .orderedAscending
    }

    static func hasUnsafeSharedRuntimeConsumer(
        selected runtime: OpenClawRuntimeInstallation,
        consumers: [OpenClawRuntimeInstallation]
    ) -> Bool {
        let shared = consumers.filter {
            $0.package.resolvingSymlinksInPath() == runtime.package.resolvingSymlinksInPath()
        }
        let selectedConsumerMatches = shared.contains {
            runtime.serviceLabel != nil && $0.serviceLabel == runtime.serviceLabel &&
                $0.node.resolvingSymlinksInPath() == runtime.node.resolvingSymlinksInPath() &&
                $0.state.resolvingSymlinksInPath() == runtime.state.resolvingSymlinksInPath() &&
                $0.config.resolvingSymlinksInPath() == runtime.config.resolvingSymlinksInPath()
        }
        return shared.count > 1 || (!shared.isEmpty && !selectedConsumerMatches)
    }

    private static func canSafelyRepairSelectedStateInSharedRuntime(
        selected runtime: OpenClawRuntimeInstallation,
        consumers: [OpenClawRuntimeInstallation]
    ) -> Bool {
        guard let selectedLabel = runtime.serviceLabel else { return false }
        let shared = consumers.filter {
            $0.package.resolvingSymlinksInPath() == runtime.package.resolvingSymlinksInPath()
        }
        guard shared.count > 1 else { return false }

        let selectedState = OpenClawRuntimeInstallation.canonicalPath(runtime.state)
        let selectedConfig = OpenClawRuntimeInstallation.canonicalPath(runtime.config)
        guard selectedConfig.hasPrefix(selectedState + "/") else { return false }
        func matchesSelected(_ consumer: OpenClawRuntimeInstallation) -> Bool {
            consumer.serviceLabel == selectedLabel &&
                consumer.node.resolvingSymlinksInPath() == runtime.node.resolvingSymlinksInPath() &&
                OpenClawRuntimeInstallation.canonicalPath(consumer.state) == selectedState &&
                OpenClawRuntimeInstallation.canonicalPath(consumer.config) == selectedConfig
        }
        guard shared.filter(matchesSelected).count == 1 else { return false }
        func overlaps(_ lhs: String, _ rhs: String) -> Bool {
            lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
        }
        for consumer in shared where !matchesSelected(consumer) {
            guard consumer.serviceLabel != selectedLabel else { return false }
            let otherState = OpenClawRuntimeInstallation.canonicalPath(consumer.state)
            let otherConfig = OpenClawRuntimeInstallation.canonicalPath(consumer.config)
            guard !overlaps(selectedState, otherState),
                  !overlaps(selectedState, otherConfig),
                  !overlaps(selectedConfig, otherState),
                  selectedConfig != otherConfig else { return false }
        }
        return true
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
            if OpenClawUpdateCheckpoint.load(home: home, runtime: runtime) != nil {
                return allowRuntimeUpdate ? updateUnlocked()
                    : StepResult(state: .fail, message: "OpenClaw post-update repair is pending. Use Repair Gateway to finish. No request was sent.")
            }
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
                    let selectedEnvironment = runtime.applying(to: environment)
                    guard let installed = try OpenClawRuntimeInstallation.managed(home: home, environment: selectedEnvironment),
                          installed.package.resolvingSymlinksInPath() == runtime.package.resolvingSymlinksInPath(),
                          installed.node.resolvingSymlinksInPath() == runtime.node.resolvingSymlinksInPath(),
                          OpenClawRuntimeInstallation.canonicalPath(installed.state) ==
                            OpenClawRuntimeInstallation.canonicalPath(runtime.state),
                          OpenClawRuntimeInstallation.canonicalPath(installed.config) ==
                            OpenClawRuntimeInstallation.canonicalPath(runtime.config),
                          (installed.profile ?? "default") == (runtime.profile ?? "default"),
                          runtime.port == nil || installed.port == runtime.port else {
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
                    if allowRuntimeUpdate, Self.supportsPostCoreRepair(runtime.version),
                       OpenClawUpdateResult.needsPluginApproval(start.1) {
                        return updateUnlocked()
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
        run(bounded(runtime.command("gateway status --json --require-rpc --timeout 5000"), seconds: 25))
    }

    private func validateConfiguration(_ runtime: OpenClawRuntimeInstallation) -> (Int32, String) {
        run(bounded(runtime.command("config validate --json"), seconds: 30))
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
        var restartOnFailure: OpenClawRuntimeInstallation?
        do {
            report("Checking free disk space before contacting npm...")
            try OpenClawStorageRecovery.requireSpace(at: home, freeBytes: freeBytes)
            let runtime = try installation()
            let installedConsumers = try OpenClawRuntimeInstallation.installedGatewayServices(home: home)
            let unsafeSharedRuntime = Self.hasUnsafeSharedRuntimeConsumer(
                selected: runtime, consumers: installedConsumers
            )
            let sharedConsumers = installedConsumers.filter {
                $0.package.resolvingSymlinksInPath() == runtime.package.resolvingSymlinksInPath()
            }
            let sharedLabels = sharedConsumers.compactMap(\.serviceLabel).sorted().joined(separator: ", ")
            let sharedRuntimeFailure = MaintenanceError(
                "OpenClaw update stopped: multiple Gateway profiles share this npm runtime (\(sharedLabels)). " +
                "Only an isolated, same-version configuration repair can run without replacing their shared core. " +
                "Upgrades, reinstalls, overlapping states, and unscoped repairs remain blocked. " +
                "No service, database, or package was changed."
            )
            for directory in [runtime.prefix, runtime.state] where fm.fileExists(atPath: directory.path) {
                try OpenClawStorageRecovery.requireSpace(at: directory, freeBytes: freeBytes)
            }
            if let checkpoint = OpenClawUpdateCheckpoint.load(home: home, runtime: runtime),
               Self.supportsPostCoreRepair(runtime.version),
               Self.isSupportedUpdateTarget(checkpoint.target) {
                if unsafeSharedRuntime {
                    guard Self.canSafelyRepairSelectedStateInSharedRuntime(
                        selected: runtime, consumers: installedConsumers
                    ) else { throw sharedRuntimeFailure }
                    report("Resuming an isolated selected-profile repair on the shared OpenClaw core. Core replacement remains disabled...")
                }
                backupPath = checkpoint.archive
                report("Resuming OpenClaw \(checkpoint.target) repair with the existing verified backup. No core reinstall...")
                // A resumed repair can reinstall or restart the selected service.
                // Keep compensation armed until every post-update verification
                // has succeeded, just like the first update attempt.
                restartOnFailure = runtime
                let result = try finishUpdate(runtime, target: checkpoint.target, updater: runtime.cli, repairOnly: true)
                restartOnFailure = nil
                return result
            }
            report("Checking the Gateway installation: \(runtime.package.path)")
            let validation = validateConfiguration(runtime)
            var repairingConfig = repairConfiguration || OpenClawRecoveryDiagnostic.hasInvalidConfiguration(validation.1)
            let pendingApprovals = hasLegacyExecApprovals(runtime)
            guard let current = runtime.version else {
                throw MaintenanceError("The installed OpenClaw version could not be verified. No database or runtime was replaced.")
            }
            let isolatedSharedRepair = unsafeSharedRuntime && repairingConfig && !pendingApprovals &&
                Self.supportsPostCoreRepair(current) && Self.isSupportedUpdateTarget(current) &&
                Self.canSafelyRepairSelectedStateInSharedRuntime(
                    selected: runtime, consumers: installedConsumers
                )
            if unsafeSharedRuntime && !isolatedSharedRepair { throw sharedRuntimeFailure }
            let target: String
            if isolatedSharedRepair {
                // Native repair is bound to the already-installed core. Never let a
                // later `latest` release turn selected-profile repair into a shared
                // package replacement.
                target = current
            } else if repairingConfig || pendingApprovals {
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
            guard current.compare(target, options: .numeric) != .orderedDescending else {
                throw MaintenanceError("The selected release would downgrade OpenClaw. No database or runtime was replaced.")
            }
            let repairOnly = current == target && Self.supportsPostCoreRepair(current)
            if unsafeSharedRuntime {
                guard isolatedSharedRepair, repairOnly else { throw sharedRuntimeFailure }
                report("The selected profile has an isolated state on a shared OpenClaw core. Core replacement remains disabled; continuing with backup-first native configuration repair only...")
            }
            let approvalsHelper: URL?
            if pendingApprovals && target == "2026.8.1" {
                report("Checking LocalClaw repair resources before creating a recovery backup...")
                approvalsHelper = try migrationHelper()
            } else {
                approvalsHelper = nil
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
                if try offlineBackup(runtime, archive: archive) {
                    restartOnFailure = runtime
                }
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
            } else if mismatch && !repairOnly {
                guard try updateTarget(runtime, cli: updater, tag: target) == target else {
                    throw MaintenanceError("The installed updater changed the requested release. No package was replaced.")
                }
            }

            // From this point onward, approval migration or the native updater can
            // change files and service state. Any failure must attempt a bounded,
            // verified service compensation, regardless of backup strategy.
            restartOnFailure = runtime
            if let helper = approvalsHelper {
                report("Migrating legacy execution approvals with OpenClaw's verified importer...")
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

            let result = try finishUpdate(runtime, target: target, updater: updater,
                                          repairOnly: repairOnly)
            restartOnFailure = nil
            return result
        } catch {
            var serviceRecovery = ""
            if let runtime = restartOnFailure {
                report("Maintenance failed after runtime or service mutation. Reinstalling the selected service definition and verifying RPC...")
                let install = run(bounded(runtime.command("gateway install --force --json"), seconds: 90))
                var recoveryRuntime = runtime
                if install.0 == 0 {
                    let selectedEnvironment = runtime.applying(to: environment)
                    if let installed = try? OpenClawRuntimeInstallation.managed(home: home, environment: selectedEnvironment),
                       installed.package.resolvingSymlinksInPath() == runtime.package.resolvingSymlinksInPath(),
                       installed.state.resolvingSymlinksInPath() == runtime.state.resolvingSymlinksInPath(),
                       installed.config.resolvingSymlinksInPath() == runtime.config.resolvingSymlinksInPath() {
                        recoveryRuntime = installed
                    }
                }
                var activation = run(bounded(recoveryRuntime.command("gateway restart --json"), seconds: 90))
                if activation.0 != 0 {
                    activation = run(bounded(recoveryRuntime.command("gateway start --json"), seconds: 90))
                }
                let probe = activation.0 == 0
                    ? run(bounded(recoveryRuntime.command("gateway status --json --require-rpc --timeout 5000"), seconds: 30))
                    : (-1, "Gateway activation failed before RPC verification.")
                if install.0 == 0, activation.0 == 0, probe.0 == 0,
                   InstallerEngine.gatewayIsHealthy(statusOutput: probe.1) {
                    serviceRecovery = "\nThe selected Gateway service was reinstalled and RPC health was verified after the failure."
                } else {
                    serviceRecovery = "\nGateway compensation was attempted but RPC health was not verified. OpenClaw data remains backed up; review these bounded diagnostics before retrying.\nInstall: \(String(install.1.suffix(1_000)))\nActivate: \(String(activation.1.suffix(1_000)))\nStatus: \(String(probe.1.suffix(1_000)))"
                }
            }
            let backup = backupPath.map { "\nRecovery backup: \($0)" } ?? ""
            let guidance = OpenClawStorageRecovery.isStorageFailure(error.localizedDescription) ? "\(OpenClawStorageRecovery.explanation)\n\n" : ""
            return StepResult(state: .fail, message: SecretRedactor.redactConfigText("\(guidance)OpenClaw maintenance stopped: \(error.localizedDescription)\(backup)\(serviceRecovery)\nYour database was not deleted or downgraded. No chat request was replayed."))
        }
    }

    private func finishUpdate(_ runtime: OpenClawRuntimeInstallation, target: String, updater: URL, repairOnly: Bool) throws -> StepResult {
        report(repairOnly ? "Finishing Doctor and plugin repair without reinstalling OpenClaw..."
               : "Updating the Gateway, synchronizing plugins and checking startup...")
        let arguments = repairOnly ? "update repair --yes --json" : "update --tag \(q(target)) --yes --json"
        let update = run(bounded(runtime.command(
            arguments + " --timeout 600",
            cli: updater,
            externalServiceRepair: repairOnly
        ), seconds: 1800))
        // Keep a resumable checkpoint even if Doctor fails after the package swap.
        if runtime.version == target, let backupPath {
            try OpenClawUpdateCheckpoint.save(home: home, runtime: runtime, target: target, archive: URL(fileURLWithPath: backupPath))
        }
        let output = update.1
        guard let result = OpenClawUpdateResult.envelope(in: output),
              let root = result["root"] as? String,
              URL(fileURLWithPath: root).resolvingSymlinksInPath() == runtime.package.resolvingSymlinksInPath() else {
            throw MaintenanceError("OpenClaw maintenance returned no verifiable result for this installation (exit \(update.0)).\n\(output)")
        }
        if repairOnly {
            guard result["mode"] as? String == "finalize", result["restart"] as? Bool == false else {
                throw MaintenanceError("OpenClaw repair did not confirm finalize-only mode with service restart disabled. The shared core was not approved for replacement.\n\(output)")
            }
        }
        guard runtime.version == target else {
            throw MaintenanceError("The Gateway package is not version \(target) after updating. No task was replayed.\n\(output)")
        }
        if let pluginFailure = OpenClawUpdateResult.pluginFailure(in: result) {
            throw MaintenanceError(pluginFailure)
        }
        guard update.0 == 0, result["status"] as? String == "ok" else {
            throw MaintenanceError("OpenClaw \(target) is installed, but post-update maintenance did not finish (exit \(update.0)).\n\(output)")
        }
        let configCheck = validateConfiguration(runtime)
        guard configCheck.0 == 0, InstallerEngine.firstJSONObject(in: configCheck.1)?["valid"] as? Bool == true else {
            throw MaintenanceError("Configuration validation failed after updating OpenClaw.\n\(configCheck.1)")
        }
        if repairOnly {
            // Unlike `update`, native `update repair` deliberately never restarts.
            report("Installing the repaired Gateway service and restarting it...")
            _ = try checked(bounded(runtime.command("gateway install --force --json"), seconds: 90), stage: "Install repaired Gateway")
        }
        if runtime.serviceLabel != nil || repairOnly {
            let selectedEnvironment = runtime.applying(to: environment)
            guard let installed = try OpenClawRuntimeInstallation.managed(home: home, environment: selectedEnvironment),
                  installed.package.resolvingSymlinksInPath() == runtime.package.resolvingSymlinksInPath(),
                  installed.node.resolvingSymlinksInPath() == runtime.node.resolvingSymlinksInPath(),
                  installed.state.resolvingSymlinksInPath() == runtime.state.resolvingSymlinksInPath(),
                  installed.config.resolvingSymlinksInPath() == runtime.config.resolvingSymlinksInPath() else {
                let actual = (try? OpenClawRuntimeInstallation.managed(home: home, environment: selectedEnvironment)).map {
                    "package=\($0.package.path), node=\($0.node.path), state=\($0.state.path), config=\($0.config.path), label=\($0.serviceLabel ?? "none")"
                } ?? "no uniquely selected managed Gateway"
                throw MaintenanceError("The Gateway service points to a different installation after updating. Expected package=\(runtime.package.path), node=\(runtime.node.path), state=\(runtime.state.path), config=\(runtime.config.path), label=\(runtime.serviceLabel ?? "none"); found \(actual).")
            }
        }
        if repairOnly {
            _ = try checked(bounded(runtime.command("gateway restart --json"), seconds: 90), stage: "Restart repaired Gateway")
        }
        report("Verifying Gateway version and RPC health...")
        var samples = 0
        var verified = ""
        for delay in [0.0, 1.0, 2.0, 3.0, 5.0, 5.0] {
            wait(delay)
            let probe = probeGateway(runtime)
            verified = probe.1
            samples = probe.0 == 0 && Self.verifiedGateway(probe.1, expectedVersion: target) ? samples + 1 : 0
            if samples == 2 {
                try OpenClawUpdateCheckpoint.remove(home: home, runtime: runtime)
                return StepResult(state: .ok, message: "OpenClaw \(target) ready; configuration, Gateway version and two RPC checks verified.\nRecovery backup: \(backupPath ?? "unknown")\nNo chat request was replayed.")
            }
        }
        throw MaintenanceError("The Gateway is not running the expected version with healthy RPC.\n\(verified)")
    }

    private func updateTarget(_ runtime: OpenClawRuntimeInstallation, cli: URL, tag: String) throws -> String {
        let output = try checked(bounded(runtime.command("update --tag \(q(tag)) --dry-run --json", cli: cli), seconds: 90), stage: "Check update target")
        guard let plan = InstallerEngine.firstJSONObject(in: output), plan["dryRun"] as? Bool == true,
              let root = plan["root"] as? String,
              URL(fileURLWithPath: root).resolvingSymlinksInPath().path == runtime.package.path,
              let version = plan["targetVersion"] as? String,
              Self.isSupportedUpdateTarget(version) else {
            throw MaintenanceError("The updater could not confirm the target version and Gateway package location. No package was replaced.\n\(output)")
        }
        return version
    }

    private func registryTarget(_ runtime: OpenClawRuntimeInstallation) throws -> String {
        let output = try checked(bounded(runtime.environmentPrefix + "npm view openclaw@latest version --json", seconds: 60), stage: "Resolve recovery release")
        guard let data = output.data(using: .utf8),
              let version = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String,
              Self.isSupportedUpdateTarget(version) else {
            throw MaintenanceError("The package registry did not return a valid OpenClaw release. Nothing was replaced.")
        }
        return version
    }

    private static func isReleaseVersion(_ value: String) -> Bool {
        value.range(of: #"^\d{4}\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil
    }

    static func isSupportedUpdateTarget(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}\.\d+\.\d+$"#, options: .regularExpression) != nil else { return false }
        return value.compare("2026.8.1", options: .numeric) != .orderedAscending
    }

    /// Returns true when this operation stopped a previously loaded Gateway.
    private func offlineBackup(_ runtime: OpenClawRuntimeInstallation, archive: URL) throws -> Bool {
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
        var stoppedLoadedService = false
        if loaded.0 == 0 {
            _ = try checked("/bin/launchctl bootout \(q(service))", stage: "Stop incompatible Gateway")
            stoppedLoadedService = true
        } else if !loaded.1.contains("Could not find service") {
            throw MaintenanceError("Could not confirm the Gateway service state.\n\(loaded.1)")
        }
        do {
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
            return stoppedLoadedService
        } catch {
            guard stoppedLoadedService else { throw error }
            report("Offline backup failed after stopping the Gateway. Restoring and verifying the previous service...")
            let restart = run(bounded(runtime.command("gateway start --json"), seconds: 90))
            let probe = restart.0 == 0
                ? run(bounded(runtime.command("gateway status --json --require-rpc --timeout 5000"), seconds: 30))
                : (-1, "Gateway start failed before RPC verification.")
            guard restart.0 == 0, probe.0 == 0, InstallerEngine.gatewayIsHealthy(statusOutput: probe.1) else {
                throw MaintenanceError(
                    "\(error.localizedDescription)\nThe previously loaded Gateway was stopped for the backup and could not be restored with verified RPC health.\nStart: \(restart.1)\nStatus: \(probe.1)"
                )
            }
            report("The previous Gateway service was restored and RPC health was verified.")
            throw error
        }
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
