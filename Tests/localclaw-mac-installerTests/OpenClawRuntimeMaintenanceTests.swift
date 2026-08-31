import Foundation
import Testing
@testable import localclaw_mac_installer

@Suite(.serialized)
struct OpenClawRuntimeMaintenanceTests {
    private let mismatch = "OpenClaw state database /Users/bot/.openclaw/state/openclaw.sqlite uses newer schema version 15; this OpenClaw build supports 1."

    @Test func schemaErrorTakesPriorityOverConnectionAndModelErrors() throws {
        let diagnostic = mismatch + "\nECONNREFUSED lmstudio Gateway may still be running this turn"
        let value = try #require(OpenClawSchemaMismatch.detect(in: diagnostic))
        #expect(value.stored == 15)
        #expect(value.supported == 1)
        #expect(ChatRecoveryPlan.classify(error: diagnostic).kind == .runtimeVersion)
        #expect(OpenClawSchemaMismatch.detect(in: value.explanation) == value)
        #expect(OpenClawSchemaMismatch.detect(in: "uses newer schema version 1; this build supports 15") == nil)
    }

    @Test func uncertainAgentDeliveryNeverOffersAutomaticReplay() {
        let plan = ChatRecoveryPlan.classify(error: "Gateway agent call connection closed; the Gateway may still be running this turn. ECONNREFUSED")
        #expect(plan.kind == .deliveryUnknown)
        #expect(plan.primaryActionLabel == "Repair Gateway")
        #expect(!plan.replaysRequestAfterRepair)
        #expect(!ChatRecoveryPlan.classify(error: "Gateway closed with 1006 abnormal closure").replaysRequestAfterRepair)
    }

    @Test func currentConfigFailureWinsOverOldModuleAndModelErrors() {
        let diagnostic = """
        Gateway is not ready. Your message was not sent.
        Gateway recovery stopped: Gateway start failed (1).
        OpenClaw config is invalid
        File: ~/.openclaw/openclaw.json
        Problem:
          - meta: Invalid input
          - agents.defaults: Invalid input
          - memory: Invalid input
        Fix: openclaw doctor --fix
        {"config":{"cli":{"valid":true},"daemon":{"valid":true}},"cli":{"version":"2026.7.1-2"},"rpc":{"ok":false}}
        Recent startup log (gateway.log):
        2026-05-18 ERR_MODULE_NOT_FOUND /opt/homebrew/lib/node_modules/openclaw/dist/old.js
        2026-05-18 lmstudio request timed out
        """
        let plan = ChatRecoveryPlan.classify(error: diagnostic)
        #expect(plan.kind == .configuration)
        #expect(plan.primaryActionLabel == "Repair Gateway")
        #expect(!plan.replaysRequestAfterRepair)
        #expect(InstallerViewModel.friendlyChatDiagnostic(from: diagnostic) == nil)
    }

    @Test func historicalErrorsDoNotOverrideCurrentConnectionFailure() {
        for marker in ["Recent startup log (gateway.log):", "Historical startup log (gateway.log):", "LocalClaw Gateway diagnostic:"] {
            let diagnostic = "Gateway is not ready. ECONNREFUSED\n\(marker)\n\(mismatch)\nERR_MODULE_NOT_FOUND lmstudio timeout"
            #expect(ChatRecoveryPlan.classify(error: diagnostic).kind == .gateway)
            #expect(InstallerViewModel.friendlyChatDiagnostic(from: diagnostic) == nil)
        }
        #expect(ChatRecoveryPlan.classify(error: "ERR_MODULE_NOT_FOUND openclaw/dist/current.js").kind == .runtimeFiles)
    }

    @Test func structuredInvalidConfigurationIsDetectedWithoutEnglishErrorText() {
        #expect(OpenClawRecoveryDiagnostic.hasInvalidConfiguration(#"{"ok":false,"valid":false,"issues":[{"path":"meta","message":"Invalid input"}]}"#))
        #expect(OpenClawRecoveryDiagnostic.hasInvalidConfiguration(#"{"config":{"daemon":{"valid":false}}}"#))
        #expect(!OpenClawRecoveryDiagnostic.hasInvalidConfiguration(#"{"valid":true}"#))
    }

    @Test func explicitCLIFailureCannotBeMistakenForAnAssistantReply() {
        let raw = #"{"ok":false,"error":{"type":"cli_error","message":"Gateway not reachable (ECONNREFUSED)"}}"#
        #expect(InstallerViewModel.normalizedAgentResult((0, raw)).0 != 0)
        let uncertain = "Gateway may still be running this turn. Request timed out."
        #expect(InstallerViewModel.friendlyChatDiagnostic(from: uncertain) == nil)
        #expect(InstallerViewModel.friendlyChatDiagnostic(from: mismatch + " Request timed out") == nil)
    }

    @Test func agentProcessUsesTheServiceExecutableAndConfigInsteadOfAmbientHomebrew() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let process = Process()
        let arguments = ["agent", "--message-file", "/tmp/prompt with spaces.txt", "--session-id", "test"]
        try OpenClawRuntimeInstallation.configureCLIProcess(
            process, arguments: arguments, environment: ["PATH": "/opt/homebrew/bin:/usr/bin", "KEPT": "yes"], home: fixture.home
        )
        #expect(process.executableURL?.path == fixture.home.appendingPathComponent(".hermes/node/bin/node").path)
        #expect(process.arguments == [fixture.package.appendingPathComponent("openclaw.mjs").path] + arguments)
        #expect(process.environment?["OPENCLAW_CONFIG_PATH"] == fixture.home.appendingPathComponent(".openclaw/openclaw.json").path)
        #expect(process.environment?["OPENCLAW_DIST_DIR"] == fixture.package.appendingPathComponent("dist").path)
        #expect(process.environment?["KEPT"] == "yes")
    }

    @Test func serviceInstallationOverridesAmbientNpmAndPreservesStateScope() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let resolved = try OpenClawRuntimeInstallation.managed(home: fixture.home)
        let runtime = try #require(resolved)
        #expect(runtime.package.path == fixture.package.path)
        #expect(runtime.prefix.path == fixture.home.appendingPathComponent(".local").path)
        #expect(runtime.node.path.contains(".hermes/node/bin/node"))
        let environment = runtime.applying(to: ["PATH": "/opt/homebrew/bin", "UNCHANGED": "yes"])
        #expect(environment["PATH"]?.hasPrefix(runtime.node.deletingLastPathComponent().path) == true)
        #expect(environment["OPENCLAW_DIST_DIR"] == runtime.package.appendingPathComponent("dist").path)
        #expect(environment["UNCHANGED"] == "yes")
        #expect(runtime.command("update").contains("npm_config_prefix="))
    }

    @Test func generatedServiceWrapperIsReadWithoutExecutingItsEnvironmentFile() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.wrapService()
        let runtime = try OpenClawRuntimeInstallation.managed(home: fixture.home)
        #expect(runtime?.package.path == fixture.package.path)
        #expect(runtime?.state.path == fixture.home.appendingPathComponent(".openclaw").path)
        #expect(runtime?.config.path == fixture.home.appendingPathComponent(".openclaw/openclaw.json").path)
    }

    @Test func migratedDatabaseUsesOfflineBackupAndFreshUpdaterBeforeActivation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = try Data(contentsOf: fixture.database)
        let result = fixture.maintenance().update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(try Data(contentsOf: fixture.database) == original)
        #expect(fixture.commands.contains { $0.contains("bootout") })
        #expect(!fixture.commands.contains { $0.contains("backup create") })
        let archived = try #require(fixture.commands.firstIndex { $0.contains("tar -tzf") })
        let prepared = try #require(fixture.commands.firstIndex { $0.contains("npm install --global --prefix") })
        let updated = try #require(fixture.commands.firstIndex { $0.contains("--yes --json") })
        #expect(archived < prepared && prepared < updated)
        #expect(fixture.commands[updated].contains("updater-"))
        #expect(fixture.commands[prepared].contains("--allow-scripts=openclaw"))
        #expect(!fixture.commands.contains { $0.contains("--accept-capabilities") || $0.contains("--local") })
        #expect(fixture.commands.allSatisfy { !$0.contains("agent --") && !$0.contains("doctor --fix") })
        let archives = try fixture.archives()
        #expect(archives.count == 1)
        #expect((try FileManager.default.attributesOfItem(atPath: archives[0].path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.backups.path).allSatisfy { !$0.hasPrefix("updater-") })
    }

    @Test func explicitChatRecoveryUsesTheSameMigratedDatabaseRepair() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = try Data(contentsOf: fixture.database)
        let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(try Data(contentsOf: fixture.database) == original)
        #expect(fixture.commands.contains { $0.contains("--yes --json") })
        #expect(!fixture.commands.contains { $0.contains("agent ") })
    }

    @Test func healthySchemaUsesSupportedOnlineBackupAndManagedUpdate() throws {
        let fixture = try Fixture(schemaMismatch: false)
        defer { fixture.cleanUp() }
        let result = fixture.maintenance().update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(fixture.commands.contains { $0.contains("backup create") && $0.contains("--verify") })
        #expect(!fixture.commands.contains { $0.contains("npm install") || $0.contains("bootout") })
    }

    @Test func invalidConfigWithBestEffortValidStatusRequiresExplicitRepair() throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true)
        defer { fixture.cleanUp() }
        let original = try Data(contentsOf: fixture.home.appendingPathComponent(".openclaw/openclaw.json"))
        let result = fixture.maintenance().prepareGateway()
        #expect(result.state == .fail)
        #expect(ChatRecoveryPlan.classify(error: result.message).kind == .configuration)
        #expect(fixture.commands.contains { $0.contains("config validate --json") })
        #expect(!fixture.commands.contains { $0.contains("gateway start") || $0.contains("npm ") || $0.contains("doctor") })
        #expect(try Data(contentsOf: fixture.home.appendingPathComponent(".openclaw/openclaw.json")) == original)
    }

    @Test func invalidConfigUsesBackupAndNewUpdaterWithoutRunningOldDoctor() throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true)
        defer { fixture.cleanUp() }
        let original = try Data(contentsOf: fixture.database)
        let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(try Data(contentsOf: fixture.database) == original)
        #expect(try fixture.archives().count == 1)
        let registry = try #require(fixture.commands.firstIndex { $0.contains("npm view openclaw@latest version --json") })
        let backup = try #require(fixture.commands.firstIndex { $0.contains("tar -tzf") })
        let staged = try #require(fixture.commands.firstIndex { $0.contains("npm install") })
        let update = try #require(fixture.commands.firstIndex { $0.contains("--yes --json") })
        let validated = try #require(fixture.commands.lastIndex { $0.contains("config validate --json") })
        #expect(registry < backup && backup < staged && staged < update && update < validated)
        #expect(fixture.commands[registry].contains(".hermes/node/bin"))
        #expect(fixture.commands[update].contains("updater-"))
        #expect(!fixture.commands.contains { $0.contains("backup create") || $0.contains("doctor --fix") || $0.contains("agent ") })
        #expect(fixture.commands.filter { $0.contains("--dry-run") }.allSatisfy { $0.contains("updater-") })
    }

    @Test(arguments: [Failure.registryUnavailable, .invalidRegistryVersion, .downgrade])
    func untrustedOrUnavailableRecoveryTargetCannotStopOrReplaceGateway(_ failure: Failure) throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true, failure: failure)
        defer { fixture.cleanUp() }
        let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
        #expect(result.state == .fail)
        #expect(!fixture.commands.contains { $0.contains("bootout") || $0.contains("npm install") || $0.contains("--yes --json") })
    }

    @Test func configurationFromANewerReleaseIsNeverPrunedByAnOlderDoctor() throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true)
        defer { fixture.cleanUp() }
        let config = fixture.home.appendingPathComponent(".openclaw/openclaw.json")
        let original = Data(#"{"meta":{"lastTouchedVersion":"2026.9.1"}}"#.utf8)
        try original.write(to: config)
        let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
        #expect(result.state == .fail)
        #expect(result.message.contains("newer than available release"))
        #expect(try Data(contentsOf: config) == original)
        #expect(!fixture.commands.contains { $0.contains("bootout") || $0.contains("doctor") || $0.contains("--yes --json") })
    }

    @Test(arguments: [Failure.backup, .corruptArchive, .activeWriter, .wrongTarget, .downgrade, .staging])
    func preflightOrBackupFailureNeverReplacesTheRuntime(_ failure: Failure) throws {
        let fixture = try Fixture(schemaMismatch: failure != .backup, failure: failure)
        defer { fixture.cleanUp() }
        let original = try Data(contentsOf: fixture.database)
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        #expect(!fixture.commands.contains { $0.contains("--yes --json") })
        #expect(try Data(contentsOf: fixture.database) == original)
        let runtime = try OpenClawRuntimeInstallation.managed(home: fixture.home)
        #expect(runtime?.version == "2026.7.1-2")
    }

    @Test(arguments: [Failure.update, .wrongVersion, .unhealthy, .schemaRemains, .pluginWarning, .configRemains])
    func PostUpdateFailuresAreNotReportedAsSuccess(_ failure: Failure) throws {
        let fixture = try Fixture(failure: failure)
        defer { fixture.cleanUp() }
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        #expect(result.message.contains("Recovery backup:"))
        #expect(result.message.contains("No chat request was replayed"))
        #expect(try fixture.archives().count == 1)
    }

    @Test func healthRequiresGatewayVersionNotJustCLIOrPort() {
        #expect(!OpenClawRuntimeMaintenance.verifiedGateway(#"{"service":{"runtime":{"status":"running"}},"rpc":{"ok":true},"cli":{"version":"2026.8.1"},"gateway":{"version":"2026.7.1-2"}}"#, expectedVersion: "2026.8.1"))
        #expect(OpenClawRuntimeMaintenance.verifiedGateway(#"{"service":{"runtime":{"status":"running"}},"rpc":{"ok":true,"server":{"version":"2026.8.1"}}}"#, expectedVersion: "2026.8.1"))
    }

    @Test func inspectionErrorIncludesTheCauseWithoutInventingAnOwner() throws {
        let fixture = try Fixture(failure: .activeWriter)
        defer { fixture.cleanUp() }
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        #expect(result.message.contains("could not verify"))
        #expect(result.message.contains("cannot inspect open files"))
        #expect(!result.message.contains("still open in another process"))
        #expect(!fixture.commands.contains { $0.contains("tar -czf") || $0.contains("npm install") })
    }

    @Test func confirmedFileOwnerIsNamedAndNeverKilled() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.inspections = [(0, "p123\0cnode\0\nf7\0tREG\0n\(fixture.database.path)\0\n")]
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        #expect(result.message.contains("node (PID 123)"))
        #expect(result.message.contains(fixture.database.path))
        #expect(fixture.commands.filter { $0.contains("lsof") }.count == 5)
        #expect(!fixture.commands.contains { $0.contains("tar -czf") || $0.contains("npm install") || $0.contains("kill") })
    }

    @Test func transientOwnerCanExitBeforeBackup() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.inspections = [(0, "p123\0cnode\0\nf7\0tREG\0n\(fixture.database.path)\0\n"), (1, "")]
        let result = fixture.maintenance().update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(fixture.commands.filter { $0.contains("lsof") }.count == 2)
    }

    @Test func workingDirectoryAloneAllowsOfflineRecovery() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.inspections = [(0, "p123\0czsh\0\nfcwd\0tDIR\0n\(fixture.database.deletingLastPathComponent().path)\0\n")]
        let result = fixture.maintenance().update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(fixture.commands.filter { $0.contains("lsof") }.count == 1)
    }

    @Test func failedNativeBackupDoesNotLeaveAnotherLargeArchive() throws {
        let fixture = try Fixture(schemaMismatch: false, failure: .backup)
        defer { fixture.cleanUp() }
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        #expect(try fixture.archives().isEmpty)
        #expect(!fixture.commands.contains { $0.contains("npm install") || $0.contains("--yes --json") })
    }

    @Test func nativeSchemaFailureCanFallBackWithoutReusingAnIncompleteArchive() throws {
        let fixture = try Fixture(schemaMismatch: false, failure: .nativeBackupSchema)
        defer { fixture.cleanUp() }
        let result = fixture.maintenance().update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(fixture.commands.contains { $0.contains("backup create") })
        #expect(fixture.commands.contains { $0.contains("tar -czf") && $0.contains(".partial") && $0.contains("--no-recursion") })
        #expect(try fixture.archives().count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.backups.path).allSatisfy { !$0.hasSuffix(".partial") && !$0.hasSuffix(".files") })
    }

    @Test func npmLifecycleFlagsMatchSupportedNpmVersions() {
        #expect(OpenClawRuntimeMaintenance.npmLifecycleFlags(version: "10.9.3") == "")
        #expect(OpenClawRuntimeMaintenance.npmLifecycleFlags(version: "11.15.0") == "")
        #expect(OpenClawRuntimeMaintenance.npmLifecycleFlags(version: "11.16.0").contains("--allow-scripts=openclaw"))
        #expect(OpenClawRuntimeMaintenance.npmLifecycleFlags(version: "12.0.0").contains("--allow-scripts=openclaw"))
    }

    enum Failure: String, Sendable { case backup, nativeBackupSchema, corruptArchive, activeWriter, wrongTarget, downgrade, staging, update, wrongVersion, unhealthy, schemaRemains, pluginWarning, configRemains, registryUnavailable, invalidRegistryVersion }

    private final class Fixture {
        let home: URL
        let package: URL
        let database: URL
        let backups: URL
        let schemaMismatch: Bool
        let invalidConfig: Bool
        let failure: Failure?
        var commands: [String] = []
        var didUpdate = false
        var inspections: [(Int32, String)] = []

        init(schemaMismatch: Bool = true, invalidConfig: Bool = false, failure: Failure? = nil) throws {
            self.schemaMismatch = schemaMismatch
            self.invalidConfig = invalidConfig
            self.failure = failure
            home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("runtime fixture's \(UUID().uuidString)")
            package = home.appendingPathComponent(".local/lib/node_modules/openclaw")
            database = home.appendingPathComponent(".openclaw/state/openclaw.sqlite")
            backups = home.appendingPathComponent("Library/Application Support/LocalClaw/runtime-backups")
            let fm = FileManager.default
            let node = home.appendingPathComponent(".hermes/node/bin/node")
            let plist = home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.gateway.plist")
            for directory in [package, database.deletingLastPathComponent(), node.deletingLastPathComponent(), plist.deletingLastPathComponent()] {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try fm.createSymbolicLink(at: node, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
            try Data().write(to: package.appendingPathComponent("openclaw.mjs"))
            try writeVersion("2026.7.1-2")
            try Data("fixture state must survive".utf8).write(to: database)
            try Data("{\"gateway\":{\"mode\":\"local\"}}".utf8).write(to: home.appendingPathComponent(".openclaw/openclaw.json"))
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "Label": "ai.openclaw.gateway", "ProgramArguments": [node.path, package.appendingPathComponent("dist/index.js").path, "gateway", "--port", "18789"]
            ], format: .xml, options: 0)
            try data.write(to: plist)
        }

        func maintenance() -> OpenClawRuntimeMaintenance { .init(home: home, run: execute, wait: { _ in }) }
        func cleanUp() { try? FileManager.default.removeItem(at: home) }
        func archives() throws -> [URL] { try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).filter { $0.pathExtension == "gz" } }
        func writeVersion(_ version: String) throws {
            try JSONSerialization.data(withJSONObject: ["name": "openclaw", "version": version]).write(to: package.appendingPathComponent("package.json"))
        }

        func wrapService() throws {
            let plist = home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.gateway.plist")
            var root = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
            var arguments = root["ProgramArguments"] as! [String]
            arguments.insert("--max-old-space-size=4096", at: 1)
            let directory = home.appendingPathComponent(".openclaw/service-env")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let envFile = directory.appendingPathComponent("ai.openclaw.gateway.env")
            let wrapper = directory.appendingPathComponent("ai.openclaw.gateway-env-wrapper.sh")
            let quote = OpenClawRuntimeInstallation.quote
            try Data("export OPENCLAW_STATE_DIR=\(quote(home.appendingPathComponent(".openclaw").path))\nexport OPENCLAW_CONFIG_PATH=\(quote(home.appendingPathComponent(".openclaw/openclaw.json").path))\n".utf8).write(to: envFile)
            root["ProgramArguments"] = ["/bin/sh", wrapper.path, envFile.path] + arguments
            try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0).write(to: plist)
        }

        func execute(_ command: String) -> (Int32, String) {
            commands.append(command)
            do {
                if command.contains("config validate --json") {
                    if invalidConfig && !didUpdate || failure == .configRemains {
                        return (1, #"{"ok":false,"valid":false,"issues":[{"path":"meta","message":"Invalid input"},{"path":"agents.defaults","message":"Invalid input"},{"path":"memory","message":"Invalid input"}]}"#)
                    }
                    return (0, #"{"valid":true}"#)
                }
                if command.contains("npm view openclaw@latest version --json") {
                    if failure == .registryUnavailable { return (1, "registry unavailable") }
                    if failure == .invalidRegistryVersion { return (0, #""2026.8.1; unwanted-command""#) }
                    return (0, failure == .downgrade ? #""2026.6.1""# : #""2026.8.1""#)
                }
                if command.contains("--dry-run") {
                    if invalidConfig && !didUpdate && !command.contains("updater-") {
                        return (1, "OpenClaw config is invalid\nmeta: Invalid input\nagents.defaults: Invalid input\nmemory: Invalid input")
                    }
                    return (0, String(data: try JSONSerialization.data(withJSONObject: [
                        "dryRun": true, "root": failure == .wrongTarget ? "/wrong/package" : package.path,
                        "targetVersion": failure == .downgrade ? "2026.6.1" : "2026.8.1"
                    ]), encoding: .utf8)!)
                }
                if command.contains("gateway status") {
                    if invalidConfig && !didUpdate {
                        return (1, #"{"service":{"runtime":{"status":"stopped"}},"config":{"cli":{"valid":true},"daemon":{"valid":true}},"cli":{"version":"2026.7.1-2"},"rpc":{"ok":false,"error":"ECONNREFUSED"}}"#)
                    }
                    if !didUpdate && schemaMismatch || failure == .schemaRemains {
                        return (1, "Config health-state write failed: OpenClaw state database uses newer schema version 15; this OpenClaw build supports 1.")
                    }
                    return (0, #"{"service":{"runtime":{"status":"running"}},"rpc":{"ok":true},"gateway":{"version":"VERSION"}}"#.replacingOccurrences(of: "VERSION", with: failure == .unhealthy ? "2026.7.1-2" : "2026.8.1"))
                }
                if command.contains("backup create") {
                    let regex = try NSRegularExpression(pattern: #"openclaw-[0-9A-Fa-f-]+\.tar\.gz"#)
                    let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command))!
                    let name = String(command[Range(match.range, in: command)!])
                    try Data("verified archive fixture".utf8).write(to: backups.appendingPathComponent(name))
                    if failure == .backup { return (1, "backup failed") }
                    if failure == .nativeBackupSchema { return (1, "OpenClaw state database uses newer schema version 15; this OpenClaw build supports 1.") }
                    return (0, "{}")
                }
                if command.contains("launchctl") { return (0, "") }
                if command.contains("lsof") {
                    if !inspections.isEmpty { return inspections.count > 1 ? inspections.removeFirst() : inspections[0] }
                    return failure == .activeWriter ? (1, "cannot inspect open files") : (1, "")
                }
                if command.contains("tar -tzf"), failure == .corruptArchive { return (1, "archive corrupt") }
                if command.contains("/usr/bin/tar") {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    process.arguments = ["-c", command]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    process.waitUntilExit()
                    return (process.terminationStatus, "")
                }
                if command.contains("npm --version") { return (0, "12.0.0") }
                if command.contains("npm install") {
                    if failure == .staging { return (1, "download failed") }
                    let staging = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("updater-") }!
                    let cli = staging.appendingPathComponent("lib/node_modules/openclaw/openclaw.mjs")
                    try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data().write(to: cli)
                    return (0, "")
                }
                if command.contains("--yes --json") {
                    if failure == .update { return (1, "post-core repair failed") }
                    didUpdate = true
                    if failure != .wrongVersion { try writeVersion("2026.8.1") }
                    try wrapService()
                    return (0, failure == .pluginWarning ? #"{"status":"ok","postUpdate":{"plugins":{"status":"warning"}}}"# : #"{"status":"ok"}"#)
                }
                return (1, "Unexpected fixture command")
            } catch { return (1, error.localizedDescription) }
        }
    }
}
