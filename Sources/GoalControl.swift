import Foundation
import SwiftUI

enum GoalLifecycleStatus: String, Codable, Sendable {
    case active
    case paused
    case blocked
    case complete
    case usageLimited = "usage_limited"
    case budgetLimited = "budget_limited"

    var label: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .blocked: return "Blocked"
        case .complete: return "Complete"
        case .usageLimited: return "Usage limited"
        case .budgetLimited: return "Budget limited"
        }
    }
}

struct OpenClawGoalSnapshot: Codable, Equatable, Sendable {
    let id: String
    let objective: String
    let status: GoalLifecycleStatus
    let createdAt: Int64
    let updatedAt: Int64
    let tokensUsed: Int
    let tokenBudget: Int?
    let continuationTurns: Int
    let lastStatusNote: String?

    var createdDate: Date { Date(timeIntervalSince1970: TimeInterval(createdAt) / 1_000) }
}

enum GoalReadinessLevel: String, Equatable, Sendable {
    case ready
    case caution
    case blocked
}

struct GoalRuntimeReadiness: Equatable, Sendable {
    let level: GoalReadinessLevel
    let title: String
    let detail: String
    let recommendation: String?
    let canStart: Bool
}

enum GoalWorkPrompt {
    static func make(objective: String, starting: Bool) -> String {
        let objective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = starting ? "Begin" : "Continue"
        return """
        A LocalClaw Goal is active for this OpenClaw session.

        Objective:
        \(objective)

        \(action) working on it now. Do not ask the user to repeat the objective. Make one meaningful, concrete step and report what changed, what remains, and any blocker. When the objective is fully achieved, call update_goal with status complete. If work is genuinely blocked, call update_goal with status blocked. Otherwise leave the Goal active.
        """
    }
}

enum GoalCapabilityAdvisor {
    static func cloud(openClawInstalled: Bool, authReady: Bool, modelID: String, modeName: String) -> GoalRuntimeReadiness {
        guard openClawInstalled else {
            return .init(level: .blocked, title: "OpenClaw is missing", detail: "Install or repair OpenClaw before creating a goal.", recommendation: nil, canStart: false)
        }
        guard authReady else {
            return .init(level: .blocked, title: "\(modeName) needs authentication", detail: "Connect the provider in Models, then return here.", recommendation: nil, canStart: false)
        }
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .init(level: .blocked, title: "Choose a model", detail: "A goal needs a model for the work turns.", recommendation: nil, canStart: false)
        }
        return .init(level: .ready, title: "Ready for goals", detail: "Goal controls use zero model tokens. Only useful work is sent to \(modelID).", recommendation: nil, canStart: true)
    }

    static func local(
        openClawInstalled: Bool,
        modelName: String,
        isLoaded: Bool,
        fit: LocalModelFit?,
        toolUseScore: Double?,
        contextTokens: Int,
        recommendedModel: String?
    ) -> GoalRuntimeReadiness {
        guard openClawInstalled else {
            return .init(level: .blocked, title: "OpenClaw is missing", detail: "Install or repair OpenClaw before creating a goal.", recommendation: nil, canStart: false)
        }
        guard !modelName.isEmpty else {
            return .init(level: .blocked, title: "Choose a local model", detail: "No LM Studio model is selected.", recommendation: recommendedModel, canStart: false)
        }
        guard isLoaded else {
            return .init(level: .blocked, title: "Prepare the local model", detail: "\(modelName) must be loaded in LM Studio before it can work on a goal.", recommendation: recommendedModel, canStart: false)
        }
        if fit == .tooLarge || fit == .unsupported || fit == .tight {
            return .init(level: .blocked, title: "This model is not reliable on this Mac", detail: "Goal work needs memory headroom for tools and longer context.", recommendation: recommendedModel, canStart: false)
        }
        if let toolUseScore, toolUseScore < 4.0 {
            return .init(level: .blocked, title: "Chat-ready, not Goal-ready", detail: "\(modelName) is too weak at tool use for a dependable multi-step goal.", recommendation: recommendedModel, canStart: false)
        }
        if contextTokens > 0 && contextTokens < 16_000 {
            return .init(level: .blocked, title: "Context is too small", detail: "Reload the model with at least a 16K context window.", recommendation: recommendedModel, canStart: false)
        }
        if toolUseScore == nil || fit == nil {
            return .init(level: .caution, title: "Custom model, limited confidence", detail: "LocalClaw cannot rate this model yet. You can run the goal, but a rated model is safer.", recommendation: recommendedModel, canStart: true)
        }
        return .init(level: .ready, title: "Local Goal-ready", detail: "\(modelName) has enough tool-use capability and memory headroom for goal work.", recommendation: nil, canStart: true)
    }
}

private struct GoalControllerRequest: Encodable {
    let id: String
    let action: String
    let sessionKey: String
    let objective: String?
    let note: String?
}

private struct GoalControllerEnvelope: Decodable {
    let type: String
    let id: String?
    let ok: Bool
    let message: String?
    let goal: OpenClawGoalSnapshot?
}

enum OpenClawGoalBridgeError: LocalizedError {
    case resourceMissing
    case processFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .resourceMissing: return "LocalClaw Goal controller is missing from this build."
        case .processFailed(let message): return message
        case .invalidResponse: return "OpenClaw returned an invalid Goal response."
        }
    }
}

actor OpenClawGoalBridge {
    static let shared = OpenClawGoalBridge()

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var outputBuffer = Data()

    func request(action: String, sessionKey: String, objective: String? = nil, note: String? = nil) throws -> (OpenClawGoalSnapshot?, String) {
        try ensureProcess()
        let request = GoalControllerRequest(
            id: UUID().uuidString,
            action: action,
            sessionKey: sessionKey,
            objective: objective,
            note: note
        )
        let payload = try JSONEncoder().encode(request)
        guard let input else { throw OpenClawGoalBridgeError.processFailed("Goal controller is not running.") }
        try input.write(contentsOf: payload + Data([0x0A]))

        while let line = try readLine() {
            guard let envelope = try? JSONDecoder().decode(GoalControllerEnvelope.self, from: line) else { continue }
            guard envelope.type == "response", envelope.id == request.id else { continue }
            guard envelope.ok else {
                throw OpenClawGoalBridgeError.processFailed(envelope.message ?? "OpenClaw Goal action failed.")
            }
            return (envelope.goal, envelope.message ?? "Goal updated.")
        }
        resetProcess()
        throw OpenClawGoalBridgeError.processFailed("OpenClaw Goal controller stopped unexpectedly.")
    }

    private func ensureProcess() throws {
        if let process, process.isRunning, input != nil, output != nil { return }
        resetProcess()

        guard let scriptURL = Bundle.module.url(forResource: "goal-controller", withExtension: "mjs") else {
            throw OpenClawGoalBridgeError.resourceMissing
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", scriptURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:\(environment["PATH"] ?? "")"
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw OpenClawGoalBridgeError.processFailed("Could not start the Goal controller: \(error.localizedDescription)")
        }

        self.process = process
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        outputBuffer.removeAll(keepingCapacity: true)

        let readyLine = try readLine()
        let ready = readyLine.flatMap { try? JSONDecoder().decode(GoalControllerEnvelope.self, from: $0) }
        guard let ready, ready.type == "ready", ready.ok else {
            let message = ready?.message
            resetProcess()
            throw OpenClawGoalBridgeError.processFailed(message ?? "OpenClaw Goal control is unavailable.")
        }
    }

    private func readLine() throws -> Data? {
        while true {
            if let newline = outputBuffer.firstIndex(of: 0x0A) {
                let line = Data(outputBuffer[..<newline])
                outputBuffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                return line
            }
            guard let output else { return nil }
            let chunk = output.availableData
            if chunk.isEmpty { return nil }
            outputBuffer.append(chunk)
        }
    }

    private func resetProcess() {
        if let process, process.isRunning { process.terminate() }
        try? input?.close()
        try? output?.close()
        process = nil
        input = nil
        output = nil
        outputBuffer.removeAll(keepingCapacity: false)
    }
}

@MainActor
final class GoalCenterModel: ObservableObject {
    @Published var selectedChatSessionID = ""
    @Published var objective = ""
    @Published var note = ""
    @Published var snapshot: OpenClawGoalSnapshot?
    @Published var statusMessage = "Choose a discussion to create a durable objective."
    @Published var isBusy = false
    @Published var showClearConfirmation = false
    @Published var lastRefresh: Date?

    private let bridge = OpenClawGoalBridge.shared

    static func runtimeSessionID(for chatSessionID: String) -> String {
        let cleaned = chatSessionID.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        }
        return "\(String(cleaned).prefix(120))-goal"
    }

    static func openClawSessionKey(for chatSessionID: String) -> String {
        "agent:main:explicit:\(runtimeSessionID(for: chatSessionID))"
    }

    func selectSession(_ sessionID: String) async {
        guard !sessionID.isEmpty else {
            selectedChatSessionID = ""
            snapshot = nil
            return
        }
        selectedChatSessionID = sessionID
        await refresh()
    }

    func refresh() async {
        guard !selectedChatSessionID.isEmpty, !isBusy else { return }
        await perform(action: "status")
    }

    func start() async -> Bool {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Describe the result you want first."
            return false
        }
        return await perform(action: "start", objective: trimmed)
    }

    func edit() async -> Bool {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "The goal objective cannot be empty."
            return false
        }
        return await perform(action: "edit", objective: trimmed)
    }

    func pause() async { _ = await perform(action: "pause", note: note) }
    func resume() async { _ = await perform(action: "resume", note: note) }
    func complete() async { _ = await perform(action: "complete", note: note) }
    func block() async { _ = await perform(action: "block", note: note) }
    func clear() async { _ = await perform(action: "clear") }

    @discardableResult
    private func perform(action: String, objective: String? = nil, note: String? = nil) async -> Bool {
        guard !selectedChatSessionID.isEmpty else {
            statusMessage = "Choose a discussion first."
            return false
        }
        isBusy = true
        statusMessage = action == "status" ? "Reading Goal state..." : "Updating Goal..."
        do {
            let result = try await bridge.request(
                action: action,
                sessionKey: Self.openClawSessionKey(for: selectedChatSessionID),
                objective: objective,
                note: note?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            snapshot = result.0
            if let snapshot { self.objective = snapshot.objective }
            statusMessage = result.1
            lastRefresh = Date()
            isBusy = false
            return true
        } catch {
            statusMessage = error.localizedDescription
            isBusy = false
            return false
        }
    }
}
