import SwiftUI
import AppKit

enum OpenClawPluginReview {
    static func script(runtime: OpenClawRuntimeInstallation, expectedVersion: String) -> String {
        let q = OpenClawRuntimeInstallation.quote
        return """
        #!/bin/zsh
        set -e
        actual=$(\(q(runtime.node.path)) -p 'require(process.argv[1]).version' \(q(runtime.package.appendingPathComponent("package.json").path)))
        if [[ "$actual" != \(q(expectedVersion)) ]]; then
          printf '%s\\n' 'OpenClaw changed. Return to LocalClaw and run Repair Gateway again.'
          exit 1
        fi
        printf '%s\\n' 'Review each plugin and its requested capabilities. You may decline.'
        \(runtime.command("update repair --timeout 600"))
        printf '%s\\n' 'Review finished. Return to LocalClaw and click Finish Repair to verify the Gateway.'
        """
    }

    static func prepare(home: URL, runtime: OpenClawRuntimeInstallation) throws -> URL {
        guard let checkpoint = OpenClawUpdateCheckpoint.load(home: home, runtime: runtime),
              OpenClawRuntimeMaintenance.supportsPostCoreRepair(runtime.version) else {
            throw MaintenanceError("Run Finish Repair first to prepare a verified backup for this installation.")
        }
        let folder = home.appendingPathComponent("Library/Application Support/LocalClaw/plugin-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("review-\(UUID().uuidString).command")
        try Data(script(runtime: runtime, expectedVersion: checkpoint.target).utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
}

struct PluginRecoveryView: View {
    let diagnostic: String
    let finish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Plugin Permissions", systemImage: "hand.raised.fill").font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.help("Close")
            }
            Label("OpenClaw core installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text("One or more plugins need approval for new capabilities. No additional permissions have been granted.")
            Text("Review the exact plugin versions and capabilities in OpenClaw's Terminal prompt. You can accept or decline each request. After the command finishes, return here to finish repair.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                Text(diagnostic).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !status.isEmpty { Text(status).font(.callout).textSelection(.enabled) }
            Divider()
            HStack(spacing: 12) {
                Button { Task { await review() } } label: { Label("Review in Terminal", systemImage: "terminal") }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(action: finish) { Label("Finish Repair", systemImage: "wrench.and.screwdriver") }
                    .buttonStyle(.borderedProminent)
            }.disabled(busy)
        }
        .padding(24).frame(width: 680, height: 540)
        .interactiveDismissDisabled(busy)
    }

    @MainActor private func review() async {
        guard !busy else { return }
        busy = true
        status = await Task.detached {
            do {
                guard !OpenClawRuntimeMaintenance.isActive else {
                    throw MaintenanceError("Wait for the current OpenClaw repair to finish.")
                }
                let engine = InstallerEngine()
                let runtime = try OpenClawRuntimeMaintenance(run: engine.maintenanceShell).installation()
                let file = try OpenClawPluginReview.prepare(home: FileManager.default.homeDirectoryForCurrentUser, runtime: runtime)
                let result = engine.maintenanceShell("/usr/bin/open -a Terminal " + OpenClawRuntimeInstallation.quote(file.path))
                guard result.0 == 0 else { throw MaintenanceError(result.1) }
                return "Terminal opened. Complete or decline the review there before clicking Finish Repair."
            } catch { return SecretRedactor.redactConfigText(error.localizedDescription) }
        }.value
        busy = false
    }
}
