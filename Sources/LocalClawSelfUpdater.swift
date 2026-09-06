import AppKit
import Darwin
import Foundation

/// The only executable accepted as an update helper is the authenticated new
/// LocalClaw app itself. No generated script or privileged shell is involved.
enum LocalClawSelfUpdater {
    static let helperArgument = "--apply-self-update"
    static let bundleIdentifier = "io.localclaw.installer"
    static let teamIdentifier = "923MBLC4X4"

    struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    struct Request: Codable {
        let destination: String
        let version: String
        let build: String
        let previousVersion: String
        let previousBuild: String
        let parentPID: Int32
        let parentLaunchDate: Date
    }

    /// Returns only once the helper has checked everything and is waiting for
    /// this exact process to exit. The caller should then terminate LocalClaw.
    static func prepareAndLaunch(verifiedDMG: URL, expectedVersion: String, expectedBuild: String) throws {
        let fm = FileManager.default
        let destination = Bundle.main.bundleURL.standardizedFileURL
        try validateDestination(destination)
        guard fm.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            throw UpdateError("macOS does not allow this account to replace LocalClaw in Applications. Install LocalClaw in your user Applications folder to enable updates without administrator permission.")
        }
        let old = try identity(at: destination)
        try verifySignature(at: destination, gatekeeper: false)
        guard isNewer(version: expectedVersion, build: expectedBuild,
                      thanVersion: old.version, build: old.build) else {
            throw UpdateError("The downloaded LocalClaw build is not newer than the running app.")
        }
        guard let parent = NSRunningApplication(processIdentifier: getpid()),
              let launchDate = parent.launchDate else {
            throw UpdateError("Cannot establish the identity of the running LocalClaw process.")
        }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".localclaw-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        var handedOff = false
        defer { if !handedOff { try? fm.removeItem(at: staging) } }
        let mount = staging.appendingPathComponent("mount", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: false)
        try run("/usr/bin/hdiutil", ["attach", verifiedDMG.path, "-readonly", "-nobrowse", "-quiet", "-mountpoint", mount.path])
        do {
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }
            let source = mount.appendingPathComponent("LocalClaw.app", isDirectory: true)
            let candidate = staging.appendingPathComponent("LocalClaw.app", isDirectory: true)
            try verifyIdentity(at: source, version: expectedVersion, build: expectedBuild)
            try verifySignature(at: source, gatekeeper: true)
            // ditto preserves the sealed bundle, executable modes and xattrs.
            try run("/usr/bin/ditto", [source.path, candidate.path])
            try verifyIdentity(at: candidate, version: expectedVersion, build: expectedBuild)
            try verifySignature(at: candidate, gatekeeper: true)
        }
        let candidate = staging.appendingPathComponent("LocalClaw.app", isDirectory: true)
        let request = Request(destination: destination.path, version: expectedVersion, build: expectedBuild,
                              previousVersion: old.version, previousBuild: old.build,
                              parentPID: getpid(), parentLaunchDate: launchDate)
        let requestURL = staging.appendingPathComponent("request.json")
        try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        let helper = Process()
        helper.executableURL = candidate.appendingPathComponent("Contents/MacOS/LocalClaw")
        helper.arguments = [helperArgument, requestURL.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        let deadline = Date().addingTimeInterval(30)
        let readyURL = staging.appendingPathComponent("ready")
        while Date() < deadline {
            if fm.fileExists(atPath: readyURL.path) {
                handedOff = true
                return
            }
            if !helper.isRunning { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        stop(helper)
        let detail = (try? String(contentsOf: staging.appendingPathComponent("error.txt"), encoding: .utf8)) ?? "Update helper did not become ready."
        throw UpdateError(detail)
    }

    /// Invoked before constructing SwiftUI, the model, or any OpenClaw clients.
    static func runHelper(arguments: [String]) -> Int32 {
        guard arguments.count == 3, arguments[1] == helperArgument else { return 2 }
        let requestURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let staging = requestURL.deletingLastPathComponent()
        var authenticatedStaging = false
        var parentDidExit = false
        var validatedRequest: Request?
        do {
            try validateStaging(staging, requestURL: requestURL)
            authenticatedStaging = true
            let data = try Data(contentsOf: requestURL)
            guard data.count <= 16_384 else { throw UpdateError("Update request is too large.") }
            let request = try JSONDecoder().decode(Request.self, from: data)
            let destination = URL(fileURLWithPath: request.destination).standardizedFileURL
            try validateDestination(destination)
            guard staging.deletingLastPathComponent().path == destination.deletingLastPathComponent().path else {
                throw UpdateError("The update must be staged on the application's volume.")
            }
            let candidate = staging.appendingPathComponent("LocalClaw.app", isDirectory: true)
            guard Bundle.main.bundleURL.standardizedFileURL.path == candidate.path else {
                throw UpdateError("The update helper must run from the authenticated staged app.")
            }
            try verifyIdentity(at: candidate, version: request.version, build: request.build)
            try verifySignature(at: candidate, gatekeeper: true)
            try verifyIdentity(at: destination, version: request.previousVersion, build: request.previousBuild)
            try verifySignature(at: destination, gatekeeper: false)
            guard isNewer(version: request.version, build: request.build,
                          thanVersion: request.previousVersion, build: request.previousBuild) else {
                throw UpdateError("The update helper refused an older or identical app build.")
            }
            guard request.parentPID == getppid(),
                  let parent = NSRunningApplication(processIdentifier: request.parentPID),
                  parentMatches(parent, request: request) else {
                throw UpdateError("The requesting process is not the installed LocalClaw app.")
            }
            guard !hasOtherRunningApp(at: destination, excluding: [request.parentPID, getpid()]) else {
                throw UpdateError("Close the other LocalClaw instance before installing this update.")
            }
            validatedRequest = request
            // A kernel process-exit source tracks this process instance even if
            // its PID is reused; AppKit's cached isTerminated needs a run loop.
            let parentExit = DispatchSemaphore(value: 0)
            let exitSource = DispatchSource.makeProcessSource(identifier: request.parentPID, eventMask: .exit, queue: .global())
            exitSource.setEventHandler { parentExit.signal() }
            exitSource.resume()
            defer { exitSource.cancel() }
            try Data("ready".utf8).write(to: staging.appendingPathComponent("ready"), options: .atomic)
            guard parentExit.wait(timeout: .now() + 120) == .success else {
                throw UpdateError("LocalClaw did not quit. The installed app was left unchanged.")
            }
            parentDidExit = true
            // Re-check after waiting: a second update or external replacement
            // must never get silently overwritten.
            try verifyIdentity(at: destination, version: request.previousVersion, build: request.previousBuild)
            try verifySignature(at: destination, gatekeeper: false)
            try verifyIdentity(at: candidate, version: request.version, build: request.build)
            try verifySignature(at: candidate, gatekeeper: true)
            guard !hasOtherRunningApp(at: destination, excluding: [getpid()]) else {
                throw UpdateError("Another LocalClaw instance was opened during the update. The app was left unchanged.")
            }
            try LocalClawUpdateTransaction.replace(candidate: candidate, destination: destination) { installed in
                try verifyIdentity(at: installed, version: request.version, build: request.build)
                try verifySignature(at: installed, gatekeeper: true)
                try launchAndConfirm(installed, arguments: ["--self-update-completed"])
            }
            try? FileManager.default.removeItem(at: staging)
            return 0
        } catch {
            if authenticatedStaging {
                let errorURL = staging.appendingPathComponent("error.txt")
                try? Data(error.localizedDescription.utf8).write(to: errorURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: errorURL.path)
            }
            if parentDidExit, let request = validatedRequest {
                let destination = URL(fileURLWithPath: request.destination)
                // Only relaunch the restored original, never an unverified or
                // partially replaced app after a rollback failure.
                if (try? verifyIdentity(at: destination, version: request.previousVersion, build: request.previousBuild)) != nil,
                   (try? verifySignature(at: destination, gatekeeper: false)) != nil,
                   !hasOtherRunningApp(at: destination, excluding: [getpid()]) {
                    try? launchAndConfirm(destination, arguments: ["--self-update-failed", staging.appendingPathComponent("error.txt").path])
                }
            }
            return 1
        }
    }

    /// Failure details are read only from a private updater-owned sibling
    /// directory. Keep that directory: it may still contain the rollback app.
    static func launchFailureMessage(arguments: [String] = CommandLine.arguments,
                                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        guard let index = arguments.firstIndex(of: "--self-update-failed"),
              index + 1 < arguments.count else { return nil }
        let errorURL = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        let staging = errorURL.deletingLastPathComponent()
        let allowedParents = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        guard errorURL.lastPathComponent == "error.txt",
              allowedParents.contains(where: { $0.standardizedFileURL.path == staging.deletingLastPathComponent().path }),
              errorURL.resolvingSymlinksInPath().path == errorURL.path else { return nil }
        do {
            try validateStaging(staging, requestURL: staging.appendingPathComponent("request.json"))
            let attributes = try FileManager.default.attributesOfItem(atPath: errorURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0,
                  let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 16_384 else { return nil }
            let input = try FileHandle(forReadingFrom: errorURL)
            defer { try? input.close() }
            guard let data = try input.read(upToCount: 16_385), data.count <= 16_384,
                  let message = String(data: data, encoding: .utf8), !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return message
        } catch { return nil }
    }

    static func validateDestination(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let destination = url.standardizedFileURL
        let allowed = [URL(fileURLWithPath: "/Applications/LocalClaw.app"),
                       home.appendingPathComponent("Applications/LocalClaw.app")].map(\.standardizedFileURL)
        guard allowed.contains(where: { $0.path == destination.path }), destination.resolvingSymlinksInPath().path == destination.path else {
            throw UpdateError("Install LocalClaw in Applications or your user Applications folder before using automatic updates.")
        }
        let values = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw UpdateError("The installed LocalClaw app is not a regular application bundle.")
        }
    }

    private static func validateStaging(_ staging: URL, requestURL: URL) throws {
        guard staging.lastPathComponent.hasPrefix(".localclaw-update-"),
              staging.resolvingSymlinksInPath().path == staging.path,
              requestURL.lastPathComponent == "request.json" else {
            throw UpdateError("Invalid update staging directory.")
        }
        let fm = FileManager.default
        for url in [staging, requestURL] {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let mode = attributes[.posixPermissions] as? NSNumber,
                  mode.intValue & 0o077 == 0,
                  attributes[.type] as? FileAttributeType == (url == staging ? .typeDirectory : .typeRegular) else {
                throw UpdateError("The update request is not privately owned by this user.")
            }
        }
    }

    private static func parentMatches(_ parent: NSRunningApplication, request: Request) -> Bool {
        parent.bundleIdentifier == bundleIdentifier &&
        parent.bundleURL?.standardizedFileURL.path == request.destination &&
        parent.launchDate == request.parentLaunchDate && !parent.isTerminated
    }

    private static func hasOtherRunningApp(at destination: URL, excluding: Set<Int32>) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains {
            !excluding.contains($0.processIdentifier) && !$0.isTerminated &&
            $0.bundleURL?.standardizedFileURL.path == destination.standardizedFileURL.path
        }
    }

    private static func launchAndConfirm(_ installed: URL, arguments: [String]) throws {
        let child = Process()
        child.executableURL = installed.appendingPathComponent("Contents/MacOS/LocalClaw")
        child.arguments = arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        // First launch includes hardware/runtime discovery and can take longer
        // on an existing installation; do not roll back a healthy slow startup.
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline, child.isRunning {
            if let app = NSRunningApplication(processIdentifier: child.processIdentifier),
               app.bundleIdentifier == bundleIdentifier,
               app.bundleURL?.standardizedFileURL.path == installed.standardizedFileURL.path,
               app.isFinishedLaunching, !app.isTerminated {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        // This is exactly our child process, not an arbitrary app instance.
        // It must stop before the transaction rolls its executable back.
        stop(child)
        guard !child.isRunning else {
            throw LocalClawUpdateTransaction.RollbackUnsafe()
        }
        throw UpdateError("The updated LocalClaw did not finish launching; the previous app was restored.")
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        let killDeadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < killDeadline { Thread.sleep(forTimeInterval: 0.05) }
    }

    static func isNewer(version: String, build: String, thanVersion oldVersion: String, build oldBuild: String) -> Bool {
        guard !version.isEmpty, !build.isEmpty, !oldVersion.isEmpty, !oldBuild.isEmpty else { return false }
        let versionOrder = version.compare(oldVersion, options: .numeric)
        return versionOrder == .orderedDescending ||
            (versionOrder == .orderedSame && build.compare(oldBuild, options: .numeric) == .orderedDescending)
    }

    private static func identity(at app: URL) throws -> (version: String, build: String) {
        let values = try app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              info["CFBundleExecutable"] as? String == "LocalClaw",
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
            throw UpdateError("The update bundle does not have the expected LocalClaw identity.")
        }
        return (version, build)
    }

    static func verifyIdentity(at app: URL, version: String, build: String) throws {
        let actual = try identity(at: app)
        guard actual.version == version, actual.build == build else {
            throw UpdateError("The LocalClaw update version or build does not match its release manifest.")
        }
    }

    static func verifySignature(at app: URL, gatekeeper: Bool) throws {
        // The requirement is evaluated by codesign, not inferred from printed
        // TeamIdentifier metadata. Ad-hoc and third-party signatures fail.
        let requirement = "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", requirement, app.path])
        if gatekeeper { try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path]) }
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let fm = FileManager.default
        let outputDirectory = fm.temporaryDirectory.appendingPathComponent("localclaw-command-\(UUID().uuidString)")
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: outputDirectory) }
        let outputURL = outputDirectory.appendingPathComponent("output")
        guard fm.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw UpdateError("Cannot create private update command output.")
        }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        try process.run()
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            stop(process)
            throw UpdateError("\(URL(fileURLWithPath: executable).lastPathComponent) timed out. The update was stopped.")
        }
        let input = try FileHandle(forReadingFrom: outputURL)
        defer { try? input.close() }
        let message = String(decoding: try input.read(upToCount: 8192) ?? Data(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw UpdateError("\(URL(fileURLWithPath: executable).lastPathComponent) failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return message
    }
}

/// Small, independently testable transaction. Production enters this only after
/// authenticating both bundles, the destination and the requesting process.
enum LocalClawUpdateTransaction {
    struct RollbackUnsafe: LocalizedError {
        var errorDescription: String? {
            "The updated LocalClaw could not be stopped after failing to launch. Automatic rollback was paused; the previous app is preserved in the update staging folder."
        }
    }

    static func replace(candidate: URL, destination: URL, acceptInstalled: (URL) throws -> Void) throws {
        try swap(candidate, destination)
        do {
            try acceptInstalled(destination)
        } catch {
            if error is RollbackUnsafe { throw error }
            do { try swap(candidate, destination) }
            catch let rollbackError {
                throw LocalClawSelfUpdater.UpdateError("Update verification failed, and automatic rollback failed: \(rollbackError.localizedDescription). The previous app is preserved at \(candidate.path).")
            }
            throw error
        }
    }

    private static func swap(_ candidate: URL, _ destination: URL) throws {
        guard candidate.standardizedFileURL.path != destination.standardizedFileURL.path,
              candidate.resolvingSymlinksInPath().path == candidate.standardizedFileURL.path,
              destination.resolvingSymlinksInPath().path == destination.standardizedFileURL.path else {
            throw LocalClawSelfUpdater.UpdateError("Unsafe application replacement paths.")
        }
        let result = candidate.path.withCString { source in
            destination.path.withCString { target in renamex_np(source, target, UInt32(RENAME_SWAP)) }
        }
        guard result == 0 else {
            throw LocalClawSelfUpdater.UpdateError("macOS could not replace LocalClaw: \(String(cString: strerror(errno))). The installed app was preserved.")
        }
    }
}
