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

enum GoalSessionMaintenance {
    static let localTranscriptLines = 12
    static let newGoalTranscriptLines = 1
    static let localGoalTokenBudget = 80_000
    static let localRunTokenBudget = 60_000

    static func isLocalModel(_ modelID: String) -> Bool {
        modelID.lowercased().hasPrefix("lmstudio/")
    }

    static func compactCommand(sessionKey: String, maxLines: Int) -> String {
        let escaped = sessionKey.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "openclaw --no-color sessions compact '\(escaped)' --max-lines \(max(maxLines, 1)) --timeout 30000 --json 2>&1"
    }

    static func isTimeoutMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("timed out before") || lower.contains("request timed out") || lower.contains("deadline exceeded")
    }

    static func isContextOverflowMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("context overflow") ||
            lower.contains("prompt too large") ||
            (lower.contains("context length") && lower.contains("exceed"))
    }

    static func exceededRunBudget(startTokens: Int, currentTokens: Int, budget: Int = localRunTokenBudget) -> Bool {
        max(currentTokens - startTokens, 0) >= budget
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
    var approvalIssue: String? {
        if objective.trimmed.isEmpty { return "Describe the Goal before approval." }
        if !output.isDefined { return "Complete every expected output field before approval." }
        if steps.count < 2 { return "Add at least two concrete plan steps before approval." }
        if steps.count > 8 { return "Keep the plan to eight steps or fewer." }
        if !steps.allSatisfy(\.isDefined) { return "Complete the outcome and definition of done for every step." }
        return nil
    }
    var isReadyForApproval: Bool { approvalIssue == nil }
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

        Use 2 to 8 meaningful steps. Prefer 2 or 3 steps for a small, focused deliverable. If the output is one HTML, text, script, or document file, use exactly two steps: create the complete final file, then verify that exact file. Never add a placeholder-only project structure step for a single-file output. The output contract must make it unambiguous what files or result the user receives and how completion is verified. Use a concrete absolute destination inside the user's workspace when the output is a file or folder.

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

    static func sessionIDsByMostRecentUpdate() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let plans = try? JSONDecoder().decode([String: GoalExecutionPlan].self, from: data) else { return [] }
        return plans.values.sorted { $0.updatedAt > $1.updatedAt }.map(\.sessionID)
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
        let previousSummary = plan.currentStep?.summary.trimmed ?? ""
        let previousEvidence = plan.currentStep?.evidence.map { "- \($0)" }.joined(separator: "\n") ?? ""
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

        Previous checkpoint for this step:
        \(previousSummary.isEmpty ? "No verified progress has been saved yet." : previousSummary)
        \(previousEvidence.isEmpty ? "" : previousEvidence)

        \(localOutputInstruction)

        \(action) the current step from the existing workspace and session state. Inspect existing work before changing anything, preserve completed results, and do not repeat successful external calls. Work only toward the current step and approved output contract.

        Actually call the available file, shell, and test tools when work or verification requires them. Never invent a tool result, never describe an unexecuted command as evidence, and never claim a file exists unless the tool call confirmed it on disk.

        Execution discipline for compact and local models:
        - Start with the first necessary tool call instead of narrating a plan.
        - Complete only this current step in the fewest useful tool calls.
        - For a single-file deliverable, write the complete file directly instead of creating placeholders.
        - Keep the visible final response below 180 words; put substantive work in the artifact and tool calls.

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

struct LocalGoalArtifactGeneration: Equatable, Sendable {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
}

enum LocalGoalArtifactError: LocalizedError {
    case unsupportedDestination
    case invalidResponse(String)
    case invalidArtifact(String)
    case contextBudget(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDestination:
            return "The approved output must be one supported file inside ~/.openclaw/workspace."
        case .invalidResponse(let message), .invalidArtifact(let message), .contextBudget(let message), .server(let message):
            return message
        }
    }
}

enum LocalGoalArtifactSupport {
    private static let supportedExtensions = Set([
        "css", "csv", "html", "htm", "js", "json", "md", "py", "sh", "svg", "swift", "txt", "xml", "yaml", "yml",
    ])

    static func destination(
        for plan: GoalExecutionPlan,
        homeDirectory: String = NSHomeDirectory()
    ) -> URL? {
        guard let path = GoalOutputVerifier.resolvedLocalPath(plan.output.location) else { return nil }
        let destination = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let workspace = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".openclaw/workspace", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard destination.path.hasPrefix(workspace.path + "/"),
              supportedExtensions.contains(destination.pathExtension.lowercased()) else { return nil }
        return destination
    }

    static func estimatedTokenCount(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }

    static func outputTokenBudget(prompt: String, contextTokens: Int) throws -> Int {
        let context = max(contextTokens, 4_096)
        let promptTokens = estimatedTokenCount(prompt)
        let safetyReserve = max(768, context / 16)
        let available = context - promptTokens - safetyReserve
        guard available >= 1_024 else {
            throw LocalGoalArtifactError.contextBudget(
                "The approved specification itself is too large for the loaded local context. Shorten the Goal or reload the model with a larger context window."
            )
        }
        return min(12_000, min(context * 2 / 5, available))
    }

    static func artifactContent(from rawText: String, pathExtension: String) throws -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fencedParts = text.components(separatedBy: "```")
        if fencedParts.count >= 3 {
            let candidates = stride(from: 1, to: fencedParts.count, by: 2).map { index -> String in
                var candidate = fencedParts[index]
                if let newline = candidate.firstIndex(of: "\n") {
                    let firstLine = candidate[..<newline].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if firstLine.count <= 16 && !firstLine.contains("<") && !firstLine.contains("{") {
                        candidate = String(candidate[candidate.index(after: newline)...])
                    }
                }
                return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let largest = candidates.max(by: { $0.count < $1.count }), !largest.isEmpty {
                text = largest
            }
        }

        let ext = pathExtension.lowercased()
        if ext == "html" || ext == "htm" {
            let lower = text.lowercased()
            if let start = lower.range(of: "<!doctype html")?.lowerBound ?? lower.range(of: "<html")?.lowerBound {
                text = String(text[start...])
            }
            let normalized = text.lowercased()
            guard (normalized.contains("<!doctype html") || normalized.contains("<html")),
                  normalized.contains("</html>") else {
                throw LocalGoalArtifactError.invalidArtifact("The local model returned incomplete HTML, so LocalClaw did not publish a partial file.")
            }
        }
        guard !text.isEmpty else {
            throw LocalGoalArtifactError.invalidArtifact("The local model returned an empty artifact.")
        }
        return text + (text.hasSuffix("\n") ? "" : "\n")
    }

    static func parseResponse(_ data: Data) throws -> LocalGoalArtifactGeneration {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalGoalArtifactError.invalidResponse("LM Studio returned an unreadable response.")
        }

        func strings(in value: Any?) -> [String] {
            if let value = value as? String { return [value] }
            if let values = value as? [Any] { return values.flatMap { strings(in: $0) } }
            if let value = value as? [String: Any] {
                if let text = value["text"] as? String { return [text] }
                return strings(in: value["content"])
            }
            return []
        }

        var content = ""
        if let output = root["output"] as? [[String: Any]] {
            content = output
                .filter { ($0["type"] as? String) == "message" || $0["content"] != nil }
                .flatMap { strings(in: $0["content"]) }
                .joined(separator: "\n")
        }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {
            content = strings(in: message["content"]).joined(separator: "\n")
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = ((root["error"] as? [String: Any])?["message"] as? String)
                ?? "LM Studio finished without returning file content."
            throw LocalGoalArtifactError.invalidResponse(message)
        }

        let stats = root["stats"] as? [String: Any]
        let usage = root["usage"] as? [String: Any]
        let inputTokens = (stats?["input_tokens"] as? NSNumber)?.intValue
            ?? (usage?["prompt_tokens"] as? NSNumber)?.intValue
            ?? 0
        let outputTokens = (stats?["output_tokens"] as? NSNumber)?.intValue
            ?? (stats?["total_output_tokens"] as? NSNumber)?.intValue
            ?? (usage?["completion_tokens"] as? NSNumber)?.intValue
            ?? 0
        return LocalGoalArtifactGeneration(content: content, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    static func write(_ content: String, to destination: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = content.data(using: .utf8) else {
            throw LocalGoalArtifactError.invalidArtifact("The generated artifact could not be encoded as UTF-8.")
        }
        try data.write(to: destination, options: .atomic)
    }
}

actor LocalGoalArtifactGenerator {
    static let shared = LocalGoalArtifactGenerator()

    func generate(
        modelID: String,
        plan: GoalExecutionPlan,
        existingContent: String? = nil,
        contextTokens: Int = 32_768
    ) async throws -> LocalGoalArtifactGeneration {
        guard let destination = LocalGoalArtifactSupport.destination(for: plan) else {
            throw LocalGoalArtifactError.unsupportedDestination
        }
        let settings = Self.lmStudioSettings()
        var request = URLRequest(url: settings.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 360
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = settings.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let model = modelID.lowercased().hasPrefix("lmstudio/")
            ? String(modelID.dropFirst("lmstudio/".count))
            : modelID
        let criteria = plan.output.completionCriteria.map { "- \($0)" }.joined(separator: "\n")
        let task = if let existingContent {
            """
            Review the existing file below against every completion criterion. Correct all functional, structural, and syntax problems, then return the complete corrected file.

            Existing file:
            <existing_file>
            \(existingContent)
            </existing_file>
            """
        } else {
            "Create the complete approved file now."
        }
        let objective = existingContent == nil
            ? plan.objective
            : String(plan.objective.prefix(1_200))
        let prompt = """
        \(task)

        Objective:
        \(objective)

        Output type: \(plan.output.type)
        Format: \(plan.output.format)
        Filename: \(destination.lastPathComponent)
        Completion criteria:
        \(criteria)

        Return only the exact raw contents of that one file. Do not use Markdown fences, JSON wrappers, commentary, placeholders, TODOs, or tool calls. The file must be complete and usable as delivered.
        """
        let maxOutputTokens = try LocalGoalArtifactSupport.outputTokenBudget(
            prompt: prompt,
            contextTokens: contextTokens
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": prompt,
            "system_prompt": "You generate complete standalone file contents. Output only the requested file, with no explanation and no tool calls.",
            "reasoning": "off",
            "temperature": 0.15,
            "max_output_tokens": maxOutputTokens,
            "stream": false,
        ])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 360
        configuration.timeoutIntervalForResource = 390
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                let detail = (try? LocalGoalArtifactSupport.parseResponse(data).content)
                    ?? String(data: data, encoding: .utf8)
                    ?? "HTTP \(status)"
                throw LocalGoalArtifactError.server("LM Studio could not generate the approved file: \(detail.prefix(500))")
            }
            return try LocalGoalArtifactSupport.parseResponse(data)
        } catch let error as LocalGoalArtifactError {
            throw error
        } catch {
            throw LocalGoalArtifactError.server("LM Studio did not finish the direct file generation: \(error.localizedDescription)")
        }
    }

    private static func lmStudioSettings() -> (endpoint: URL, apiKey: String?) {
        var baseURL = URL(string: "http://127.0.0.1:1234/v1")!
        var apiKey: String?
        let configURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".openclaw/openclaw.json")
        if let data = try? Data(contentsOf: configURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = root["models"] as? [String: Any],
           let providers = models["providers"] as? [String: Any],
           let lmStudio = providers["lmstudio"] as? [String: Any] {
            if let configured = lmStudio["baseUrl"] as? String, let url = URL(string: configured) {
                baseURL = url
            }
            apiKey = lmStudio["apiKey"] as? String
        }
        if baseURL.path.hasSuffix("/v1") {
            baseURL.deleteLastPathComponent()
        }
        return (baseURL.appendingPathComponent("api/v1/chat"), apiKey)
    }
}

private enum LocalGoalDirectTurnResult {
    case unsupported
    case progressed
    case finished
    case failed
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
    let tokenBudget: Int?
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
    static func locate(scriptName: String = "goal-controller.mjs") -> URL? {
        let fileManager = FileManager.default
        return candidateURLs(
            bundleURL: Bundle.main.bundleURL,
            resourceURL: Bundle.main.resourceURL,
            executableURL: Bundle.main.executableURL,
            scriptName: scriptName
        ).first { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }

    static func candidateURLs(bundleURL: URL, resourceURL: URL?, executableURL: URL?, scriptName: String = "goal-controller.mjs") -> [URL] {
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

    func request(action: String, sessionKey: String, objective: String? = nil, note: String? = nil, tokenBudget: Int? = nil) throws -> (OpenClawGoalSnapshot?, String) {
        try ensureProcess()
        let request = GoalControllerRequest(
            id: UUID().uuidString,
            action: action,
            sessionKey: sessionKey,
            objective: objective,
            note: note,
            tokenBudget: tokenBudget
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
    private static let selectedSessionDefaultsKey = "localclaw.goal.selectedSessionID"

    @Published var selectedChatSessionID = UserDefaults.standard.string(forKey: GoalCenterModel.selectedSessionDefaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(selectedChatSessionID, forKey: Self.selectedSessionDefaultsKey) }
    }
    @Published var projectName = ""
    @Published var objective = ""
    @Published var outputHint = ""
    @Published var note = ""
    @Published var snapshot: OpenClawGoalSnapshot?
    @Published var plan: GoalExecutionPlan?
    @Published var statusMessage = "Name the project and describe the result you want."
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

    static func planningRuntimeSessionID(for chatSessionID: String, nonce: String = UUID().uuidString) -> String {
        "\(runtimeSessionID(for: chatSessionID))-plan-\(String(nonce.prefix(12)))"
    }

    static func workRuntimeSessionID(chatSessionID: String, stepID: String, turn: Int) -> String {
        let cleanedStep = stepID.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        }
        return "\(runtimeSessionID(for: chatSessionID))-work-\(String(cleanedStep).prefix(32))-\(max(turn, 0))"
    }

    static func openClawSessionKey(for chatSessionID: String, agentID: String = "main") -> String {
        "agent:\(agentID):explicit:\(runtimeSessionID(for: chatSessionID))"
    }

    func selectSession(_ sessionID: String, projectName: String? = nil) async {
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
        if let projectName, !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.projectName = projectName
        }
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

    func beginNewGoal() {
        stopContinuousRun(message: "Name the project and describe the result you want.")
        selectedChatSessionID = ""
        projectName = ""
        objective = ""
        outputHint = ""
        note = ""
        snapshot = nil
        plan = nil
        statusMessage = "Name the project and describe the result you want."
    }

    func refresh() async {
        guard !selectedChatSessionID.isEmpty, !isBusy else { return }
        await perform(action: "status")
    }

    func start(tokenBudget: Int? = nil) async -> Bool {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Describe the result you want first."
            return false
        }
        return await perform(action: "start", objective: trimmed, tokenBudget: tokenBudget)
    }

    func generatePlan(using viewModel: InstallerViewModel) {
        let trimmedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedObjective.isEmpty else {
            statusMessage = "Describe the result you want first."
            return
        }
        if selectedChatSessionID.isEmpty {
            let trimmedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedProjectName.isEmpty else {
                statusMessage = "Name this Goal project first."
                return
            }
            selectedChatSessionID = viewModel.createGoalDiscussion(projectName: trimmedProjectName)
            projectName = trimmedProjectName
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
            viewModel.removeGoalMessage(sessionID: sessionID, messageID: latest.id)
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
        guard var plan, !plan.isApproved, plan.steps.count > 2 else { return }
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
                if GoalSessionMaintenance.isLocalModel(viewModel.selectedGoalModelID) {
                    self.statusMessage = "Preparing a clean local Goal session..."
                    _ = await self.compactGoalTranscript(maxLines: GoalSessionMaintenance.newGoalTranscriptLines)
                }
                let tokenBudget = GoalSessionMaintenance.isLocalModel(viewModel.selectedGoalModelID)
                    ? GoalSessionMaintenance.localGoalTokenBudget
                    : nil
                ready = await self.start(tokenBudget: tokenBudget)
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

    func resumeForExecution(using viewModel: InstallerViewModel) async -> Bool {
        if snapshot?.status == .complete, plan?.isComplete == false {
            guard await perform(action: "clear") else { return false }
            let tokenBudget = GoalSessionMaintenance.isLocalModel(viewModel.selectedGoalModelID)
                ? GoalSessionMaintenance.localGoalTokenBudget
                : nil
            return await start(tokenBudget: tokenBudget)
        }
        await resume()
        return snapshot?.status == .active
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
        selectedChatSessionID = ""
        projectName = ""
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

    private func executeDirectLocalArtifactTurn(
        using viewModel: InstallerViewModel,
        plan currentPlan: GoalExecutionPlan,
        sessionID: String
    ) async -> LocalGoalDirectTurnResult {
        guard let destination = LocalGoalArtifactSupport.destination(for: currentPlan),
              let currentIndex = currentPlan.currentStepIndex else { return .unsupported }

        do {
            var generatedTokens = 0
            var generatedArtifact = false
            var reviewedArtifact = false
            var verification = GoalOutputVerifier.verify(currentPlan.output)
            if currentIndex == 0 || !verification.isSatisfied || currentIndex == currentPlan.steps.indices.last {
                let existingContent: String?
                if currentIndex == currentPlan.steps.indices.last, verification.isSatisfied {
                    existingContent = try String(contentsOf: destination, encoding: .utf8)
                    reviewedArtifact = true
                    statusMessage = "Reviewing and correcting the approved file with the local model..."
                } else {
                    existingContent = nil
                    statusMessage = "Generating the approved file directly with the local model..."
                }
                let generation = try await LocalGoalArtifactGenerator.shared.generate(
                    modelID: viewModel.selectedGoalModelID,
                    plan: currentPlan,
                    existingContent: existingContent,
                    contextTokens: viewModel.activeLocalLMStudioContext ?? 32_768
                )
                let content = try LocalGoalArtifactSupport.artifactContent(
                    from: generation.content,
                    pathExtension: destination.pathExtension
                )
                try LocalGoalArtifactSupport.write(content, to: destination)
                generatedTokens = generation.outputTokens
                generatedArtifact = true
                verification = GoalOutputVerifier.verify(currentPlan.output)
                guard verification.isSatisfied else {
                    throw LocalGoalArtifactError.invalidArtifact(verification.detail)
                }
            }

            var updatedPlan = currentPlan
            let isVerificationStep = currentIndex == updatedPlan.steps.indices.last
            let tokenEvidence = generatedTokens > 0 ? " · \(generatedTokens.formatted()) output tokens" : ""
            let report = GoalStepProgressReport(
                status: .complete,
                summary: isVerificationStep
                    ? (reviewedArtifact
                        ? "The local model reviewed the artifact and LocalClaw verified it on disk."
                        : "The local model generated the artifact and LocalClaw verified it on disk.")
                    : (generatedArtifact
                        ? "The local model generated the complete artifact and LocalClaw saved it atomically."
                        : "The complete artifact already satisfies this approved checkpoint."),
                evidence: ["\(destination.path) exists and is not empty\(tokenEvidence)"]
            )
            updatedPlan.apply(report)
            plan = updatedPlan
            GoalPlanStore.save(updatedPlan)
            automaticTurns += 1

            viewModel.appendGoalStatusMessage(
                sessionID: sessionID,
                text: isVerificationStep
                    ? "Verified the approved output at `\(destination.path)`."
                    : "Generated and saved the approved output at `\(destination.path)`. LocalClaw wrote the file directly so the local model did not need to serialize a large `write` tool call.",
                metadata: "local artifact · verified",
                modelName: viewModel.selectedGoalModelID
            )

            if updatedPlan.isComplete {
                statusMessage = "Every approved step is complete. Finalizing the Goal..."
                await complete()
                return .finished
            }
            statusMessage = "Checkpoint complete. Continuing with a fresh bounded step..."
            return .progressed
        } catch {
            let reason = error.localizedDescription
            viewModel.appendGoalStatusMessage(
                sessionID: sessionID,
                text: "Local file generation stopped safely: \(reason)",
                metadata: "local artifact · stopped",
                modelName: viewModel.selectedGoalModelID
            )
            await pauseForSafety("Local Goal paused because LM Studio could not produce a complete approved file. \(reason)")
            return .failed
        }
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
        let localExecution = GoalSessionMaintenance.isLocalModel(viewModel.selectedGoalModelID)
        let runStartTokens = snapshot?.tokensUsed ?? 0
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
            var consecutiveTimeouts = 0

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

                if localExecution,
                   GoalSessionMaintenance.exceededRunBudget(
                    startTokens: runStartTokens,
                    currentTokens: self.snapshot?.tokensUsed ?? runStartTokens
                   ) {
                    await self.pauseForSafety("Local Goal paused after using \(GoalSessionMaintenance.localRunTokenBudget.formatted()) tokens in this run. Review the current step or choose the recommended local model before continuing.")
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
                if localExecution {
                    let directResult = await self.executeDirectLocalArtifactTurn(
                        using: viewModel,
                        plan: currentPlan,
                        sessionID: sessionID
                    )
                    switch directResult {
                    case .progressed:
                        isStartingTurn = false
                        continue
                    case .finished, .failed:
                        return
                    case .unsupported:
                        break
                    }
                }
                self.statusMessage = localExecution
                    ? "Starting this step with a fresh local context..."
                    : "Starting this step with a fresh model context..."
                let previousMessageID = viewModel.normalChatSessions
                    .first(where: { $0.id == sessionID })?
                    .messages.last?.id
                let stepNumber = (currentPlan.currentStepIndex ?? 0) + 1
                self.statusMessage = "Working on Step \(stepNumber) of \(currentPlan.steps.count): \(currentPlan.currentStep?.title ?? "Current step")"
                viewModel.sendGoalAdvance(
                    chatSessionID: sessionID,
                    runtimeSessionID: Self.workRuntimeSessionID(
                        chatSessionID: sessionID,
                        stepID: currentPlan.currentStep?.id ?? "step",
                        turn: self.automaticTurns
                    ),
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

                if latestRole == "error", let latestMessage,
                   GoalSessionMaintenance.isTimeoutMessage(latestMessage.text) ||
                    GoalSessionMaintenance.isContextOverflowMessage(latestMessage.text) {
                    consecutiveTimeouts += 1
                    if consecutiveTimeouts == 1 {
                        viewModel.removeGoalMessage(sessionID: sessionID, messageID: latestMessage.id)
                        self.statusMessage = "The model reached a run limit. Retrying once with a fresh step context and the saved workspace..."
                        isStartingTurn = false
                        continue
                    }
                    viewModel.replaceGoalMessageText(
                        sessionID: sessionID,
                        messageID: latestMessage.id,
                        text: "The selected model reached its run limit twice on the same Goal step. LocalClaw paused safely without deleting project files. Choose another model or runtime before resuming."
                    )
                    await self.pauseForSafety("This model reached its run limit twice on the current step. Project files are preserved; choose another model or runtime before resuming.")
                    return
                }

                if latestRole == "assistant", let latestMessage, var updatedPlan = self.plan {
                    consecutiveTimeouts = 0
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

    private func compactGoalTranscript(maxLines: Int) async -> Bool {
        let agentID = await Task.detached(priority: .utility) {
            InstallerEngine().resolvedChatAgentID()
        }.value
        guard let agentID else { return false }
        let command = GoalSessionMaintenance.compactCommand(
            sessionKey: Self.openClawSessionKey(for: selectedChatSessionID, agentID: agentID),
            maxLines: maxLines
        )
        let result = await Task.detached(priority: .utility) {
            InstallerEngine().shell(command)
        }.value
        return result.0 == 0
    }

    @discardableResult
    private func perform(action: String, objective: String? = nil, note: String? = nil, tokenBudget: Int? = nil) async -> Bool {
        guard !selectedChatSessionID.isEmpty else {
            statusMessage = "Choose a discussion first."
            return false
        }
        isBusy = true
        statusMessage = action == "status" ? "Reading Goal state..." : "Updating Goal..."
        do {
            let agentID = await Task.detached(priority: .utility) {
                InstallerEngine().resolvedChatAgentID()
            }.value
            guard let agentID else {
                throw OpenClawGoalBridgeError.processFailed("Select an owning OpenClaw agent before using Goals. Existing sessions were left unchanged.")
            }
            let result = try await bridge.request(
                action: action,
                sessionKey: Self.openClawSessionKey(for: selectedChatSessionID, agentID: agentID),
                objective: objective,
                note: note?.trimmingCharacters(in: .whitespacesAndNewlines),
                tokenBudget: tokenBudget
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
