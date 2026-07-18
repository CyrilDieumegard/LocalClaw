import Foundation

struct RecoveryPoint: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let reason: String
    let directoryPath: String
    let files: [String]
}

final class RecoveryService: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String

    init(fileManager: FileManager = .default, homeDirectory: String = NSHomeDirectory()) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    var recoveryRoot: URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".openclaw/localclaw-recovery", isDirectory: true)
    }

    func createSnapshot(reason: String) throws -> RecoveryPoint {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let identifier = "snapshot-\(timestamp)-\(UUID().uuidString.prefix(8))"
        let directory = recoveryRoot.appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let candidates = [
            ("openclaw.json", URL(fileURLWithPath: homeDirectory).appendingPathComponent(".openclaw/openclaw.json")),
            ("auth-profiles.json", URL(fileURLWithPath: homeDirectory).appendingPathComponent(".openclaw/agents/main/agent/auth-profiles.json")),
            ("LocalClaw-preferences.plist", URL(fileURLWithPath: homeDirectory).appendingPathComponent("Library/Preferences/io.localclaw.installer.plist"))
        ]
        var copiedFiles: [String] = []
        for (name, source) in candidates where fileManager.fileExists(atPath: source.path) {
            let destination = directory.appendingPathComponent(name)
            try fileManager.copyItem(at: source, to: destination)
            copiedFiles.append(name)
        }

        let point = RecoveryPoint(
            id: identifier,
            createdAt: Date(),
            reason: reason,
            directoryPath: directory.path,
            files: copiedFiles
        )
        let metadata = try JSONEncoder.localClaw.encode(point)
        try metadata.write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
        try setPrivatePermissions(at: directory)
        return point
    }

    func listSnapshots() -> [RecoveryPoint] {
        guard let directories = try? fileManager.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil) else { return [] }
        return directories.compactMap { directory in
            let metadata = directory.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadata),
                  let point = try? JSONDecoder.localClaw.decode(RecoveryPoint.self, from: data) else { return nil }
            return point
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func restore(_ point: RecoveryPoint) throws {
        let directory = URL(fileURLWithPath: point.directoryPath, isDirectory: true)
        let destinations = [
            "openclaw.json": URL(fileURLWithPath: homeDirectory).appendingPathComponent(".openclaw/openclaw.json"),
            "auth-profiles.json": URL(fileURLWithPath: homeDirectory).appendingPathComponent(".openclaw/agents/main/agent/auth-profiles.json"),
            "LocalClaw-preferences.plist": URL(fileURLWithPath: homeDirectory).appendingPathComponent("Library/Preferences/io.localclaw.installer.plist")
        ]

        for file in point.files {
            guard let destination = destinations[file] else { continue }
            let source = directory.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func createSupportReport(
        snapshot: RuntimeSnapshot,
        appVersion: String,
        appBuild: String,
        logs: [String]
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: homeDirectory).appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        let output = downloads.appendingPathComponent("LocalClaw-Support-\(formatter.string(from: Date())).txt")

        let configURL = URL(fileURLWithPath: homeDirectory).appendingPathComponent(".openclaw/openclaw.json")
        let redactedConfig: String = {
            guard let raw = try? String(contentsOf: configURL, encoding: .utf8) else { return "Config unavailable" }
            return SecretRedactor.redactConfigText(raw)
        }()
        let issueSummary = snapshot.issues
            .map { "\($0.title): \($0.detail)" }
            .joined(separator: " | ")
        let report = [
            "LocalClaw support report",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "App: \(appVersion) (build \(appBuild))",
            "OpenClaw: \(snapshot.openClawVersion)",
            "Runtime: \(snapshot.health.rawValue)",
            snapshot.routeLine,
            "Snapshot: \(snapshot.freshnessLabel)",
            "Issues: \(issueSummary.isEmpty ? "none" : issueSummary)",
            "",
            "Recent LocalClaw logs",
            SecretRedactor.redactConfigText(logs.filter { !$0.isEmpty }.joined(separator: "\n\n")),
            "",
            "Redacted OpenClaw config",
            redactedConfig
        ].joined(separator: "\n")
        try report.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    private func setPrivatePermissions(at url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        for child in (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: child.path)
        }
    }
}

private extension JSONEncoder {
    static var localClaw: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var localClaw: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
