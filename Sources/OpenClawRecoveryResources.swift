import Foundation

enum OpenClawRecoveryResources {
    private final class ResourceAnchor {}
    static let bundleName = "localclaw-mac-installer_localclaw-mac-installer.bundle"
    static let scriptName = "exec-approvals-migration.mjs"
    static let failureMessage = "LocalClaw repair resource is missing or unreadable. Update or reinstall LocalClaw before retrying Repair Gateway. No recovery backup or OpenClaw update was started."

    static func migrationHelper(in bundle: Bundle = .main) throws -> URL {
        let candidate: URL?
        if bundle.bundleURL.pathExtension.lowercased() == "app" {
            // A distributed app must never fall back to a developer's build tree.
            let resources = bundle.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            let packaged = resources.appendingPathComponent(bundleName, isDirectory: true).appendingPathComponent(scriptName)
            guard packaged.resolvingSymlinksInPath().path.hasPrefix(
                bundle.bundleURL.resolvingSymlinksInPath().appendingPathComponent("Contents/Resources").path + "/"
            ) else { throw MaintenanceError(failureMessage) }
            candidate = packaged
        } else {
            let codeBundle = Bundle(for: ResourceAnchor.self)
            candidate = GoalControllerResourceLocator.candidateURLs(
                bundleURL: codeBundle.bundleURL, resourceURL: codeBundle.resourceURL,
                executableURL: codeBundle.executableURL, scriptName: scriptName
            ).first { FileManager.default.fileExists(atPath: $0.path) }
        }
        guard let candidate,
              let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey]),
              values.isRegularFile == true, values.isReadable == true,
              let size = values.fileSize, size > 0, size <= 1_048_576,
              let content = try? String(contentsOf: candidate, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MaintenanceError(failureMessage)
        }
        return candidate
    }
}
