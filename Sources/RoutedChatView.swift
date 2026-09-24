import SwiftUI

struct RoutedChatView: View {
    @StateObject private var model = RoutedChatViewModel()
    @AppStorage("localclaw.routedChat.economicalModel.v1") private var economicalModel = ""
    @AppStorage("localclaw.routedChat.reasoningModel.v1") private var reasoningModel = ""
    @AppStorage("localclaw.routedChat.codingModel.v1") private var codingModel = ""
    @State private var expandedReplies = Set<UUID>()

    private var mapping: RoutedModelMapping {
        RoutedModelMapping(economical: economicalModel, reasoning: reasoningModel, coding: codingModel)
    }

    private var draftTrimmed: String {
        model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedModelsAvailable: Bool {
        let ids = Set(model.availableModels.map(\.id))
        return !economicalModel.isEmpty && !reasoningModel.isEmpty && !codingModel.isEmpty &&
            economicalModel != reasoningModel && mapping.modelIDs.allSatisfy(ids.contains)
    }

    private var usesRecommendedGPT6: Bool {
        mapping == RoutedChatService.recommendedGPT6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(UI.accent)
                Text("Routed Chat")
                    .font(AppFont.heading(28))
                    .foregroundStyle(UI.text)
                Text("NEW · BETA")
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(UI.accent))
                Spacer()
                Button("New conversation") { model.newConversation() }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(model.isBusy)
                Button("Refresh") { model.refresh() }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(model.isBusy || model.isSettingUp || model.isRefreshing)
            }

            introduction
            configuration

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.turns.isEmpty {
                            emptyState
                        } else {
                            ForEach(model.turns) { turn in
                                turnCard(turn)
                                    .id(turn.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.turns.count) { _ in
                    if let last = model.turns.last?.id {
                        // Animated layout over a long code reply can keep
                        // SwiftUI measuring the full history indefinitely.
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            composer
        }
        .padding(18)
        .onAppear { model.refresh() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("How this beta works")
                .font(AppFont.bodySemi(13))
                .foregroundStyle(UI.text)
            Text("A small ONNX model (about 300 MB to download) classifies your request on this Mac. LocalClaw applies your model map, then OpenClaw sends the full request to the selected cloud or OAuth chat model. The local decision uses no cloud inference tokens.")
                .font(AppFont.body(12))
                .foregroundStyle(UI.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Setup downloads verified model files once and adds a dedicated OpenClaw router agent. Your default decision model is left unchanged. After setup, routing stays on this Mac. Savings depend on your chosen chat models and are not guaranteed.")
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("This beta routes text conversations. Browser control is not connected here yet. Each turn shows the ONNX proposal, any local adjustment, the requested chat model and the model OpenClaw actually used. Routing scores compare categories, not answer accuracy.")
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: model.routerReady ? "checkmark.shield.fill" : "cpu")
                    .foregroundStyle(model.routerReady ? Color(NSColor.systemGreen) : UI.accent)
                Text(model.status)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.text)
                    .lineLimit(2)
                Spacer()
                Button(model.isSettingUp ? "Setting up…" : (model.routerReady ? "Router ready" : "Set up local router")) {
                    model.setupRouter()
                }
                .buttonStyle(CompactChatButton(primary: true))
                .disabled(model.routerReady || model.isSettingUp || model.isBusy || model.isRefreshing)
            }

            DisclosureGroup("Choose which chat model handles each task") {
                HStack(alignment: .top, spacing: 12) {
                    modelPicker("Simple · economical", selection: $economicalModel)
                    modelPicker("Analysis · stronger", selection: $reasoningModel)
                    modelPicker("Code", selection: $codingModel)
                }
                .padding(.top, 8)
                Text("Choose at least two different available models. A close or unclear local decision uses the Analysis model. The Code slot may use the same model as Analysis.")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .padding(.top, 4)
            }
            .font(AppFont.bodySemi(12))
            .foregroundStyle(UI.text)

            if model.routerReady {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GPT-6 routing")
                            .font(AppFont.bodySemi(11))
                        Text("Luna for simple requests · Astra for analysis · Sol for code. The decision stays on this Mac; chat usage follows your OpenAI account or API billing.")
                            .font(AppFont.body(10))
                            .foregroundStyle(UI.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if model.hasGPT6Options {
                        Button(usesRecommendedGPT6 ? "GPT-6 selected" : "Use GPT-6 routing") {
                            economicalModel = RoutedChatService.recommendedGPT6.economical
                            reasoningModel = RoutedChatService.recommendedGPT6.reasoning
                            codingModel = RoutedChatService.recommendedGPT6.coding
                        }
                        .buttonStyle(CompactChatButton(primary: false))
                        .disabled(usesRecommendedGPT6 || model.isBusy || model.isRefreshing)
                    } else {
                        Button(model.isEnablingGPT6 ? "Adding GPT-6…" : "Enable GPT-6 choices") {
                            model.enableGPT6Options()
                        }
                        .buttonStyle(CompactChatButton(primary: false))
                        .disabled(model.isEnablingGPT6 || model.isBusy || model.isRefreshing)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func modelPicker(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.muted)
            Picker(title, selection: selection) {
                Text("Choose model").tag("")
                ForEach(model.availableModels) { option in
                    Text("\(option.name) · \(option.source)").tag(option.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test the routing before sending")
                .font(AppFont.heading(18))
                .foregroundStyle(UI.text)
            Text("Try a short translation, a multi-step analysis, then a coding request. Preview runs only the local router; Send also calls the chat model you mapped to that route.")
                .font(AppFont.body(12))
                .foregroundStyle(UI.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextEditor(text: $model.draft)
                .font(AppFont.body(13))
                .foregroundStyle(UI.text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 86)
                .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
                .disabled(model.isBusy || model.isSettingUp)

            if let preview = model.previewForCurrentDraft(mapping: mapping) {
                routeCard(preview, actualModel: nil, inputTokens: nil, outputTokens: nil)
            }

            HStack(spacing: 10) {
            Text("Text chat only: this beta cannot open websites for you. Long prompts use their beginning and end for the local decision; the complete message goes to the selected chat model.")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Preview local route") { model.previewRoute(mapping: mapping) }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(!model.routerReady || !selectedModelsAvailable || draftTrimmed.isEmpty || model.isBusy || model.isRefreshing)
                Button("Send") { model.send(mapping: mapping) }
                    .buttonStyle(CompactChatButton(primary: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.routerReady || !selectedModelsAvailable || draftTrimmed.isEmpty || model.isBusy || model.isRefreshing || model.hasPendingTurn)
            }
        }
    }

    private func turnCard(_ turn: RoutedChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOU")
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(UI.accent)
                Spacer()
                Text(turn.createdAt, style: .time)
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
            }
            Text(turn.prompt)
                .font(AppFont.body(13))
                .foregroundStyle(UI.text)
                .textSelection(.enabled)

            routeCard(turn.selection, actualModel: turn.actualModelID,
                      inputTokens: turn.inputTokens, outputTokens: turn.outputTokens)

            if let reply = turn.reply {
                Divider()
                Text("ASSISTANT")
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(UI.accent)
                Text(reply)
                    .font(AppFont.body(13))
                    .foregroundStyle(UI.text)
                    .textSelection(.enabled)
                    .lineLimit(expandedReplies.contains(turn.id) ? nil : 18)
                if reply.count > 1_600 {
                    Button(expandedReplies.contains(turn.id) ? "Show less" : "Show full reply") {
                        if expandedReplies.contains(turn.id) {
                            expandedReplies.remove(turn.id)
                        } else {
                            expandedReplies.insert(turn.id)
                        }
                    }
                    .buttonStyle(CompactChatButton(primary: false))
                }
                if turn.modelMatched == false {
                    Label("OpenClaw used a different model than the local route selected. Review this turn.", systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.body(11))
                        .foregroundStyle(Color(NSColor.systemOrange))
                }
            } else if let error = turn.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.body(11))
                    .foregroundStyle(Color(NSColor.systemOrange))
            } else {
                ProgressView("Waiting for the selected model…")
                    .font(AppFont.body(11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func routeCard(_ selection: RoutedSelection, actualModel: String?,
                           inputTokens: Int?, outputTokens: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("LOCAL ROUTE · \(selection.task.label)", systemImage: "cpu")
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(UI.accent)
                Spacer()
                Text(selection.routerModel)
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
            }
            Text(selection.explanation)
                .font(AppFont.body(11))
                .foregroundStyle(UI.text)
            if selection.routerTask != selection.task {
                Text("ONNX proposal: \(selection.routerTask.label) · LocalClaw adjustment: \(selection.task.label)")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
            }
            Text("Selected chat model: \(selection.modelID)")
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.text)
            if let actualModel {
                Text("Actually used: \(actualModel)")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(actualModel == selection.modelID ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
            }
            if let inputTokens, let outputTokens {
                Text("Chat usage: \(inputTokens) input · \(outputTokens) output tokens. Local routing used no cloud inference tokens.")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
            }
            if selection.excerpted {
                Text("The router evaluated the beginning and end of this long message.")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
            }
            let ordered = RoutedTask.allCases.compactMap { task -> String? in
                guard let value = selection.probabilities[task.rawValue] else { return nil }
                return "\(task.label) \(Int((value * 100).rounded()))%"
            }
            Text("Relative category scores: \(ordered.joined(separator: " · "))")
                .font(AppFont.body(10))
                .foregroundStyle(UI.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(UI.cardSoft))
    }
}
