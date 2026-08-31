import Foundation
import SwiftUI

@main
enum LocalClawMain {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().contains("--check-update-output") {
            var result: [String: Any] = ["ok": false, "gatewayVerified": false]
            do {
                guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--check-update-output" else {
                    throw MaintenanceError("Usage: --check-update-output <diagnostic-file>")
                }
                let file = URL(fileURLWithPath: CommandLine.arguments[2])
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? NSNumber, size.uint64Value <= 16 * 1024 * 1024,
                      let envelope = OpenClawUpdateResult.envelope(in: try String(contentsOf: file, encoding: .utf8)) else {
                    throw MaintenanceError("No recognized update result in this diagnostic file.")
                }
                result["ok"] = true
                result["updateStatus"] = envelope["status"]
                result["mode"] = envelope["mode"]
                let failure = OpenClawUpdateResult.pluginFailure(in: envelope)
                result["pluginRepairPending"] = failure != nil
                result["needsPluginApproval"] = failure.map(OpenClawUpdateResult.needsPluginApproval) ?? false
            } catch { result["error"] = error.localizedDescription }
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                FileHandle.standardOutput.write(data + Data("\n".utf8))
            }
            exit(result["ok"] as? Bool == true ? 0 : 1)
        }
        // This diagnostic exits before constructing any UI, model or service client.
        if CommandLine.arguments.dropFirst().contains("--check-recovery-resources") {
            var result: [String: Any] = [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            ]
            let status: Int32
            do {
                guard Bundle.main.bundleURL.pathExtension.lowercased() == "app" else {
                    throw MaintenanceError("Run this diagnostic from a packaged LocalClaw.app.")
                }
                result["resource"] = try OpenClawRecoveryResources.migrationHelper().path
                result["ok"] = true
                status = 0
            } catch {
                result["ok"] = false
                result["error"] = error.localizedDescription
                status = 1
            }
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            exit(status)
        }
        LocalClawInstallerApp.main()
    }
}
