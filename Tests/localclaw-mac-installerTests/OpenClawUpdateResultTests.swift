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

    @Test func terminalReviewIsInteractiveAndBoundToTheService() {
        let runtime = OpenClawRuntimeInstallation(node: URL(fileURLWithPath: "/tmp/user's node/bin/node"),
            package: URL(fileURLWithPath: "/tmp/runtime/lib/node_modules/openclaw"),
            prefix: URL(fileURLWithPath: "/tmp/runtime"), state: URL(fileURLWithPath: "/tmp/state"),
            config: URL(fileURLWithPath: "/tmp/config.json"), serviceLabel: "ai.openclaw.gateway")
        let script = OpenClawPluginReview.script(runtime: runtime, expectedVersion: "2026.8.1")
        #expect(script.contains("update repair --timeout 600"))
        #expect(script.contains("OPENCLAW_STATE_DIR='/tmp/state'"))
        #expect(script.contains("user'\\''s node"))
        #expect(!script.contains("--accept-capabilities"))
        #expect(!script.contains("--yes") && !script.contains("--json"))
        #expect(!script.contains("gateway restart") && !script.contains("agent --"))
    }

    @Test func maintenanceOutputKeepsJSONIntactAndDrainsLargeDiagnostics() throws {
        let command = #"/usr/bin/perl -e '$|=1; print "{\"status\":\"ok\","; print STDERR "Doctor: " . ("x" x 150000) . "\n"; print "\"mode\":\"npm\",\"root\":\"/fixture\",\"steps\":[]}";'"#
        let result = InstallerEngine().maintenanceShell(command)
        #expect(result.0 == 0)
        #expect(result.1.contains(String(repeating: "x", count: 150000)))
        #expect(OpenClawUpdateResult.envelope(in: result.1)?["status"] as? String == "ok")
    }
}
