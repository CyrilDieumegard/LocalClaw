import Foundation

enum RoutedTask: String, Codable, CaseIterable, Sendable {
    case economical
    case reasoning
    case coding
    case unclear

    var label: String {
        switch self {
        case .economical: "Simple"
        case .reasoning: "Analysis"
        case .coding: "Code"
        case .unclear: "Unclear"
        }
    }

    var explanation: String {
        switch self {
        case .economical: "The request looks routine. Your economical chat model is selected."
        case .reasoning: "The request appears to need several reasoning steps. Your analysis model is selected."
        case .coding: "The request concerns software or debugging. Your code model is selected."
        case .unclear: "The router lacks enough context. Your analysis model is selected conservatively."
        }
    }
}

struct RoutedDecision: Decodable, Sendable {
    let status: String
    let route: RoutedTask?
    let probabilities: [String: Double]?
    let routerModel: String?
    let providerId: String?
    let rubricVersion: String?
    let reason: String?
}

struct RoutedModelMapping: Sendable, Equatable {
    let economical: String
    let reasoning: String
    let coding: String

    var modelIDs: [String] { [economical, reasoning, coding] }
}

struct RoutedSelection: Codable, Sendable {
    let routerTask: RoutedTask
    let task: RoutedTask
    let modelID: String
    let explanation: String
    let routeMargin: Double?
    let wasAmbiguous: Bool
    let excerpted: Bool
    let routerModel: String
    let probabilities: [String: Double]
}

enum RoutedChatPolicy {
    static let minimumMargin = 0.12
    // GLiNER2.5 Small accepts at most 512 tokens including the bridge rubric.
    // Its current rubric uses about 124 tokens. Bound the UTF-8 state to 320
    // bytes so multilingual text and the previous-turn context retain room.
    static let currentPromptByteLimit = 224
    static let priorPromptByteLimit = 56

    // Local checks protect against observed high-score mistakes in the beta classifier.
    private static let codeTerms = [
        "swiftui", "python", "javascript", "typescript", "sql", "node.js",
        "debug", "bug", "endpoint", "api", "code", "coding", "programming",
        "programmation", "composant", "function", "fonction", "script", "react"
    ]
    private static let analysisTerms = [
        "plan strategique", "strategic plan", "strategie", "strategy",
        "risque", "risques", "risk", "risks", "tradeoff", "tradeoffs", "compromis",
        "compare", "comparer", "comparaison", "comparison", "comparing",
        "analyse", "analyser", "analysez", "analysis", "analyze", "analyzing",
        "probabilite", "probability", "calculate", "calculation", "calcul",
        "churn", "growth", "croissance", "pourcentage", "%",
        "multi-step", "plusieurs etapes"
    ]
    private static let shortTranslationTerms = [
        "traduis", "traduire", "traduction", "translate", "translation"
    ]

    static func excerpt(_ text: String) -> (text: String, excerpted: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count > currentPromptByteLimit else { return (trimmed, false) }
        let separator = "\n…\n"
        let contentBudget = currentPromptByteLimit - separator.utf8.count
        let beginning = utf8Prefix(trimmed, limit: contentBudget / 2)
        let ending = utf8Suffix(trimmed, limit: contentBudget - beginning.utf8.count)
        return (beginning + separator + ending, true)
    }

    static func priorContext(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return utf8Prefix(trimmed, limit: priorPromptByteLimit)
    }

    private static func utf8Prefix(_ text: String, limit: Int) -> String {
        var result = ""
        var bytes = 0
        for scalar in text.unicodeScalars {
            let size = String(scalar).utf8.count
            guard bytes + size <= limit else { break }
            result.unicodeScalars.append(scalar)
            bytes += size
        }
        return result
    }

    private static func utf8Suffix(_ text: String, limit: Int) -> String {
        var reversed: [Unicode.Scalar] = []
        var bytes = 0
        for scalar in text.unicodeScalars.reversed() {
            let size = String(scalar).utf8.count
            guard bytes + size <= limit else { break }
            reversed.append(scalar)
            bytes += size
        }
        return String(String.UnicodeScalarView(reversed.reversed()))
    }

    static func select(
        decision: RoutedDecision,
        mapping: RoutedModelMapping,
        availableModelIDs: Set<String>,
        prompt: String,
        excerpted: Bool
    ) throws -> RoutedSelection {
        guard decision.status == "ok", decision.providerId == "onnx",
              let task = decision.route,
              let probabilities = decision.probabilities,
              let routerModel = decision.routerModel, !routerModel.isEmpty else {
            throw RoutedChatError.routerUnavailable(decision.reason ?? "invalid-decision")
        }
        guard !mapping.economical.isEmpty, !mapping.reasoning.isEmpty,
              !mapping.coding.isEmpty, mapping.economical != mapping.reasoning,
              mapping.modelIDs.allSatisfy(availableModelIDs.contains) else {
            throw RoutedChatError.invalidModelMapping
        }
        guard Set([RoutedTask.economical, .reasoning, .coding].map(\.rawValue)) == Set(probabilities.keys),
              probabilities.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw RoutedChatError.routerUnavailable("incomplete-distribution")
        }

        let sorted = probabilities.values.sorted(by: >)
        let margin = sorted.count > 1 ? sorted[0] - sorted[1] : nil
        let ambiguous = margin.map { $0 < minimumMargin } ?? true
        let request = String(prompt.prefix(220)).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = request.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let codeGuard = containsTerm(in: request, terms: codeTerms)
        let analysisGuard = containsTerm(in: request, terms: analysisTerms)
        let shortTranslation = !excerpted && prompt.utf8.count <= 160 &&
            words.count <= 24 && !analysisGuard &&
            containsTerm(in: request, terms: shortTranslationTerms)
        let lacksContext = words.count <= 3 && !codeGuard
        let effectiveTask: RoutedTask
        let explanation: String
        if codeGuard {
            effectiveTask = .coding
            explanation = task == .coding ? task.explanation : "ONNX proposed \(task.label), but the request includes software terms. Your code model is selected."
        } else if shortTranslation {
            effectiveTask = .economical
            explanation = task == .economical ? task.explanation : "ONNX proposed \(task.label), but this is a short translation. Your economical model is selected."
        } else if ambiguous || lacksContext {
            effectiveTask = .unclear
            explanation = "The request lacks context or local scores are close. Your analysis model is selected."
        } else if task == .economical && analysisGuard {
            effectiveTask = .reasoning
            explanation = "ONNX proposed Simple, but the request includes analysis, calculation or planning. Your analysis model is selected."
        } else {
            effectiveTask = task
            explanation = task.explanation
        }
        let modelID: String
        switch effectiveTask {
        case .economical: modelID = mapping.economical
        case .reasoning, .unclear: modelID = mapping.reasoning
        case .coding: modelID = mapping.coding
        }
        return RoutedSelection(
            routerTask: task,
            task: effectiveTask,
            modelID: modelID,
            explanation: explanation,
            routeMargin: margin,
            wasAmbiguous: effectiveTask == .unclear,
            excerpted: excerpted,
            routerModel: routerModel,
            probabilities: probabilities
        )
    }

    private static func containsTerm(in text: String, terms: [String]) -> Bool {
        terms.contains { term in
            guard let range = text.range(of: term) else { return false }
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            return (before == nil || !before!.isLetter) && (after == nil || !after!.isLetter)
        }
    }
}

enum RoutedChatError: LocalizedError {
    case requiresOpenClawUpdate
    case routerSetupRequired
    case invalidModelMapping
    case routerUnavailable(String)
    case gatewayNotLocal
    case noAgent
    case commandTimedOut
    case commandFailed(String)
    case unexpectedReply
    case modelMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .requiresOpenClawUpdate:
            "Update OpenClaw to 2026.9.6 or newer in Updates before setting up the local router."
        case .routerSetupRequired:
            "Set up local router to download the decision model and enable routing on this Mac."
        case .invalidModelMapping:
            "Choose available models for all three routes, with different models for Simple and Analysis."
        case .routerUnavailable(let reason):
            "The local decision model could not classify this request (\(reason)). Nothing was sent to a chat model."
        case .gatewayNotLocal:
            "The selected OpenClaw Gateway is not local to this Mac. Local routing is unavailable for this setup."
        case .noAgent:
            "LocalClaw could not identify the chat agent. No message was sent."
        case .commandTimedOut:
            "The local router command timed out. Check its status before retrying."
        case .commandFailed(let message):
            message
        case .unexpectedReply:
            "OpenClaw did not return a verifiable reply and model identity. Check the Gateway before retrying."
        case .modelMismatch(let expected, let actual):
            "OpenClaw used \(actual), although the route selected \(expected). This turn needs review."
        }
    }
}
