import SwiftUI

enum GoalModelIdentity {
    static func normalized(_ raw: String) -> String {
        var value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("lmstudio/") { value.removeFirst("lmstudio/".count) }
        value = value.split(separator: "@").first.map(String.init) ?? value
        return value.replacingOccurrences(of: "_", with: "-")
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        return !left.isEmpty && !right.isEmpty && (left == right || left.hasSuffix(right) || right.hasSuffix(left))
    }
}

extension InstallerViewModel {
    var selectedGoalModelID: String {
        switch inferenceMode {
        case .local:
            let selected = Self.localLMStudioModelID(from: selectedChatModel)
            let local = selected.isEmpty ? selectedLocalLMStudioModel : selected
            return local.isEmpty ? "" : "lmstudio/\(local)"
        case .oauth:
            return Self.isOAuthRuntimeModelID(selectedChatModel) ? selectedChatModel : selectedOAuthModelIdentifier()
        case .cloud:
            return selectedChatModel.hasPrefix("openrouter/") ? selectedChatModel : selectedOpenRouterModel
        }
    }

    var recommendedGoalLocalModel: LocalModelRecommendation? {
        recommendedLocalModels(workload: .reasoning).first {
            ($0.match.fit == .great || $0.match.fit == .good) &&
            $0.model.toolUseScore >= 4.0 &&
            $0.model.maxContextK >= 32
        }
    }

    var selectedGoalLocalRecommendation: LocalModelRecommendation? {
        let selected = selectedGoalModelID
        return recommendedLocalModels(workload: .reasoning).first {
            GoalModelIdentity.matches($0.model.providerId, selected) ||
            GoalModelIdentity.matches($0.model.query, selected)
        }
    }

    var goalRuntimeReadiness: GoalRuntimeReadiness {
        let openClawReady = hasExistingOpenClawSetup || statusOpenClaw == "OK" || statusOpenClaw == "SKIP"
        switch inferenceMode {
        case .cloud:
            return GoalCapabilityAdvisor.cloud(
                openClawInstalled: openClawReady,
                authReady: cloudProviderAuthConfigured || openRouterKeyVerified || !openRouterApiKey.isEmpty,
                modelID: selectedGoalModelID,
                modeName: "Cloud LLM"
            )
        case .oauth:
            return GoalCapabilityAdvisor.cloud(
                openClawInstalled: openClawReady,
                authReady: cloudProviderAuthConfigured,
                modelID: selectedGoalModelID,
                modeName: "OAuth LLM"
            )
        case .local:
            let selected = selectedGoalModelID
            let loaded = GoalModelIdentity.matches(selected, activeLocalLMStudioModel) && currentModel.hasPrefix("lmstudio/")
            let recommendation = selectedGoalLocalRecommendation
            return GoalCapabilityAdvisor.local(
                openClawInstalled: openClawReady,
                modelName: Self.localLMStudioModelID(from: selected),
                isLoaded: loaded,
                fit: recommendation?.match.fit,
                toolUseScore: recommendation?.model.toolUseScore,
                contextTokens: activeLocalLMStudioContext ?? (loaded ? 32_768 : 0),
                recommendedModel: recommendedGoalLocalModel?.model.name
            )
        }
    }

    func selectGoalInferenceMode(_ mode: InferenceMode) {
        selectInferenceModeFromUser(mode)
        switch mode {
        case .local:
            selectedChatResponseMode = .local
            refreshLocalLMStudioModels()
            let preferred = activeLocalLMStudioModel.isEmpty ? selectedLocalLMStudioModel : activeLocalLMStudioModel
            if !preferred.isEmpty {
                selectedLocalLMStudioModel = preferred
                selectedChatModel = "lmstudio/\(preferred)"
            }
        case .oauth:
            selectedChatResponseMode = .cloud
            prepareOAuthModelSelection()
            if !cloudProviderAuthConfigured { showOAuthSetupAssistant = true }
        case .cloud:
            selectedChatResponseMode = .cloud
            prepareCloudModelSelection()
        }
        applyInferenceModeSwitch()
    }

    func prepareRecommendedGoalLocalModel() {
        guard let recommendation = recommendedGoalLocalModel else { return }
        selectInferenceModeFromUser(.local)
        selectedChatResponseMode = .local
        if let installed = installedLocalModelID(for: recommendation.model) {
            selectedLocalLMStudioModel = installed
            selectedChatModel = "lmstudio/\(installed)"
            autoSetupLocalLMStudioModel(modelId: installed, source: .chat)
        } else {
            selectOrDownloadLocalModel(recommendation)
        }
    }
}

struct GoalCenterView: View {
    @ObservedObject var vm: InstallerViewModel
    @ObservedObject var goal: GoalCenterModel

    private var readiness: GoalRuntimeReadiness { vm.goalRuntimeReadiness }

    private var selectedSession: InstallerViewModel.ChatSession? {
        vm.normalChatSessions.first { $0.id == goal.selectedChatSessionID }
    }

    private var latestResult: InstallerViewModel.ChatMessage? {
        selectedSession?.messages.last { $0.role == "assistant" || $0.role == "error" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                workspaceAndRuntime
                if let snapshot = goal.snapshot {
                    activeGoal(snapshot)
                } else {
                    newGoal
                }
                latestProgress
            }
            .padding(22)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .task {
            vm.refreshRuntimeSnapshot()
            if goal.selectedChatSessionID.isEmpty {
                await goal.selectSession(vm.activeChatSessionID)
            } else {
                await goal.refresh()
            }
        }
        .onChange(of: vm.chatIsSending) { isSending in
            if !isSending { Task { await goal.refresh() } }
        }
        .alert("Clear this goal?", isPresented: $goal.showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Goal", role: .destructive) { Task { await goal.clear() } }
        } message: {
            Text("This removes the durable objective from this OpenClaw session. Discussion messages are kept.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(UI.accent)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("GOALS")
                    .font(AppFont.heading(28))
                    .foregroundStyle(UI.text)
                Text("Give one durable objective to any Local, OAuth, or Cloud model. Goal controls never spend model tokens.")
                    .font(AppFont.body(13))
                    .foregroundStyle(UI.muted)
            }

            Spacer()

            Button {
                Task { await goal.refresh() }
            } label: {
                Label(goal.isBusy ? "Checking" : "Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CompactChatButton(primary: false))
            .disabled(goal.isBusy)
        }
    }

    private var workspaceAndRuntime: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Discussion")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)
                    Picker("Discussion", selection: $goal.selectedChatSessionID) {
                        ForEach(vm.normalChatSessions) { session in
                            Text(session.title).tag(session.id)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 260, maxWidth: .infinity)
                    .onChange(of: goal.selectedChatSessionID) { sessionID in
                        Task { await goal.selectSession(sessionID) }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Runtime")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)
                    Picker("Runtime", selection: Binding(
                        get: { vm.inferenceMode },
                        set: { vm.selectGoalInferenceMode($0) }
                    )) {
                        Text("Cloud").tag(InstallerViewModel.InferenceMode.cloud)
                        Text("OAuth").tag(InstallerViewModel.InferenceMode.oauth)
                        Text("Local").tag(InstallerViewModel.InferenceMode.local)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)
                    Picker("Model", selection: $vm.selectedChatModel) {
                        ForEach(vm.availableChatModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 300, maxWidth: .infinity)
                    .onChange(of: vm.selectedChatModel) { _ in
                        vm.handleChatModelSelectionChanged(useDeveloperSession: false)
                    }
                }
            }

            readinessRow
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
    }

    private var readinessRow: some View {
        HStack(spacing: 12) {
            Image(systemName: readinessIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(readinessColor)
                .frame(width: 34, height: 34)
                .background(Circle().fill(readinessColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(readiness.title)
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)
                Text(readiness.detail)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if vm.inferenceMode == .local, let recommendation = readiness.recommendation {
                Button {
                    vm.prepareRecommendedGoalLocalModel()
                } label: {
                    Label("Use \(recommendation)", systemImage: "wand.and.stars")
                }
                .buttonStyle(CompactChatButton(primary: readiness.level == .blocked))
                .disabled(vm.modelsApplyInProgress || vm.localLMStudioSetupInProgress)
            }
        }
    }

    private var newGoal: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("New goal")
                        .font(AppFont.heading(19))
                        .foregroundStyle(UI.text)
                    Text("Describe the result, not every individual step.")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text("1 objective per discussion")
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(UI.muted)
            }

            TextEditor(text: $goal.objective)
                .font(AppFont.body(14))
                .foregroundStyle(UI.text)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 110, maxHeight: 170)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))

            HStack(spacing: 12) {
                Label("Runs continuously until complete, blocked, paused, or an error occurs", systemImage: "repeat")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                Label("Use Cron Jobs for schedules", systemImage: "calendar.badge.clock")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                Spacer()
                Button {
                    Task {
                        if await goal.start() {
                            goal.startContinuousRun(using: vm, starting: true)
                        }
                    }
                } label: {
                    Label("Start Continuous Goal", systemImage: "play.fill")
                }
                .buttonStyle(CTAButton(primary: true))
                .disabled(!readiness.canStart || goal.isBusy || vm.chatIsSending || goal.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            statusText
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func activeGoal(_ snapshot: OpenClawGoalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if vm.chatIsSending && goal.continuousRunEnabled {
                            ProgressView()
                                .controlSize(.small)
                            Text("Working now")
                                .font(AppFont.bodySemi(12))
                                .foregroundStyle(Color(NSColor.systemGreen))
                        } else {
                            Label(goalStatusLabel(snapshot), systemImage: statusIcon(snapshot.status))
                                .font(AppFont.bodySemi(12))
                                .foregroundStyle(statusColor(snapshot.status))
                        }
                        Text("\(snapshot.tokensUsed.formatted()) tokens")
                            .font(AppFont.bodySemi(10))
                            .foregroundStyle(UI.muted)
                    }
                    Text(snapshot.objective)
                        .font(AppFont.heading(18))
                        .foregroundStyle(UI.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(snapshot.createdDate, style: .relative)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                TextField("Edit objective", text: $goal.objective, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(13))
                    .padding(10)
                    .lineLimit(2...5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))

                Button {
                    Task { _ = await goal.edit() }
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(CompactChatButton(primary: false))
                .disabled(goal.isBusy || snapshot.status == .complete || goal.objective == snapshot.objective)
            }

            HStack(spacing: 10) {
                if snapshot.status == .active {
                    if goal.continuousRunEnabled {
                        Label(
                            vm.chatIsSending ? "Model working" : "Continuing automatically",
                            systemImage: vm.chatIsSending ? "sparkles" : "repeat"
                        )
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(Color(NSColor.systemGreen))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color(NSColor.systemGreen).opacity(0.10)))
                    } else {
                        Button {
                            goal.startContinuousRun(using: vm, starting: false)
                        } label: {
                            Label("Run continuously", systemImage: "repeat")
                        }
                        .buttonStyle(CTAButton(primary: true))
                        .disabled(goal.isBusy || vm.chatIsSending || !readiness.canStart)

                        Button {
                            vm.sendGoalAdvance(
                                chatSessionID: goal.selectedChatSessionID,
                                runtimeSessionID: GoalCenterModel.runtimeSessionID(for: goal.selectedChatSessionID),
                                objective: snapshot.objective,
                                starting: false
                            )
                        } label: {
                            Label("Run one step", systemImage: "forward.frame.fill")
                        }
                        .buttonStyle(CompactChatButton(primary: false))
                        .disabled(goal.isBusy || vm.chatIsSending || !readiness.canStart)
                    }

                    Button { Task { await goal.pause() } } label: {
                        Label(goal.continuousRunEnabled ? "Stop & Pause" : "Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(goal.isBusy)
                } else if snapshot.status != .complete {
                    Button {
                        Task {
                            await goal.resume()
                            guard goal.snapshot?.status == .active else { return }
                            goal.startContinuousRun(using: vm, starting: false)
                        }
                    } label: {
                        Label("Resume continuously", systemImage: "play.fill")
                    }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(goal.isBusy || vm.chatIsSending || !readiness.canStart)
                }

                if snapshot.status != .complete {
                    Button { Task { await goal.complete() } } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(goal.isBusy)
                }

                Spacer()

                Button(role: .destructive) {
                    goal.showClearConfirmation = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(CompactChatButton(primary: false))
                .disabled(goal.isBusy)
            }

            statusText
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(statusColor(snapshot.status).opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private var latestProgress: some View {
        if let latestResult {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label(
                        vm.chatIsSending && goal.continuousRunEnabled ? "Model is working now" : "Latest progress",
                        systemImage: vm.chatIsSending && goal.continuousRunEnabled ? "sparkles" : "text.bubble"
                    )
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.text)
                    if vm.chatIsSending && goal.continuousRunEnabled {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button("Open discussion") { vm.screen = .chat }
                        .buttonStyle(CompactChatButton(primary: false))
                }
                Text(latestResult.text)
                    .font(AppFont.body(12))
                    .foregroundStyle(latestResult.role == "error" ? Color(NSColor.systemRed) : UI.text)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
        }
    }

    private var statusText: some View {
        HStack(spacing: 7) {
            if goal.isBusy { ProgressView().scaleEffect(0.65) }
            Text(goal.statusMessage)
                .font(AppFont.body(11))
                .foregroundStyle(goal.statusMessage.lowercased().contains("fail") || goal.statusMessage.lowercased().contains("error") ? Color(NSColor.systemRed) : UI.muted)
        }
    }

    private var readinessColor: Color {
        switch readiness.level {
        case .ready: return Color(NSColor.systemGreen)
        case .caution: return Color(NSColor.systemOrange)
        case .blocked: return Color(NSColor.systemRed)
        }
    }

    private var readinessIcon: String {
        switch readiness.level {
        case .ready: return "checkmark.seal.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .blocked: return "xmark.octagon.fill"
        }
    }

    private func statusIcon(_ status: GoalLifecycleStatus) -> String {
        switch status {
        case .active: return "target"
        case .paused: return "pause.circle.fill"
        case .blocked, .usageLimited, .budgetLimited: return "exclamationmark.octagon.fill"
        case .complete: return "checkmark.seal.fill"
        }
    }

    private func goalStatusLabel(_ snapshot: OpenClawGoalSnapshot) -> String {
        guard snapshot.status == .active else { return snapshot.status.label }
        if goal.continuousRunEnabled { return "Continuing automatically" }
        return "Waiting"
    }

    private func statusColor(_ status: GoalLifecycleStatus) -> Color {
        switch status {
        case .active: return Color(NSColor.systemGreen)
        case .paused: return Color(NSColor.systemOrange)
        case .blocked, .usageLimited, .budgetLimited: return Color(NSColor.systemRed)
        case .complete: return Color(NSColor.systemBlue)
        }
    }
}
