import Foundation

struct RoutedChatTurn: Identifiable, Codable, Sendable {
    let id: UUID
    let prompt: String
    let createdAt: Date
    let selection: RoutedSelection
    var reply: String?
    var actualModelID: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var modelMatched: Bool?
    var error: String?
}

@MainActor
final class RoutedChatViewModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var turns: [RoutedChatTurn] = []
    @Published private(set) var availableModels: [RoutedModelOption] = []
    @Published private(set) var routerReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSettingUp = false
    @Published private(set) var isEnablingGPT6 = false
    @Published private(set) var status = "Checking the local router…"
    @Published private(set) var preview: RoutedSelection?
    @Published private(set) var previewPrompt = ""

    var hasPendingTurn: Bool {
        guard let last = turns.last else { return false }
        return last.reply == nil && last.error == nil
    }

    var hasGPT6Options: Bool {
        let ids = Set(availableModels.map(\.id))
        return RoutedChatService.recommendedGPT6.modelIDs.allSatisfy(ids.contains)
    }

    private static let storageKey = "localclaw.routedChat.beta.v1"
    private let service = RoutedChatService()
    private var sessionID = "localclaw-routed-\(UUID().uuidString)"
    private var previewMapping: RoutedModelMapping?

    private struct StoredChat: Codable {
        let sessionID: String
        let turns: [RoutedChatTurn]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(StoredChat.self, from: data),
           stored.sessionID.hasPrefix("localclaw-routed-") {
            sessionID = stored.sessionID
            turns = stored.turns
        }
    }

    func previewForCurrentDraft(mapping: RoutedModelMapping) -> RoutedSelection? {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previewPrompt == prompt, previewMapping == mapping else { return nil }
        return preview
    }

    func refresh() {
        guard !isBusy && !isSettingUp && !isRefreshing else { return }
        isRefreshing = true
        status = "Checking the local router and chat models…"
        let service = self.service
        Task {
            do {
                let models = try await Task.detached(priority: .utility) { try service.availableChatModels() }.value
                availableModels = models
                let check = try await Task.detached(priority: .utility) {
                    try service.classify(prompt: "Translate this short sentence.", prior: nil)
                }.value
                routerReady = check.status == "ok" && check.providerId == "onnx"
                status = routerReady
                    ? "Local router ready · \(models.count) available chat models"
                    : "Local router needs setup: \(check.reason ?? "unknown result")"
            } catch {
                routerReady = false
                status = error.localizedDescription
            }
            await recoverPendingTurn()
            isRefreshing = false
        }
    }

    func setupRouter() {
        guard !isSettingUp && !isBusy && !isRefreshing else { return }
        isSettingUp = true
        status = "Preparing the local decision model…"
        let service = self.service
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try service.setup { [weak self] message in
                        Task { @MainActor [weak self] in
                            if self?.isSettingUp == true { self?.status = message }
                        }
                    }
                }.value
                routerReady = true
                status = "Local router ready. Decisions stay on this Mac."
                isSettingUp = false
                refresh()
            } catch {
                routerReady = false
                status = error.localizedDescription
                isSettingUp = false
            }
        }
    }

    func enableGPT6Options() {
        guard !isEnablingGPT6 && !isBusy && !isRefreshing && !isSettingUp else { return }
        isEnablingGPT6 = true
        status = "Adding GPT-6 Luna, Sol and Astra to this agent's model choices…"
        let service = self.service
        Task {
            do {
                try await Task.detached(priority: .utility) { try service.enableGPT6Options() }.value
                isEnablingGPT6 = false
                refresh()
            } catch {
                status = error.localizedDescription
                isEnablingGPT6 = false
            }
        }
    }

    func previewRoute(mapping: RoutedModelMapping) {
        guard !isBusy && !isSettingUp && !isRefreshing else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { status = "Write a message first."; return }
        isBusy = true
        status = "Classifying on this Mac…"
        Task {
            do {
                let selection = try await decide(prompt: prompt, mapping: mapping)
                preview = selection
                previewPrompt = prompt
                previewMapping = mapping
                status = "Local preview complete. No chat request was sent."
            } catch {
                preview = nil
                previewMapping = nil
                status = error.localizedDescription
            }
            isBusy = false
        }
    }

    func send(mapping: RoutedModelMapping) {
        guard !isBusy && !isSettingUp && !isRefreshing else { return }
        guard !hasPendingTurn else {
            status = "Check the previous turn with Refresh before sending another request."
            return
        }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { status = "Write a message first."; return }
        isBusy = true
        status = "Choosing a model on this Mac…"
        Task {
            do {
                // Re-evaluate at send time so a preview cannot become a stale
                // authorization to send after the router configuration changes.
                let selection = try await decide(prompt: prompt, mapping: mapping)
                let turnID = UUID()
                turns.append(RoutedChatTurn(
                    id: turnID, prompt: prompt, createdAt: Date(), selection: selection,
                    reply: nil, actualModelID: nil, inputTokens: nil, outputTokens: nil,
                    modelMatched: nil, error: nil
                ))
                save()
                draft = ""
                preview = nil
                previewPrompt = ""
                previewMapping = nil
                status = "Sending to \(selection.modelID)…"
                let service = self.service
                let sessionID = self.sessionID
                do {
                    let reply = try await Task.detached(priority: .userInitiated) {
                        try service.send(prompt: prompt, modelID: selection.modelID, sessionID: sessionID)
                    }.value
                    if let index = turns.firstIndex(where: { $0.id == turnID }) {
                        turns[index].reply = reply.text
                        turns[index].actualModelID = reply.actualModelID
                        turns[index].inputTokens = reply.inputTokens
                        turns[index].outputTokens = reply.outputTokens
                        turns[index].modelMatched = reply.modelMatched
                        save()
                    }
                    status = reply.modelMatched
                        ? "Completed with \(reply.actualModelID)"
                        : "Model mismatch: review this turn before continuing"
                } catch {
                    if let index = turns.firstIndex(where: { $0.id == turnID }) {
                        turns[index].error = error.localizedDescription
                        save()
                    }
                    status = error.localizedDescription
                }
            } catch {
                status = error.localizedDescription
            }
            isBusy = false
        }
    }

    func newConversation() {
        guard !isBusy else { return }
        sessionID = "localclaw-routed-\(UUID().uuidString)"
        turns = []
        draft = ""
        preview = nil
        previewPrompt = ""
        previewMapping = nil
        save()
        status = routerReady ? "New routed conversation ready" : "Set up the local router to begin"
    }

    private func decide(prompt: String, mapping: RoutedModelMapping) async throws -> RoutedSelection {
        guard routerReady else { throw RoutedChatError.routerUnavailable("not-ready") }
        let available = Set(availableModels.map(\.id))
        guard !mapping.economical.isEmpty, !mapping.reasoning.isEmpty,
              !mapping.coding.isEmpty, mapping.economical != mapping.reasoning,
              mapping.modelIDs.allSatisfy(available.contains) else {
            throw RoutedChatError.invalidModelMapping
        }
        let excerpt = RoutedChatPolicy.excerpt(prompt)
        let prior = turns.last.flatMap { RoutedChatPolicy.priorContext($0.prompt) }
        let service = self.service
        let decision = try await Task.detached(priority: .userInitiated) {
            try service.classify(prompt: excerpt.text, prior: prior)
        }.value
        return try RoutedChatPolicy.select(
            decision: decision, mapping: mapping,
            availableModelIDs: available, prompt: prompt, excerpted: excerpt.excerpted
        )
    }

    private func recoverPendingTurn() async {
        guard let index = turns.indices.last,
              turns[index].reply == nil, turns[index].error == nil else { return }
        let turn = turns[index]
        let sessionID = self.sessionID
        let service = self.service
        do {
            let outcome = try await Task.detached(priority: .utility) {
                try service.recoverPendingReply(sessionID: sessionID, createdAt: turn.createdAt,
                                                expectedModelID: turn.selection.modelID)
            }.value
            guard turns.indices.contains(index), turns[index].id == turn.id else { return }
            switch outcome {
            case .recovered(let reply):
                turns[index].reply = reply.text
                turns[index].actualModelID = reply.actualModelID
                turns[index].inputTokens = reply.inputTokens
                turns[index].outputTokens = reply.outputTokens
                turns[index].modelMatched = reply.modelMatched
                status = "Recovered the completed reply from OpenClaw. No request was repeated."
                save()
            case .running:
                status = "The previous request is still running in OpenClaw. Click Refresh later."
            case .unmatched:
                turns[index].error = "The previous reply could not be matched safely. No request was repeated. Check OpenClaw history before sending it again."
                status = "Previous routed turn needs review"
                save()
            }
        } catch {
            status = "Could not check the previous turn: \(error.localizedDescription). Click Refresh to try again."
        }
    }

    private func save() {
        let stored = StoredChat(sessionID: sessionID, turns: turns)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
