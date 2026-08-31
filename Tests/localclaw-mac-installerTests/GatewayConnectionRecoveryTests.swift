import Foundation
import Testing

@testable import localclaw_mac_installer

extension RuntimeRecoveryTests.OpenClawRuntimeMaintenanceTests {
@Suite(.serialized)
struct GatewayConnectionRecoveryTests {
    @Test func exactCustomerErrorOffersRecoveryWithoutResending() {
      let error = #"""
        Gateway agent call connection closed; the Gateway may still be running this turn. Check `openclaw gateway status` and the session transcript before retrying or rerunning with --local, so the turn does not execute twice.
        {"ok":false,"error":{"type":"cli_error","message":"Gateway not reachable at ws://127.0.0.1:18789 (ECONNREFUSED).\nConfig: /Users/bot/.openclaw/openclaw.json"}}
        Gateway not reachable at ws://127.0.0.1:18789 (ECONNREFUSED).
        """#
      let plan = ChatRecoveryPlan.classify(error: error)
      #expect(plan.kind == .deliveryUnknown)
      #expect(plan.primaryActionLabel == "Repair Gateway")
      #expect(!plan.replaysRequestAfterRepair)
    }

    @Test func healthyServiceIsCheckedBeforeEveryRequestWithoutRestart() throws {
      let fixture = try Fixture(probes: [.healthy, .healthy])
      defer { fixture.cleanUp() }
      #expect(fixture.maintenance().prepareGateway().state == .ok)
      #expect(fixture.maintenance().prepareGateway().state == .ok)
      #expect(fixture.probeCount == 2)
      #expect(
        !fixture.commands.contains {
          $0.contains("gateway start") || $0.contains("restart") || $0.contains("install")
        })
    }

    @Test func stoppedServiceStartsOnceAndWaitsForTwoSuccessfulRPCChecks() throws {
      let fixture = try Fixture(probes: [.stopped, .warming, .healthy, .healthy])
      defer { fixture.cleanUp() }
      let result = fixture.maintenance().prepareGateway()
      #expect(result.state == .ok, Comment(rawValue: result.message))
      #expect(fixture.commands.filter { $0.contains("gateway start") }.count == 1)
      #expect(fixture.probeCount == 4)
      #expect(fixture.commands.contains { $0.contains("--require-rpc") })
      #expect(
        fixture.commands.allSatisfy {
          !$0.contains("agent ") && !$0.contains("--local") && !$0.contains("restart")
        })
    }

    @Test func successfulStartCommandCannotHideAnImmediatelyCrashingGateway() throws {
      let fixture = try Fixture(
        probes: [.stopped], startupError: "Fatal startup error: ENOSPC no space left on device")
      defer { fixture.cleanUp() }
      let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
      #expect(result.state == .fail)
      #expect(result.message.contains("ENOSPC"))
      #expect(result.message.contains("Gateway recovery stopped"))
      #expect(fixture.probeCount == 7)
      #expect(fixture.commands.filter { $0.contains("gateway start") }.count == 1)
      #expect(!fixture.commands.contains { $0.contains("npm ") || $0.contains("doctor") })
    }

    @Test func runningButUnreachableGatewayIsNeverKilledToReplayAnUncertainTask() throws {
      let fixture = try Fixture(probes: [.warming])
      defer { fixture.cleanUp() }
      let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
      #expect(result.state == .fail)
      #expect(result.message.contains("running process was left untouched"))
      #expect(fixture.commands.allSatisfy { $0.contains("gateway status") || $0.contains("config validate") })
    }

    @Test func startupFailurePreservesTheRealErrorAndNeverCallsTheModel() throws {
      let fixture = try Fixture(probes: [.stopped])
      defer { fixture.cleanUp() }
      fixture.startFailure = "launchctl bootstrap failed: Operation not permitted"
      let result = fixture.maintenance().prepareGateway()
      #expect(result.state == .fail)
      #expect(result.message.contains("Operation not permitted"))
      #expect(!fixture.commands.contains { $0.contains("agent ") })
    }

    @Test func diagnosticOnlyServiceIsNeverStartedForADifferentGatewayTarget() throws {
      let fixture = try Fixture(probes: [.diagnosticOnly])
      defer { fixture.cleanUp() }
      let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
      #expect(result.state == .fail)
      #expect(result.message.contains("different Gateway"))
      #expect(fixture.commands.count == 1)
    }

    @Test func invalidServiceNeverFallsBackToAnUnrelatedCLI() throws {
      let fixture = try Fixture(probes: [.healthy])
      defer { fixture.cleanUp() }
      let plist = fixture.home.appendingPathComponent(
        "Library/LaunchAgents/ai.openclaw.gateway.plist")
      try Data("invalid plist".utf8).write(to: plist)
      let result = fixture.maintenance().prepareGateway(allowRuntimeUpdate: true)
      #expect(result.state == .fail)
      #expect(fixture.commands.isEmpty)
      let process = Process()
      #expect(throws: (any Error).self) {
        try OpenClawRuntimeInstallation.configureCLIProcess(
          process, arguments: ["agent"], environment: ["PATH": "/opt/homebrew/bin"],
          home: fixture.home)
      }
      #expect(process.executableURL == nil)
    }

    @Test func missingServiceRequiresExplicitRepairAndBindsTheInstalledRuntime() throws {
      let fixture = try Fixture(probes: [.stopped, .healthy, .healthy])
      defer { fixture.cleanUp() }
      let plist = fixture.home.appendingPathComponent(
        "Library/LaunchAgents/ai.openclaw.gateway.plist")
      let plistData = try Data(contentsOf: plist)
      try FileManager.default.removeItem(at: plist)
      var installed = false
      let maintenance = OpenClawRuntimeMaintenance(
        home: fixture.home,
        run: { command in
          if command == "command -v openclaw" {
            return (0, fixture.package.appendingPathComponent("openclaw.mjs").path)
          }
          if command == "command -v node" {
            return (0, fixture.home.appendingPathComponent(".hermes/node/bin/node").path)
          }
          if command.contains("gateway install") {
            installed = true
            do {
              try plistData.write(to: plist)
              return (0, #"{"ok":true}"#)
            } catch { return (1, error.localizedDescription) }
          }
          return fixture.execute(command)
        }, wait: { _ in })
      #expect(maintenance.prepareGateway().state == .fail)
      #expect(!installed)
      fixture.probeCount = 0
      let result = maintenance.prepareGateway(allowRuntimeUpdate: true)
      #expect(result.state == .ok, Comment(rawValue: result.message))
      #expect(installed)
      #expect(
        fixture.commands.contains {
          $0.contains("OPENCLAW_GATEWAY_PORT=19877") && $0.contains("gateway start")
        })
      #expect(!fixture.commands.contains { $0.contains("agent ") || $0.contains("restart") })
    }

    @Test func failedStatusWithExitZeroStillBlocksSending() throws {
      let fixture = try Fixture(probes: [.falseSuccess])
      defer { fixture.cleanUp() }
      #expect(fixture.maintenance().prepareGateway().state == .fail)
    }

    @Test func transientHealthySampleDoesNotMarkACrashingServiceReady() throws {
      let fixture = try Fixture(probes: [.stopped, .healthy, .stopped])
      defer { fixture.cleanUp() }
      #expect(fixture.maintenance().prepareGateway().state == .fail)
    }

    @Test func currentSchemaFailureBlocksAgentWithoutSilentlyUpdating() throws {
      let fixture = try Fixture(probes: [.schemaMismatch])
      defer { fixture.cleanUp() }
      let result = fixture.maintenance().prepareGateway()
      #expect(result.state == .fail)
      #expect(result.message.contains("schema version 15"))
      #expect(ChatRecoveryPlan.classify(error: result.message).kind == .runtimeVersion)
      #expect(fixture.commands.count == 1)
    }

    @Test func newStartupSchemaErrorIsDetectedButStaleLogDoesNotInvalidateHealthyRPC() throws {
      let fixture = try Fixture(probes: [.stopped], startupError: Probe.schemaMismatch.output)
      defer { fixture.cleanUp() }
      let result = fixture.maintenance().prepareGateway()
      #expect(result.state == .fail)
      #expect(result.message.contains("schema version 15"))
      #expect(fixture.probeCount == 2)

      let healthy = try Fixture(probes: [.healthy])
      defer { healthy.cleanUp() }
      try Data(Probe.schemaMismatch.output.utf8).write(to: healthy.log)
      #expect(healthy.maintenance().prepareGateway().state == .ok)
    }

    @Test func newStartupConfigFailureIsKeptAsCurrentEvidence() throws {
      let fixture = try Fixture(probes: [.stopped], startupError: "OpenClaw config is invalid: agents.defaults: Invalid input")
      defer { fixture.cleanUp() }
      let result = fixture.maintenance().prepareGateway()
      #expect(result.state == .fail)
      #expect(ChatRecoveryPlan.classify(error: result.message).kind == .configuration)
      #expect(fixture.probeCount == 2)
      #expect(!fixture.commands.contains { $0.contains("npm ") })
    }

    @Test func rejectedStartIsNotLostWhenConfigValidationInitiallyPasses() throws {
      let fixture = try Fixture(probes: [.stopped])
      defer { fixture.cleanUp() }
      fixture.startFailure = "OpenClaw config is invalid\nmeta: Invalid input\nagents.defaults: Invalid input\nmemory: Invalid input"
      let result = fixture.maintenance().prepareGateway()
      #expect(result.state == .fail)
      #expect(ChatRecoveryPlan.classify(error: result.message).kind == .configuration)
      #expect(fixture.commands.contains { $0.contains("gateway start") })
    }

    @Test func diagnosticSkipsLogFilesThatHaveNotChangedRecently() throws {
      let fixture = try Fixture(probes: [.stopped])
      defer { fixture.cleanUp() }
      try Data("ERR_MODULE_NOT_FOUND May historical failure\n".utf8).write(to: fixture.log)
      try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400)], ofItemAtPath: fixture.log.path)
      let diagnostic = fixture.maintenance().gatewayDiagnostic()
      #expect(!diagnostic.contains("ERR_MODULE_NOT_FOUND"))
      #expect(ChatRecoveryPlan.classify(error: diagnostic).kind == .gateway)
    }

    @Test func readOnlyDiagnosticShowsStartupCauseAndRedactsCredentials() throws {
      let fixture = try Fixture(probes: [.stopped])
      defer { fixture.cleanUp() }
      try Data("Fatal startup error: token=sk-or-v1-1234567890abcdefghijklmnopqrstuv\n".utf8).write(
        to: fixture.log)
      let text = fixture.maintenance().gatewayDiagnostic()
      #expect(text.contains("Fatal startup error"))
      #expect(!text.contains("sk-or-v1-1234567890abcdefghijklmnopqrstuv"))
      #expect(fixture.commands.count == 1)
    }

    @Test func agentLaunchBindsServicePortAndPreservesArgumentsWithoutShellExpansion() throws {
      let fixture = try Fixture(probes: [.healthy])
      defer { fixture.cleanUp() }
      let process = Process()
      let arguments = ["agent", "--message-file", "/tmp/a 'quoted' prompt.txt"]
      try OpenClawRuntimeInstallation.configureCLIProcess(
        process, arguments: arguments, environment: ["PATH": "/opt/homebrew/bin"],
        home: fixture.home)
      #expect(process.environment?["OPENCLAW_GATEWAY_PORT"] == "19877")
      #expect(
        process.arguments == [fixture.package.appendingPathComponent("openclaw.mjs").path]
          + arguments)
      #expect(
        process.executableURL?.path
          == fixture.home.appendingPathComponent(".hermes/node/bin/node").path)
    }

    @Test func launchedClientActuallyUsesTheServiceEvenWithAnotherOpenClawOnPATH() throws {
      let fixture = try Fixture(probes: [.healthy])
      defer { fixture.cleanUp() }
      let node = fixture.home.appendingPathComponent(".hermes/node/bin/node")
      try FileManager.default.removeItem(at: node)
      try FileManager.default.createSymbolicLink(
        at: node, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
      try Data(
        "printf '%s\\n' 'SERVICE_CLIENT' \"$OPENCLAW_CONFIG_PATH\" \"$OPENCLAW_GATEWAY_PORT\" \"$@\"\n"
          .utf8
      )
      .write(to: fixture.package.appendingPathComponent("openclaw.mjs"))
      let ambient = fixture.home.appendingPathComponent("other/bin")
      try FileManager.default.createDirectory(at: ambient, withIntermediateDirectories: true)
      let wrongCLI = ambient.appendingPathComponent("openclaw")
      try Data("#!/bin/sh\nprintf 'WRONG_CLIENT'\n".utf8).write(to: wrongCLI)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrongCLI.path)
      let process = Process()
      let pipe = Pipe()
      let arguments = ["agent", "--message-file", "/tmp/prompt $(must-not-run).txt"]
      try OpenClawRuntimeInstallation.configureCLIProcess(
        process, arguments: arguments, environment: ["PATH": ambient.path + ":/usr/bin:/bin"],
        home: fixture.home)
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      try process.run()
      let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      process.waitUntilExit()
      #expect(process.terminationStatus == 0)
      #expect(output.hasPrefix("SERVICE_CLIENT\n"))
      #expect(output.contains("19877\n"))
      #expect(output.contains("/tmp/prompt $(must-not-run).txt"))
      #expect(!output.contains("WRONG_CLIENT"))
    }

    enum Probe {
      case healthy, stopped, warming, falseSuccess, schemaMismatch, diagnosticOnly
      var output: String {
        switch self {
        case .healthy:
          return
            #"{"service":{"runtime":{"status":"running"}},"rpc":{"ok":true},"gateway":{"version":"2026.8.1"}}"#
        case .stopped, .falseSuccess:
          return
            #"{"service":{"runtime":{"status":"stopped"}},"rpc":{"ok":false,"error":"ECONNREFUSED 127.0.0.1:19877"}}"#
        case .warming:
          return
            #"{"service":{"runtime":{"status":"running"}},"rpc":{"ok":false,"error":"ECONNREFUSED 127.0.0.1:19877"}}"#
        case .schemaMismatch:
          return
            "OpenClaw state database uses newer schema version 15; this OpenClaw build supports 1."
        case .diagnosticOnly:
          return
            #"{"service":{"targetRole":"diagnostic-only","runtime":{"status":"stopped"}},"rpc":{"ok":false}}"#
        }
      }
      var code: Int32 { self == .healthy || self == .falseSuccess ? 0 : 1 }
    }

    private final class Fixture {
      let home: URL
      let package: URL
      let log: URL
      let probes: [Probe]
      let startupError: String?
      var startFailure: String?
      var probeCount = 0
      var commands: [String] = []

      init(probes: [Probe], startupError: String? = nil) throws {
        self.probes = probes
        self.startupError = startupError
        home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
          .appendingPathComponent("gateway recovery \(UUID().uuidString)")
        package = home.appendingPathComponent(".local/lib/node_modules/openclaw")
        log = home.appendingPathComponent("Library/Logs/openclaw/gateway.log")
        let node = home.appendingPathComponent(".hermes/node/bin/node")
        let plist = home.appendingPathComponent("Library/LaunchAgents/ai.openclaw.gateway.plist")
        for directory in [
          package, log.deletingLastPathComponent(), node.deletingLastPathComponent(),
          plist.deletingLastPathComponent(),
        ] {
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(
          at: node, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
        try Data().write(to: package.appendingPathComponent("openclaw.mjs"))
        try JSONSerialization.data(withJSONObject: ["name": "openclaw", "version": "2026.8.1"])
          .write(to: package.appendingPathComponent("package.json"))
        try PropertyListSerialization.data(
          fromPropertyList: [
            "Label": "ai.openclaw.gateway",
            "ProgramArguments": [
              node.path, package.appendingPathComponent("dist/index.js").path, "gateway", "--port",
              "19877",
            ],
          ], format: .xml, options: 0
        ).write(to: plist)
      }

      func cleanUp() { try? FileManager.default.removeItem(at: home) }
      func maintenance() -> OpenClawRuntimeMaintenance {
        .init(home: home, run: execute, wait: { _ in })
      }
      func execute(_ command: String) -> (Int32, String) {
        commands.append(command)
        if command.contains("config validate --json") { return (0, #"{"valid":true}"#) }
        if command.contains("gateway status") {
          let probe = probes[min(probeCount, probes.count - 1)]
          probeCount += 1
          return (probe.code, probe.output)
        }
        if command.contains("gateway start") {
          if let startFailure { return (1, startFailure) }
          if let startupError { try? Data(startupError.utf8).write(to: log) }
          return (0, #"{"ok":true,"result":"started"}"#)
        }
        return (1, "Unexpected fixture command")
      }
    }
  }
}
