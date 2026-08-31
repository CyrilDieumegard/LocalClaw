import Foundation

struct OpenClawStorageRecovery {
    let home: URL
    private let fm = FileManager.default

    struct Snapshot: Sendable {
        let available: UInt64
        let required: UInt64
        let cacheBytes: UInt64?
        let backupBytes: UInt64?
        let detail: String
        var canRetry: Bool { available >= required }
    }

    var cache: URL { home.appendingPathComponent(".npm/_cacache") }
    var backups: URL { home.appendingPathComponent("Library/Application Support/LocalClaw/runtime-backups") }

    static func isStorageFailure(_ text: String) -> Bool {
        let current = OpenClawRecoveryDiagnostic.currentFailure(in: text).lowercased()
        return ["enospc", "no space left on device", "not enough free disk space", "disk quota exceeded", "edquot"].contains(where: current.contains)
    }

    static let explanation = "Disk space is blocking OpenClaw repair. Open Storage Recovery to review space and clear the npm download cache with your approval. Models, projects, chats and existing backups are not deleted. Free enough space, then retry repair; your message will not be resent."

    static func formatted(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    static func requireSpace(at directory: URL, required: UInt64 = OpenClawOfflineBackup.maintenanceReserve,
                             freeBytes: (URL) throws -> UInt64 = OpenClawOfflineBackup.availableBytes) throws {
        let available = try freeBytes(directory)
        guard available >= required else {
            throw MaintenanceError("Not enough free disk space at \(directory.path). Available: \(formatted(available)); required: \(formatted(required)). \(explanation)")
        }
    }

    func snapshot() throws -> Snapshot {
        let available = try OpenClawOfflineBackup.availableBytes(at: home)
        var required = OpenClawOfflineBackup.maintenanceReserve
        var detail = "Includes update reserve. Offline backup space is checked separately before the Gateway is stopped."
        do {
            let state = try OpenClawRuntimeInstallation.managed(home: home)?.state ?? home.appendingPathComponent(".openclaw")
            if fm.fileExists(atPath: state.path) {
                required = try OpenClawOfflineBackup.inventory(state: state).requiredBytes
                detail = "Conservative offline backup estimate plus update reserve. Actual free space is checked again before repair."
            }
        } catch {
            detail += " Backup estimate unavailable: \(error.localizedDescription)"
        }
        let cacheBytes: UInt64? = (try? validatedCache()) == nil ? nil : try? size(of: cache)
        return Snapshot(available: available, required: required, cacheBytes: cacheBytes,
                        backupBytes: try? size(of: backups), detail: detail)
    }

    /// Only the default npm download cache is eligible, never arbitrary error paths.
    func clearCache(confirmed: Bool, run: OpenClawRuntimeMaintenance.Runner) throws {
        guard confirmed else { throw MaintenanceError("Cache cleanup requires your confirmation.") }
        guard let target = try validatedCache() else { return }
        let inspection = run(OpenClawStateInspection.command(state: target.path))
        switch OpenClawStateInspection.parse(code: inspection.0, output: inspection.1) {
        case .clear: break
        case .busy(let owners):
            throw MaintenanceError("The npm cache is in use. Let the download finish before cleaning it.\n" + owners.prefix(5).map(\.summary).joined(separator: "\n"))
        case .failed(let detail):
            throw MaintenanceError("Could not verify that the npm cache is idle. Nothing was deleted.\n\(detail)")
        }
        guard try validatedCache() == target else { throw MaintenanceError("The cache location changed. Nothing was deleted.") }
        // Detach this cache before removal; do not delete any newly-created npm cache.
        let detached = target.deletingLastPathComponent().appendingPathComponent("_cacache.localclaw-cleanup-\(UUID().uuidString)")
        try fm.moveItem(at: target, to: detached)
        do { try fm.removeItem(at: detached) }
        catch {
            if !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: detached, to: target) }
            throw MaintenanceError("Cache cleanup could not finish: \(error.localizedDescription). Remaining cache location: \(fm.fileExists(atPath: detached.path) ? detached.path : target.path). Models and backups were not touched.")
        }
    }

    private func validatedCache() throws -> URL? {
        for directory in [home.appendingPathComponent(".npm"), cache] {
            do {
                let attributes = try fm.attributesOfItem(atPath: directory.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory,
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
                    throw MaintenanceError("The default npm cache is linked, custom or not owned by this user. Automatic cleanup is unavailable; no files were deleted.")
                }
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                return nil
            }
        }
        return cache
    }

    private func size(of directory: URL) throws -> UInt64 {
        guard fm.fileExists(atPath: directory.path) else { return 0 }
        guard try fm.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw MaintenanceError("Storage location is not a directory.")
        }
        var scanError: Error?
        guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey], errorHandler: { _, error in
            scanError = error
            return false
        }) else { throw MaintenanceError("Could not measure storage.") }
        var bytes: UInt64 = 0
        for case let url as URL in entries {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey])
            if values.isRegularFile == true { bytes += UInt64(max(0, values.totalFileAllocatedSize ?? 0)) }
        }
        if let scanError { throw scanError }
        return bytes
    }
}
