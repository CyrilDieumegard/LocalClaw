import Foundation
import Testing
@testable import localclaw_mac_installer

struct LocalClawSelfUpdaterTests {
    @Test func updateOrderingRejectsDowngradesAndIdenticalReleases() {
        #expect(LocalClawSelfUpdater.isNewer(version: "0.8.10", build: "1", thanVersion: "0.8.9", build: "99"))
        #expect(LocalClawSelfUpdater.isNewer(version: "0.8.9", build: "101", thanVersion: "0.8.9", build: "99"))
        #expect(!LocalClawSelfUpdater.isNewer(version: "0.8.9", build: "101", thanVersion: "0.8.10", build: "1"))
        #expect(!LocalClawSelfUpdater.isNewer(version: "0.8.9", build: "99", thanVersion: "0.8.9", build: "99"))
        #expect(!LocalClawSelfUpdater.isNewer(version: "0.8.10", build: "", thanVersion: "0.8.9", build: "99"))
    }

    @Test func onlyInstalledApplicationLocationsAreEligible() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try LocalClawSelfUpdater.validateDestination(fixture.destination, home: fixture.root)
        #expect(throws: LocalClawSelfUpdater.UpdateError.self) {
            try LocalClawSelfUpdater.validateDestination(fixture.candidate, home: fixture.root)
        }
    }

    @Test func symlinkedInstalledAppIsRejectedWithoutChangingItsTarget() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.removeItem(at: fixture.destination)
        try FileManager.default.createSymbolicLink(at: fixture.destination, withDestinationURL: fixture.candidate)
        #expect(throws: LocalClawSelfUpdater.UpdateError.self) {
            try LocalClawSelfUpdater.validateDestination(fixture.destination, home: fixture.root)
        }
        #expect(try fixture.content(of: fixture.candidate) == "new")
    }

    @Test func manifestVersionAndBuildMustMatchBothFields() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeIdentity(version: "0.9.2", build: "100")
        try LocalClawSelfUpdater.verifyIdentity(at: fixture.candidate, version: "0.9.2", build: "100")
        #expect(throws: LocalClawSelfUpdater.UpdateError.self) {
            try LocalClawSelfUpdater.verifyIdentity(at: fixture.candidate, version: "0.9.2", build: "101")
        }
        #expect(throws: LocalClawSelfUpdater.UpdateError.self) {
            try LocalClawSelfUpdater.verifyIdentity(at: fixture.candidate, version: "0.9.3", build: "100")
        }
    }

    @Test(arguments: ["identifier", "executable"])
    func bundleIdentityCannotRedirectTheHelper(_ mismatch: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeIdentity(version: "0.9.2", build: "100",
                                  identifier: mismatch == "identifier" ? "other.app" : LocalClawSelfUpdater.bundleIdentifier,
                                  executable: mismatch == "executable" ? "other-program" : "LocalClaw")
        #expect(throws: LocalClawSelfUpdater.UpdateError.self) {
            try LocalClawSelfUpdater.verifyIdentity(at: fixture.candidate, version: "0.9.2", build: "100")
        }
    }

    @Test func successfulReplacementIsAtomicAndRetainsPreviousBundleUntilCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try LocalClawUpdateTransaction.replace(candidate: fixture.candidate, destination: fixture.destination) { installed in
            #expect(try fixture.content(of: installed) == "new")
            #expect(try fixture.content(of: fixture.candidate) == "old")
        }
        #expect(try fixture.content(of: fixture.destination) == "new")
        #expect(try fixture.content(of: fixture.candidate) == "old")
    }

    @Test func failedPostInstallValidationRestoresTheOriginalApp() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(throws: TestFailure.self) {
            try LocalClawUpdateTransaction.replace(candidate: fixture.candidate, destination: fixture.destination) { _ in
                throw TestFailure.validationFailed
            }
        }
        #expect(try fixture.content(of: fixture.destination) == "old")
        #expect(try fixture.content(of: fixture.candidate) == "new")
    }

    @Test func anUnstoppableLaunchedCandidatePreservesBackupWithoutReplacingItsRunningCode() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(throws: LocalClawUpdateTransaction.RollbackUnsafe.self) {
            try LocalClawUpdateTransaction.replace(candidate: fixture.candidate, destination: fixture.destination) { _ in
                throw LocalClawUpdateTransaction.RollbackUnsafe()
            }
        }
        #expect(try fixture.content(of: fixture.destination) == "new")
        #expect(try fixture.content(of: fixture.candidate) == "old")
    }

    @Test func unsignedBundleCannotPassTheProductionSignatureGate() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeIdentity(version: "0.9.2", build: "100")
        #expect(throws: LocalClawSelfUpdater.UpdateError.self) {
            try LocalClawSelfUpdater.verifySignature(at: fixture.candidate, gatekeeper: false)
        }
        #expect(try fixture.content(of: fixture.destination) == "old")
    }

    @Test func missingCandidateDoesNotRemoveOrRenameTheInstalledApp() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.removeItem(at: fixture.candidate)
        #expect(throws: LocalClawSelfUpdater.UpdateError.self) {
            try LocalClawUpdateTransaction.replace(candidate: fixture.candidate, destination: fixture.destination) { _ in
                Issue.record("A missing candidate must not reach post-install validation")
            }
        }
        #expect(try fixture.content(of: fixture.destination) == "old")
    }

    @Test func symlinkedCandidateDoesNotReplaceTheInstalledApp() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let link = fixture.root.appendingPathComponent("candidate-link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.candidate)
        #expect(throws: LocalClawSelfUpdater.UpdateError.self) {
            try LocalClawUpdateTransaction.replace(candidate: link, destination: fixture.destination) { _ in
                Issue.record("A symlinked candidate must not reach post-install validation")
            }
        }
        #expect(try fixture.content(of: fixture.destination) == "old")
        #expect(try fixture.content(of: fixture.candidate) == "new")
    }

    @Test func malformedHelperInvocationExitsBeforeTouchingAnApp() {
        #expect(LocalClawSelfUpdater.runHelper(arguments: ["LocalClaw", LocalClawSelfUpdater.helperArgument]) == 2)
        #expect(LocalClawSelfUpdater.runHelper(arguments: ["LocalClaw", "--wrong", "/Applications/LocalClaw.app"]) == 2)
    }

    @Test func helperRejectsUnsignedUntrustedFixturesBeforeAnyReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let request = fixture.candidate.deletingLastPathComponent().appendingPathComponent("request.json")
        try Data("{}".utf8).write(to: request)
        #expect(LocalClawSelfUpdater.runHelper(arguments: ["LocalClaw", LocalClawSelfUpdater.helperArgument, request.path]) == 1)
        #expect(try fixture.content(of: fixture.destination) == "old")
        #expect(try fixture.content(of: fixture.candidate) == "new")
    }

    @Test func startupReadsPrivateFailureDetailsWithoutRemovingRollbackFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let error = try fixture.writeFailure("Signature verification failed; original app restored.")
        let message = LocalClawSelfUpdater.launchFailureMessage(arguments: ["LocalClaw", "--self-update-failed", error.path], home: fixture.root)
        #expect(message == "Signature verification failed; original app restored.")
        #expect(try fixture.content(of: fixture.candidate) == "new")
        #expect(FileManager.default.fileExists(atPath: error.path))
    }

    @Test(arguments: ["symlink", "public", "oversize", "outside"])
    func startupRejectsUnsafeFailureReferences(_ damage: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var error = try fixture.writeFailure("Failure details")
        switch damage {
        case "symlink":
            try FileManager.default.removeItem(at: error)
            try FileManager.default.createSymbolicLink(at: error, withDestinationURL: fixture.destination.appendingPathComponent("payload"))
        case "public":
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: error.path)
        case "oversize":
            try Data(repeating: 65, count: 16_385).write(to: error)
        default:
            error = fixture.destination.appendingPathComponent("payload")
        }
        #expect(LocalClawSelfUpdater.launchFailureMessage(arguments: ["LocalClaw", "--self-update-failed", error.path], home: fixture.root) == nil)
        #expect(try fixture.content(of: fixture.destination) == "old")
    }

    private enum TestFailure: Error { case validationFailed }

    private struct Fixture {
        let root: URL
        let destination: URL
        let candidate: URL

        init() throws {
            let fm = FileManager.default
            root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("self updater's test \(UUID())")
            destination = root.appendingPathComponent("Applications/LocalClaw.app")
            candidate = root.appendingPathComponent("Applications/.localclaw-update-test/LocalClaw.app")
            for (app, content) in [(destination, "old"), (candidate, "new")] {
                try fm.createDirectory(at: app, withIntermediateDirectories: true)
                try Data(content.utf8).write(to: app.appendingPathComponent("payload"))
            }
        }

        func writeIdentity(version: String, build: String,
                           identifier: String = LocalClawSelfUpdater.bundleIdentifier,
                           executable: String = "LocalClaw") throws {
            let contents = candidate.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": executable,
                        "CFBundleShortVersionString": version, "CFBundleVersion": build]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }

        func content(of app: URL) throws -> String {
            try String(contentsOf: app.appendingPathComponent("payload"), encoding: .utf8)
        }

        func writeFailure(_ message: String) throws -> URL {
            let staging = candidate.deletingLastPathComponent()
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
            let request = staging.appendingPathComponent("request.json")
            let error = staging.appendingPathComponent("error.txt")
            try Data("{}".utf8).write(to: request)
            try Data(message.utf8).write(to: error)
            for file in [request, error] {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            return error
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}
