import Foundation

struct RecoveryPoint: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let reason: String
    let directoryPath: String
    let files: [String]
    let statePath: String?
    let configPath: String?
}

final class RecoveryService: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String
    private let copyItem: (URL, URL) throws -> Void
    private let moveItem: (URL, URL) throws -> Void
    private let removeItem: (URL) throws -> Void

    init(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory(),
        copyItem: ((URL, URL) throws -> Void)? = nil,
        moveItem: ((URL, URL) throws -> Void)? = nil,
        removeItem: ((URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.copyItem = copyItem ?? { try fileManager.copyItem(at: $0, to: $1) }
        self.moveItem = moveItem ?? { try fileManager.moveItem(at: $0, to: $1) }
        self.removeItem = removeItem ?? { try fileManager.removeItem(at: $0) }
    }

    var recoveryRoot: URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent("Library/Application Support/LocalClaw/config-snapshots", isDirectory: true)
    }

    private var legacyRecoveryRoot: URL {
        URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".openclaw/localclaw-recovery", isDirectory: true)
    }

    func createSnapshot(reason: String) throws -> RecoveryPoint {
        let home = URL(fileURLWithPath: homeDirectory)
        let state = try OpenClawRuntimeInstallation.selectedState(home: home)
        let config = try OpenClawRuntimeInstallation.selectedConfig(home: home)
        return try createSnapshot(reason: reason, state: state, config: config)
    }

    /// Creates a snapshot for an already-selected runtime. Maintenance uses
    /// this overload so a named profile can never be backed up as `default`.
    func createSnapshot(reason: String, state: URL, config: URL) throws -> RecoveryPoint {
        let home = URL(fileURLWithPath: homeDirectory)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let identifier = "snapshot-\(timestamp)-\(UUID().uuidString.prefix(8))"
        let directory = recoveryRoot.appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let candidates = [
            ("openclaw.json", config),
            ("auth-profiles.json", state.appendingPathComponent("agents/main/agent/auth-profiles.json")),
            ("LocalClaw-preferences.plist", home.appendingPathComponent("Library/Preferences/io.localclaw.installer.plist"))
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
            files: copiedFiles,
            statePath: state.resolvingSymlinksInPath().path,
            configPath: config.resolvingSymlinksInPath().path
        )
        let metadata = try JSONEncoder.localClaw.encode(point)
        try metadata.write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
        try setPrivatePermissions(at: directory)
        return point
    }

    func listSnapshots() -> [RecoveryPoint] {
        let directories = [recoveryRoot, legacyRecoveryRoot].flatMap {
            (try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        return directories.compactMap { directory in
            let metadata = directory.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadata),
                  let point = try? JSONDecoder.localClaw.decode(RecoveryPoint.self, from: data) else { return nil }
            return point
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func restore(_ point: RecoveryPoint) throws {
        let home = URL(fileURLWithPath: homeDirectory)
        let currentState = try OpenClawRuntimeInstallation.selectedState(home: home).resolvingSymlinksInPath()
        let currentConfig = try OpenClawRuntimeInstallation.selectedConfig(home: home).resolvingSymlinksInPath()
        let expectedState = URL(fileURLWithPath: point.statePath ?? home.appendingPathComponent(".openclaw").path).resolvingSymlinksInPath()
        let expectedConfig = URL(fileURLWithPath: point.configPath ?? expectedState.appendingPathComponent("openclaw.json").path).resolvingSymlinksInPath()
        guard currentState == expectedState, currentConfig == expectedConfig else {
            throw MaintenanceError("This config snapshot belongs to a different OpenClaw profile. Select that profile before restoring it; no file was changed.")
        }
        let directory = URL(fileURLWithPath: point.directoryPath, isDirectory: true)
        let destinations = [
            "openclaw.json": currentConfig,
            "auth-profiles.json": currentState.appendingPathComponent("agents/main/agent/auth-profiles.json"),
            "LocalClaw-preferences.plist": home.appendingPathComponent("Library/Preferences/io.localclaw.installer.plist")
        ]
        struct RestoreOperation {
            let destination: URL
            let staging: URL
            let previous: URL
            let hadOriginal: Bool
            var originalMoved = false
            var replacementInstalled = false
        }
        var operations: [RestoreOperation] = []

        // Stage every replacement first. A preparation failure must never touch
        // a destination: at this point every destination is still the live file.
        do {
            for file in point.files {
                guard let destination = destinations[file] else { continue }
                let source = directory.appendingPathComponent(file)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staging = destination.deletingLastPathComponent()
                    .appendingPathComponent(".localclaw-restore-\(UUID().uuidString)")
                let previous = destination.deletingLastPathComponent()
                    .appendingPathComponent(".localclaw-previous-\(UUID().uuidString)")
                try copyItem(source, staging)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
                operations.append(.init(
                    destination: destination,
                    staging: staging,
                    previous: previous,
                    hadOriginal: fileManager.fileExists(atPath: destination.path)
                ))
            }
        } catch {
            for operation in operations {
                if fileManager.fileExists(atPath: operation.staging.path) {
                    try? removeItem(operation.staging)
                }
            }
            throw error
        }

        do {
            for index in operations.indices {
                if operations[index].hadOriginal {
                    try moveItem(operations[index].destination, operations[index].previous)
                    operations[index].originalMoved = true
                }
                try moveItem(operations[index].staging, operations[index].destination)
                operations[index].replacementInstalled = true
            }
        } catch {
            // Roll back only transitions that actually happened. In particular,
            // never remove an untouched destination from a later operation.
            var rollbackFailures: [String] = []
            for operation in operations.reversed() {
                if operation.replacementInstalled,
                   fileManager.fileExists(atPath: operation.destination.path) {
                    do { try removeItem(operation.destination) }
                    catch { rollbackFailures.append("remove \(operation.destination.path): \(error.localizedDescription)") }
                }
                if operation.originalMoved,
                   fileManager.fileExists(atPath: operation.previous.path) {
                    do { try moveItem(operation.previous, operation.destination) }
                    catch { rollbackFailures.append("restore \(operation.destination.path): \(error.localizedDescription)") }
                }
                if fileManager.fileExists(atPath: operation.staging.path) {
                    try? removeItem(operation.staging)
                }
            }
            if rollbackFailures.isEmpty { throw error }
            throw MaintenanceError(
                "Config snapshot restore failed and rollback needs manual review. " +
                "Original error: \(error.localizedDescription)\n" + rollbackFailures.joined(separator: "\n")
            )
        }
        for operation in operations where fileManager.fileExists(atPath: operation.previous.path) {
            try? removeItem(operation.previous)
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

        let home = URL(fileURLWithPath: homeDirectory)
        let configURL = try? OpenClawRuntimeInstallation.selectedConfig(home: home)
        let redactedConfig: String = {
            guard let configURL, let raw = try? String(contentsOf: configURL, encoding: .utf8) else {
                return "Config unavailable or OpenClaw profile selection required"
            }
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
