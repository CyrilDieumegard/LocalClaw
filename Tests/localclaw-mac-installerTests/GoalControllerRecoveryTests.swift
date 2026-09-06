import Foundation
import Testing
@testable import localclaw_mac_installer

@Suite("Goal controller and automation recovery")
struct GoalControllerRecoveryTests {
    @Test func goalWorkspaceMatchesOpenClawAgentOwnership() throws {
        let cases: [(String, String, String)] = [
            (#"{"agents":{"ownership":"explicit","entries":{"main":{},"writer":{}},"defaults":{"workspace":"/fixture/projects"}}}"#, "writer", "/fixture/projects/writer"),
            (#"{"agents":{"ownership":"explicit","entries":{"main":{},"writer":{}},"defaults":{"workspace":"/fixture/projects"}}}"#, "main", "/fixture/projects/main"),
            (#"{"agents":{"ownership":"explicit","entries":{"writer":{}},"defaults":{"workspace":"/fixture/projects"}}}"#, "writer", "/fixture/projects"),
            (#"{"agents":{"ownership":"explicit","entries":{"main":{},"writer":{}}}}"#, "writer", "/fixture/state/workspace-writer"),
            (#"{"agents":{"list":[{"id":"main"},{"id":"writer","default":true}],"defaults":{"workspace":"/fixture/projects"}}}"#, "writer", "/fixture/projects"),
            (#"{"agents":{"entries":{"writer":{"workspace":"~/chosen"}},"defaults":{"workspace":"/fixture/projects"}}}"#, "writer", "/fixture/home/chosen"),
            (#"{"agents":{"entries":{"writer":{"workspace":"relative/project"}}}}"#, "writer", "/fixture/cwd/relative/project"),
            (#"{"agents":{"entries":{"writer":{}}}}"#, "writer", "/fixture/state/workspace"),
            (#"{}"#, "main", "/fixture/state/workspace"),
        ]
        for (rawConfig, agentID, expected) in cases {
            let config = try #require(JSONSerialization.jsonObject(with: Data(rawConfig.utf8)) as? [String: Any])
            let result = GoalWorkspaceBinding.resolve(
                agentID: agentID, config: config,
                state: URL(fileURLWithPath: "/fixture/state"), home: URL(fileURLWithPath: "/fixture/home"),
                environment: [:], workingDirectory: URL(fileURLWithPath: "/fixture/cwd")
            )
            #expect(result.path == expected)
        }
    }

    @Test func unresponsiveControllerStopsAtDeadline() throws {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        var reader = GoalControllerLineReader()
        let started = ProcessInfo.processInfo.systemUptime
        #expect(throws: OpenClawGoalBridgeError.self) {
            try reader.readLine(from: pipe.fileHandleForReading, deadline: started + 0.05)
        }
        #expect(ProcessInfo.processInfo.systemUptime - started < 2)
    }

    @Test func partialAndBufferedResponsesStaySeparate() throws {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        var reader = GoalControllerLineReader()
        try pipe.fileHandleForWriting.write(contentsOf: Data("partial".utf8))
        #expect(throws: OpenClawGoalBridgeError.self) {
            try reader.readLine(from: pipe.fileHandleForReading, deadline: ProcessInfo.processInfo.systemUptime + 0.05)
        }
        try pipe.fileHandleForWriting.write(contentsOf: Data(" response\n\nnext response\n".utf8))
        let first = try reader.readLine(from: pipe.fileHandleForReading, deadline: ProcessInfo.processInfo.systemUptime + 1)
        let second = try reader.readLine(from: pipe.fileHandleForReading, deadline: ProcessInfo.processInfo.systemUptime + 1)
        #expect(first == Data("partial response".utf8))
        #expect(second == Data("next response".utf8))
    }

    @Test func oversizedControllerResponseIsRejected() throws {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        try pipe.fileHandleForWriting.write(contentsOf: Data((String(repeating: "x", count: 33) + "\n").utf8))
        var reader = GoalControllerLineReader()
        #expect(throws: OpenClawGoalBridgeError.self) {
            try reader.readLine(from: pipe.fileHandleForReading, deadline: ProcessInfo.processInfo.systemUptime + 1, maxLineBytes: 32)
        }
    }

    @Test func closedControllerReturnsWithoutWaiting() throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        try pipe.fileHandleForWriting.close()
        var reader = GoalControllerLineReader()
        let line = try reader.readLine(from: pipe.fileHandleForReading, deadline: ProcessInfo.processInfo.systemUptime + 1)
        #expect(line == nil)
    }

    @Test func restartMarksUnobservedAutomationAsUnknown() throws {
        let suite = "io.localclaw.receipt-recovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let running = AutomationReceipt(
            source: .cron, sourceID: "fixture-running", title: "Running fixture",
            agentID: "writer", modelID: "fixture", destination: "fixture"
        )
        let finished = AutomationReceipt(
            source: .kanban, sourceID: "fixture-done", title: "Finished fixture",
            finishedAt: Date(), status: .succeeded,
            agentID: "writer", modelID: "fixture", destination: nil, summary: "Verified"
        )
        AutomationReceiptStore.save([running, finished], defaults: defaults)
        let restored = AutomationReceiptStore.load(defaults: defaults)
        let recovered = try #require(restored.first { $0.id == running.id })
        #expect(recovered.status == .unknown)
        #expect(recovered.finishedAt == nil)
        #expect(recovered.agentID == running.agentID)
        #expect(recovered.summary?.contains("Check OpenClaw history before retrying") == true)
        let completed = try #require(restored.first { $0.id == finished.id })
        #expect(completed.status == .succeeded)
        #expect(completed.summary == finished.summary)
        #expect(completed.finishedAt != nil)
    }
}
