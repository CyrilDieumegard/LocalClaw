import Foundation
import Testing
@testable import localclaw_mac_installer

struct InstallerEngineTests {
    @Test func recommendationForLowMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M1", memoryGB: 8, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Nemotron 3 Nano 4B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForMidMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M2", memoryGB: 16, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Nemotron 3 Nano 4B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForHighMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M4", memoryGB: 36, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Qwen 3.5 35B-A3B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func versionInfoFallbackWhenCommandMissing() {
        let engine = InstallerEngine()
        let version = engine.installedVersion(for: "definitely-not-a-command")
        #expect(version == "Not installed")
    }

    @Test func shellAddsHomebrewAndNpmPathsForAppLaunchedCommands() {
        #expect(InstallerEngine.shellPathPrefix.contains("/opt/homebrew/bin"))
        #expect(InstallerEngine.shellPathPrefix.contains("/usr/local/bin"))
        #expect(InstallerEngine.shellPathPrefix.contains("$HOME/.npm-global/bin"))
        #expect(InstallerEngine.shellPathPrefix.contains("$HOME/.local/bin"))
    }

    @Test func nodeVersionSupportMatchesOpenClawRequirement() {
        #expect(!InstallerEngine.isNodeVersionSupported("v22.18.0"))
        #expect(InstallerEngine.isNodeVersionSupported("v22.19.0"))
        #expect(InstallerEngine.isNodeVersionSupported("v26.0.0"))
        #expect(!InstallerEngine.isNodeVersionSupported("Not installed"))
    }

    @Test func providerAuthDetectsNamedOAuthProfiles() {
        let profiles: [String: Any] = [
            "openai-codex:cdieumegard@gmail.com": [
                "type": "oauth",
                "provider": "openai-codex"
            ],
            "openrouter:default": [
                "type": "api_key",
                "provider": "openrouter",
                "key": "sk-or-secret"
            ]
        ]

        #expect(InstallerEngine.providerAuthConfigured(in: profiles, provider: "openai-codex"))
        #expect(InstallerEngine.providerAuthConfigured(in: profiles, provider: "openrouter"))
        #expect(!InstallerEngine.providerAuthConfigured(in: profiles, provider: "openai"))
    }

    @Test func usageSummaryFiltersBySelectedWindow() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = InstallerViewModel.ModelUsageRecord(createdAt: now, model: "openrouter/openai/gpt-5.4-mini", inputTokens: 1_000, outputTokens: 500, totalTokens: 1_500, estimatedCostUSD: 0)
        let yesterday = InstallerViewModel.ModelUsageRecord(createdAt: calendar.date(byAdding: .day, value: -1, to: now)!, model: "openai-codex/gpt-5.4", inputTokens: 2_000, outputTokens: 1_000, totalTokens: 3_000, estimatedCostUSD: 0)
        let old = InstallerViewModel.ModelUsageRecord(createdAt: calendar.date(byAdding: .day, value: -5, to: now)!, model: "lmstudio/nvidia/nemotron-3-nano-4b", inputTokens: 10_000, outputTokens: 10_000, totalTokens: 20_000, estimatedCostUSD: 0)

        let todaySummary = InstallerViewModel.usageSummary(records: [today, yesterday, old], window: .today, now: now, calendar: calendar)
        let threeDaySummary = InstallerViewModel.usageSummary(records: [today, yesterday, old], window: .threeDays, now: now, calendar: calendar)

        #expect(todaySummary.totalTokens == 1_500)
        #expect(todaySummary.requestCount == 1)
        #expect(threeDaySummary.totalTokens == 4_500)
        #expect(threeDaySummary.inputTokens == 3_000)
        #expect(InstallerViewModel.formatTokenCount(12_300) == "12.3K")
    }

    @Test func oauthUsageParserToleratesWarningsBeforeJSON() throws {
        let raw = """
        [tasks/registry] Failed to restore task registry
        {
          "usage": {
            "updatedAt": 1779395478146,
            "providers": [
              {
                "provider": "openai-codex",
                "displayName": "Codex",
                "plan": "Codex Week",
                "windows": [
                  { "label": "5h", "usedPercent": 73, "resetAt": 1779398278146 },
                  { "label": "Codex Week", "usedPercent": 20 }
                ]
              }
            ]
          }
        }
        """

        let snapshot = try #require(InstallerViewModel.oauthUsageSnapshot(from: raw, providerHint: "openai-codex"))

        #expect(snapshot.displayName == "Codex")
        #expect(snapshot.primaryUsedPercent == 73)
        #expect(snapshot.primaryRemainingPercent == 27)
        #expect(snapshot.buttonLabel == "Usage 27% left")
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.tooltipLabel.contains("Codex Week"))
        #expect(snapshot.tooltipLabel.contains("80% left"))
        #expect(snapshot.tooltipLabel.contains("73% used"))
    }

    @Test func redactsSecretsFromConfigJSON() {
        let raw = """
        {
          "gateway": {
            "auth": {
              "token": "super-secret-token"
            }
          },
          "auth": {
            "profiles": {
              "openrouter:default": {
                "type": "api_key",
                "provider": "openrouter",
                "key": "sk-or-secret"
              }
            }
          },
          "agents": {
            "defaults": {
              "model": {
                "primary": "openrouter/moonshotai/kimi-k2.5"
              }
            }
          }
        }
        """

        let redacted = SecretRedactor.redactConfigText(raw)

        #expect(!redacted.contains("super-secret-token"))
        #expect(!redacted.contains("sk-or-secret"))
        #expect(redacted.contains("<redacted>"))
        #expect(redacted.contains("kimi-k2.5"))
    }

    @Test func computesSHA256ForDownloadedInstaller() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("localclaw-sha-test-\(UUID().uuidString)")
        try "LocalClaw".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let hash = try InstallerViewModel.sha256Hex(for: url)

        #expect(hash == "a1c2aaf18a271d28ac8433e25331c5ae53b09ff48b1db8b960c65e243545aea0")
    }

    @Test func shellSingleQuoteEscapesApostrophes() {
        let quoted = InstallerViewModel.shellSingleQuote("/Users/cyril/LocalClaw's update/localclaw.dmg")

        #expect(quoted == #"'/Users/cyril/LocalClaw'"'"'s update/localclaw.dmg'"#)
    }

    @MainActor @Test func licenseKeyNormalizationHandlesCopiedFormatting() {
        let normalized = InstallerViewModel.normalizedLicenseKey(" LCW\u{2011}20260519\u{200b} \n 1860\u{2014}9516 ")

        #expect(normalized == "LCW-20260519-1860-9516")
    }

    @Test func cronInventoryRefreshIncludesDisabledJobs() {
        #expect(InstallerViewModel.cronListInventoryCommand == "openclaw --no-color cron list --all --json")
    }

    @Test func channelConfigFallbackDetectsConfiguredAccounts() {
        let root: [String: Any] = [
            "channels": [
                "telegram": [
                    "enabled": true,
                    "token": "secret-token"
                ],
                "whatsapp": [
                    "accounts": [
                        "default": [
                            "enabled": true
                        ]
                    ]
                ],
                "slack": [
                    "enabled": false,
                    "accounts": [:]
                ]
            ]
        ]

        let snapshots = InstallerViewModel.configuredChannelSnapshots(from: root)

        #expect(snapshots["telegram"]?.configured == true)
        #expect(snapshots["telegram"]?.accounts == ["default"])
        #expect(snapshots["telegram"]?.tokenSource == "config")
        #expect(snapshots["whatsapp"]?.configured == true)
        #expect(snapshots["whatsapp"]?.accounts == ["default"])
        #expect(snapshots["slack"] == nil)
    }

    @Test func telegramTokenMigrationCreatesDefaultAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("openclaw.json")
        let config: [String: Any] = [
            "channels": [
                "telegram": [
                    "enabled": true,
                    "name": "Telegram",
                    "tokenFile": "/tmp/localclaw-telegram-token"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: configURL)

        InstallerViewModel.ensureTelegramDefaultAccountToken(configPath: configURL.path)

        let updatedData = try Data(contentsOf: configURL)
        let root = try #require(JSONSerialization.jsonObject(with: updatedData) as? [String: Any])
        let channels = try #require(root["channels"] as? [String: Any])
        let telegram = try #require(channels["telegram"] as? [String: Any])
        let accounts = try #require(telegram["accounts"] as? [String: Any])
        let defaultAccount = try #require(accounts["default"] as? [String: Any])

        #expect(telegram["defaultAccount"] as? String == "default")
        #expect(defaultAccount["enabled"] as? Bool == true)
        #expect(defaultAccount["tokenFile"] as? String == "/tmp/localclaw-telegram-token")
    }

    @Test func telegramPairingErrorExplainsMissingPendingCode() {
        let message = InstallerViewModel.telegramPairingErrorMessage(
            code: "PR5HK9V5",
            output: "[openclaw] Reason: No pending pairing request found for code \"PR5HK9V5\"."
        )

        #expect(message.contains("No pending Telegram request"))
        #expect(message.contains("/start"))
        #expect(!message.contains("[openclaw]"))
    }

    @Test func discordChannelProfileUsesNativeBotTokenField() {
        let profile = InstallerViewModel.channelCredentialProfile(for: "discord", label: "Discord")

        #expect(profile.title == "Discord setup")
        #expect(profile.primaryButton == "Save Discord")
        #expect(profile.fields.map(\.id) == ["botToken"])
        #expect(profile.fields.first?.cliOption == "--bot-token")
    }

    @Test func knownChannelCredentialOptionsAreSupportedByOpenClawAdd() {
        let supportedOptions: Set<String> = [
            "--account", "--app-token", "--auth-dir", "--base-url", "--bot-token", "--channel",
            "--cli-path", "--db-path", "--http-host", "--http-port", "--http-url", "--name",
            "--password", "--region", "--secret", "--secret-file", "--service", "--signal-number",
            "--token", "--token-file", "--url", "--use-env"
        ]
        let channels = InstallerViewModel.openClawAddSupportedChannelIDs

        #expect(!channels.contains("wecom"))
        #expect(!channels.contains("yuanbao"))
        #expect(!channels.contains("openclaw-weixin"))

        for channel in channels {
            let profile = InstallerViewModel.channelCredentialProfile(for: channel)
            for field in profile.fields {
                #expect(supportedOptions.contains(field.cliOption), "Unsupported option \(field.cliOption) for \(channel)")
            }
        }
    }

    @Test func canonicalChatRuntimeModelMapsOpenAIGPTModels() {
        #expect(InstallerViewModel.canonicalChatRuntimeModelID("openrouter/openai/gpt-5.5") == "openrouter/openai/gpt-5.5")
        #expect(InstallerViewModel.canonicalChatRuntimeModelID("openrouter/openai/gpt-5.4") == "openrouter/openai/gpt-5.4")
        #expect(InstallerViewModel.canonicalChatRuntimeModelID("openrouter/openai/gpt-5.4-mini") == "openrouter/openai/gpt-5.4-mini")
        #expect(InstallerViewModel.canonicalChatRuntimeModelID("openrouter/moonshotai/kimi-k2.5") == "openrouter/openai/gpt-5.4-mini")
    }

    @Test func developerRuntimeSessionIDChangesWithModel() {
        let base = "localclaw-developer-chat-abc"

        let gpt = InstallerViewModel.runtimeSessionID(base: base, modelID: "openai/gpt-5.5", useDeveloperSession: true)
        let gemma = InstallerViewModel.runtimeSessionID(base: base, modelID: "lmstudio/google/gemma-4-e2b", useDeveloperSession: true)

        #expect(gpt != base)
        #expect(gemma != base)
        #expect(gpt != gemma)
        #expect(InstallerViewModel.runtimeSessionID(base: base, modelID: "openai/gpt-5.5", useDeveloperSession: false) == base)
    }

    @Test func developerRuntimeSessionIDCanUseFreshTurnScope() {
        let base = "localclaw-developer-chat-abc"

        let first = InstallerViewModel.runtimeSessionID(base: base, modelID: "openai/gpt-5.5", useDeveloperSession: true, freshTurnID: "turn-a")
        let second = InstallerViewModel.runtimeSessionID(base: base, modelID: "openai/gpt-5.5", useDeveloperSession: true, freshTurnID: "turn-b")

        #expect(first != second)
        #expect(first.contains("-turn-turn-a"))
        #expect(second.contains("-turn-turn-b"))
    }

    @Test func regularChatRuntimeSessionIDCanUseFreshTurnScope() {
        let base = "localclaw-ui-chat-abc"

        #expect(InstallerViewModel.runtimeSessionID(base: base, modelID: "lmstudio/nvidia/nemotron-3-nano-4b", useDeveloperSession: false) == base)
        #expect(InstallerViewModel.runtimeSessionID(base: base, modelID: "lmstudio/nvidia/nemotron-3-nano-4b", useDeveloperSession: false, freshTurnID: "local-a") == "\(base)-turn-local-a")
    }

    @Test func fastDeveloperRequestsUseLowThinkingAndShortTimeout() {
        #expect(InstallerViewModel.agentThinkingLevel(for: .fast) == "low")
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .fast, useDeveloperSession: true) == 90)
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .cloud, useDeveloperSession: true) == 420)
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .deep, useDeveloperSession: true) == 600)
    }

    @Test func simpleDeveloperEditsUseTightBudget() {
        #expect(InstallerViewModel.isSimpleDeveloperEdit("change the game color to purple"))
        #expect(InstallerViewModel.isSimpleDeveloperEdit("set the theme to violet"))
        #expect(!InstallerViewModel.isSimpleDeveloperEdit("refactor the backend auth and database migration"))
        #expect(InstallerViewModel.simpleDeveloperEditTimeoutSeconds == 60)
        #expect(InstallerViewModel.wallClockTimeoutSeconds(forAgentTimeout: 60) == 180)
    }

    @Test func localLMStudioModelIDNormalizesPickerValues() {
        #expect(InstallerViewModel.localLMStudioModelID(from: "lmstudio/google/gemma-4-e4b") == "google/gemma-4-e4b")
        #expect(InstallerViewModel.localLMStudioModelID(from: "google/gemma-4-e4b") == "google/gemma-4-e4b")
        #expect(InstallerViewModel.localLMStudioModelID(from: "openrouter/openai/gpt-5.5") == "")
        #expect(InstallerViewModel.localLMStudioModelID(from: "openai/gpt-5.4") == "")
        #expect(InstallerViewModel.localLMStudioModelID(from: "google-gemini-cli/gemini-3.1-pro-preview") == "")
        #expect(InstallerViewModel.localLMStudioModelID(from: "  lmstudio/nvidia/nemotron-3-nano-4b  ") == "nvidia/nemotron-3-nano-4b")
    }

    @Test func machineYearUsesMacStudioModelIdentifier() {
        #expect(InstallerViewModel.machineYear(modelIdentifier: "Mac14,13", modelName: "Mac Studio") == "2023")
        #expect(InstallerViewModel.machineYear(modelIdentifier: "Mac13,2", modelName: "Mac Studio") == "2022")
    }

    @MainActor
    @Test func oauthSelectionKeepsSelectedOAuthRuntimeModel() {
        let vm = InstallerViewModel()
        vm.inferenceMode = .oauth
        vm.selectedCloudAuthMode = .oauth
        vm.selectedChatResponseMode = .cloud
        vm.oauthModelsLive = [
            InstallerViewModel.OpenRouterModel(id: "openai/gpt-5.4-mini", displayName: "GPT-5.4 Mini"),
            InstallerViewModel.OpenRouterModel(id: "openai/gpt-5.4", displayName: "GPT-5.4")
        ]
        vm.selectedChatModel = "openai/gpt-5.4-mini"

        vm.handleChatModelSelectionChanged(useDeveloperSession: false)

        #expect(vm.inferenceMode == .oauth)
        #expect(vm.selectedChatResponseMode == .cloud)
        #expect(vm.selectedChatModel == "openai/gpt-5.4-mini")
        #expect(vm.selectedOAuthModelIdentifier() == "openai/gpt-5.4-mini")
    }

    @Test func quickDeveloperColorEditRewritesStyleFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("localclaw-quick-color-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        body { background: #120a24; color: #ddd6fe; }
        .snake { border-color: purple; box-shadow: 0 0 12px #7c3aed; }
        """
        .write(to: root.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)

        let result = InstallerViewModel.applyQuickDeveloperColorEdit(projectPath: root.path, requestText: "change the game color to yellow")
        let updated = try String(contentsOf: root.appendingPathComponent("style.css"), encoding: .utf8)

        #expect(result?.colorName == "yellow")
        #expect(result?.changedFiles == ["style.css"])
        #expect(updated.contains("#181107"))
        #expect(updated.contains("yellow"))
        #expect(!updated.contains("purple"))
    }

    @Test func newDeveloperProjectNameSkipsExistingProjectSlugs() {
        let existing: Set<String> = ["my-app", "my-app-2", "snake"]

        #expect(InstallerViewModel.nextDeveloperProjectName(existingSlugs: existing) == "My App 3")
        #expect(InstallerViewModel.nextDeveloperProjectName(existingSlugs: existing, baseName: "Snake") == "Snake 2")
    }

    @MainActor
    @Test func chatModelListShowsOnlyLocalModelsInLocalMode() {
        let vm = InstallerViewModel()
        vm.inferenceMode = .local
        vm.selectedChatResponseMode = .local
        vm.currentModel = "openrouter/openai/gpt-5.5"
        vm.localLMStudioModels = ["google/gemma-4-e2b", "nvidia/nemotron-3-nano-4b"]
        vm.selectedChatModel = "openrouter/openai/gpt-5.5"

        vm.ensureSelectedChatModel()

        #expect(vm.availableChatModels.allSatisfy { $0.id.hasPrefix("lmstudio/") })
        #expect(vm.availableChatModels.map(\.id) == ["lmstudio/google/gemma-4-e2b", "lmstudio/nvidia/nemotron-3-nano-4b"])
        #expect(vm.selectedChatModel == "lmstudio/google/gemma-4-e2b")
    }

    @MainActor
    @Test func chatModelListShowsOnlyCloudModelsInCloudMode() {
        let vm = InstallerViewModel()
        vm.inferenceMode = .cloud
        vm.selectedChatResponseMode = .cloud
        vm.currentModel = "lmstudio/google/gemma-4-e2b"
        vm.localLMStudioModels = ["google/gemma-4-e2b"]
        vm.openRouterModelsLive = [
            InstallerViewModel.OpenRouterModel(id: "openrouter/openai/gpt-5.5", displayName: "GPT-5.5"),
            InstallerViewModel.OpenRouterModel(id: "openrouter/openai/gpt-5.4-mini", displayName: "GPT-5.4 Mini")
        ]
        vm.selectedChatModel = "lmstudio/google/gemma-4-e2b"

        vm.ensureSelectedChatModel()

        #expect(vm.availableChatModels.allSatisfy { $0.id.hasPrefix("openrouter/") })
        #expect(vm.availableChatModels.map(\.id) == ["openrouter/openai/gpt-5.5", "openrouter/openai/gpt-5.4-mini"])
        #expect(vm.selectedChatModel == "openrouter/openai/gpt-5.5")
    }

    @MainActor
    @Test func oauthModeKeepsOAuthModelList() {
        let vm = InstallerViewModel()
        vm.inferenceMode = .oauth
        vm.selectedCloudAuthMode = .oauth
        vm.selectedChatResponseMode = .cloud
        vm.currentModel = "openrouter/openai/gpt-5.5"
        vm.openRouterModelsLive = [
            InstallerViewModel.OpenRouterModel(id: "openrouter/openai/gpt-5.5", displayName: "GPT-5.5")
        ]
        vm.selectedChatModel = "openrouter/openai/gpt-5.5"

        vm.prepareModelListForSelectedMode()
        vm.ensureSelectedChatModel()

        #expect(vm.inferenceMode == .oauth)
        #expect(vm.selectedCloudAuthMode == .oauth)
        #expect(vm.availableChatModels.map(\.id).contains("openai-codex/gpt-5.5"))
        #expect(vm.selectedChatModel == "openai-codex/gpt-5.5")
        #expect(vm.effectiveAuthProvider() == "openai-codex")
    }

    @MainActor
    @Test func userSwitchingOAuthDoesNotFallBackToLocalMode() {
        let vm = InstallerViewModel()
        vm.inferenceMode = .local
        vm.selectedChatResponseMode = .local
        vm.currentModel = "lmstudio/google/gemma-4-e2b"
        vm.localLMStudioModels = ["google/gemma-4-e2b"]
        vm.selectedChatModel = "lmstudio/google/gemma-4-e2b"

        vm.selectInferenceModeFromUser(.oauth)

        #expect(vm.inferenceMode == .oauth)
        #expect(vm.selectedChatResponseMode == .cloud)
        #expect(vm.selectedCloudAuthMode == .oauth)
        #expect(vm.selectedProvider == .openAI)
        #expect(vm.selectedChatModel == "openai-codex/gpt-5.5")
        #expect(vm.availableChatModels.map(\.id).contains("openai-codex/gpt-5.5"))
        vm.presentOAuthSetupAssistantIfNeeded(authConfigured: false)
        #expect(vm.showOAuthSetupAssistant == true)
    }

    @MainActor
    @Test func userSwitchingCloudDoesNotKeepOAuthAuthMode() {
        let vm = InstallerViewModel()
        vm.inferenceMode = .oauth
        vm.selectedCloudAuthMode = .oauth
        vm.selectedProvider = .openAI
        vm.selectedChatResponseMode = .cloud
        vm.openRouterModelsLive = [
            InstallerViewModel.OpenRouterModel(id: "openrouter/openai/gpt-5.4-mini", displayName: "GPT-5.4 Mini")
        ]

        vm.selectInferenceModeFromUser(.cloud)

        #expect(vm.inferenceMode == .cloud)
        #expect(vm.selectedChatResponseMode == .cloud)
        #expect(vm.selectedCloudAuthMode == .api)
        #expect(vm.selectedProvider == .openRouter)
        #expect(vm.selectedChatModel == "openrouter/openai/gpt-5.4-mini")
    }

    @MainActor
    @Test func kanbanTaskCanPrepareCronForm() {
        let vm = InstallerViewModel()
        vm.kanbanAutomationSyncEnabled = false
        vm.beginCreateKanbanCard()
        vm.kanbanEditorTitle = "Daily roadmap check"
        vm.kanbanEditorDetail = "Summarize blockers and next actions."
        vm.kanbanEditorPriority = "High"
        vm.kanbanEditorAgentID = "main"
        vm.kanbanEditorScheduleValue = "1d"
        vm.kanbanEditorDeliveryMode = "channel"
        vm.kanbanEditorDeliveryChannel = "telegram"
        vm.kanbanEditorDeliveryTo = "12345"

        vm.saveKanbanTaskEditor()
        let card = vm.kanbanColumns.first { $0.id == "backlog" }?.cards.first
        #expect(card?.title == "Daily roadmap check")

        vm.prepareCronFromKanbanCard(card!)

        #expect(vm.showCronJobCreator)
        #expect(vm.cronCreateName == "Daily roadmap check")
        #expect(vm.cronCreateAgentID == "main")
        #expect(vm.cronCreateScheduleValue == "1d")
        #expect(vm.cronCreateDeliveryMode == "channel")
        #expect(vm.cronCreateDeliveryChannel == "telegram")
        #expect(vm.cronCreateDeliveryTo == "12345")
        #expect(vm.cronCreateMessage.contains("Summarize blockers"))
    }

    @MainActor
    @Test func kanbanTaskEditorLoadsExistingCardValues() {
        let vm = InstallerViewModel()
        vm.kanbanAutomationSyncEnabled = false
        vm.beginCreateKanbanCard()
        vm.kanbanEditorTitle = "Draft launch checklist"
        vm.kanbanEditorDetail = "Confirm the release notes and support plan."
        vm.kanbanEditorPriority = "Urgent"
        vm.kanbanEditorScheduleKind = "cron"
        vm.kanbanEditorScheduleValue = "0 9 * * *"
        vm.kanbanEditorDeliveryMode = "channel"
        vm.kanbanEditorDeliveryChannel = "telegram"
        vm.kanbanEditorDeliveryTo = "67890"
        vm.saveKanbanTaskEditor()

        let card = vm.kanbanColumns.first { $0.id == "backlog" }!.cards.first!
        vm.beginEditKanbanCard(card, columnID: "backlog")

        #expect(vm.kanbanEditorTitle == "Draft launch checklist")
        #expect(vm.kanbanEditorPriority == "Urgent")
        #expect(vm.kanbanEditorScheduleKind == "cron")
        #expect(vm.kanbanEditorScheduleValue == "0 9 * * *")
        #expect(vm.kanbanEditorDeliveryMode == "channel")
        #expect(vm.kanbanEditorDeliveryTo == "67890")

        vm.kanbanEditorTitle = "Updated launch checklist"
        vm.kanbanEditorDeliveryTo = "99999"
        vm.saveKanbanTaskEditor()

        let updatedCard = vm.kanbanColumns.first { $0.id == "backlog" }!.cards.first!
        #expect(updatedCard.title == "Updated launch checklist")
        #expect(updatedCard.deliveryTo == "99999")
        #expect(updatedCard.priority == "Urgent")
    }

    @MainActor
    @Test func kanbanTaskStartsOnlyWhenMovedToProgress() {
        let vm = InstallerViewModel()
        vm.kanbanAutomationSyncEnabled = false
        vm.beginCreateKanbanCard()
        vm.kanbanEditorTitle = "Prepare weekly report"
        vm.saveKanbanTaskEditor()

        let card = vm.kanbanColumns.first { $0.id == "backlog" }!.cards.first!

        vm.startKanbanCard(card.id)

        #expect(vm.kanbanColumns.first { $0.id == "backlog" }?.cards.contains { $0.id == card.id } == false)
        #expect(vm.kanbanColumns.first { $0.id == "doing" }?.cards.contains { $0.id == card.id } == true)
        #expect(vm.kanbanStatus.contains("Work starts now"))
    }

    @Test func kanbanRunCommandUsesAgentAndDeliveryDestination() {
        let command = InstallerViewModel.kanbanRunCommand(
            agentID: "localagent",
            message: "Envoyez un résumé",
            deliveryMode: "channel",
            deliveryChannel: "telegram",
            deliveryAccount: "",
            deliveryTo: "1636626469"
        )

        #expect(command.contains("openclaw --no-color agent"))
        #expect(command.contains("--agent 'localagent'"))
        #expect(command.contains("--deliver"))
        #expect(command.contains("--reply-channel 'telegram'"))
        #expect(command.contains("--reply-to '1636626469'"))
    }

    @Test func kanbanCronCommandCreatesRealScheduledJob() {
        let card = InstallerViewModel.KanbanCard.fresh(
            title: "Tortue",
            detail: "Parle moi d'une tortue",
            priority: "Urgent",
            agentID: "localagent",
            reviewSchedule: "2026-05-22T11:55:29+02:00",
            scheduleTimeZoneID: "Europe/Zurich",
            scheduleKind: "at",
            cronEnabled: true,
            deliveryMode: "channel",
            deliveryChannel: "telegram",
            deliveryTo: "1636626469"
        )

        let command = InstallerViewModel.kanbanCronAddCommand(card: card)

        #expect(command.contains("openclaw --no-color cron add"))
        #expect(command.contains("--at '2026-05-22T11:55:29+02:00'"))
        #expect(command.contains("--delete-after-run"))
        #expect(command.contains("--agent 'localagent'"))
        #expect(command.contains("--channel 'telegram'"))
        #expect(command.contains("--to '1636626469'"))
    }

    @Test func extractsCronJobIDFromJSONOutput() {
        #expect(InstallerViewModel.extractCronJobID(from: #"{"id":"job-123"}"#) == "job-123")
        #expect(InstallerViewModel.extractCronJobID(from: #"{"job":{"id":"job-456"}}"#) == "job-456")
        #expect(InstallerViewModel.extractCronJobID(from: #"""
Created job
{"id":"job-789","name":"Tortue"}
"""#) == "job-789")
    }

    @Test func atScheduleDateFormatsForOpenClawCron() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 3600)
        components.year = 2026
        components.month = 5
        components.day = 22
        components.hour = 14
        components.minute = 30
        components.second = 0
        let date = components.date!

        let value = InstallerViewModel.cronAtDateString(date, timeZoneID: "Europe/Zurich")
        let parsed = InstallerViewModel.cronAtDate(from: value)

        #expect(value.contains("2026-05-22T"))
        #expect(value.hasSuffix("+02:00"))
        #expect(parsed != nil)
    }

    @Test func timezoneLabelShowsLocationAndOffset() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 5
        components.day = 22
        components.hour = 12
        let date = components.date!

        let label = InstallerViewModel.timeZoneDisplayLabel("Europe/Zurich", date: date)

        #expect(label.contains("Europe/Zurich"))
        #expect(label.contains("GMT+02:00"))
    }

    @Test func createsRunnableDeveloperPreviewScaffold() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("localclaw-preview-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try InstallerViewModel.createDeveloperPreviewScaffold(at: root, appName: "Cyril's App")

        let package = try String(contentsOf: root.appendingPathComponent("package.json"), encoding: .utf8)
        let index = try String(contentsOf: root.appendingPathComponent("index.html"), encoding: .utf8)
        let main = try String(contentsOf: root.appendingPathComponent("src/main.jsx"), encoding: .utf8)

        #expect(package.contains(#""dev" : "vite --host 127.0.0.1""#) || package.contains(#""dev": "vite --host 127.0.0.1""#))
        #expect(package.contains(#""name" : "cyril-s-app""#) || package.contains(#""name": "cyril-s-app""#))
        #expect(index.contains("<div id=\"root\"></div>"))
        #expect(main.contains(#"const appName = "Cyril's App";"#))
    }

    @Test func addsPreviewScriptToExistingPackage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("localclaw-preview-existing-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try #"{"scripts":{"build":"vite build"},"dependencies":{"react":"18"}}"#
            .write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        try InstallerViewModel.createDeveloperPreviewScaffold(at: root, appName: "Existing App")

        let package = try String(contentsOf: root.appendingPathComponent("package.json"), encoding: .utf8)
        #expect(package.contains(#""build" : "vite build""#) || package.contains(#""build": "vite build""#))
        #expect(package.contains(#""dev" : "vite --host 127.0.0.1""#) || package.contains(#""dev": "vite --host 127.0.0.1""#))
        #expect(package.contains(#""react" : "18""#) || package.contains(#""react": "18""#))
        #expect(package.contains(#""vite" : "latest""#) || package.contains(#""vite": "latest""#))
    }
}
