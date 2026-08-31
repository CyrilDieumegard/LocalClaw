import Foundation
import Testing
@testable import localclaw_mac_installer

struct OpenClawStorageRecoveryTests {
    @Test(arguments: ["npm error code ENOSPC", "tar: Write error: No space left on device", "Not enough free disk space for a safe recovery backup", "EDQUOT: disk quota exceeded"])
    func storageFailureWinsOverConfigurationAndNeverReplays(_ error: String) {
        let message = "OpenClaw config is invalid for runtime 2026.7.1-2.\n" + error
        let plan = ChatRecoveryPlan.classify(error: message)
        #expect(plan.kind == .storage)
        #expect(plan.primaryActionLabel == "Storage Recovery")
        #expect(!plan.replaysRequestAfterRepair)
        #expect(plan.explanation.contains("your approval"))
    }

    @Test func historicalDiskFailureDoesNotOverrideCurrentConfigError() {
        let message = "OpenClaw config is invalid.\nRecent startup log (gateway.log):\nENOSPC"
        #expect(ChatRecoveryPlan.classify(error: message).kind == .configuration)
    }

    @Test func genericRecoveryPreservesDiskCauseWithoutRunningDoctor() {
        let result = InstallerEngine().recoverOpenClawRuntime(errorText: "npm error ENOSPC; invalid config", allowPackageReinstall: false)
        #expect(result.state == .fail)
        #expect(result.message.contains("ENOSPC"))
        #expect(result.message.contains("Storage Recovery"))
        #expect(ChatRecoveryPlan.classify(error: result.message).kind == .storage)
    }

    @Test func cleanupRequiresConfirmationAndPreservesAllNonCacheData() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let service = OpenClawStorageRecovery(home: fixture.home)
        let fm = FileManager.default
        var commands: [String] = []
        let runner: OpenClawRuntimeMaintenance.Runner = { commands.append($0); return (1, "") }
        #expect(throws: (any Error).self) { try service.clearCache(confirmed: false, run: runner) }
        #expect(commands.isEmpty)
        #expect(fm.fileExists(atPath: fixture.payload.path))
        try service.clearCache(confirmed: true, run: runner)
        #expect(commands.count == 1)
        #expect(commands[0].contains("lsof"))
        #expect(!fm.fileExists(atPath: service.cache.path))
        for path in fixture.protected {
            #expect(try Data(contentsOf: path) == Data("protected".utf8))
        }
        #expect(try fm.contentsOfDirectory(atPath: fixture.home.appendingPathComponent(".npm").path) == ["_logs"])
    }

    @Test(arguments: [".npm", ".npm/_cacache"])
    func linkedCacheRootIsNeverDeleted(_ link: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fm = FileManager.default
        let source = fixture.home.appendingPathComponent(link)
        let other = fixture.home.appendingPathComponent("unrelated")
        try fm.moveItem(at: source, to: other)
        try fm.createSymbolicLink(at: source, withDestinationURL: other)
        var ran = false
        #expect(throws: (any Error).self) {
            try OpenClawStorageRecovery(home: fixture.home).clearCache(confirmed: true, run: { _ in ran = true; return (1, "") })
        }
        #expect(!ran)
        #expect(fm.fileExists(atPath: fixture.payload.path))
        #expect(fm.fileExists(atPath: other.path))
    }

    @Test(arguments: [false, true])
    func activeOrUninspectableCacheIsKept(_ active: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let output = active ? "p123\0cnpm\0\nf4\0tREG\0n\(fixture.payload.path)\0\n" : "lsof: permission denied"
        #expect(throws: (any Error).self) {
            try OpenClawStorageRecovery(home: fixture.home).clearCache(confirmed: true, run: { _ in (active ? 0 : 1, output) })
        }
        #expect(FileManager.default.fileExists(atPath: fixture.payload.path))
    }

    @Test func lowSpaceBeforeRuntimeDiscoveryRunsNoCommands() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var commands: [String] = []
        let result = OpenClawRuntimeMaintenance(home: fixture.home, run: { commands.append($0); return (1, "unexpected") }, freeBytes: { _ in 0 }).update()
        #expect(result.state == .fail)
        #expect(commands.isEmpty)
        #expect(result.message.contains("Available: \(OpenClawStorageRecovery.formatted(0))"))
        #expect(result.message.contains("Storage Recovery"))
        #expect(ChatRecoveryPlan.classify(error: result.message).kind == .storage)
        for path in fixture.protected { #expect(try Data(contentsOf: path) == Data("protected".utf8)) }
    }

    @Test func snapshotMeasuresOnlyCacheAndBackupsWithoutDeletingAnything() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let snapshot = try OpenClawStorageRecovery(home: fixture.home).snapshot()
        #expect((snapshot.cacheBytes ?? 0) > 0)
        #expect((snapshot.backupBytes ?? 0) > 0)
        #expect(snapshot.required >= OpenClawOfflineBackup.maintenanceReserve)
        #expect(FileManager.default.fileExists(atPath: fixture.payload.path))
    }

    private struct Fixture {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("storage-test-\(UUID().uuidString)")
        var payload: URL { home.appendingPathComponent(".npm/_cacache/content-v2/cache-data") }
        var protected: [URL] {
            [".npmrc", ".npm/_logs/keep.log", ".openclaw/state/openclaw.sqlite", ".openclaw/workspace/game.html", ".lmstudio/models/gemma.gguf", ".lmstudio/models/nemotron.gguf", "Library/Application Support/LocalClaw/runtime-backups/old.tar.gz"].map { home.appendingPathComponent($0) }
        }
        init() throws {
            for path in protected + [payload] {
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("protected".utf8).write(to: path)
            }
            // A symlink inside a disposable cache must not delete its target.
            try FileManager.default.createSymbolicLink(at: payload.deletingLastPathComponent().appendingPathComponent("model-link"), withDestinationURL: home.appendingPathComponent(".lmstudio/models"))
        }
        func cleanUp() { try? FileManager.default.removeItem(at: home) }
    }
}
