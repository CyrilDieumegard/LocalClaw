import Foundation
import CryptoKit

enum OpenClawUpdateResult {
    // Doctor can print valid JSON examples before the CLI's final result. Never
    // interpret examples, nested steps, or plugin outcomes as the update envelope.
    static func envelope(in output: String) -> [String: Any]? {
        objects(in: output).last {
            $0["status"] is String && $0["root"] is String && $0["mode"] is String &&
            ($0["steps"] is [Any] || ($0["mode"] as? String == "finalize" &&
                $0["restart"] as? Bool == false && $0["phaseTimings"] is [Any] && $0["postUpdate"] is [String: Any]))
        }
    }

    static func objects(in output: String) -> [[String: Any]] {
        let bytes = Array(output.utf8)
        var objects: [[String: Any]] = []
        var start = 0
        while start < bytes.count {
            guard bytes[start] == 0x7B || bytes[start] == 0x5B else { start += 1; continue }
            var stack: [UInt8] = []
            var quoted = false
            var escaped = false
            var end: Int?
            for index in start..<bytes.count {
                let byte = bytes[index]
                if quoted {
                    if escaped { escaped = false }
                    else if byte == 0x5C { escaped = true }
                    else if byte == 0x22 { quoted = false }
                } else if byte == 0x22 { quoted = true }
                else if byte == 0x7B { stack.append(0x7D) }
                else if byte == 0x5B { stack.append(0x5D) }
                else if byte == 0x7D || byte == 0x5D {
                    guard stack.last == byte else { break }
                    stack.removeLast()
                    if stack.isEmpty { end = index; break }
                }
            }
            if let end, let value = try? JSONSerialization.jsonObject(with: Data(bytes[start...end])) {
                if let object = value as? [String: Any] { objects.append(object) }
                start = end + 1
            } else { start += 1 }
        }
        return objects
    }

    static func needsPluginApproval(_ text: String) -> Bool {
        let current = OpenClawRecoveryDiagnostic.currentFailure(in: text).lowercased()
        return current.contains("plugin_capability_consent_required") ||
            current.contains("requires capability consent") || current.contains("plugin approval required")
    }

    static func serviceRecoveryRefusal(in result: [String: Any]) -> String? {
        guard let recovery = result["recovery"] as? [String: Any],
              recovery["serviceRestartSafe"] as? Bool == false else { return nil }
        let reason = recovery["reason"] as? String ?? "runtime-verification-failed"
        var message = "OpenClaw could not verify that this installation is safe to restart (\(reason)). LocalClaw did not reinstall or restart the Gateway after this result."
        if reason == "state-migration-started" {
            message += " Candidate Doctor may have migrated state; keep the candidate installed and do not roll back code alone."
        }
        return message + " Diagnose the selected installation with openclaw triage before restarting it."
    }

    /// OpenClaw 2026.9.6 reports completed finalization with advisory Doctor
    /// findings as `warning` and exit 0. This checks only its native receipt;
    /// LocalClaw must still run a final Doctor, prove no plugin migration is
    /// pending, and verify the selected Gateway before accepting it.
    static func isStructurallyAdvisoryFinalization(_ result: [String: Any], exitCode: Int32) -> Bool {
        guard exitCode == 0,
              result["status"] as? String == "warning",
              result["mode"] as? String == "finalize",
              result["restart"] as? Bool == false,
              result["reason"] == nil,
              result["recovery"] == nil,
              result["verification"] == nil,
              emptyOrAbsent(result["failureFacts"]),
              let phases = result["phaseTimings"] as? [[String: Any]], !phases.isEmpty,
              phases.allSatisfy({ $0["outcome"] as? String == "completed" }),
              Set(["preflight", "targetConfigValidation", "configSnapshot", "doctor",
                   "plugins", "targetConfigConvergence", "completionCache"]).isSubset(
                of: Set(phases.compactMap { $0["phase"] as? String })
              ),
              let postUpdate = result["postUpdate"] as? [String: Any],
              let doctor = postUpdate["doctor"] as? [String: Any],
              let doctorStatus = doctor["status"] as? String,
              ["ok", "warning"].contains(doctorStatus),
              emptyOrAbsent(doctor["failureFacts"]),
              let plugins = postUpdate["plugins"] as? [String: Any],
              let pluginStatus = plugins["status"] as? String,
              ["ok", "warning"].contains(pluginStatus),
              doctorStatus == "warning" || pluginStatus == "warning",
              let assessment = plugins["assessment"] as? [String: Any],
              assessment["kind"] as? String == "no-payload-repair",
              plugins["reason"] == nil,
              emptyOrAbsent(plugins["failureFacts"]),
              emptyOrAbsent(plugins["integrityDrifts"]),
              let sync = plugins["sync"] as? [String: Any],
              emptyOrAbsent(sync["errors"]),
              emptyOrAbsent(sync["warnings"]),
              let npm = plugins["npm"] as? [String: Any],
              let outcomes = npm["outcomes"] as? [[String: Any]],
              !outcomes.contains(where: { outcome in
                  ["error", "failed", "blocked"].contains(outcome["status"] as? String ?? "") ||
                      outcome["code"] as? String == "PLUGIN_CAPABILITY_CONSENT_REQUIRED"
              }),
              let lint = plugins["doctorLint"] as? [String: Any],
              lint["exitCode"] as? Int == 0,
              lint["termination"] as? String == "exit",
              lint["outputLimitExceeded"] as? Bool != true,
              emptyOrAbsent(lint["doctorLintFindings"]),
              emptyOrAbsent(lint["failureFacts"]) else { return false }

        if doctorStatus == "warning" {
            guard let warnings = doctor["warnings"] as? [String], !warnings.isEmpty else { return false }
        }
        if pluginStatus == "warning" {
            guard let warnings = plugins["warnings"] as? [[String: Any]], !warnings.isEmpty,
                  warnings.allSatisfy({ $0["reason"] as? String == "doctor-advisory" }) else { return false }
        }
        return true
    }

    private static func emptyOrAbsent(_ value: Any?) -> Bool {
        value == nil || (value as? [Any])?.isEmpty == true
    }

    static func pluginFailure(in result: [String: Any]) -> String? {
        guard let plugins = (result["postUpdate"] as? [String: Any])?["plugins"] as? [String: Any],
              let status = plugins["status"] as? String, ["error", "warning"].contains(status) else { return nil }
        let data = (try? JSONSerialization.data(withJSONObject: plugins, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let details = String(decoding: data, as: UTF8.self)
        if needsPluginApproval(details) {
            return "Plugin approval required. The OpenClaw core is installed; new plugin permissions were not accepted. Review Plugin Permissions, then Finish Repair. The core will not be reinstalled.\n\(details)"
        }
        return "The OpenClaw core is installed, but plugin repair needs attention. Repair will resume without reinstalling the core.\n\(details)"
    }
}

/// Persists native activation refusals across app relaunches, including ordinary
/// upgrades that do not require a full backup/checkpoint. Only verified repair
/// clears this record; changing the installed version alone is not health proof.
enum OpenClawActivationBlock {
    static let pluginRepairPendingReason = "plugin-repair-pending"

    private static func location(home: URL, runtime: OpenClawRuntimeInstallation) -> URL {
        // Replacing Node cannot prove that a partially migrated package/state is
        // runnable. Keep the refusal stable across a Node upgrade or relink.
        let identity = [runtime.package, runtime.state, runtime.config]
            .map { $0.resolvingSymlinksInPath().path }.joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(identity.utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
        return home.appendingPathComponent("Library/Application Support/LocalClaw/runtime-backups", isDirectory: true)
            .appendingPathComponent("activation-blocked-\(digest).json")
    }

    static func isPresent(home: URL, runtime: OpenClawRuntimeInstallation) -> Bool {
        let path = location(home: home, runtime: runtime).path
        return FileManager.default.fileExists(atPath: path) ||
            (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    /// A native update with an unknown or explicitly unsafe outcome cannot be
    /// made safe by automatically repeating it. A verified-core plugin repair
    /// is the sole resumable activation block: native `update repair` handles it.
    static func requiresManualRecovery(home: URL, runtime: OpenClawRuntimeInstallation) -> Bool {
        guard isPresent(home: home, runtime: runtime) else { return false }
        let file = location(home: home, runtime: runtime)
        guard let data = try? Data(contentsOf: file),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reason = record["reason"] as? String,
              let blockedVersion = record["version"] as? String,
              blockedVersion == runtime.version else { return true }
        return reason != pluginRepairPendingReason
    }

    static func save(home: URL, runtime: OpenClawRuntimeInstallation, reason: String) throws {
        let file = location(home: home, runtime: runtime)
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let record = ["version": runtime.version ?? "unknown", "reason": reason]
        try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func remove(home: URL, runtime: OpenClawRuntimeInstallation) throws {
        if isPresent(home: home, runtime: runtime) {
            try FileManager.default.removeItem(at: location(home: home, runtime: runtime))
        }
    }
}

struct OpenClawUpdateCheckpoint: Codable {
    let package: String
    let node: String
    let state: String
    let config: String
    let target: String
    let archive: String
    let archiveSize: UInt64
    let archiveModified: Date
    let archiveSHA256: String

    // LocalClaw 1.0.201 wrote the global pending-update.json before backup
    // digests were added. Keep this DTO isolated so a missing digest can never
    // silently weaken the canonical checkpoint format.
    private struct LegacyCheckpointV1: Codable {
        let package: String
        let node: String
        let state: String
        let config: String
        let target: String
        let archive: String
        let archiveSize: UInt64
        let archiveModified: Date
    }

    private static func directory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/LocalClaw/runtime-backups", isDirectory: true)
    }

    private static func legacyLocation(home: URL) -> URL {
        directory(home: home).appendingPathComponent("pending-update.json")
    }

    static func location(home: URL, runtime: OpenClawRuntimeInstallation) -> URL {
        let identity = [runtime.package, runtime.node, runtime.state, runtime.config]
            .map { $0.resolvingSymlinksInPath().path }
            .joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(identity.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return directory(home: home).appendingPathComponent("pending-update-\(digest).json")
    }

    static func save(home: URL, runtime: OpenClawRuntimeInstallation, target: String, archive: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        guard let size = attributes[.size] as? NSNumber, size.uint64Value > 0,
              let modified = attributes[.modificationDate] as? Date else {
            throw MaintenanceError("The verified recovery backup is no longer available.")
        }
        let archiveSHA256 = try sha256(archive)
        let checkpoint = Self(package: runtime.package.resolvingSymlinksInPath().path,
                              node: runtime.node.resolvingSymlinksInPath().path,
                              state: runtime.state.resolvingSymlinksInPath().path,
                              config: runtime.config.resolvingSymlinksInPath().path,
                              target: target, archive: archive.resolvingSymlinksInPath().path,
                              archiveSize: size.uint64Value, archiveModified: modified,
                              archiveSHA256: archiveSHA256)
        let directory = directory(home: home)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let file = location(home: home, runtime: runtime)
        try JSONEncoder().encode(checkpoint).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let legacy = legacyLocation(home: home)
        if legacy != file,
           let data = try? Data(contentsOf: legacy),
           legacyData(data, matches: runtime) {
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    static func load(home: URL, runtime: OpenClawRuntimeInstallation) -> Self? {
        let scoped = location(home: home, runtime: runtime)
        if FileManager.default.fileExists(atPath: scoped.path) {
            // A scoped V2 checkpoint is authoritative. Never downgrade to the
            // global V1 file when V2 exists but fails integrity validation.
            return loadCurrent(at: scoped, home: home, runtime: runtime)
        }

        let legacy = legacyLocation(home: home)
        guard let data = try? Data(contentsOf: legacy),
              let value = try? JSONDecoder().decode(LegacyCheckpointV1.self, from: data),
              matchesIdentity(value, runtime: runtime),
              value.target == runtime.version,
              OpenClawRuntimeMaintenance.isSupportedUpdateTarget(value.target),
              let digest = validatedArchiveDigest(
                home: home,
                archive: value.archive,
                size: value.archiveSize,
                modified: value.archiveModified
              ) else { return nil }

        let migrated = Self(
            package: value.package,
            node: value.node,
            state: value.state,
            config: value.config,
            target: value.target,
            archive: value.archive,
            archiveSize: value.archiveSize,
            archiveModified: value.archiveModified,
            archiveSHA256: digest
        )
        do {
            let backupDirectory = directory(home: home)
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: backupDirectory.path
            )
            try JSONEncoder().encode(migrated).write(to: scoped, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scoped.path)
            guard let verified = loadCurrent(at: scoped, home: home, runtime: runtime) else {
                try? FileManager.default.removeItem(at: scoped)
                return nil
            }
            try FileManager.default.removeItem(at: legacy)
            return verified
        } catch {
            try? FileManager.default.removeItem(at: scoped)
            return nil
        }
    }

    static func remove(home: URL, runtime: OpenClawRuntimeInstallation) throws {
        let scoped = location(home: home, runtime: runtime)
        if FileManager.default.fileExists(atPath: scoped.path) {
            try FileManager.default.removeItem(at: scoped)
        }
        let legacy = legacyLocation(home: home)
        if let data = try? Data(contentsOf: legacy),
           legacyData(data, matches: runtime) {
            try FileManager.default.removeItem(at: legacy)
        }
    }

    private static func loadCurrent(
        at file: URL,
        home: URL,
        runtime: OpenClawRuntimeInstallation
    ) -> Self? {
        guard let checkpointAttributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              checkpointAttributes[.type] as? FileAttributeType == .typeRegular,
              let mode = checkpointAttributes[.posixPermissions] as? NSNumber,
              mode.intValue & 0o777 == 0o600,
              let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              matchesIdentity(value, runtime: runtime),
              value.target == runtime.version,
              OpenClawRuntimeMaintenance.isSupportedUpdateTarget(value.target),
              value.archiveSHA256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
              ) != nil,
              let digest = validatedArchiveDigest(
                home: home,
                archive: value.archive,
                size: value.archiveSize,
                modified: value.archiveModified
              ),
              digest == value.archiveSHA256 else { return nil }
        return value
    }

    private static func validatedArchiveDigest(
        home: URL,
        archive: String,
        size: UInt64,
        modified: Date
    ) -> String? {
        guard size > 0 else { return nil }
        let archiveURL = URL(fileURLWithPath: archive)
        guard archiveURL.deletingLastPathComponent().resolvingSymlinksInPath() ==
                directory(home: home).resolvingSymlinksInPath(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: archiveURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.uint64Value == size,
              attributes[.modificationDate] as? Date == modified else { return nil }
        return try? sha256(archiveURL)
    }

    private static func legacyData(
        _ data: Data,
        matches runtime: OpenClawRuntimeInstallation
    ) -> Bool {
        if let current = try? JSONDecoder().decode(Self.self, from: data) {
            return matchesIdentity(current, runtime: runtime)
        }
        if let legacy = try? JSONDecoder().decode(LegacyCheckpointV1.self, from: data) {
            return matchesIdentity(legacy, runtime: runtime)
        }
        return false
    }

    private static func matchesIdentity(_ value: Self, runtime: OpenClawRuntimeInstallation) -> Bool {
        matchesIdentity(
            package: value.package,
            node: value.node,
            state: value.state,
            config: value.config,
            runtime: runtime
        )
    }

    private static func matchesIdentity(
        _ value: LegacyCheckpointV1,
        runtime: OpenClawRuntimeInstallation
    ) -> Bool {
        matchesIdentity(
            package: value.package,
            node: value.node,
            state: value.state,
            config: value.config,
            runtime: runtime
        )
    }

    private static func matchesIdentity(
        package: String,
        node: String,
        state: String,
        config: String,
        runtime: OpenClawRuntimeInstallation
    ) -> Bool {
        func matches(_ stored: String, _ current: URL) -> Bool {
            URL(fileURLWithPath: stored).resolvingSymlinksInPath() == current.resolvingSymlinksInPath()
        }
        return matches(package, runtime.package) && matches(node, runtime.node) &&
            matches(state, runtime.state) && matches(config, runtime.config)
    }

    private static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
