import Foundation
import CryptoKit
import Testing
@testable import localclaw_mac_installer

@Suite(.serialized)
struct RuntimeRecoveryTests {}

extension RuntimeRecoveryTests {
@Suite(.serialized)
struct OpenClawRuntimeMaintenanceTests {
    private let mismatch = "OpenClaw state database /Users/bot/.openclaw/state/openclaw.sqlite uses newer schema version 15; this OpenClaw build supports 1."

    private struct LegacyCheckpointFixture: Codable {
        let package: String
        let node: String
        let state: String
        let config: String
        let target: String
        let archive: String
        let archiveSize: UInt64
        let archiveModified: Date

        init(_ value: OpenClawUpdateCheckpoint) {
            package = value.package
            node = value.node
            state = value.state
            config = value.config
            target = value.target
            archive = value.archive
            archiveSize = value.archiveSize
            archiveModified = value.archiveModified
        }

        init(
            runtime: OpenClawRuntimeInstallation,
            target: String,
            archive: URL,
            size: UInt64,
            modified: Date
        ) {
            package = runtime.package.resolvingSymlinksInPath().path
            node = runtime.node.resolvingSymlinksInPath().path
            state = runtime.state.resolvingSymlinksInPath().path
            config = runtime.config.resolvingSymlinksInPath().path
            self.target = target
            self.archive = archive.path
            archiveSize = size
            archiveModified = modified
        }
    }

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
        #expect(process.environment?["OPENCLAW_CONFIG_PATH"].map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() } ==
                fixture.home.appendingPathComponent(".openclaw/openclaw.json").resolvingSymlinksInPath())
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

    @Test func managedSelectionAcceptsSymlinkEquivalentMissingStateAndConfigPaths() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let canonicalParent = fixture.home.appendingPathComponent("canonical-root", isDirectory: true)
        let aliasParent = fixture.home.appendingPathComponent("selected-root", isDirectory: true)
        let state = canonicalParent.appendingPathComponent("missing-state", isDirectory: true)
        let config = state.appendingPathComponent("openclaw.json")
        try FileManager.default.createDirectory(at: canonicalParent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasParent, withDestinationURL: canonicalParent)

        let plist = fixture.home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.gateway.plist")
        var root = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
        )
        root["EnvironmentVariables"] = [
            "OPENCLAW_STATE_DIR": state.path,
            "OPENCLAW_CONFIG_PATH": config.path,
        ]
        try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0).write(to: plist)
        #expect(!FileManager.default.fileExists(atPath: state.path))

        let runtime = try #require(try OpenClawRuntimeInstallation.managed(
            home: fixture.home,
            environment: [
                "OPENCLAW_STATE_DIR": aliasParent.appendingPathComponent("missing-state").path,
                "OPENCLAW_CONFIG_PATH": aliasParent.appendingPathComponent("missing-state/openclaw.json").path,
            ]
        ))

        #expect(runtime.state.path == state.path)
        #expect(runtime.config.path == config.path)
    }

    @Test func namedProfileUsesItsOwnStateConfigPortAndServiceIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addNamedProfile("client", port: 19789, removeDefault: true)

        let runtime = try #require(try OpenClawRuntimeInstallation.managed(
            home: fixture.home,
            environment: ["OPENCLAW_PROFILE": "client"]
        ))
        #expect(runtime.serviceLabel == "ai.openclaw.client")
        #expect(runtime.profile == "client")
        #expect(runtime.state.path == fixture.home.appendingPathComponent(".openclaw-client").path)
        #expect(runtime.config.path == fixture.home.appendingPathComponent(".openclaw-client/openclaw.json").path)
        #expect(runtime.port == 19789)
        let environment = runtime.applying(to: [:])
        #expect(environment["OPENCLAW_PROFILE"] == "client")
        #expect(environment["OPENCLAW_GATEWAY_PORT"] == "19789")
    }

    @Test func freshProfilePortAndProfileSelectorsAreValidatedBeforeConfiguration() throws {
        #expect(try OpenClawRuntimeInstallation.gatewayPort(environment: ["OPENCLAW_GATEWAY_PORT": "19999"]) == 19999)
        #expect(try OpenClawRuntimeInstallation.gatewayPort(environment: [:]) == nil)
        #expect(throws: MaintenanceError.self) {
            try OpenClawRuntimeInstallation.gatewayPort(environment: ["OPENCLAW_GATEWAY_PORT": "70000"])
        }
        #expect(throws: MaintenanceError.self) {
            try OpenClawRuntimeInstallation.selectedState(
                home: FileManager.default.temporaryDirectory,
                environment: ["OPENCLAW_PROFILE": "../another-user"]
            )
        }
    }

    @Test func newNamedProfileRequiresAnUnusedPortWhenDefaultPortIsAlreadyOccupied() throws {
        let occupied = Set([18789])

        #expect(throws: MaintenanceError.self) {
            try OpenClawRuntimeInstallation.gatewayPortForConfiguration(
                managedPort: nil,
                configuredPort: nil,
                isManaged: false,
                environment: ["OPENCLAW_PROFILE": "client"],
                occupiedPorts: occupied
            )
        }
        #expect(try OpenClawRuntimeInstallation.gatewayPortForConfiguration(
            managedPort: nil,
            configuredPort: nil,
            isManaged: false,
            environment: [
                "OPENCLAW_PROFILE": "client",
                "OPENCLAW_GATEWAY_PORT": "19789",
            ],
            occupiedPorts: occupied
        ) == 19789)
        #expect(throws: MaintenanceError.self) {
            try OpenClawRuntimeInstallation.gatewayPortForConfiguration(
                managedPort: nil,
                configuredPort: nil,
                isManaged: false,
                environment: [
                    "OPENCLAW_PROFILE": "client",
                    "OPENCLAW_GATEWAY_PORT": "18789",
                ],
                occupiedPorts: occupied
            )
        }
    }

    @Test func existingNamedProfileConfigSuppliesPortWhenItsServiceIsMissing() throws {
        let config: [String: Any] = [
            "gateway": [
                "mode": "local",
                "port": 19789,
            ],
        ]
        let configuredPort = try #require(
            try OpenClawRuntimeInstallation.configuredGatewayPort(in: config)
        )

        #expect(try OpenClawRuntimeInstallation.gatewayPortForConfiguration(
            managedPort: nil,
            configuredPort: configuredPort,
            isManaged: false,
            environment: ["OPENCLAW_PROFILE": "client"],
            occupiedPorts: Set([18789])
        ) == 19789)
    }

    @Test func installedServicePortFallsBackToItsConfigThenOpenClawDefault() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var runtime = try #require(try OpenClawRuntimeInstallation.managed(home: fixture.home))
        runtime.port = nil
        #expect(runtime.port == nil)

        let customConfig: [String: Any] = ["gateway": ["port": 19789]]
        let customData = try JSONSerialization.data(withJSONObject: customConfig)
        try customData.write(to: runtime.config, options: .atomic)
        #expect(try runtime.gatewayPortForCollisionCheck() == 19789)

        try FileManager.default.removeItem(at: runtime.config)
        #expect(try runtime.gatewayPortForCollisionCheck() == 18789)
    }

    @Test func unmanagedProfileCannotUpdateAPackageUsedByAnotherGatewayService() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let managed = try #require(try OpenClawRuntimeInstallation.managed(home: fixture.home))
        let unmanaged = try OpenClawRuntimeInstallation.resolve(
            node: managed.node,
            entry: managed.cli,
            state: fixture.home.appendingPathComponent(".openclaw-new-client"),
            config: fixture.home.appendingPathComponent(".openclaw-new-client/openclaw.json"),
            serviceLabel: nil,
            selectedProfile: "new-client"
        )
        #expect(OpenClawRuntimeMaintenance.hasUnsafeSharedRuntimeConsumer(selected: unmanaged, consumers: [managed]))
        #expect(!OpenClawRuntimeMaintenance.hasUnsafeSharedRuntimeConsumer(selected: managed, consumers: [managed]))
    }

    @Test func multipleGatewayProfilesFailClosedWithoutASelector() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.addNamedProfile("client", port: 19789)

        #expect(throws: MaintenanceError.self) {
            try OpenClawRuntimeInstallation.managed(home: fixture.home, environment: [:])
        }
        let selected = try #require(try OpenClawRuntimeInstallation.managed(
            home: fixture.home,
            environment: ["OPENCLAW_STATE_DIR": fixture.home.appendingPathComponent(".openclaw-client").path]
        ))
        #expect(selected.serviceLabel == "ai.openclaw.client")
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

    @Test(arguments: [Failure.corruptArchive, .activeWriter, .staging])
    func offlineFailureRestartsAPreviouslyLoadedGateway(_ failure: Failure) throws {
        let fixture = try Fixture(failure: failure)
        defer { fixture.cleanUp() }
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        let stopped = try #require(fixture.commands.firstIndex { $0.contains("launchctl bootout") })
        let activated = try #require(fixture.commands.lastIndex {
            $0.contains("gateway start --json") || $0.contains("gateway restart --json")
        })
        #expect(stopped < activated)
        if failure == .staging {
            #expect(fixture.commands.contains { $0.contains("gateway install --force --json") })
            #expect(fixture.commands.contains { $0.contains("gateway status --json --require-rpc") })
            #expect(result.message.contains("Gateway compensation was attempted but RPC health was not verified"))
        }
        #expect(result.message.contains("previously loaded Gateway service was restarted") ||
                result.message.contains("database was not deleted"))
    }

    @Test(arguments: [Failure.update, .wrongVersion, .unhealthy, .schemaRemains, .pluginWarning, .configRemains, .consent, .malformedResult, .wrongResultRoot, .nonzeroSuccess])
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

    @Test func automaticUpdateTargetsOnlyStableOpenClawTwoReleases() {
        #expect(!OpenClawRuntimeMaintenance.isSupportedUpdateTarget("2026.7.1-2"))
        #expect(!OpenClawRuntimeMaintenance.isSupportedUpdateTarget("2026.8.1-beta.1"))
        #expect(!OpenClawRuntimeMaintenance.isSupportedUpdateTarget("2026.8.0"))
        #expect(OpenClawRuntimeMaintenance.isSupportedUpdateTarget("2026.8.1"))
        #expect(OpenClawRuntimeMaintenance.isSupportedUpdateTarget("2026.9.0"))
    }

    @Test func registryDiskFailureStaysActionableWithoutBackingUpOrStoppingService() throws {
        let fixture = try Fixture(invalidConfig: true, failure: .registryNoSpace)
        defer { fixture.cleanUp() }
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        #expect(result.message.contains("ENOSPC"))
        #expect(result.message.contains("Storage Recovery"))
        #expect(ChatRecoveryPlan.classify(error: result.message).kind == .storage)
        #expect(!fixture.commands.contains { $0.contains("launchctl") || $0.contains("tar -czf") || $0.contains("npm install") })
    }

    @Test func offlineSpaceIsCheckedBeforeStoppingTheGateway() throws {
        let fixture = try Fixture(invalidConfig: true)
        defer { fixture.cleanUp() }
        let maintenance = OpenClawRuntimeMaintenance(home: fixture.home, run: fixture.execute, wait: { _ in }, freeBytes: { path in
            path.lastPathComponent == "runtime-backups" ? 0 : UInt64.max
        })
        let result = maintenance.update()
        #expect(result.state == .fail)
        #expect(result.message.contains("Not enough free disk space"))
        #expect(!fixture.commands.contains { $0.contains("launchctl") || $0.contains("tar -czf") || $0.contains("npm install") })
        #expect(try fixture.archives().isEmpty)
    }

    @Test func confirmedCacheCleanupAllowsRepairToResumeWithoutDeletingStateOrOldBackups() throws {
        let fixture = try Fixture(invalidConfig: true)
        defer { fixture.cleanUp() }
        let fm = FileManager.default
        let cache = fixture.home.appendingPathComponent(".npm/_cacache")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("download cache".utf8).write(to: cache.appendingPathComponent("payload"))
        try fm.createDirectory(at: fixture.backups, withIntermediateDirectories: true)
        let previous = fixture.backups.appendingPathComponent("previous.tar.gz")
        try Data("keep previous archive".utf8).write(to: previous)
        let originalState = try Data(contentsOf: fixture.database)
        let maintenance = OpenClawRuntimeMaintenance(home: fixture.home, run: fixture.execute, wait: { _ in }, freeBytes: { _ in
            fm.fileExists(atPath: cache.path) ? 0 : UInt64.max
        })
        #expect(maintenance.update().state == .fail)
        #expect(fixture.commands.isEmpty)
        #expect(maintenance.clearDownloadCache(confirmed: true).state == .ok)
        let result = maintenance.update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(fixture.didUpdate)
        #expect(try Data(contentsOf: fixture.database) == originalState)
        #expect(try Data(contentsOf: previous) == Data("keep previous archive".utf8))
        #expect(try fixture.archives().count == 2)
        #expect(!fixture.commands.contains { $0.contains("agent --") || $0.contains("rm -rf") })
    }

    @Test func legacyApprovalErrorOffersRepairWithoutReplay() {
        let error = "Legacy exec approvals exist at /Users/bot/.openclaw/exec-approvals.json. Run `openclaw doctor --fix`."
        let plan = ChatRecoveryPlan.classify(error: error)
        #expect(plan.kind == .configuration)
        #expect(!plan.replaysRequestAfterRepair)
        #expect(!OpenClawRecoveryDiagnostic.hasLegacyExecApprovals("Current unrelated error\nHistorical startup log (old):\n" + error))
    }

    @Test(arguments: ["2026.7.1-2", "2026.8.1"])
    func legacyApprovalsAreMigratedAfterBackupBeforeUpdate(_ installedVersion: String) throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true)
        defer { fixture.cleanUp() }
        try fixture.writeVersion(installedVersion)
        let source = fixture.home.appendingPathComponent(".openclaw/exec-approvals.json")
        try Data("preserve existing permissions".utf8).write(to: source)
        let result = fixture.maintenance().update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
        let backup = try #require(fixture.commands.firstIndex { $0.contains("tar -tzf") })
        let migration = try #require(fixture.commands.firstIndex { $0.contains("exec-approvals-migration.mjs") })
        let update = try #require(fixture.commands.firstIndex { $0.contains("--yes --json") })
        #expect(backup < migration && migration < update)
        #expect(fixture.commands[migration].contains("OPENCLAW_STATE_DIR="))
        #expect(fixture.commands[migration].contains("updater-") == (installedVersion != "2026.8.1"))
        #expect(fixture.commands.contains { $0.contains("npm install") } == (installedVersion != "2026.8.1"))
        #expect(try fixture.archives().count == 1)
        #expect(fixture.commands.filter { $0.contains("--yes --json") }.count == 1)
        #expect(!fixture.commands.contains { $0.contains("agent --") || $0.contains("approvals set") || $0.contains("doctor --fix") })
    }

    @Test(arguments: [Failure.approvalsMigration, .unverifiedApprovalsMigration, .activeWriter])
    func migrationFailureKeepsPermissionsAndNeverActivatesUpdate(_ failure: Failure) throws {
        let fixture = try Fixture(schemaMismatch: false, failure: failure)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        let source = fixture.home.appendingPathComponent(".openclaw/exec-approvals.json")
        let original = Data("preserve existing permissions".utf8)
        try original.write(to: source)
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        #expect(try Data(contentsOf: source) == original)
        #expect(!fixture.commands.contains { $0.contains("--yes --json") })
        if failure != .activeWriter { #expect(result.message.contains("Recovery backup:")) }
    }

    @Test func healthyRPCDoesNotHideLegacyApprovalGateOrAuthorizeAutomaticMigration() throws {
        let fixture = try Fixture(schemaMismatch: false)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        try Data("permissions".utf8).write(to: fixture.home.appendingPathComponent(".openclaw/exec-approvals.json"))
        let result = fixture.maintenance().prepareGateway()
        #expect(result.state == .fail)
        #expect(result.message.contains("Legacy exec approvals"))
        #expect(fixture.commands.count == 1)
        #expect(fixture.maintenance().execApprovalsNeedMigration())
        let repaired = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
        #expect(repaired.state == .ok, Comment(rawValue: repaired.message))
    }

    @Test(arguments: ["2026.7.1-2", "2026.8.1"])
    func missingRepairResourceStopsBeforeBackupStagingMigrationOrServiceChanges(_ version: String) throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true)
        defer { fixture.cleanUp() }
        try fixture.writeVersion(version)
        let approvals = fixture.home.appendingPathComponent(".openclaw/exec-approvals.json")
        let original = Data("preserve existing permissions".utf8)
        try original.write(to: approvals)
        let maintenance = OpenClawRuntimeMaintenance(home: fixture.home, run: fixture.execute, wait: { _ in },
            migrationHelper: { throw MaintenanceError(OpenClawRecoveryResources.failureMessage) })
        let result = maintenance.update()
        #expect(result.state == .fail)
        #expect(result.message.contains("LocalClaw repair resource"))
        #expect(ChatRecoveryPlan.classify(error: result.message).kind == .appResources)
        #expect(!FileManager.default.fileExists(atPath: fixture.backups.path))
        #expect(try Data(contentsOf: approvals) == original)
        #expect(!fixture.commands.contains {
            $0.contains("backup create") || $0.contains("tar ") || $0.contains("npm install") ||
            $0.contains("launchctl") || $0.contains("--yes --json") || $0.contains("exec-approvals-migration.mjs")
        })
    }

    @Test func maintenanceWithoutLegacyApprovalsDoesNotRequireMigrationResource() throws {
        let fixture = try Fixture(schemaMismatch: false)
        defer { fixture.cleanUp() }
        let maintenance = OpenClawRuntimeMaintenance(home: fixture.home, run: fixture.execute, wait: { _ in },
            migrationHelper: { throw MaintenanceError("Unexpected helper lookup") })
        let result = maintenance.update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
    }

    @Test func installedCoreUsesPostUpdateRepairThenExplicitActivation() throws {
        let fixture = try Fixture(schemaMismatch: false)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        let result = fixture.maintenance().update()
        #expect(result.state == .ok, Comment(rawValue: result.message))
        let repair = try #require(fixture.commands.firstIndex { $0.contains("update repair --yes --json") })
        let install = try #require(fixture.commands.firstIndex { $0.contains("gateway install --force --json") })
        let restart = try #require(fixture.commands.firstIndex { $0.contains("gateway restart --json") })
        #expect(repair < install && install < restart)
        #expect(fixture.commands.suffix(from: restart).filter { $0.contains("gateway status") }.count == 2)
        #expect(!fixture.commands.contains { $0.contains("npm install") || ($0.contains("update --tag") && $0.contains("--yes")) })
    }

    @Test func invalidSelectedProfileRepairsSharedCurrentCoreWithoutMutatingPeerProfile() throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true, failure: .newerRegistry)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        try fixture.addNamedProfile("client", port: 19789)
        let packageManifest = fixture.package.appendingPathComponent("package.json")
        let peerState = fixture.home.appendingPathComponent(".openclaw-client")
        let peerConfig = peerState.appendingPathComponent("openclaw.json")
        let peerMarker = peerState.appendingPathComponent("state/peer.sqlite")
        let peerPlist = fixture.home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.client.plist")
        try FileManager.default.createDirectory(at: peerMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("peer state must not change".utf8).write(to: peerMarker)
        let originalPeerConfig = try Data(contentsOf: peerConfig)
        let originalPeerMarker = try Data(contentsOf: peerMarker)
        let originalPeerPlist = try Data(contentsOf: peerPlist)
        let originalPackageManifest = try Data(contentsOf: packageManifest)

        let result = fixture.maintenance(environment: ["OPENCLAW_PROFILE": "default"]).update()

        #expect(result.state == .ok, Comment(rawValue: result.message))
        let backup = try #require(fixture.commands.firstIndex { $0.contains("/usr/bin/tar -czf") })
        let repair = try #require(fixture.commands.firstIndex { $0.contains("update repair --yes --json") })
        #expect(backup < repair)
        #expect(fixture.commands[repair].contains("OPENCLAW_SERVICE_REPAIR_POLICY=external"))
        let selectedState = fixture.home.appendingPathComponent(".openclaw").path
        #expect(fixture.commands[repair].contains(
            "OPENCLAW_STATE_DIR=\(OpenClawRuntimeInstallation.quote(selectedState))"
        ))
        #expect(fixture.commands[repair].contains("OPENCLAW_LAUNCHD_LABEL='ai.openclaw.gateway'"))
        #expect(!fixture.commands.contains { $0.contains("npm install") || ($0.contains("update --tag") && $0.contains("--yes --json")) })
        #expect(!fixture.commands.contains { $0.contains("npm view openclaw@latest") || $0.contains("--dry-run") })
        #expect(!fixture.commands.contains { $0.contains("ai.openclaw.client") })
        #expect(try fixture.archives().count == 1)
        #expect(try Data(contentsOf: peerConfig) == originalPeerConfig)
        #expect(try Data(contentsOf: peerMarker) == originalPeerMarker)
        #expect(try Data(contentsOf: peerPlist) == originalPeerPlist)
        #expect(try Data(contentsOf: packageManifest) == originalPackageManifest)
    }

    @Test func sharedRuntimeStillBlocksCoreUpgradeBeforeBackupOrServiceMutation() throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true)
        defer { fixture.cleanUp() }
        try fixture.addNamedProfile("client", port: 19789)

        let result = fixture.maintenance(environment: ["OPENCLAW_PROFILE": "default"]).update()

        #expect(result.state == .fail)
        #expect(result.message.contains("shared core"))
        #expect(!FileManager.default.fileExists(atPath: fixture.backups.path))
        #expect(!fixture.commands.contains {
            $0.contains("/usr/bin/tar") || $0.contains("npm install") ||
                $0.contains("--yes --json") || $0.contains("launchctl") ||
                $0.contains("gateway install") || $0.contains("gateway restart")
        })
    }

    @Test func samePackageWithDifferentNodeStillCountsAsSharedCoreAndBlocksUpgrade() throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true)
        defer { fixture.cleanUp() }
        let alternateNode = fixture.home.appendingPathComponent("alternate-node/bin/node")
        try FileManager.default.createDirectory(
            at: alternateNode.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: alternateNode, withDestinationURL: URL(fileURLWithPath: "/usr/bin/false")
        )
        try fixture.addNamedProfile("client", port: 19789, node: alternateNode)
        let selected = try #require(try OpenClawRuntimeInstallation.managed(
            home: fixture.home, environment: ["OPENCLAW_PROFILE": "default"]
        ))
        let consumers = try OpenClawRuntimeInstallation.installedGatewayServices(home: fixture.home)
        #expect(OpenClawRuntimeMaintenance.hasUnsafeSharedRuntimeConsumer(
            selected: selected, consumers: consumers
        ))

        let result = fixture.maintenance(environment: ["OPENCLAW_PROFILE": "default"]).update()

        #expect(result.state == .fail)
        #expect(result.message.contains("shared core"))
        #expect(!FileManager.default.fileExists(atPath: fixture.backups.path))
        #expect(!fixture.commands.contains {
            $0.contains("update repair") || $0.contains("npm install") ||
                $0.contains("--yes --json") || $0.contains("launchctl")
        })
    }

    @Test func sharedRuntimeDoesNotRunRepairOnlyForHealthyConfiguration() throws {
        let fixture = try Fixture(schemaMismatch: false)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        try fixture.addNamedProfile("client", port: 19789)

        let result = fixture.maintenance(environment: ["OPENCLAW_PROFILE": "default"]).update()

        #expect(result.state == .fail)
        #expect(result.message.contains("shared core"))
        #expect(!FileManager.default.fileExists(atPath: fixture.backups.path))
        #expect(!fixture.commands.contains {
            $0.contains("update repair") || $0.contains("npm install") ||
                $0.contains("--yes --json") || $0.contains("launchctl")
        })
    }

    @Test func sharedRuntimeRejectsRepairWhenAnotherProfileStateOverlapsSelection() throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        try fixture.addNamedProfile("client", port: 19789)
        let overlappingState = fixture.home.appendingPathComponent(".openclaw/client-profile")
        let overlappingConfig = overlappingState.appendingPathComponent("openclaw.json")
        try FileManager.default.createDirectory(at: overlappingState, withIntermediateDirectories: true)
        try Data(#"{"gateway":{"mode":"local","port":19789}}"#.utf8).write(to: overlappingConfig)
        let plist = fixture.home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.client.plist")
        var root = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
        )
        var serviceEnvironment = try #require(root["EnvironmentVariables"] as? [String: String])
        serviceEnvironment["OPENCLAW_STATE_DIR"] = overlappingState.path
        serviceEnvironment["OPENCLAW_CONFIG_PATH"] = overlappingConfig.path
        root["EnvironmentVariables"] = serviceEnvironment
        try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0).write(to: plist)
        let originalPeerConfig = try Data(contentsOf: overlappingConfig)
        let originalPeerPlist = try Data(contentsOf: plist)

        let result = fixture.maintenance(environment: ["OPENCLAW_PROFILE": "default"]).update()

        #expect(result.state == .fail)
        #expect(result.message.contains("overlapping states"))
        #expect(!FileManager.default.fileExists(atPath: fixture.backups.path))
        #expect(!fixture.commands.contains {
            $0.contains("update repair") || $0.contains("/usr/bin/tar") || $0.contains("launchctl")
        })
        #expect(try Data(contentsOf: overlappingConfig) == originalPeerConfig)
        #expect(try Data(contentsOf: plist) == originalPeerPlist)
    }

    @Test func sharedRuntimeRejectsRepairResultWithoutFinalizeOnlyProof() throws {
        let fixture = try Fixture(
            schemaMismatch: false, invalidConfig: true, failure: .wrongRepairMode
        )
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        try fixture.addNamedProfile("client", port: 19789)
        let packageManifest = fixture.package.appendingPathComponent("package.json")
        let originalPackageManifest = try Data(contentsOf: packageManifest)

        let result = fixture.maintenance(environment: ["OPENCLAW_PROFILE": "default"]).update()

        #expect(result.state == .fail)
        #expect(result.message.contains("finalize-only mode"))
        #expect(fixture.commands.contains { $0.contains("update repair --yes --json") })
        #expect(!fixture.commands.contains { $0.contains("npm install") })
        #expect(try Data(contentsOf: packageManifest) == originalPackageManifest)
    }

    @Test func pluginConsentSurvivesRelaunchAndReusesBackupWithoutCoreReinstall() throws {
        let fixture = try Fixture(failure: .consent)
        defer { fixture.cleanUp() }
        let first = fixture.maintenance().update()
        #expect(first.state == .fail)
        #expect(ChatRecoveryPlan.classify(error: first.message).kind == .pluginPermissions)
        let runtime = try #require(try OpenClawRuntimeInstallation.managed(home: fixture.home))
        #expect(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: runtime) != nil)
        let script = try OpenClawPluginReview.prepare(home: fixture.home, runtime: runtime)
        #expect((try FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        fixture.commands.removeAll()
        #expect(fixture.maintenance().prepareGateway().state == .fail)
        #expect(fixture.commands.isEmpty)
        fixture.failure = nil
        let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
        #expect(result.state == .ok, Comment(rawValue: result.message))
        #expect(try fixture.archives().count == 1)
        #expect(!fixture.maintenance().hasPendingUpdate())
        #expect(fixture.commands.contains { $0.contains("update repair --yes --json") })
        #expect(!fixture.commands.contains { $0.contains("backup create") || $0.contains("npm ") || $0.contains("--dry-run") || $0.contains("tar ") || $0.contains("--accept-capabilities") })
    }

    @Test func sharedRuntimeResumesVerifiedConsentCheckpointWithoutCoreOrPeerMutation() throws {
        let fixture = try Fixture(schemaMismatch: false, invalidConfig: true, failure: .consent)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        try fixture.addNamedProfile("client", port: 19789)
        let peerConfig = fixture.home.appendingPathComponent(".openclaw-client/openclaw.json")
        let peerPlist = fixture.home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.client.plist")
        let packageManifest = fixture.package.appendingPathComponent("package.json")
        let originalPeerConfig = try Data(contentsOf: peerConfig)
        let originalPeerPlist = try Data(contentsOf: peerPlist)
        let originalPackageManifest = try Data(contentsOf: packageManifest)
        let maintenance = fixture.maintenance(environment: ["OPENCLAW_PROFILE": "default"])

        let first = maintenance.update()
        #expect(first.state == .fail)
        #expect(ChatRecoveryPlan.classify(error: first.message).kind == .pluginPermissions)
        #expect(maintenance.hasPendingUpdate())
        #expect(try fixture.archives().count == 1)

        fixture.commands.removeAll()
        fixture.failure = nil
        let resumed = maintenance.update()

        #expect(resumed.state == .ok, Comment(rawValue: resumed.message))
        #expect(!maintenance.hasPendingUpdate())
        let repair = try #require(fixture.commands.first { $0.contains("update repair --yes --json") })
        #expect(repair.contains("OPENCLAW_SERVICE_REPAIR_POLICY=external"))
        #expect(!fixture.commands.contains {
            $0.contains("npm view") || $0.contains("npm install") ||
                $0.contains("--dry-run") || $0.contains("/usr/bin/tar")
        })
        #expect(try fixture.archives().count == 1)
        #expect(try Data(contentsOf: peerConfig) == originalPeerConfig)
        #expect(try Data(contentsOf: peerPlist) == originalPeerPlist)
        #expect(try Data(contentsOf: packageManifest) == originalPackageManifest)
    }

    @Test func resumedCheckpointFailureCompensatesServiceAndVerifiesRPC() throws {
        let fixture = try Fixture(failure: .consent)
        defer { fixture.cleanUp() }
        #expect(fixture.maintenance().update().state == .fail)
        #expect(fixture.maintenance().hasPendingUpdate())

        fixture.commands.removeAll()
        fixture.failure = .restart
        let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)

        #expect(result.state == .fail)
        #expect(fixture.commands.filter { $0.contains("gateway install --force --json") }.count == 2)
        #expect(fixture.commands.filter { $0.contains("gateway restart --json") }.count == 2)
        #expect(fixture.commands.contains { $0.contains("gateway start --json") })
        #expect(result.message.contains("service was reinstalled and RPC health was verified"))
        #expect(fixture.maintenance().hasPendingUpdate())
    }

    @Test func changedOrMissingBackupCannotBeReused() throws {
        let fixture = try Fixture(failure: .pluginWarning)
        defer { fixture.cleanUp() }
        #expect(fixture.maintenance().update().state == .fail)
        let runtime = try #require(try OpenClawRuntimeInstallation.managed(home: fixture.home))
        let checkpoint = try #require(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: runtime))
        let archive = URL(fileURLWithPath: checkpoint.archive)
        let original = try Data(contentsOf: archive)
        let modified = try #require(try FileManager.default.attributesOfItem(atPath: archive.path)[.modificationDate] as? Date)
        var tampered = original
        tampered[0] ^= 0xff
        try tampered.write(to: archive)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: archive.path)
        #expect((try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber)?.uint64Value == checkpoint.archiveSize)
        #expect(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: runtime) == nil)
        #expect(throws: MaintenanceError.self) { try OpenClawPluginReview.prepare(home: fixture.home, runtime: runtime) }
    }

    @Test func legacyGlobalCheckpointMigratesToScopedDigestAndResumesWithoutAnotherBackup() throws {
        let fixture = try Fixture(failure: .consent)
        defer { fixture.cleanUp() }
        let maintenance = fixture.maintenance()
        #expect(maintenance.update().state == .fail)
        let runtime = try #require(try OpenClawRuntimeInstallation.managed(home: fixture.home))
        let scoped = OpenClawUpdateCheckpoint.location(home: fixture.home, runtime: runtime)
        let current = try JSONDecoder().decode(
            OpenClawUpdateCheckpoint.self,
            from: Data(contentsOf: scoped)
        )
        let legacy = fixture.backups.appendingPathComponent("pending-update.json")
        try JSONEncoder().encode(LegacyCheckpointFixture(current)).write(to: legacy, options: .atomic)
        try FileManager.default.removeItem(at: scoped)

        let migrated = try #require(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: runtime))
        let expectedDigest = SHA256.hash(
            data: try Data(contentsOf: URL(fileURLWithPath: migrated.archive))
        ).map { String(format: "%02x", $0) }.joined()
        #expect(migrated.archiveSHA256 == expectedDigest)
        #expect(migrated.archiveSHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil)
        #expect(FileManager.default.fileExists(atPath: scoped.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))

        fixture.commands.removeAll()
        fixture.failure = nil
        let resumed = maintenance.update()
        #expect(resumed.state == .ok, Comment(rawValue: resumed.message))
        #expect(try fixture.archives().count == 1)
        #expect(fixture.commands.contains { $0.contains("update repair --yes --json") })
        #expect(!fixture.commands.contains {
            $0.contains("npm view") || $0.contains("npm install") ||
                $0.contains("--dry-run") || $0.contains("/usr/bin/tar")
        })
    }

    @Test func corruptScopedCheckpointNeverFallsBackToValidLegacyCheckpoint() throws {
        let fixture = try Fixture(schemaMismatch: false)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        let runtime = try #require(try OpenClawRuntimeInstallation.managed(home: fixture.home))
        try FileManager.default.createDirectory(at: fixture.backups, withIntermediateDirectories: true)
        let archive = fixture.backups.appendingPathComponent("verified.tar.gz")
        try Data("verified backup".utf8).write(to: archive)
        try OpenClawUpdateCheckpoint.save(
            home: fixture.home,
            runtime: runtime,
            target: try #require(runtime.version),
            archive: archive
        )
        let scoped = OpenClawUpdateCheckpoint.location(home: fixture.home, runtime: runtime)
        let current = try JSONDecoder().decode(
            OpenClawUpdateCheckpoint.self,
            from: Data(contentsOf: scoped)
        )
        let legacy = fixture.backups.appendingPathComponent("pending-update.json")
        try JSONEncoder().encode(LegacyCheckpointFixture(current)).write(to: legacy, options: .atomic)
        try Data("{}".utf8).write(to: scoped, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scoped.path)

        #expect(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: runtime) == nil)
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func legacyCheckpointRejectsArchiveOutsideBackupDirectoryWithoutMutation() throws {
        let fixture = try Fixture(schemaMismatch: false)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        let runtime = try #require(try OpenClawRuntimeInstallation.managed(home: fixture.home))
        try FileManager.default.createDirectory(at: fixture.backups, withIntermediateDirectories: true)
        let archive = fixture.home.appendingPathComponent("outside-backup.tar.gz")
        try Data("outside".utf8).write(to: archive)
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        let size = try #require(attributes[.size] as? NSNumber).uint64Value
        let modified = try #require(attributes[.modificationDate] as? Date)
        let legacy = fixture.backups.appendingPathComponent("pending-update.json")
        try JSONEncoder().encode(LegacyCheckpointFixture(
            runtime: runtime,
            target: try #require(runtime.version),
            archive: archive,
            size: size,
            modified: modified
        )).write(to: legacy, options: .atomic)

        #expect(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: runtime) == nil)
        #expect(!FileManager.default.fileExists(
            atPath: OpenClawUpdateCheckpoint.location(home: fixture.home, runtime: runtime).path
        ))
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func failedGatewayRestartKeepsCheckpointAndDoesNotClaimSuccess() throws {
        let fixture = try Fixture(schemaMismatch: false, failure: .restart)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        let result = fixture.maintenance().update()
        #expect(result.state == .fail)
        #expect(result.message.contains("Restart repaired Gateway failed"))
        #expect(fixture.maintenance().hasPendingUpdate())
    }

    @Test func pendingUpdateCheckpointsAreNamespacedByRuntimeIdentity() throws {
        let fixture = try Fixture(schemaMismatch: false)
        defer { fixture.cleanUp() }
        try fixture.writeVersion("2026.8.1")
        let first = try #require(try OpenClawRuntimeInstallation.managed(home: fixture.home))
        let second = try OpenClawRuntimeInstallation.resolve(
            node: first.node,
            entry: first.cli,
            state: fixture.home.appendingPathComponent(".openclaw-client"),
            config: fixture.home.appendingPathComponent(".openclaw-client/openclaw.json"),
            serviceLabel: "ai.openclaw.client",
            selectedProfile: "client"
        )
        try FileManager.default.createDirectory(at: fixture.backups, withIntermediateDirectories: true)
        let firstArchive = fixture.backups.appendingPathComponent("first.tar.gz")
        let secondArchive = fixture.backups.appendingPathComponent("second.tar.gz")
        try Data("first verified backup".utf8).write(to: firstArchive)
        try Data("second verified backup".utf8).write(to: secondArchive)

        try OpenClawUpdateCheckpoint.save(home: fixture.home, runtime: first, target: "2026.8.1", archive: firstArchive)
        try OpenClawUpdateCheckpoint.save(home: fixture.home, runtime: second, target: "2026.8.1", archive: secondArchive)

        #expect(OpenClawUpdateCheckpoint.location(home: fixture.home, runtime: first) !=
                OpenClawUpdateCheckpoint.location(home: fixture.home, runtime: second))
        #expect(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: first)?.archive == firstArchive.resolvingSymlinksInPath().path)
        #expect(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: second)?.archive == secondArchive.resolvingSymlinksInPath().path)

        try OpenClawUpdateCheckpoint.remove(home: fixture.home, runtime: first)
        #expect(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: first) == nil)
        #expect(OpenClawUpdateCheckpoint.load(home: fixture.home, runtime: second) != nil)
    }

    enum Failure: String, Sendable { case backup, nativeBackupSchema, corruptArchive, activeWriter, wrongTarget, downgrade, staging, update, wrongVersion, unhealthy, schemaRemains, pluginWarning, configRemains, registryUnavailable, registryNoSpace, invalidRegistryVersion, newerRegistry, approvalsMigration, unverifiedApprovalsMigration, consent, malformedResult, wrongRepairMode, wrongResultRoot, nonzeroSuccess, restart }

    private final class Fixture {
        let home: URL
        let package: URL
        let database: URL
        let backups: URL
        let schemaMismatch: Bool
        let invalidConfig: Bool
        var failure: Failure?
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

        func maintenance(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> OpenClawRuntimeMaintenance {
            .init(home: home, environment: environment, run: execute, wait: { _ in })
        }
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

        func addNamedProfile(_ name: String, port: Int, removeDefault: Bool = false,
                             node alternateNode: URL? = nil) throws {
            let fm = FileManager.default
            let node = alternateNode ?? home.appendingPathComponent(".hermes/node/bin/node")
            let state = home.appendingPathComponent(".openclaw-\(name)")
            try fm.createDirectory(at: state, withIntermediateDirectories: true)
            try Data("{\"gateway\":{\"mode\":\"local\",\"port\":\(port)}}".utf8)
                .write(to: state.appendingPathComponent("openclaw.json"))
            let label = "ai.openclaw.\(name)"
            let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
            let data = try PropertyListSerialization.data(fromPropertyList: [
                "Label": label,
                "EnvironmentVariables": [
                    "OPENCLAW_PROFILE": name,
                    "OPENCLAW_STATE_DIR": state.path,
                    "OPENCLAW_CONFIG_PATH": state.appendingPathComponent("openclaw.json").path,
                    "OPENCLAW_GATEWAY_PORT": String(port),
                ],
                "ProgramArguments": [node.path, package.appendingPathComponent("dist/index.js").path, "gateway", "--port", String(port)],
            ], format: .xml, options: 0)
            try data.write(to: plist)
            if removeDefault {
                try fm.removeItem(at: home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.gateway.plist"))
            }
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
                    if failure == .registryNoSpace { return (1, "npm error code ENOSPC\nnpm error path /Users/bot/.npm/_cacache/tmp/example\nno space left on device") }
                    if failure == .registryUnavailable { return (1, "registry unavailable") }
                    if failure == .invalidRegistryVersion { return (0, #""2026.8.1; unwanted-command""#) }
                    if failure == .newerRegistry { return (0, #""2026.9.0""#) }
                    return (0, failure == .downgrade ? #""2026.6.1""# : #""2026.8.1""#)
                }
                if command.contains("--dry-run") {
                    if invalidConfig && !didUpdate && !command.contains("updater-") &&
                        (try? OpenClawRuntimeInstallation.managed(home: home))?.version != "2026.8.1" {
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
                if command.contains("gateway start --json") { return (0, #"{"ok":true}"#) }
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
                if command.contains("gateway install --force --json") { return (0, #"{"ok":true}"#) }
                if command.contains("gateway restart --json") { return failure == .restart ? (1, "restart refused") : (0, #"{"ok":true}"#) }
                if command.contains("exec-approvals-migration.mjs") {
                    if failure == .approvalsMigration { return (1, "Preserved malformed legacy exec approvals for operator recovery.") }
                    if failure != .unverifiedApprovalsMigration {
                        try FileManager.default.removeItem(at: home.appendingPathComponent(".openclaw/exec-approvals.json"))
                    }
                    return (0, String(data: try JSONSerialization.data(withJSONObject: [
                        "ok": true, "version": "2026.8.1", "stateDir": home.appendingPathComponent(".openclaw").path
                    ]), encoding: .utf8)!)
                }
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
                    if !command.contains("update repair"), failure != .wrongVersion {
                        try writeVersion("2026.8.1")
                    }
                    if !command.contains("update repair") { try wrapService() }
                    if failure == .malformedResult { return (0, #"{"status":"ok"}"#) }
                    var result: [String: Any] = ["status": "ok", "mode": "npm", "root": failure == .wrongResultRoot ? "/wrong/package" : package.path, "steps": []]
                    if command.contains("update repair"), failure != .wrongRepairMode {
                        result["mode"] = "finalize"
                        result.removeValue(forKey: "steps")
                        result["restart"] = false
                        result["phaseTimings"] = [["phase": "doctor", "outcome": "completed", "durationMs": 42]]
                        result["postUpdate"] = ["doctor": ["status": "ok"], "plugins": ["status": "ok"]]
                    }
                    if failure == .pluginWarning { result["postUpdate"] = ["plugins": ["status": "warning"]] }
                    if failure == .consent {
                        result["postUpdate"] = ["plugins": ["status": "warning", "npm": ["outcomes": [["pluginId": "codex", "status": "error", "code": "PLUGIN_CAPABILITY_CONSENT_REQUIRED"]]]]]
                    }
                    let diagnostic = #"Doctor: openclaw config set commands.ownerAllowFrom '["telegram:123456789"]'"#
                    return (failure == .nonzeroSuccess ? 1 : 0, diagnostic + "\n" + String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
                }
                return (1, "Unexpected fixture command")
            } catch { return (1, error.localizedDescription) }
        }
    }
}
}
