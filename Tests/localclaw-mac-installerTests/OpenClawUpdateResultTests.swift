import Foundation
import Testing
@testable import localclaw_mac_installer

struct OpenClawUpdateResultTests {
    @Test func doctorExamplesAndNestedSuccessDoNotReplaceFinalEnvelope() throws {
        let transcript = #"openclaw config set commands.ownerAllowFrom '["telegram:123456789"]'"# + "\n" +
            #"{"status":"ok","step":"doctor"}"# + "\n" +
            #"{"status":"ok","mode":"npm","root":"/fixture/openclaw","steps":[{"stdoutTail":"quoted { and \\"}],"postUpdate":{"plugins":{"status":"warning","npm":{"outcomes":[{"pluginId":"codex","status":"error","code":"PLUGIN_CAPABILITY_CONSENT_REQUIRED"}]}}}}"#
        let result = try #require(OpenClawUpdateResult.envelope(in: transcript))
        #expect(result["root"] as? String == "/fixture/openclaw")
        #expect(OpenClawUpdateResult.pluginFailure(in: result)?.contains("Plugin approval required") == true)
    }

    @Test func finalErrorCannotBeHiddenByEarlierSuccess() throws {
        let output = #"{"status":"ok","mode":"npm","root":"/fixture","steps":[]}"# + "\n" +
            #"{"status":"error","mode":"unknown","root":"/fixture","steps":[]}"#
        #expect(OpenClawUpdateResult.envelope(in: output)?["status"] as? String == "error")
        #expect(OpenClawUpdateResult.envelope(in: #"[{"status":"ok","mode":"npm","root":"/fixture","steps":[]}]"#) == nil)
        #expect(OpenClawUpdateResult.envelope(in: #"{"status":"ok"}"#) == nil)
    }

    @Test func nativeRepairUsesFinalizeEnvelopeWithoutSteps() {
        let output = #"{"status":"ok","mode":"finalize","root":"/fixture","restart":false,"phaseTimings":[{"phase":"doctor","outcome":"completed"}],"postUpdate":{"doctor":{"status":"ok"},"plugins":{"status":"ok"}}}"#
        #expect(OpenClawUpdateResult.envelope(in: output)?["mode"] as? String == "finalize")
        #expect(OpenClawUpdateResult.envelope(in: output)?["steps"] == nil)
    }

    @Test func capabilityWarningUsesExplicitReviewWithoutReplay() {
        let text = "Plugin codex requires capability consent; rerun with --accept-capabilities."
        let plan = ChatRecoveryPlan.classify(error: text)
        #expect(plan.kind == .pluginPermissions)
        #expect(!plan.replaysRequestAfterRepair)
        #expect(plan.primaryActionLabel == "Review Plugin Permissions")
        #expect(ChatRecoveryPlan.classify(error: "OpenClaw post-update repair is pending.").kind == .gateway)
    }

    @Test func terminalReviewIsInteractiveAndDefersGatewayLifecycleToLocalClaw() {
        let runtime = OpenClawRuntimeInstallation(node: URL(fileURLWithPath: "/tmp/user's node/bin/node"),
            package: URL(fileURLWithPath: "/tmp/runtime/lib/node_modules/openclaw"),
            prefix: URL(fileURLWithPath: "/tmp/runtime"), state: URL(fileURLWithPath: "/tmp/state"),
            config: URL(fileURLWithPath: "/tmp/config.json"), serviceLabel: "ai.openclaw.gateway")
        let script = OpenClawPluginReview.script(
            runtime: runtime,
            expectedVersion: "2026.8.1",
            statusURL: URL(fileURLWithPath: "/tmp/review status"),
            successReceipt: "success:fixture-receipt"
        )
        #expect(script.contains("update repair --timeout 600"))
        #expect(script.contains("OPENCLAW_STATE_DIR='/tmp/state'"))
        #expect(script.contains("OPENCLAW_SERVICE_REPAIR_POLICY=external"))
        #expect(script.contains("user'\\''s node"))
        #expect(!script.contains("--accept-capabilities"))
        #expect(!script.contains("--yes") && !script.contains("--json"))
        #expect(!script.contains("gateway stop") && !script.contains("gateway restart") && !script.contains("agent --"))
        #expect(script.contains("success:fixture-receipt"))
        #expect(script.contains("write_status running"))
        #expect(script.contains("write_status \"failed:${code}\""))
    }

    @Test func terminalReviewUnlockReceiptRequiresSuccessfulOpenClawRepair() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugin-review-fixture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let node = home.appendingPathComponent("bin/node")
        let package = home.appendingPathComponent("lib/node_modules/openclaw")
        try FileManager.default.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["name": "openclaw", "version": "2026.8.2"])
            .write(to: package.appendingPathComponent("package.json"))
        try Data().write(to: package.appendingPathComponent("openclaw.mjs"))
        let runtime = OpenClawRuntimeInstallation(
            node: node, package: package, prefix: home,
            state: home.appendingPathComponent("state"),
            config: home.appendingPathComponent("state/openclaw.json"),
            serviceLabel: "ai.openclaw.gateway"
        )
        func writeNode(exitCode: Int) throws {
            let body = """
            #!/bin/zsh
            if [[ "$1" == "-p" ]]; then
              printf '%s\\n' '2026.8.2'
              exit 0
            fi
            if [[ "${OPENCLAW_SERVICE_REPAIR_POLICY:-}" != "external" ]]; then
              printf '%s\\n' 'Doctor contended with the LocalClaw-owned Gateway.' >&2
              exit 19
            fi
            exit \(exitCode)
            """
            try Data(body.utf8).write(to: node, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: node.path)
        }

        try writeNode(exitCode: 0)
        let success = try OpenClawPluginReview.prepare(home: home, runtime: runtime)
        let successResult = InstallerEngine().maintenanceShell(
            "/bin/zsh " + OpenClawRuntimeInstallation.quote(success.commandURL.path)
        )
        #expect(successResult.0 == 0, Comment(rawValue: successResult.1))
        #expect(try String(contentsOf: success.statusURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) == success.successReceipt)

        try writeNode(exitCode: 7)
        let failure = try OpenClawPluginReview.prepare(home: home, runtime: runtime)
        let failureResult = InstallerEngine().maintenanceShell(
            "/bin/zsh " + OpenClawRuntimeInstallation.quote(failure.commandURL.path)
        )
        #expect(failureResult.0 == 7)
        #expect(try String(contentsOf: failure.statusURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "failed:7")
    }

    @Test func maintenanceOutputKeepsJSONIntactAndDrainsLargeDiagnostics() throws {
        let command = #"/usr/bin/perl -e '$|=1; print "{\"status\":\"ok\","; print STDERR "Doctor: " . ("x" x 150000) . "\n"; print "\"mode\":\"npm\",\"root\":\"/fixture\",\"steps\":[]}";'"#
        let result = InstallerEngine().maintenanceShell(command)
        #expect(result.0 == 0)
        #expect(result.1.contains(String(repeating: "x", count: 150000)))
        #expect(OpenClawUpdateResult.envelope(in: result.1)?["status"] as? String == "ok")
    }
}
