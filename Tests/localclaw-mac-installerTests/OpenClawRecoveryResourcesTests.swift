import Foundation
import Testing
@testable import localclaw_mac_installer

struct OpenClawRecoveryResourcesTests {
    @Test func packagedAppResolvesItsOwnResourceWithoutBuildFallback() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let result = try OpenClawRecoveryResources.migrationHelper(in: fixture.bundle)
        #expect(result == fixture.script)
    }

    @Test(arguments: ["missing", "empty", "whitespace", "directory", "symlink", "invalid-utf8"])
    func damagedResourceThrowsInsteadOfTrappingOrUsingAnExternalCopy(_ damage: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fm = FileManager.default
        try fm.removeItem(at: fixture.script)
        switch damage {
        case "empty": try Data().write(to: fixture.script)
        case "whitespace": try Data(" \n\t".utf8).write(to: fixture.script)
        case "directory": try fm.createDirectory(at: fixture.script, withIntermediateDirectories: false)
        case "symlink": try fm.createSymbolicLink(at: fixture.script, withDestinationURL: fixture.decoy)
        case "invalid-utf8": try Data([0xFF, 0xFE]).write(to: fixture.script)
        default: break
        }
        #expect(throws: MaintenanceError.self) {
            try OpenClawRecoveryResources.migrationHelper(in: fixture.bundle)
        }
        #expect(try Data(contentsOf: fixture.decoy) == Data("external resource must not be used".utf8))
    }

    @Test func swiftPMTestsFindTheRealMigrationHelperWithoutBundleModule() throws {
        let helper = try OpenClawRecoveryResources.migrationHelper()
        #expect(helper.lastPathComponent == OpenClawRecoveryResources.scriptName)
        #expect(try String(contentsOf: helper, encoding: .utf8).contains("migrateLegacyExecApprovals"))
    }

    @Test func resourceFailureOffersAppUpdateWithoutReplayOrOpenClawReinstall() {
        let plan = ChatRecoveryPlan.classify(error: OpenClawRecoveryResources.failureMessage)
        #expect(plan.kind == .appResources)
        #expect(plan.primaryActionLabel == "Open Updates")
        #expect(!plan.replaysRequestAfterRepair)
    }

    private struct Fixture {
        let root: URL
        let bundle: Bundle
        let script: URL
        let decoy: URL

        init() throws {
            let fm = FileManager.default
            root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("resource fixture's \(UUID())")
            let app = root.appendingPathComponent("Applications/LocalClaw.app")
            script = app.appendingPathComponent("Contents/Resources")
                .appendingPathComponent(OpenClawRecoveryResources.bundleName)
                .appendingPathComponent(OpenClawRecoveryResources.scriptName)
            decoy = app.deletingLastPathComponent().appendingPathComponent(OpenClawRecoveryResources.bundleName)
                .appendingPathComponent(OpenClawRecoveryResources.scriptName)
            try fm.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(at: decoy.deletingLastPathComponent(), withIntermediateDirectories: true)
            let info = try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": "io.localclaw.resource-test.\(UUID())",
                "CFBundlePackageType": "APPL", "CFBundleExecutable": "LocalClaw"
            ], format: .xml, options: 0)
            try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
            try Data("export const fixture = true;".utf8).write(to: script)
            try Data("external resource must not be used".utf8).write(to: decoy)
            bundle = try #require(Bundle(url: app))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}
