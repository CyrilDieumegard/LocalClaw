import Foundation
import Testing
@testable import localclaw_mac_installer

@Suite(.serialized)
struct OpenClawStateInspectionTests {
    private func record(pid: Int = 42, descriptor: String = "5", type: String = "REG", path: String = "/state/openclaw.sqlite") -> String {
        "p\(pid)\0cnode\0\nf\(descriptor)\0t\(type)\0n\(path)\0\n"
    }

    @Test func noMatchesMatchesCustomerTerminalResult() {
        #expect(OpenClawStateInspection.parse(code: 1, output: "") == .clear)
        #expect(OpenClawStateInspection.parse(code: 1, output: "\n") == .clear)
    }

    @Test func workingDirectoriesDoNotBlockButDataHandlesDo() {
        let cwd = record(descriptor: "cwd", type: "DIR", path: "/state")
        #expect(OpenClawStateInspection.parse(code: 0, output: cwd) == .clear)
        #expect(OpenClawStateInspection.parse(code: 1, output: cwd) == .clear)
        #expect(OpenClawStateInspection.parse(code: 0, output: record(descriptor: "rtd", type: "DIR")) == .clear)
        let data = record(pid: 43)
        guard case .busy(let owners) = OpenClawStateInspection.parse(code: 0, output: cwd + data) else {
            Issue.record("An open data file must block the offline backup")
            return
        }
        #expect(owners.count == 1)
        #expect(owners[0].pid == 43)
        #expect(owners[0].summary.contains("openclaw.sqlite"))
        #expect(owners[0].summary.contains("node (PID 43)"))
        #expect(OpenClawStateInspection.parse(code: 1, output: cwd + data) == .busy(owners))
        guard case .busy = OpenClawStateInspection.parse(code: 0, output: record(descriptor: "cwd")) else {
            Issue.record("Only confirmed directory references can be ignored")
            return
        }
    }

    @Test func pathsPreserveWhitespaceAndFilesWithinOneProcess() {
        let path = "/state/workspace/a file's\nname.js"
        let output = record(path: path) + "f6\0tREG\0n/state/openclaw.sqlite-wal\0\n"
        guard case .busy(let owners) = OpenClawStateInspection.parse(code: 0, output: output) else {
            Issue.record("File fields should parse without splitting names on whitespace")
            return
        }
        #expect(owners.map(\.path) == [path, "/state/openclaw.sqlite-wal"])
    }

    @Test func inspectionFailuresNeverClaimAFileOwnerOrAllowBackup() {
        let failures: [(Int32, String)] = [
            (1, "lsof: permission denied"), (2, ""), (127, "command not found"),
            (0, ""), (0, "42\n"), (0, "p42\0cnode\0\n"),
            (0, record() + "lsof: WARNING: cannot stat directory\n"),
            (0, "p42\0cnode\0\nf5\0n/state/database\0\n"),
            (0, "p42\0cnode\0\nf5\0tREG\0n/state/database"),
            (0, record() + "p43\0cnode\0\n")
        ]
        for (code, output) in failures {
            guard case .failed = OpenClawStateInspection.parse(code: code, output: output) else {
                Issue.record("Inspection must fail closed for code \(code): \(output.debugDescription)")
                continue
            }
        }
        guard case .failed(let message) = OpenClawStateInspection.parse(code: 1, output: "lsof: permission denied") else { return }
        #expect(message.contains("permission denied"))
        #expect(!message.contains("still open"))
    }

    @Test func nativeInspectionDistinguishesCwdFromAReadOnlyDatabase() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lsof fixture's \(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("openclaw.sqlite")
        try Data("isolated fixture".utf8).write(to: file)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        child.currentDirectoryURL = root
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }

        func inspect() throws -> OpenClawStateInspection {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", OpenClawStateInspection.command(state: root.path)]
            process.currentDirectoryURL = root
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return .parse(code: process.terminationStatus, output: output)
        }

        let before = try inspect()
        #expect(before == .clear, Comment(rawValue: "\(before)"))
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard case .busy(let owners) = try inspect() else {
            Issue.record("A real read-only SQLite handle must remain protected")
            return
        }
        // lsof escapes punctuation in reported paths; do not treat them as shell input.
        #expect(owners.contains { $0.pid == getpid() && $0.path.hasSuffix("/openclaw.sqlite") }, Comment(rawValue: "\(owners)"))
        try handle.close()
        let after = try inspect()
        #expect(after == .clear, Comment(rawValue: "\(after)"))
    }
}
