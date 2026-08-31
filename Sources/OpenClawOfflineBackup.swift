import Darwin
import Foundation

enum OpenClawOfflineBackup {
    struct Inventory {
        let entries: [String]
        let bytes: UInt64
        let sockets: Int

        // Allow for tar headers, incompressible input and the subsequent npm update.
        var requiredBytes: UInt64 { bytes + bytes / 20 + UInt64(entries.count) * 4_096 + maintenanceReserve }
    }

    static let maintenanceReserve: UInt64 = 2 * 1_024 * 1_024 * 1_024

    static func availableBytes(at directory: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let bytes = attributes[.systemFreeSize] as? NSNumber else {
            throw MaintenanceError("Could not check free disk space for the recovery backup.")
        }
        return bytes.uint64Value
    }

    static func inventory(state: URL) throws -> Inventory {
        let fm = FileManager.default
        let root = try canonicalDirectory(state).path
        var scanError: Error?
        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                                            options: [], errorHandler: { _, error in
            scanError = error
            return false
        }) else { throw MaintenanceError("Could not inspect the OpenClaw state for backup.") }
        var entries = ["."]
        var bytes: UInt64 = 0
        var sockets = 0
        for case let url as URL in enumerator {
            guard url.path.hasPrefix(root + "/") else {
                throw MaintenanceError("Unexpected path in the recovery backup inventory: \(url.path) (state: \(root)).")
            }
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                throw MaintenanceError("Could not read file type: \(url.path)")
            }
            if type == .typeSocket {
                sockets += 1
                continue
            }
            guard type == .typeRegular || type == .typeDirectory || type == .typeSymbolicLink else {
                throw MaintenanceError("Unsupported file type in recovery backup: \(url.path)")
            }
            if type == .typeRegular {
                guard let size = attributes[.size] as? NSNumber else { throw MaintenanceError("Could not read file size: \(url.path)") }
                bytes += size.uint64Value
            }
            entries.append("./" + url.path.dropFirst(root.count + 1))
        }
        if let scanError { throw MaintenanceError("Could not read the complete OpenClaw state.\n\(scanError.localizedDescription)") }
        return Inventory(entries: entries.sorted(), bytes: bytes, sockets: sockets)
    }

    static func create(state: URL, archive: URL, run: OpenClawRuntimeMaintenance.Runner,
                       report: (String) -> Void = { _ in },
                       freeBytes: (URL) throws -> UInt64 = availableBytes) throws {
        let fm = FileManager.default
        let root = try canonicalDirectory(state)
        let destination = try canonicalDirectory(archive.deletingLastPathComponent())
        guard destination.path != root.path, !destination.path.hasPrefix(root.path + "/") else {
            throw MaintenanceError("The recovery archive must be outside the OpenClaw state directory.")
        }
        let partial = archive.appendingPathExtension("partial")
        let list = archive.appendingPathExtension("files")
        guard !fm.fileExists(atPath: archive.path), !fm.fileExists(atPath: partial.path), !fm.fileExists(atPath: list.path) else {
            throw MaintenanceError("The recovery backup destination already exists. Nothing was overwritten.")
        }
        report("Measuring recovery backup size and checking free disk space...")
        let inventory = try inventory(state: root)
        let available = try freeBytes(destination)
        guard available >= inventory.requiredBytes else {
            throw MaintenanceError("Not enough free disk space for a safe recovery backup. Available: \(gigabytes(available)); required: \(gigabytes(inventory.requiredBytes)), including update reserve. Free disk space and retry. No new archive was created; existing backups were kept.")
        }
        report("Backing up \(inventory.entries.count) entries (\(gigabytes(inventory.bytes))). Skipping \(inventory.sockets) temporary sockets; source files are unchanged.")
        let paths = Data((inventory.entries.joined(separator: "\0") + "\0").utf8)
        defer { try? fm.removeItem(at: list) }
        guard fm.createFile(atPath: list.path, contents: paths, attributes: [.posixPermissions: 0o600]) else {
            throw MaintenanceError("Could not create the private recovery backup inventory.")
        }
        let quote = OpenClawRuntimeInstallation.quote
        do {
            // Explicit entries plus no-recursion prevent tar from rediscovering sockets.
            // File bytes, modes and symlinks are preserved, without AppleDouble/xattrs.
            let command = "umask 077; COPYFILE_DISABLE=1 /usr/bin/tar -czf \(quote(partial.path)) --no-mac-metadata --no-xattrs --no-acls --no-fflags --no-recursion --null -C \(quote(root.path)) -T \(quote(list.path))"
            let packed = run(command)
            guard packed.0 == 0 else { throw MaintenanceError("Back up migrated state failed (\(packed.0)).\n\(packed.1)") }
            guard let size = try fm.attributesOfItem(atPath: partial.path)[.size] as? NSNumber, size.uint64Value > 0 else {
                throw MaintenanceError("The recovery archive is missing or empty.")
            }
            report("Verifying the recovery archive before updating OpenClaw...")
            let verified = run("COPYFILE_DISABLE=1 /usr/bin/tar -tzf \(quote(partial.path)) >/dev/null")
            guard verified.0 == 0 else { throw MaintenanceError("Verify offline recovery archive failed (\(verified.0)).\n\(verified.1)") }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: partial.path)
            try fm.moveItem(at: partial, to: archive)
        } catch {
            if fm.fileExists(atPath: partial.path) {
                do { try fm.removeItem(at: partial) }
                catch let cleanupError {
                    throw MaintenanceError("\(error.localizedDescription)\nCould not remove this attempt's incomplete backup: \(partial.path)\n\(cleanupError.localizedDescription)")
                }
            }
            throw MaintenanceError("\(error.localizedDescription)\nThis attempt's incomplete backup was removed. Existing backups and source data were kept.")
        }
    }

    private static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    private static func canonicalDirectory(_ url: URL) throws -> URL {
        // Foundation can shorten /private/tmp to /tmp while enumeration does not.
        guard let path = realpath(url.path, nil) else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { free(path) }
        let directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        guard try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw MaintenanceError("Recovery backup requires a directory: \(directory.path)")
        }
        return directory
    }
}
