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

enum GoalPlanStepStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case complete
    case blocked
}

struct GoalOutputContract: Codable, Equatable, Sendable {
    var type: String
    var format: String
    var location: String
    var launch: String
    var completionCriteria: [String]

    var isDefined: Bool {
        !type.trimmed.isEmpty &&
        !format.trimmed.isEmpty &&
        !location.trimmed.isEmpty &&
        !launch.trimmed.isEmpty &&
        !completionCriteria.filter({ !$0.trimmed.isEmpty }).isEmpty
    }
}

struct GoalOutputVerification: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case notLocal
        case missing
        case empty
        case ready
    }

    let state: State
    let path: String?

    var requiresLocalArtifact: Bool { state != .notLocal }
    var isSatisfied: Bool { state == .notLocal || state == .ready }

    var detail: String {
        switch state {
        case .notLocal:
            return "The output is not a local file or folder."
        case .missing:
            return "The expected output does not exist on disk at \(path ?? "the approved location")."
        case .empty:
            return "The expected output exists but is empty at \(path ?? "the approved location")."
        case .ready:
            return "The expected output exists on disk at \(path ?? "the approved location")."
        }
    }
}

enum GoalOutputVerifier {
    static func resolvedLocalPath(_ rawLocation: String) -> String? {
        var location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        while location.count >= 2,
              let first = location.first,
              let last = location.last,
              (first == "`" && last == "`" || first == "\"" && last == "\"") {
            location.removeFirst()
            location.removeLast()
            location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if location.hasPrefix("file://"), let url = URL(string: location), url.isFileURL {
            return url.path
        }
        guard location.hasPrefix("/") || location.hasPrefix("~") else { return nil }
        return NSString(string: location).expandingTildeInPath
    }

    static func verify(_ output: GoalOutputContract, fileManager: FileManager = .default) -> GoalOutputVerification {
        guard let path = resolvedLocalPath(output.location) else {
            return GoalOutputVerification(state: .notLocal, path: nil)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return GoalOutputVerification(state: .missing, path: path)
        }

        if isDirectory.boolValue {
            let contents = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
            return GoalOutputVerification(state: contents.isEmpty ? .empty : .ready, path: path)
        }

        let size = ((try? fileManager.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0
        return GoalOutputVerification(state: size > 0 ? .ready : .empty, path: path)
    }
}

struct GoalPlanStep: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var outcome: String
    var completionCriteria: [String]
    var status: GoalPlanStepStatus
    var summary: String
    var evidence: [String]
    var attempts: Int
    var noProgressTurns: Int

    var isDefined: Bool {
        !title.trimmed.isEmpty &&
        !outcome.trimmed.isEmpty &&
        !completionCriteria.filter({ !$0.trimmed.isEmpty }).isEmpty
    }
}

struct GoalExecutionPlan: Codable, Equatable, Sendable {
    var sessionID: String
    var objective: String
    var output: GoalOutputContract
    var steps: [GoalPlanStep]
    var approvedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var version: Int
    var lastCheckpointMessageID: UUID?

    var isApproved: Bool { approvedAt != nil }
    var isReadyForApproval: Bool {
        !objective.trimmed.isEmpty && output.isDefined && (3...8).contains(steps.count) && steps.allSatisfy(\.isDefined)
    }
    var completedStepCount: Int { steps.filter { $0.status == .complete }.count }
    var currentStepIndex: Int? {
        steps.firstIndex { $0.status == .inProgress } ??
        steps.firstIndex { $0.status == .blocked } ??
        steps.firstIndex { $0.status == .pending }
    }
    var currentStep: GoalPlanStep? { currentStepIndex.map { steps[$0] } }
    var isComplete: Bool { !steps.isEmpty && steps.allSatisfy { $0.status == .complete } }

    mutating func prepareForApproval() {
        approvedAt = Date()
        updatedAt = Date()
        version += 1
        for index in steps.indices {
            steps[index].status = index == 0 ? .inProgress : .pending
            steps[index].summary = ""
            steps[index].evidence = []
            steps[index].attempts = 0
            steps[index].noProgressTurns = 0
        }
    }

    mutating func apply(_ report: GoalStepProgressReport) {
        guard let index = currentStepIndex else { return }
        steps[index].attempts += 1

        let completesFinalOpenStep = report.status == .complete && steps.indices.allSatisfy {
            $0 == index || steps[$0].status == .complete
        }
        if completesFinalOpenStep {
            let verification = GoalOutputVerifier.verify(output)
            if verification.requiresLocalArtifact && !verification.isSatisfied {
                steps[index].status = .inProgress
                steps[index].summary = "LocalClaw rejected the completion claim. \(verification.detail)"
                steps[index].evidence = []
                steps[index].noProgressTurns += 1
                updatedAt = Date()
                return
            }
        }

        steps[index].summary = report.summary.trimmed
        steps[index].evidence = report.evidence.map(\.trimmed).filter { !$0.isEmpty }
        steps[index].noProgressTurns = report.evidence.isEmpty ? steps[index].noProgressTurns + 1 : 0

        switch report.status {
        case .working:
            steps[index].status = .inProgress
        case .blocked:
            steps[index].status = .blocked
        case .complete:
            steps[index].status = .complete
            if let next = steps.indices.first(where: { $0 > index && steps[$0].status != .complete }) {
                steps[next].status = .inProgress
            }
        }
        updatedAt = Date()
    }

    mutating func resetCurrentStepSafetyWindow() {
        guard let index = currentStepIndex else { return }
        steps[index].noProgressTurns = 0
        updatedAt = Date()
    }

    mutating func reopenFinalStepWhenOutputIsMissing() -> GoalOutputVerification? {
        guard isComplete, let index = steps.indices.last else { return nil }
        let verification = GoalOutputVerifier.verify(output)
        guard verification.requiresLocalArtifact, !verification.isSatisfied else { return nil }

        steps[index].status = .inProgress
        steps[index].summary = "LocalClaw reopened this step because the approved output is not present on disk."
        steps[index].evidence = []
        steps[index].noProgressTurns = 0
        updatedAt = Date()
        version += 1
        return verification
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum GoalStepProgressStatus: String, Codable, Sendable {
    case working
    case complete
    case blocked
}

struct GoalStepProgressReport: Codable, Equatable, Sendable {
    let status: GoalStepProgressStatus
    let summary: String
    let evidence: [String]
}

enum GoalPlanPrompt {
    static func make(objective: String, outputHint: String) -> String {
        let hint = outputHint.trimmed
        return """
        You are preparing a LocalClaw Goal. Plan the work, but do not execute it yet. Do not call tools. Do not create, edit, delete, download, or run anything. Use only the goal and context already present in this message and session.

        Goal:
        \(objective.trimmed)

        User output preference:
        \(hint.isEmpty ? "Propose the clearest concrete deliverable." : hint)

        Return only one JSON object with this exact structure:
        {
          "output": {
            "type": "Concrete deliverable type",
            "format": "Exact file format or technology",
            "location": "Concrete destination path or delivery location",
            "launch": "How the user opens, runs, or receives it",
            "completionCriteria": ["Observable final acceptance criterion"]
          },
          "steps": [
            {
              "title": "Short action title",
              "outcome": "Concrete result produced by this step",
              "completionCriteria": ["Observable evidence that this step is finished"]
            }
          ]
        }

        Use 3 to 8 meaningful steps. The output contract must make it unambiguous what files or result the user receives and how completion is verified. Use a concrete absolute destination inside the user's workspace when the output is a file or folder.

        Every step must be verifiable with local files, commands, tests, or other tools available to the agent. Never make manual user input, browser clicking, visual inspection, or unavailable UI automation a blocking completion criterion. For an interactive app or game, require deterministic automated smoke tests or static checks; a manual playthrough may be mentioned only as an optional handoff check after the automated criteria pass.

        Do not include markdown fences, commentary, estimates, hidden reasoning, or implementation work.
        """
    }
}

enum GoalPlanParser {
    static func parse(_ text: String, sessionID: String, objective: String) -> GoalExecutionPlan? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rawSteps = root["steps"] as? [[String: Any]] else { return nil }
        let rawOutput = root["output"] as? [String: Any] ?? root

        func string(_ key: String, in object: [String: Any]) -> String {
            (object[key] as? String)?.trimmed ?? ""
        }
        func criteria(in object: [String: Any]) -> [String] {
            if let values = object["completionCriteria"] as? [String] {
                return values.map(\.trimmed).filter { !$0.isEmpty }
            }
            if let value = object["completionCriteria"] as? String, !value.trimmed.isEmpty {
                return [value.trimmed]
            }
            return []
        }

        let steps = rawSteps.prefix(8).enumerated().map { index, step in
            GoalPlanStep(
                id: "step-\(index + 1)",
                title: string("title", in: step),
                outcome: string("outcome", in: step),
                completionCriteria: criteria(in: step),
                status: .pending,
                summary: "",
                evidence: [],
                attempts: 0,
                noProgressTurns: 0
            )
        }
        return GoalExecutionPlan(
            sessionID: sessionID,
            objective: objective.trimmed,
            output: GoalOutputContract(
                type: string("type", in: rawOutput),
                format: string("format", in: rawOutput),
                location: string("location", in: rawOutput),
                launch: string("launch", in: rawOutput),
                completionCriteria: criteria(in: rawOutput)
            ),
            steps: steps,
            approvedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            version: 1,
            lastCheckpointMessageID: nil
        )
    }
}

enum GoalProgressParser {
    private static let opening = "<localclaw_progress>"
    private static let closing = "</localclaw_progress>"

    static func parse(_ text: String) -> (report: GoalStepProgressReport?, cleanedText: String) {
        guard let openRange = text.range(of: opening, options: .backwards),
              let closeRange = text.range(of: closing, options: .backwards),
              openRange.upperBound <= closeRange.lowerBound else {
            return (nil, text.trimmed)
        }
        let payload = String(text[openRange.upperBound..<closeRange.lowerBound]).trimmed
        let report = payload.data(using: .utf8).flatMap { try? JSONDecoder().decode(GoalStepProgressReport.self, from: $0) }
        var cleaned = text
        cleaned.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        return (report, cleaned.trimmed)
    }
}

enum GoalPlanStore {
    private static let defaultsKey = "localclaw.goal.executionPlans.v1"

    static func load(sessionID: String) -> GoalExecutionPlan? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let plans = try? JSONDecoder().decode([String: GoalExecutionPlan].self, from: data) else { return nil }
        return plans[sessionID]
    }

    static func save(_ plan: GoalExecutionPlan) {
        var plans: [String: GoalExecutionPlan] = [:]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: GoalExecutionPlan].self, from: data) {
            plans = decoded
        }
        plans[plan.sessionID] = plan
        guard let data = try? JSONEncoder().encode(plans) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func remove(sessionID: String) {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var plans = try? JSONDecoder().decode([String: GoalExecutionPlan].self, from: data) else { return }
        plans.removeValue(forKey: sessionID)
        if let encoded = try? JSONEncoder().encode(plans) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }
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
    static func make(plan: GoalExecutionPlan, starting: Bool) -> String {
        let action = starting ? "Begin" : "Continue"
        let planLines = plan.steps.enumerated().map { index, step in
            let marker: String
            switch step.status {
            case .complete: marker = "complete"
            case .inProgress: marker = "current"
            case .blocked: marker = "blocked"
            case .pending: marker = "pending"
            }
            return "\(index + 1). [\(marker)] \(step.title) — \(step.outcome)"
        }.joined(separator: "\n")
        let outputCriteria = plan.output.completionCriteria.map { "- \($0)" }.joined(separator: "\n")
        let currentCriteria = plan.currentStep?.completionCriteria.map { "- \($0)" }.joined(separator: "\n") ?? "- Verify the approved outcome."
        let currentTitle = plan.currentStep?.title ?? "Final verification"
        let currentOutcome = plan.currentStep?.outcome ?? "Verify the complete output contract."
        let outputVerification = GoalOutputVerifier.verify(plan.output)
        let localOutputInstruction = outputVerification.requiresLocalArtifact
            ? "LocalClaw host filesystem check: \(outputVerification.detail) You must create and verify the real artifact at this exact destination before reporting the final step complete."
            : "LocalClaw host filesystem check: this output is delivered outside the local filesystem. Provide concrete delivery evidence before reporting the final step complete."
        return """
        A user-approved LocalClaw Goal plan is active for this OpenClaw session.

        Objective:
        \(plan.objective)

        Approved output contract:
        - Type: \(plan.output.type)
        - Format or technology: \(plan.output.format)
        - Destination: \(plan.output.location)
        - Open or deliver with: \(plan.output.launch)

        Final completion criteria:
        \(outputCriteria)

        Approved plan:
        \(planLines)

        Current step:
        \(currentTitle)

        Required outcome:
        \(currentOutcome)

        Step completion criteria:
        \(currentCriteria)

        \(localOutputInstruction)

        \(action) the current step from the existing workspace and session state. Inspect existing work before changing anything, preserve completed results, and do not repeat successful external calls. Work only toward the current step and approved output contract.

        Actually call the available file, shell, and test tools when work or verification requires them. Never invent a tool result, never describe an unexecuted command as evidence, and never claim a file exists unless the tool call confirmed it on disk.

        At the very end of your response, include exactly one machine-readable progress block:
        <localclaw_progress>
        {"status":"working|complete|blocked","summary":"short factual progress summary","evidence":["file, command, test, or observable result"]}
        </localclaw_progress>

        Use status complete only when every criterion for the current step is satisfied. Use blocked only for a genuine blocker that cannot be resolved autonomously. Otherwise use working.

        Verification must use tools available in this autonomous run. If an approved criterion asks for manual interaction, browser clicking, visual inspection, or unavailable UI automation, do not wait or loop on it. Replace it with the strongest deterministic automated smoke test or static verification you can run, record that evidence, and treat any remaining manual check as optional handoff guidance. Never wait for user interaction during this run.

        Do not call update_goal yourself; LocalClaw advances and completes the durable Goal from the approved plan.
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

enum GoalControllerResourceLocator {
    private static let resourceBundleName = "localclaw-mac-installer_localclaw-mac-installer.bundle"
    private static let scriptName = "goal-controller.mjs"

    static func locate() -> URL? {
        let fileManager = FileManager.default
        return candidateURLs(
            bundleURL: Bundle.main.bundleURL,
            resourceURL: Bundle.main.resourceURL,
            executableURL: Bundle.main.executableURL
        ).first { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }

    static func candidateURLs(bundleURL: URL, resourceURL: URL?, executableURL: URL?) -> [URL] {
        var roots = [bundleURL]
        if let resourceURL { roots.append(resourceURL) }
        if let executableURL { roots.append(executableURL.deletingLastPathComponent()) }

        var expandedRoots: [URL] = []
        for root in roots {
            var current = root.standardizedFileURL
            for _ in 0..<5 {
                expandedRoots.append(current)
                let parent = current.deletingLastPathComponent()
                if parent == current { break }
                current = parent
            }
        }

        var seen = Set<String>()
        var candidates: [URL] = []
        for root in expandedRoots {
            let paths = [
                root.appendingPathComponent(resourceBundleName, isDirectory: true).appendingPathComponent(scriptName),
                root.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(resourceBundleName, isDirectory: true).appendingPathComponent(scriptName),
                root.appendingPathComponent(scriptName),
            ]
            for path in paths {
                let standardized = path.standardizedFileURL
                if seen.insert(standardized.path).inserted { candidates.append(standardized) }
            }
        }
        return candidates
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

        guard let scriptURL = GoalControllerResourceLocator.locate() else {
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
    @Published var outputHint = ""
    @Published var note = ""
    @Published var snapshot: OpenClawGoalSnapshot?
    @Published var plan: GoalExecutionPlan?
    @Published var statusMessage = "Choose a discussion to create a durable objective."
    @Published var isBusy = false
    @Published var isGeneratingPlan = false
    @Published var showClearConfirmation = false
    @Published var lastRefresh: Date?
    @Published private(set) var continuousRunEnabled = false
    @Published private(set) var automaticTurns = 0

    private let bridge = OpenClawGoalBridge.shared
    private var continuousTask: Task<Void, Never>?

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
        if sessionID != selectedChatSessionID {
            stopContinuousRun(message: "Waiting for the next step.")
        }
        guard !sessionID.isEmpty else {
            selectedChatSessionID = ""
            snapshot = nil
            plan = nil
            return
        }
        selectedChatSessionID = sessionID
        var loadedPlan = GoalPlanStore.load(sessionID: sessionID)
        let outputRecovery = loadedPlan?.reopenFinalStepWhenOutputIsMissing()
        if let loadedPlan, outputRecovery != nil {
            GoalPlanStore.save(loadedPlan)
        }
        plan = loadedPlan
        if let plan { objective = plan.objective }
        await refresh()
        if let outputRecovery {
            statusMessage = "Completion was reopened: \(outputRecovery.detail) Repair the missing output to finish this Goal."
        } else if let plan, plan.isApproved, plan.currentStep?.status == .inProgress, snapshot?.status == .active {
            statusMessage = "Goal interrupted during \(plan.currentStep?.title ?? "the current step"). Resume when ready."
        }
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

    func generatePlan(using viewModel: InstallerViewModel) {
        let trimmedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedObjective.isEmpty, !selectedChatSessionID.isEmpty else {
            statusMessage = "Describe the result you want first."
            return
        }
        guard !viewModel.chatIsSending, !isGeneratingPlan else { return }

        isGeneratingPlan = true
        statusMessage = "Preparing the output contract and proposed plan..."
        let sessionID = selectedChatSessionID
        let previousMessageID = viewModel.normalChatSessions
            .first(where: { $0.id == sessionID })?
            .messages.last?.id

        viewModel.sendGoalPlanningRequest(
            chatSessionID: sessionID,
            objective: trimmedObjective,
            outputHint: outputHint
        )
        guard viewModel.chatIsSending else {
            isGeneratingPlan = false
            statusMessage = "The planning request could not start."
            return
        }

        Task { @MainActor [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            while viewModel.chatIsSending && self.selectedChatSessionID == sessionID {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard self.selectedChatSessionID == sessionID else {
                self.isGeneratingPlan = false
                return
            }
            let latest = viewModel.normalChatSessions
                .first(where: { $0.id == sessionID })?
                .messages.last
            guard latest?.id != previousMessageID, let latest, latest.role == "assistant" else {
                self.isGeneratingPlan = false
                self.statusMessage = "The model could not propose a plan. Review the latest discussion message and retry."
                return
            }
            guard let proposal = GoalPlanParser.parse(latest.text, sessionID: sessionID, objective: trimmedObjective) else {
                self.isGeneratingPlan = false
                self.statusMessage = "The proposed plan was not structured correctly. Retry or choose a stronger planning model."
                return
            }
            self.plan = proposal
            GoalPlanStore.save(proposal)
            viewModel.removeGoalPlanningMessage(sessionID: sessionID, messageID: latest.id)
            self.isGeneratingPlan = false
            self.statusMessage = proposal.isReadyForApproval
                ? "Review the output and plan before starting."
                : "Complete the missing output or step details before approval."
        }
    }

    func updateDraftPlan(_ updated: GoalExecutionPlan) {
        guard updated.sessionID == selectedChatSessionID, updated.approvedAt == nil else { return }
        var saved = updated
        saved.updatedAt = Date()
        plan = saved
        objective = saved.objective
        GoalPlanStore.save(saved)
    }

    func reconcileLatestCheckpoint(using viewModel: InstallerViewModel) async {
        guard var recoveredPlan = plan, recoveredPlan.isApproved,
              let latest = viewModel.normalChatSessions
                .first(where: { $0.id == selectedChatSessionID })?
                .messages.last,
              latest.role == "assistant" else { return }
        let parsed = GoalProgressParser.parse(latest.text)
        guard parsed.cleanedText != latest.text else { return }

        if recoveredPlan.lastCheckpointMessageID != latest.id {
            if let report = parsed.report {
                recoveredPlan.apply(report)
            } else if let index = recoveredPlan.currentStepIndex {
                recoveredPlan.steps[index].attempts += 1
                recoveredPlan.steps[index].noProgressTurns += 1
                recoveredPlan.steps[index].summary = "The recovered response did not contain a valid progress checkpoint."
                recoveredPlan.updatedAt = Date()
            }
            recoveredPlan.lastCheckpointMessageID = latest.id
            plan = recoveredPlan
            GoalPlanStore.save(recoveredPlan)
        }
        viewModel.replaceGoalMessageText(sessionID: selectedChatSessionID, messageID: latest.id, text: parsed.cleanedText)

        if recoveredPlan.isComplete, snapshot?.status != .complete {
            await complete()
        } else if recoveredPlan.currentStep?.status == .blocked, snapshot?.status == .active {
            await block()
        } else {
            statusMessage = "Recovered the latest checkpoint. Resume when ready."
        }
    }

    func addDraftStep() {
        guard var plan, !plan.isApproved, plan.steps.count < 8 else { return }
        let number = plan.steps.count + 1
        plan.steps.append(GoalPlanStep(
            id: "step-\(number)-\(UUID().uuidString.prefix(6))",
            title: "New step",
            outcome: "Describe the concrete result of this step.",
            completionCriteria: ["Describe how completion will be verified."],
            status: .pending,
            summary: "",
            evidence: [],
            attempts: 0,
            noProgressTurns: 0
        ))
        updateDraftPlan(plan)
    }

    func removeDraftStep(id: String) {
        guard var plan, !plan.isApproved, plan.steps.count > 3 else { return }
        plan.steps.removeAll { $0.id == id }
        updateDraftPlan(plan)
    }

    func moveDraftStep(id: String, offset: Int) {
        guard var plan, !plan.isApproved, let index = plan.steps.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard plan.steps.indices.contains(destination) else { return }
        let step = plan.steps.remove(at: index)
        plan.steps.insert(step, at: destination)
        updateDraftPlan(plan)
    }

    func approveAndStart(using viewModel: InstallerViewModel) {
        guard var approvedPlan = plan, approvedPlan.isReadyForApproval, !approvedPlan.isApproved else {
            statusMessage = "Define the output and every plan step before approval."
            return
        }
        approvedPlan.prepareForApproval()
        plan = approvedPlan
        objective = approvedPlan.objective
        GoalPlanStore.save(approvedPlan)
        statusMessage = "Plan approved. Creating the durable Goal..."

        Task { @MainActor [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            let ready: Bool
            if self.snapshot == nil {
                ready = await self.start()
            } else if self.snapshot?.status == .active {
                ready = await self.edit()
            } else {
                _ = await self.edit()
                await self.resume()
                ready = self.snapshot?.status == .active
            }
            guard ready else {
                if var plan = self.plan {
                    plan.approvedAt = nil
                    self.plan = plan
                    GoalPlanStore.save(plan)
                }
                return
            }
            self.startContinuousRun(using: viewModel, starting: true)
        }
    }

    func edit() async -> Bool {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "The goal objective cannot be empty."
            return false
        }
        return await perform(action: "edit", objective: trimmed)
    }

    func pause() async {
        stopContinuousRun(message: "Pausing Goal...")
        _ = await perform(action: "pause", note: note)
    }
    private func pauseForSafety(_ reason: String) async {
        stopContinuousRun(message: reason)
        _ = await perform(action: "pause", note: reason)
        statusMessage = reason
    }
    func resume() async {
        if var resumedPlan = plan {
            resumedPlan.resetCurrentStepSafetyWindow()
            plan = resumedPlan
            GoalPlanStore.save(resumedPlan)
        }
        _ = await perform(action: "resume", note: note)
    }
    func complete() async {
        stopContinuousRun(message: "Completing Goal...")
        _ = await perform(action: "complete", note: note)
    }
    func block() async {
        stopContinuousRun(message: "Blocking Goal...")
        _ = await perform(action: "block", note: note)
    }
    func clear() async {
        stopContinuousRun(message: "Clearing Goal...")
        _ = await perform(action: "clear")
        GoalPlanStore.remove(sessionID: selectedChatSessionID)
        plan = nil
        objective = ""
        outputHint = ""
    }

    static func shouldContinueAutomatically(
        enabled: Bool,
        status: GoalLifecycleStatus?,
        latestMessageRole: String?
    ) -> Bool {
        enabled && status == .active && latestMessageRole != "error"
    }

    func startContinuousRun(using viewModel: InstallerViewModel, starting: Bool) {
        guard !selectedChatSessionID.isEmpty,
              snapshot?.status == .active,
              plan?.isApproved == true,
              plan?.currentStep != nil,
              !viewModel.chatIsSending else {
            statusMessage = "Approve a complete output contract and plan before running this Goal."
            return
        }

        continuousTask?.cancel()
        continuousRunEnabled = true
        automaticTurns = 0
        let sessionID = selectedChatSessionID
        statusMessage = "Continuous run started. The model is preparing the next step."

        continuousTask = Task { @MainActor [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            defer {
                if self.selectedChatSessionID != sessionID {
                    self.continuousTask = nil
                    self.continuousRunEnabled = false
                    self.statusMessage = "Continuous run stopped because the selected discussion changed."
                }
            }
            var isStartingTurn = starting

            while !Task.isCancelled && self.continuousRunEnabled && self.selectedChatSessionID == sessionID {
                await self.refresh()
                guard Self.shouldContinueAutomatically(
                    enabled: self.continuousRunEnabled,
                    status: self.snapshot?.status,
                    latestMessageRole: nil
                ) else {
                    self.finishContinuousRunForCurrentStatus()
                    return
                }

                if viewModel.chatIsSending {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }

                guard viewModel.goalRuntimeReadiness.canStart else {
                    self.stopContinuousRun(message: "Continuous run stopped because the selected runtime is not ready.")
                    return
                }

                guard let currentPlan = self.plan, currentPlan.isApproved, currentPlan.currentStep != nil else {
                    self.stopContinuousRun(message: "Continuous run stopped because the approved plan is unavailable.")
                    return
                }
                let previousMessageID = viewModel.normalChatSessions
                    .first(where: { $0.id == sessionID })?
                    .messages.last?.id
                let stepNumber = (currentPlan.currentStepIndex ?? 0) + 1
                self.statusMessage = "Working on Step \(stepNumber) of \(currentPlan.steps.count): \(currentPlan.currentStep?.title ?? "Current step")"
                viewModel.sendGoalAdvance(
                    chatSessionID: sessionID,
                    runtimeSessionID: Self.runtimeSessionID(for: sessionID),
                    plan: currentPlan,
                    starting: isStartingTurn
                )

                guard viewModel.chatIsSending else {
                    self.stopContinuousRun(message: "Continuous run could not start the next model request.")
                    return
                }

                while viewModel.chatIsSending && !Task.isCancelled && self.continuousRunEnabled {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                guard !Task.isCancelled && self.continuousRunEnabled else { return }

                await self.refresh()
                let latestMessage = viewModel.normalChatSessions
                    .first(where: { $0.id == sessionID })?
                    .messages.last
                let latestRole = latestMessage?.id == previousMessageID ? nil : latestMessage?.role
                self.automaticTurns += 1

                if latestRole == "assistant", let latestMessage, var updatedPlan = self.plan {
                    let parsed = GoalProgressParser.parse(latestMessage.text)
                    if updatedPlan.lastCheckpointMessageID != latestMessage.id {
                        if let report = parsed.report {
                            updatedPlan.apply(report)
                        } else if let index = updatedPlan.currentStepIndex {
                            updatedPlan.steps[index].attempts += 1
                            updatedPlan.steps[index].noProgressTurns += 1
                            updatedPlan.steps[index].summary = "The model responded without a verifiable progress checkpoint."
                            updatedPlan.updatedAt = Date()
                        }
                        updatedPlan.lastCheckpointMessageID = latestMessage.id
                        self.plan = updatedPlan
                        GoalPlanStore.save(updatedPlan)
                    }
                    if parsed.cleanedText != latestMessage.text {
                        viewModel.replaceGoalMessageText(
                            sessionID: sessionID,
                            messageID: latestMessage.id,
                            text: parsed.cleanedText
                        )
                    }

                    if updatedPlan.isComplete {
                        self.statusMessage = "Every approved step is complete. Finalizing the Goal..."
                        await self.complete()
                        return
                    }
                    if updatedPlan.currentStep?.status == .blocked {
                        self.statusMessage = "The current step is blocked."
                        await self.block()
                        return
                    }
                    if let current = updatedPlan.currentStep, current.noProgressTurns >= 3 {
                        await self.pauseForSafety("Paused after three turns without verifiable progress on \(current.title).")
                        return
                    }
                }

                guard Self.shouldContinueAutomatically(
                    enabled: self.continuousRunEnabled,
                    status: self.snapshot?.status,
                    latestMessageRole: latestRole
                ) else {
                    if latestRole == "error" {
                        self.stopContinuousRun(message: "Continuous run stopped after an error. Review the latest progress, then retry when ready.")
                    } else {
                        self.finishContinuousRunForCurrentStatus()
                    }
                    return
                }

                if let plan = self.plan, let step = plan.currentStep {
                    self.statusMessage = "Checkpoint saved. Continuing with \(step.title)..."
                } else {
                    self.statusMessage = "Checkpoint saved. Continuing automatically..."
                }
                isStartingTurn = false
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stopContinuousRun(message: String = "Continuous run stopped. The Goal remains active.") {
        continuousTask?.cancel()
        continuousTask = nil
        continuousRunEnabled = false
        statusMessage = message
    }

    private func finishContinuousRunForCurrentStatus() {
        continuousTask = nil
        continuousRunEnabled = false
        switch snapshot?.status {
        case .complete:
            statusMessage = "Goal complete."
        case .blocked:
            statusMessage = "Continuous run stopped because the Goal is blocked."
        case .paused:
            statusMessage = "Goal paused."
        case .usageLimited:
            statusMessage = "Continuous run stopped at the usage limit."
        case .budgetLimited:
            statusMessage = "Continuous run stopped at the token budget."
        default:
            statusMessage = "Waiting for the next step."
        }
    }

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
