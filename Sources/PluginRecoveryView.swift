import SwiftUI
import AppKit

struct OpenClawPluginReviewSession: Equatable, Sendable {
    let commandURL: URL
    let statusURL: URL
    let successReceipt: String
}

enum OpenClawPluginReview {
    static func script(
        runtime: OpenClawRuntimeInstallation,
        expectedVersion: String,
        statusURL: URL,
        successReceipt: String
    ) -> String {
        let q = OpenClawRuntimeInstallation.quote
        return """
        #!/bin/zsh
        set -u
        umask 077
        status_file=\(q(statusURL.path))
        completed=0
        write_status() {
          local next="${status_file}.tmp.$$"
          printf '%s\\n' "$1" > "$next"
          chmod 600 "$next"
          mv -f "$next" "$status_file"
        }
        on_exit() {
          if [[ "$completed" != 1 ]]; then
            write_status failed
          fi
        }
        trap on_exit EXIT
        trap 'exit 130' HUP INT TERM
        write_status running
        actual=$(\(q(runtime.node.path)) -p 'require(process.argv[1]).version' \(q(runtime.package.appendingPathComponent("package.json").path)))
        code=$?
        if [[ "$code" != 0 || "$actual" != \(q(expectedVersion)) ]]; then
          printf '%s\\n' 'OpenClaw changed. Return to LocalClaw and start the plugin review again.'
          write_status "failed:${code}"
          completed=1
          exit 1
        fi
        printf '%s\\n' 'Review each plugin and its requested capabilities. You may accept or decline.'
        # `update repair` disables Gateway activation in its child Doctor. LocalClaw
        # owns the verified running service, so Doctor must defer its lifecycle here.
        \(runtime.command("update repair --timeout 600", externalServiceRepair: true))
        code=$?
        if [[ "$code" != 0 ]]; then
          write_status "failed:${code}"
          completed=1
          printf '%s\\n' 'Review was declined or did not finish. Nothing was accepted by LocalClaw.'
          exit "$code"
        fi
        write_status \(q(successReceipt))
        completed=1
        trap - EXIT HUP INT TERM
        printf '%s\\n' 'Review completed successfully. Return to LocalClaw; Finish Gateway Repair is now available.'
        """
    }

    static func prepare(home: URL, runtime: OpenClawRuntimeInstallation) throws -> OpenClawPluginReviewSession {
        guard let expectedVersion = runtime.version,
              OpenClawRuntimeMaintenance.supportsPostCoreRepair(expectedVersion) else {
            throw MaintenanceError("Plugin review requires an installed OpenClaw 2.0 runtime.")
        }
        let folder = home.appendingPathComponent("Library/Application Support/LocalClaw/plugin-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let identifier = UUID().uuidString
        let file = folder.appendingPathComponent("review-\(identifier).command")
        let status = folder.appendingPathComponent("review-\(identifier).status")
        let receipt = "success:\(UUID().uuidString)"
        let session = OpenClawPluginReviewSession(commandURL: file, statusURL: status, successReceipt: receipt)
        try Data("prepared\n".utf8).write(to: status, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: status.path)
        try Data(script(
            runtime: runtime,
            expectedVersion: expectedVersion,
            statusURL: status,
            successReceipt: receipt
        ).utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return session
    }
}

struct PluginRecoveryView: View {
    let diagnostic: String
    let finish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var reviewRunning = false
    @State private var reviewCompleted = false
    @State private var status = ""
    @State private var reviewSession: OpenClawPluginReviewSession?
    @State private var reviewMonitor: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Plugin Permissions", systemImage: "hand.raised.fill").font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.help("Close")
            }
            Label("OpenClaw core installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text("One or more plugins need approval for new capabilities. No additional permissions have been granted.")
            Text("Step 1: review the exact plugin version and capabilities in OpenClaw's Terminal prompt. LocalClaw remains the Gateway service owner during this review, so OpenClaw Doctor cannot fight the running service. Step 2 stays locked until that command succeeds. You may decline; LocalClaw never accepts capabilities for you.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                Text(diagnostic).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !status.isEmpty { Text(status).font(.callout).textSelection(.enabled) }
            Divider()
            HStack(spacing: 12) {
                Button { Task { await review() } } label: {
                    Label(reviewSession == nil ? "1. Review in Terminal" : "1. Review Again", systemImage: "terminal")
                }
                .disabled(busy || reviewCompleted)
                Spacer()
                if busy || reviewRunning { ProgressView().controlSize(.small) }
                Button(action: finish) { Label("2. Finish Gateway Repair", systemImage: "wrench.and.screwdriver") }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !reviewCompleted)
            }
        }
        .padding(24).frame(width: 700, height: 560)
        .interactiveDismissDisabled(busy)
        .onDisappear { reviewMonitor?.cancel() }
    }

    @MainActor private func review() async {
        guard !busy else { return }
        reviewMonitor?.cancel()
        reviewCompleted = false
        reviewRunning = false
        busy = true
        let outcome: (OpenClawPluginReviewSession?, String) = await Task.detached {
            do {
                guard !OpenClawRuntimeMaintenance.isActive else {
                    throw MaintenanceError("Wait for the current OpenClaw repair to finish.")
                }
                let engine = InstallerEngine()
                let runtime = try OpenClawRuntimeMaintenance(run: engine.maintenanceShell).installation()
                let session = try OpenClawPluginReview.prepare(
                    home: FileManager.default.homeDirectoryForCurrentUser,
                    runtime: runtime
                )
                let result = engine.maintenanceShell(
                    "/usr/bin/open -a Terminal " + OpenClawRuntimeInstallation.quote(session.commandURL.path)
                )
                guard result.0 == 0 else { throw MaintenanceError(result.1) }
                return (session, "Terminal opened. Complete or decline OpenClaw's review there; this window will detect the result.")
            } catch {
                return (nil, SecretRedactor.redactConfigText(error.localizedDescription))
            }
        }.value
        reviewSession = outcome.0
        status = outcome.1
        busy = false
        guard let session = outcome.0 else { return }
        reviewRunning = true
        monitor(session)
    }

    @MainActor private func monitor(_ session: OpenClawPluginReviewSession) {
        reviewMonitor?.cancel()
        reviewMonitor = Task { @MainActor in
            for _ in 0..<1_200 {
                guard !Task.isCancelled else { return }
                let value = (try? String(contentsOf: session.statusURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if value == session.successReceipt {
                    reviewRunning = false
                    reviewCompleted = true
                    status = "Plugin review completed. You can now finish Gateway repair."
                    return
                }
                if value.hasPrefix("failed") {
                    reviewRunning = false
                    status = "Plugin review was declined or failed. No capability was accepted by LocalClaw; use Review Again if you want to retry."
                    return
                }
                try? await Task.sleep(for: .milliseconds(750))
            }
            reviewRunning = false
            status = "Plugin review is still not confirmed. Complete it in Terminal or start the review again."
        }
    }
}
