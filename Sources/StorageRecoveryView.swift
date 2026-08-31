import SwiftUI
import AppKit

@MainActor
final class StorageRecoveryModel: ObservableObject {
    @Published var snapshot: OpenClawStorageRecovery.Snapshot?
    @Published var busy = false
    @Published var status = ""
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func refresh() async {
        guard !busy else { return }
        busy = true
        let home = home
        let result = await Task.detached { () -> (OpenClawStorageRecovery.Snapshot?, String) in
            do { return (try OpenClawStorageRecovery(home: home).snapshot(), "") }
            catch { return (nil, SecretRedactor.redactConfigText(error.localizedDescription)) }
        }.value
        snapshot = result.0
        if !result.1.isEmpty { status = result.1 }
        busy = false
    }

    func clearCache() async {
        guard !busy else { return }
        busy = true
        let home = home
        let result = await Task.detached { () -> String in
            let engine = InstallerEngine()
            return OpenClawRuntimeMaintenance(home: home, run: engine.shell).clearDownloadCache(confirmed: true).message
        }.value
        status = result
        busy = false
        await refresh()
    }
}

struct StorageRecoveryView: View {
    @ObservedObject var model: StorageRecoveryModel
    let diagnostic: String
    let retry: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCleanup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Storage Recovery", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .help("Close").disabled(model.busy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let snapshot = model.snapshot {
                        HStack(alignment: .firstTextBaseline) {
                            value("Free space", bytes: snapshot.available)
                            Spacer()
                            value("Repair space estimate", bytes: snapshot.required)
                        }
                        Label(snapshot.canRetry ? "Space check passed" : "More disk space is needed",
                              systemImage: snapshot.canRetry ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(snapshot.canRetry ? Color.green : Color.orange)
                        Text(snapshot.detail).font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(model.busy ? "Measuring disk usage..." : "Disk usage is unavailable.")
                    }
                    Divider()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("npm download cache").font(.headline)
                            Text(model.snapshot?.cacheBytes.map(OpenClawStorageRecovery.formatted) ?? "Unavailable or absent")
                                .foregroundStyle(.secondary)
                            Text("~/.npm/_cacache").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { confirmCleanup = true } label: { Label("Clear Cache", systemImage: "trash") }
                            .disabled(model.busy || (model.snapshot?.cacheBytes ?? 0) == 0)
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Existing recovery backups").font(.headline)
                            Text(model.snapshot?.backupBytes.map(OpenClawStorageRecovery.formatted) ?? "Not measured")
                                .foregroundStyle(.secondary)
                            Text("Kept unchanged. Review before deleting anything.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            let url = OpenClawStorageRecovery(home: model.home).backups
                            if !NSWorkspace.shared.open(url) { model.status = "The recovery backup folder is not available." }
                        } label: { Label("Review Backups", systemImage: "folder") }
                        .disabled(model.busy)
                    }
                    Text("Models, installed packages, projects, chats and credentials are not removed by cache cleanup.")
                        .font(.callout).foregroundStyle(.secondary)
                    if !model.status.isEmpty {
                        Text(model.status).font(.callout).textSelection(.enabled)
                    }
                    if !diagnostic.isEmpty {
                        DisclosureGroup("Technical details") {
                            Text(diagnostic).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
            }
            Divider()
            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage"),
                       !NSWorkspace.shared.open(url) { model.status = "Open System Settings > General > Storage." }
                } label: { Label("macOS Storage", systemImage: "externaldrive") }
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Check free space again").disabled(model.busy)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button(action: retry) { Label("Retry Repair", systemImage: "wrench.and.screwdriver") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.snapshot?.canRetry != true)
            }
        }
        .padding(24)
        .frame(width: 620, height: 520)
        .interactiveDismissDisabled(model.busy)
        .task { await model.refresh() }
        .alert("Clear npm download cache?", isPresented: $confirmCleanup) {
            Button("Clear Cache", role: .destructive) { Task { await model.clearCache() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only ~/.npm/_cacache will be removed. npm may download packages again. Models, installed packages, chats, projects, credentials and backups will be kept. Repair does not restart automatically.")
        }
    }

    private func value(_ title: String, bytes: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(OpenClawStorageRecovery.formatted(bytes)).font(.title2.monospacedDigit().weight(.semibold))
        }
    }
}
