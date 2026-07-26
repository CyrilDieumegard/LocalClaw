import AppKit
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
                if let plan = goal.plan, !plan.isApproved {
                    planReview(plan)
                } else if let snapshot = goal.snapshot {
                    activeGoal(snapshot)
                    if let plan = goal.plan, plan.isApproved {
                        executionPlan(plan)
                    } else {
                        planRequired
                    }
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
            await goal.reconcileLatestCheckpoint(using: vm)
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
                Text("Define the output, approve the plan, then let any Local, OAuth, or Cloud model execute it with persistent checkpoints.")
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
                    .disabled(vm.chatIsSending || goal.isGeneratingPlan || goal.continuousRunEnabled)
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Expected output")
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.muted)
                TextField("Optional preference, for example: a playable browser game or a PDF report", text: $goal.outputHint)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(13))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
            }

            HStack(spacing: 12) {
                Label("Planning does not modify files", systemImage: "doc.text.magnifyingglass")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                Label("Execution starts only after your approval", systemImage: "checkmark.shield")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                Spacer()
                Button {
                    goal.generatePlan(using: vm)
                } label: {
                    Label(goal.isGeneratingPlan ? "Generating Plan" : "Generate Output & Plan", systemImage: "wand.and.stars")
                }
                .buttonStyle(CTAButton(primary: true))
                .disabled(!readiness.canStart || goal.isBusy || goal.isGeneratingPlan || vm.chatIsSending || goal.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            statusText
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
    }

    private var planRequired: some View {
        HStack(spacing: 14) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(NSColor.systemOrange))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.systemOrange).opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text("This Goal needs an approved output and plan")
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)
                Text("LocalClaw will not continue an existing Goal blindly. Generate and review the destination and steps first.")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }
            Spacer()
            Button {
                goal.generatePlan(using: vm)
            } label: {
                Label(goal.isGeneratingPlan ? "Generating" : "Generate Plan", systemImage: "wand.and.stars")
            }
            .buttonStyle(CTAButton(primary: true))
            .disabled(!readiness.canStart || goal.isGeneratingPlan || vm.chatIsSending)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.systemOrange).opacity(0.35), lineWidth: 1))
    }

    private func planReview(_ plan: GoalExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Review before execution", systemImage: "checkmark.shield")
                        .font(AppFont.heading(19))
                        .foregroundStyle(UI.text)
                    Text("Confirm exactly what you will receive and how LocalClaw will know the Goal is finished.")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text("Execution has not started")
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(Color(NSColor.systemGreen))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Capsule().fill(Color(NSColor.systemGreen).opacity(0.10)))
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Expected output", systemImage: "shippingbox")
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)

                HStack(spacing: 10) {
                    reviewField("Deliverable type", text: planOutputBinding(\.type))
                    reviewField("Format or technology", text: planOutputBinding(\.format))
                }
                HStack(spacing: 10) {
                    reviewField("Destination", text: planOutputBinding(\.location))
                    reviewField("How it opens or is delivered", text: planOutputBinding(\.launch))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Final definition of done")
                        .font(AppFont.bodySemi(11))
                        .foregroundStyle(UI.muted)
                    TextEditor(text: outputCriteriaBinding)
                        .font(AppFont.body(12))
                        .foregroundStyle(UI.text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 62, maxHeight: 90)
                        .background(RoundedRectangle(cornerRadius: 7).fill(UI.card))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(UI.lineSoft, lineWidth: 1))
                    Text("One observable criterion per line.")
                        .font(AppFont.body(10))
                        .foregroundStyle(UI.muted)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Proposed plan", systemImage: "list.number")
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.text)
                    Spacer()
                    Text("\(plan.steps.count) steps")
                        .font(AppFont.bodySemi(10))
                        .foregroundStyle(UI.muted)
                    Button {
                        goal.addDraftStep()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(plan.steps.count >= 8)
                    .help("Add step")
                }

                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(UI.accent)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(UI.accent.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 7) {
                            TextField("Step title", text: planStepTextBinding(id: step.id, keyPath: \.title))
                                .textFieldStyle(.plain)
                                .font(AppFont.bodySemi(13))
                                .foregroundStyle(UI.text)
                            TextField("Concrete outcome", text: planStepTextBinding(id: step.id, keyPath: \.outcome))
                                .textFieldStyle(.plain)
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.muted)
                            TextField("Done when...", text: planStepCriteriaBinding(id: step.id))
                                .textFieldStyle(.plain)
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.text)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(UI.cardSoft))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(UI.lineSoft, lineWidth: 1))
                        }

                        VStack(spacing: 5) {
                            Button { goal.moveDraftStep(id: step.id, offset: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.plain).disabled(index == 0).help("Move up")
                            Button { goal.moveDraftStep(id: step.id, offset: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.plain).disabled(index == plan.steps.count - 1).help("Move down")
                            Button { goal.removeDraftStep(id: step.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).disabled(plan.steps.count <= 2).help("Remove step")
                        }
                        .foregroundStyle(UI.muted)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("The plan is saved and can be resumed after an interruption", systemImage: "externaldrive.badge.checkmark")
                        .foregroundStyle(UI.muted)
                    if let issue = plan.approvalIssue {
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(NSColor.systemOrange))
                    }
                }
                .font(AppFont.body(11))
                Spacer()
                Button {
                    goal.plan = nil
                    GoalPlanStore.remove(sessionID: goal.selectedChatSessionID)
                    goal.statusMessage = "Describe the Goal or generate another plan."
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                .buttonStyle(CompactChatButton(primary: false))

                Button {
                    goal.approveAndStart(using: vm)
                } label: {
                    Label("Approve & Start", systemImage: "play.fill")
                }
                .buttonStyle(CTAButton(primary: true))
                .disabled(!plan.isReadyForApproval || goal.isBusy || vm.chatIsSending)
            }

            statusText
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.accent.opacity(0.35), lineWidth: 1))
    }

    private func executionPlan(_ plan: GoalExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            executionPlanHeader(plan)

            ProgressView(value: Double(plan.completedStepCount), total: Double(max(plan.steps.count, 1)))
                .tint(UI.accent)

            executionOutputSummary(plan.output)

            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                executionStepRow(index: index, step: step)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func executionPlanHeader(_ plan: GoalExecutionPlan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.currentStep == nil ? "Plan complete" : "Step \((plan.currentStepIndex ?? 0) + 1) of \(plan.steps.count)")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.accent)
                Text(plan.currentStep?.title ?? "All approved steps are complete")
                    .font(AppFont.heading(18))
                    .foregroundStyle(UI.text)
                if let outcome = plan.currentStep?.outcome {
                    Text(outcome)
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                }
            }
            Spacer()
            Text("\(plan.completedStepCount) / \(plan.steps.count) complete")
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.muted)
        }
    }

    private func executionOutputSummary(_ output: GoalOutputContract) -> some View {
        let verification = GoalOutputVerifier.verify(output)
        return HStack(spacing: 8) {
            Label(output.type, systemImage: "shippingbox")
            Text("·")
            Text(output.format)
            Text("·")
            Text(output.location)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(output.location)
            if verification.requiresLocalArtifact {
                Label(
                    verification.isSatisfied ? "On disk" : "Missing",
                    systemImage: verification.isSatisfied ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(verification.isSatisfied ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
            }
            Spacer(minLength: 8)
            Button {
                revealGoalOutput(output.location)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .buttonStyle(CompactChatButton(primary: false))
            .disabled(output.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .font(AppFont.body(10))
        .foregroundStyle(UI.muted)
    }

    private func revealGoalOutput(_ rawPath: String) {
        let path = NSString(string: rawPath.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        guard !path.isEmpty else { return }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            let url = URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue)
            if isDirectory.boolValue {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            goal.statusMessage = "Opened the Goal output in Finder."
            return
        }

        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
            goal.statusMessage = "The final output is not present yet. Opened its destination folder."
        } else {
            goal.statusMessage = "Output location not found yet: \(path)"
        }
    }

    private func executionStepRow(index: Int, step: GoalPlanStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: planStepIcon(step.status))
                .foregroundStyle(planStepColor(step.status))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(index + 1). \(step.title)")
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(step.status == .pending ? UI.muted : UI.text)
                if !step.summary.isEmpty {
                    Text(step.summary)
                        .font(AppFont.body(10))
                        .foregroundStyle(UI.muted)
                        .lineLimit(2)
                }
                if !step.evidence.isEmpty {
                    Text(step.evidence.prefix(2).joined(separator: " · "))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(planStepColor(step.status))
                        .lineLimit(2)
                }
            }
            Spacer()
            if step.attempts > 0 {
                Text("\(step.attempts) turn\(step.attempts == 1 ? "" : "s")")
                    .font(AppFont.body(9))
                    .foregroundStyle(UI.muted)
            }
        }
        .padding(.vertical, 4)
    }

    private func activeGoal(_ snapshot: OpenClawGoalSnapshot) -> some View {
        let hasApprovedPlan = goal.plan?.isApproved == true
        let needsOutputRecovery = snapshot.status == .complete && goal.plan?.isComplete == false
        return VStack(alignment: .leading, spacing: 14) {
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
                        Text(snapshot.tokenBudget.map { "\(snapshot.tokensUsed.formatted()) / \($0.formatted()) tokens" } ?? "\(snapshot.tokensUsed.formatted()) tokens")
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

            HStack(spacing: 10) {
                if snapshot.status == .active && hasApprovedPlan {
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
                    }

                    Button { Task { await goal.pause() } } label: {
                        Label(goal.continuousRunEnabled ? "Stop & Pause" : "Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(goal.isBusy)
                } else if hasApprovedPlan && (snapshot.status != .complete || needsOutputRecovery) {
                    Button {
                        Task {
                            guard await goal.resumeForExecution(using: vm) else { return }
                            goal.startContinuousRun(using: vm, starting: false)
                        }
                    } label: {
                        Label(needsOutputRecovery ? "Repair missing output" : "Resume continuously", systemImage: "play.fill")
                    }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(goal.isBusy || vm.chatIsSending || !readiness.canStart)
                }

                if snapshot.status != .complete && hasApprovedPlan && goal.plan?.isComplete == true {
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

    private func reviewField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.muted)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(AppFont.body(12))
                .foregroundStyle(UI.text)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 7).fill(UI.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(UI.lineSoft, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func planOutputBinding(_ keyPath: WritableKeyPath<GoalOutputContract, String>) -> Binding<String> {
        Binding(
            get: { goal.plan?.output[keyPath: keyPath] ?? "" },
            set: { value in
                guard var plan = goal.plan, !plan.isApproved else { return }
                plan.output[keyPath: keyPath] = value
                goal.updateDraftPlan(plan)
            }
        )
    }

    private var outputCriteriaBinding: Binding<String> {
        Binding(
            get: { goal.plan?.output.completionCriteria.joined(separator: "\n") ?? "" },
            set: { value in
                guard var plan = goal.plan, !plan.isApproved else { return }
                plan.output.completionCriteria = value.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                goal.updateDraftPlan(plan)
            }
        )
    }

    private func planStepTextBinding(id: String, keyPath: WritableKeyPath<GoalPlanStep, String>) -> Binding<String> {
        Binding(
            get: { goal.plan?.steps.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var plan = goal.plan, !plan.isApproved,
                      let index = plan.steps.firstIndex(where: { $0.id == id }) else { return }
                plan.steps[index][keyPath: keyPath] = value
                goal.updateDraftPlan(plan)
            }
        )
    }

    private func planStepCriteriaBinding(id: String) -> Binding<String> {
        Binding(
            get: { goal.plan?.steps.first(where: { $0.id == id })?.completionCriteria.joined(separator: " | ") ?? "" },
            set: { value in
                guard var plan = goal.plan, !plan.isApproved,
                      let index = plan.steps.firstIndex(where: { $0.id == id }) else { return }
                plan.steps[index].completionCriteria = value.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                goal.updateDraftPlan(plan)
            }
        )
    }

    private func planStepIcon(_ status: GoalPlanStepStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "arrow.right.circle.fill"
        case .complete: return "checkmark.circle.fill"
        case .blocked: return "exclamationmark.octagon.fill"
        }
    }

    private func planStepColor(_ status: GoalPlanStepStatus) -> Color {
        switch status {
        case .pending: return UI.muted
        case .inProgress: return UI.accent
        case .complete: return Color(NSColor.systemGreen)
        case .blocked: return Color(NSColor.systemRed)
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
