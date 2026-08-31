import Darwin
import Foundation
import Testing
@testable import localclaw_mac_installer

@Suite(.serialized)
struct OpenClawOfflineBackupTests {
    private let q = OpenClawRuntimeInstallation.quote

    @Test func nativeBackupSkipsSocketsAndRestoresDataWithoutMacMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let socketPath = fixture.state.appendingPathComponent("exec-approvals.sock")
        let socket = try unixSocket(at: socketPath)
        defer { Darwin.close(socket) }
        let fm = FileManager.default
        let config = fixture.state.appendingPathComponent("openclaw.json")
        let database = fixture.state.appendingPathComponent("openclaw.sqlite")
        let project = fixture.state.appendingPathComponent("workspace/project's\nfiles")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try fm.createDirectory(at: fixture.state.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let source = project.appendingPathComponent("-game.html")
        let ordinarySockFile = project.appendingPathComponent("data.sock")
        let wal = fixture.state.appendingPathComponent("sessions.sqlite-wal")
        let shm = fixture.state.appendingPathComponent("sessions.sqlite-shm")
        try Data("<html>keep this project</html>".utf8).write(to: source)
        try Data("regular file, not a socket".utf8).write(to: ordinarySockFile)
        try Data([0, 1, 2, 255]).write(to: wal)
        try Data([4, 5, 6, 255]).write(to: shm)
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: config.path)
        try fm.setAttributes([.posixPermissions: 0o750], ofItemAtPath: source.path)
        try fm.createSymbolicLink(atPath: fixture.state.appendingPathComponent("source-link").path, withDestinationPath: "workspace/project's\nfiles/-game.html")
        let external = fixture.root.appendingPathComponent("outside.txt")
        try Data("not followed".utf8).write(to: external)
        try fm.createSymbolicLink(atPath: fixture.state.appendingPathComponent("external-link").path, withDestinationPath: external.path)
        try fm.createSymbolicLink(atPath: fixture.state.appendingPathComponent("dangling-link").path, withDestinationPath: "/missing-localclaw-fixture-file")
        try requireSuccess("/usr/bin/sqlite3 \(q(database.path)) \(q("PRAGMA user_version=15; CREATE TABLE history(value TEXT); INSERT INTO history VALUES ('keep chat history');"))")
        try requireSuccess("/usr/bin/xattr -w com.localclaw.test recovery-metadata \(q(config.path))")
        var messages: [String] = []
        let inventory = try OpenClawOfflineBackup.inventory(state: fixture.state)
        #expect(inventory.sockets == 1)
        #expect(!inventory.entries.contains("./exec-approvals.sock"))
        #expect(inventory.entries.contains { $0.hasSuffix("/data.sock") })

        let oldArchive = fixture.root.appendingPathComponent("old-method.tar.gz")
        let originalMethod = run("/usr/bin/tar -czf \(q(oldArchive.path)) -C \(q(fixture.state.path)) .")
        #expect(originalMethod.1.contains("socket"), Comment(rawValue: originalMethod.1))

        try OpenClawOfflineBackup.create(state: fixture.state, archive: fixture.archive, run: run, report: { messages.append($0) })
        #expect(messages.contains { $0.contains("Skipping 1 temporary sockets") })
        #expect(try fm.attributesOfItem(atPath: fixture.archive.path)[.posixPermissions] as? NSNumber == 0o600)
        #expect(try fm.contentsOfDirectory(atPath: fixture.backups.path) == [fixture.archive.lastPathComponent])
        let restored = fixture.root.appendingPathComponent("restored")
        try fm.createDirectory(at: restored, withIntermediateDirectories: true)
        try requireSuccess("COPYFILE_DISABLE=1 /usr/bin/tar -xzf \(q(fixture.archive.path)) -C \(q(restored.path))")
        for original in [config, source, ordinarySockFile, database, wal, shm] {
            let relative = String(original.path.dropFirst(fixture.state.path.count + 1))
            let recovered = restored.appendingPathComponent(relative)
            #expect(try Data(contentsOf: original) == Data(contentsOf: recovered))
            #expect(try fm.attributesOfItem(atPath: original.path)[.posixPermissions] as? NSNumber == fm.attributesOfItem(atPath: recovered.path)[.posixPermissions] as? NSNumber)
        }
        #expect(try fm.attributesOfItem(atPath: socketPath.path)[.type] as? FileAttributeType == .typeSocket)
        #expect(!fm.fileExists(atPath: restored.appendingPathComponent("exec-approvals.sock").path))
        #expect(fm.fileExists(atPath: restored.appendingPathComponent("empty").path))
        #expect(try fm.destinationOfSymbolicLink(atPath: restored.appendingPathComponent("source-link").path) == "workspace/project's\nfiles/-game.html")
        #expect(try fm.destinationOfSymbolicLink(atPath: restored.appendingPathComponent("external-link").path) == external.path)
        #expect(try fm.destinationOfSymbolicLink(atPath: restored.appendingPathComponent("dangling-link").path) == "/missing-localclaw-fixture-file")
        #expect(run("/usr/bin/xattr -p com.localclaw.test \(q(config.path))").1.contains("recovery-metadata"))
        #expect(run("/usr/bin/xattr -p com.localclaw.test \(q(restored.appendingPathComponent("openclaw.json").path))").0 != 0)
        let restoredDB = restored.appendingPathComponent("openclaw.sqlite")
        #expect(run("/usr/bin/sqlite3 \(q(restoredDB.path)) \(q("PRAGMA integrity_check; PRAGMA user_version; SELECT value FROM history;"))").1 == "ok\n15\nkeep chat history\n")
    }

    @Test func insufficientSpaceStopsBeforeArchiveCreation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var ran = false
        do {
            try OpenClawOfflineBackup.create(state: fixture.state, archive: fixture.archive, run: { _ in ran = true; return (0, "") }, freeBytes: { _ in 1_024 })
            Issue.record("Low disk space must stop the backup")
        } catch {
            #expect(error.localizedDescription.contains("Not enough free disk space"))
            #expect(error.localizedDescription.contains("No new archive was created"))
        }
        #expect(!ran)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.backups.path).isEmpty)
    }

    @Test(arguments: [false, true])
    func failureRemovesOnlyThisAttemptsPartialArchive(verificationFailure: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fm = FileManager.default
        let kept = fixture.backups.appendingPathComponent("old-backup.tar.gz")
        let unrelatedPartial = fixture.backups.appendingPathComponent("old-backup.tar.gz.partial")
        let original = try Data(contentsOf: fixture.state.appendingPathComponent("openclaw.json"))
        try Data("previous backup".utf8).write(to: kept)
        try Data("not owned by this attempt".utf8).write(to: unrelatedPartial)
        do {
            try OpenClawOfflineBackup.create(state: fixture.state, archive: fixture.archive, run: { command in
                if command.contains("tar -czf") {
                    try! Data("incomplete archive".utf8).write(to: fixture.archive.appendingPathExtension("partial"))
                    return verificationFailure ? (0, "") : (1, "tar: Write error")
                }
                return (1, "tar: Truncated input file")
            })
            Issue.record("Failed packing or verification must not publish an archive")
        } catch {
            #expect(error.localizedDescription.contains("incomplete backup was removed"))
            #expect(error.localizedDescription.contains(verificationFailure ? "Truncated input file" : "Write error"))
        }
        #expect(try fm.contentsOfDirectory(atPath: fixture.backups.path).sorted() == [kept.lastPathComponent, unrelatedPartial.lastPathComponent].sorted())
        #expect(try Data(contentsOf: fixture.state.appendingPathComponent("openclaw.json")) == original)
        #expect(try Data(contentsOf: kept) == Data("previous backup".utf8))
    }

    @Test func existingBackupIsNeverOverwritten() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try Data("keep existing".utf8).write(to: fixture.archive)
        #expect(throws: (any Error).self) {
            try OpenClawOfflineBackup.create(state: fixture.state, archive: fixture.archive, run: run)
        }
        #expect(try Data(contentsOf: fixture.archive) == Data("keep existing".utf8))
    }

    @Test func backupCannotArchiveItselfInsideState() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let archive = fixture.state.appendingPathComponent("backup.tar.gz")
        #expect(throws: (any Error).self) {
            try OpenClawOfflineBackup.create(state: fixture.state, archive: archive, run: run)
        }
        #expect(!FileManager.default.fileExists(atPath: archive.path))
    }

    private func requireSuccess(_ command: String) throws {
        let result = run(command)
        if result.0 != 0 { throw MaintenanceError("Native fixture command failed: \(result.1)") }
    }

    private func run(_ command: String) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func unixSocket(at url: URL) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MaintenanceError("Could not create fixture socket: \(errno)") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(url.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            throw MaintenanceError("Fixture socket path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { source in target.copyBytes(from: source) }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(fd)
            throw MaintenanceError("Could not bind fixture socket: \(code)")
        }
        return fd
    }

    private struct Fixture {
        let root = URL(fileURLWithPath: "/private/tmp/lc-bk-\(UUID().uuidString)")
        var state: URL { root.appendingPathComponent("state") }
        var backups: URL { root.appendingPathComponent("backups") }
        var archive: URL { backups.appendingPathComponent("openclaw-fixture.tar.gz") }

        init() throws {
            let fm = FileManager.default
            try fm.createDirectory(at: state, withIntermediateDirectories: true)
            try fm.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data("{\"meta\":{\"lastTouchedVersion\":\"2026.8.1\"}}".utf8).write(to: state.appendingPathComponent("openclaw.json"))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}
