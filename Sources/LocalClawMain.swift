import Foundation
import SwiftUI

@main
enum LocalClawMain {
    @MainActor static func main() {
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
