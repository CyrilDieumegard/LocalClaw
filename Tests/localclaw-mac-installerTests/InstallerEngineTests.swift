import Foundation
import Testing
@testable import localclaw_mac_installer

struct InstallerEngineTests {
    @Test func recommendationForLowMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M1", memoryGB: 8, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.model == "Qwen 3.5 2B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForMidMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M2", memoryGB: 16, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.tier == "Balanced")
        #expect(reco.model == "Qwen 3.5 9B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForMacStudioHighMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M4", memoryGB: 36, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.tier == "Power")
        #expect(reco.model == "Qwen 3.5 9B")
        #expect(reco.rationale.contains("working memory"))
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func recommendationForUltraMemory() {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M3", memoryGB: 64, isAppleSilicon: true)

        let reco = engine.recommend(for: profile)

        #expect(reco.tier == "Ultra")
        #expect(reco.model == "Qwen 3.8 27B")
        #expect(reco.quant == "Q4_K_M")
    }

    @Test func localModelRankingChangesWithWorkload() throws {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M3", memoryGB: 24, isAppleSilicon: true)
        let models = [
            LocalModelScoringInput(name: "Code specialist", fileSizeGB: 3, maxContextK: 128, quality: 3.5, coding: 5, reasoning: 2.5, speed: 3.5, toolUse: 4.5, multimodal: false),
            LocalModelScoringInput(name: "Reasoning specialist", fileSizeGB: 3, maxContextK: 128, quality: 3.5, coding: 2.5, reasoning: 5, speed: 3.5, toolUse: 4, multimodal: false)
        ]

        let coding = try #require(engine.rankLocalModels(models, for: profile, workload: .coding).first)
        let reasoning = try #require(engine.rankLocalModels(models, for: profile, workload: .reasoning).first)

        #expect(coding.model.name == "Code specialist")
        #expect(reasoning.model.name == "Reasoning specialist")
    }

    @Test func localModelRankingRejectsModelsWithoutMemoryHeadroom() throws {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M2", memoryGB: 16, isAppleSilicon: true)
        let oversized = LocalModelScoringInput(name: "Oversized", fileSizeGB: 22, maxContextK: 256, quality: 5, coding: 5, reasoning: 5, speed: 3, toolUse: 5, multimodal: true)

        let match = try #require(engine.rankLocalModels([oversized], for: profile, workload: .automatic).first)

        #expect(match.fit == .tooLarge)
        #expect(match.estimatedHeadroomGB < 0)
    }

    @Test func localModelRankingExplainsUnsupportedIntelMacs() throws {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Intel Core i9", memoryGB: 32, isAppleSilicon: false)
        let model = LocalModelScoringInput(name: "Small", fileSizeGB: 2, maxContextK: 128, quality: 3, coding: 3, reasoning: 3, speed: 5, toolUse: 3, multimodal: false)

        let match = try #require(engine.rankLocalModels([model], for: profile, workload: .automatic).first)

        #expect(match.fit == .unsupported)
        #expect(match.rationale.contains("Apple Silicon"))
    }

    @Test func longContextWorkloadBudgetsForLargerContext() throws {
        let engine = InstallerEngine()
        let profile = HardwareProfile(chip: "Apple M4", memoryGB: 64, isAppleSilicon: true)
        let model = LocalModelScoringInput(name: "Long context", fileSizeGB: 5, maxContextK: 256, quality: 4, coding: 4, reasoning: 4, speed: 4, toolUse: 4, multimodal: false)

        let automatic = try #require(engine.rankLocalModels([model], for: profile, workload: .automatic).first)
        let longContext = try #require(engine.rankLocalModels([model], for: profile, workload: .longContext).first)

        #expect(longContext.targetContextK == 128)
        #expect(longContext.estimatedWorkingMemoryGB > automatic.estimatedWorkingMemoryGB)
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

    @Test func jsonExtractorSkipsOpenClawWarningsBeforeObjects() throws {
        let output = """
        [state-migrations] Legacy state migration warnings:
        - Left plugin metadata in place
        {"rpc":{"ok":true},"health":{"healthy":true}}
        """

        let root = try #require(InstallerEngine.firstJSONObject(in: output))
        let rpc = try #require(root["rpc"] as? [String: Any])

        #expect(rpc["ok"] as? Bool == true)
    }

    @Test func jsonExtractorSupportsWarningPrefixedArrays() throws {
        let output = """
        [state-migrations] warning
        [{"id":"main"},{"id":"localagent"}]
        """

        let rows = try #require(InstallerEngine.firstJSONArray(in: output))

        #expect(rows.count == 2)
        #expect(rows.first?["id"] as? String == "main")
    }

    @Test func gatewayHealthRequiresRunningRuntimeAndRPC() {
        let healthyWithoutOptionalHealthBlock = """
        {"service":{"runtime":{"status":"running"}},"rpc":{"ok":true}}
        """
        let stopped = """
        {"service":{"runtime":{"status":"stopped"}},"rpc":{"ok":false},"health":{"healthy":false}}
        """
        let explicitlyUnhealthy = """
        {"service":{"runtime":{"status":"running"}},"rpc":{"ok":true},"health":{"healthy":false}}
        """

        #expect(InstallerEngine.gatewayIsHealthy(statusOutput: healthyWithoutOptionalHealthBlock))
        #expect(!InstallerEngine.gatewayIsHealthy(statusOutput: stopped))
        #expect(!InstallerEngine.gatewayIsHealthy(statusOutput: explicitlyUnhealthy))
    }

    @Test func pluginDriftOnlyUpdatesOfficialOpenClawPackages() {
        let output = """
        {
          "pluginVersionDrift": {
            "drifts": [
              {"source":"npm","packageName":"@openclaw/codex"},
              {"source":"npm","packageName":"third-party/plugin"},
              {"source":"path","packageName":"@openclaw/whatsapp"}
            ]
          }
        }
        """

        #expect(InstallerEngine.officialPluginUpdateSpecs(from: output) == ["@openclaw/codex@latest"])
    }

    @Test func legacyPluginIndexMustBeCoveredBeforeArchiving() throws {
        let legacy = """
        {
          "installRecords": {
            "codex": {"source":"npm","resolvedName":"@openclaw/codex","version":"2026.5.12"},
            "whatsapp": {"source":"path","sourcePath":"/old/whatsapp"}
          }
        }
        """.data(using: .utf8)!
        let coveredRegistry = """
        [state-migrations] warning
        {
          "persisted": {
            "installRecords": {
              "codex": {"source":"npm","resolvedName":"@openclaw/codex","version":"2026.7.1"},
              "whatsapp": {"source":"path","sourcePath":"/new/whatsapp"}
            }
          }
        }
        """
        let incompleteRegistry = """
        {"persisted":{"installRecords":{"codex":{"source":"npm","resolvedName":"@openclaw/codex"}}}}
        """

        #expect(InstallerEngine.legacyInstallRecordsAreCovered(legacyData: legacy, registryOutput: coveredRegistry))
        #expect(!InstallerEngine.legacyInstallRecordsAreCovered(legacyData: legacy, registryOutput: incompleteRegistry))
    }

    @Test func emptyLegacyPluginIndexIsSafeToArchive() {
        let legacy = #"{"installRecords":{}}"#.data(using: .utf8)!
        let registry = #"{"persisted":{"installRecords":{}}}"#

        #expect(InstallerEngine.legacyInstallRecordsAreCovered(legacyData: legacy, registryOutput: registry))
    }

    @Test func staleCodexSidecarsComeOnlyFromExplicitForeignHarnessWarnings() {
        let output = """
        - Left Codex binding sidecar in place because its session is owned by agent harness pi: /Users/test/.openclaw/agents/main/sessions/chat.jsonl.codex-app-server.json
        - Left Codex binding sidecar in place because its binding is invalid: /Users/test/.openclaw/agents/main/sessions/unsafe.jsonl.codex-app-server.json
        """

        #expect(InstallerEngine.staleCodexBindingSidecarPaths(in: output) == [
            "/Users/test/.openclaw/agents/main/sessions/chat.jsonl.codex-app-server.json"
        ])
    }

    @Test func nodeVersionSupportMatchesOpenClawRequirement() {
        #expect(!InstallerEngine.isNodeVersionSupported("v22.22.2"))
        #expect(InstallerEngine.isNodeVersionSupported("v22.22.3"))
        #expect(!InstallerEngine.isNodeVersionSupported("v23.11.0"))
        #expect(!InstallerEngine.isNodeVersionSupported("v24.14.0"))
        #expect(InstallerEngine.isNodeVersionSupported("v24.15.0"))
        #expect(!InstallerEngine.isNodeVersionSupported("v25.8.0"))
        #expect(InstallerEngine.isNodeVersionSupported("v25.9.0"))
        #expect(InstallerEngine.isNodeVersionSupported("v26.0.0"))
        #expect(!InstallerEngine.isNodeVersionSupported("Not installed"))
    }

    @Test func oauthFallbackIncludesCurrentOpenAIModels() {
        let ids = Set(InstallerViewModel.oauthFallbackModels.map(\.id))
        #expect(ids.contains("openai/gpt-5.6"))
        #expect(ids.contains("openai/gpt-5.6-sol"))
        #expect(ids.contains("openai/gpt-5.6-luna"))
        #expect(ids.contains("openai/gpt-5.6-terra"))
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

    @Test func providerAuthDetectsProcessEnvironmentWithoutExposingValue() {
        let environment = ["OPENROUTER_API_KEY": "configured"]

        #expect(InstallerEngine.providerAuthConfigured(in: environment, provider: "openrouter"))
        #expect(!InstallerEngine.providerAuthConfigured(in: ["OPENROUTER_API_KEY": "  "], provider: "openrouter"))
        #expect(!InstallerEngine.providerAuthConfigured(in: environment, provider: "openai"))
    }

    @Test func providerAuthDetectsOpenClawProviderConfig() {
        let config: [String: Any] = [
            "models": [
                "providers": [
                    "openrouter": ["apiKey": "configured"]
                ]
            ]
        ]

        #expect(InstallerEngine.providerAuthConfigured(inConfig: config, provider: "openrouter"))
        #expect(!InstallerEngine.providerAuthConfigured(inConfig: config, provider: "anthropic"))
    }

    @Test func providerAuthDetectsOpenClawSQLiteBackedStatus() {
        let status: [String: Any] = [
            "auth": [
                "providersWithOAuth": ["openai"],
                "missingProvidersInUse": ["anthropic"],
                "providers": [
                    [
                        "provider": "openrouter",
                        "effective": ["kind": "profiles"],
                        "profiles": ["count": 1, "oauth": 0, "token": 0, "apiKey": 1]
                    ],
                    [
                        "provider": "anthropic",
                        "effective": ["kind": "missing"],
                        "profiles": ["count": 0, "oauth": 0, "token": 0, "apiKey": 0]
                    ]
                ]
            ]
        ]

        let configured = InstallerEngine.configuredProviders(inModelStatus: status)
        #expect(configured.contains("openrouter"))
        #expect(configured.contains("openai"))
        #expect(!configured.contains("anthropic"))
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

    @Test func homeUsageSummaryShareTextIncludesModelsAndTotals() {
        let summary = InstallerViewModel.UsageSummary(inputTokens: 1_000, outputTokens: 500, totalTokens: 1_500, requestCount: 2)
        let records = [
            InstallerViewModel.ModelUsageRecord(createdAt: Date(), model: "openrouter/openai/gpt-5.4-mini", inputTokens: 1_000, outputTokens: 500, totalTokens: 1_500, estimatedCostUSD: 0),
            InstallerViewModel.ModelUsageRecord(createdAt: Date(), model: "lmstudio/nvidia/nemotron-3-nano-4b", inputTokens: 10, outputTokens: 20, totalTokens: 30, estimatedCostUSD: 0)
        ]

        let shareText = InstallerViewModel.homeUsageSummaryShareText(summary: summary, window: .today, records: records)

        #expect(shareText.contains("LocalClaw token summary"))
        #expect(shareText.contains("Total tokens: 1.5K"))
        #expect(shareText.contains("Input: 1.0K"))
        #expect(shareText.contains("Output: 500"))
        #expect(shareText.contains("2 requests"))
        #expect(shareText.contains("gpt-5.4-mini"))
        #expect(shareText.contains("nemotron-3-nano-4b"))
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

    @Test func redactsStandaloneProviderTokensFromChatText() {
        let providerToken = "msy_exampleTokenValue123456789"
        let cloudToken = "sk-exampleCloudTokenValue123456789"
        let raw = "Use \(providerToken) for assets and \(cloudToken) for the model."

        let redacted = SecretRedactor.redactConfigText(raw)

        #expect(!redacted.contains(providerToken))
        #expect(!redacted.contains(cloudToken))
        #expect(redacted.components(separatedBy: "<redacted>").count == 3)
    }

    @MainActor
    @Test func chatMessagesNeverPersistStandaloneProviderTokens() {
        let token = "msy_exampleTokenValue123456789"

        let message = InstallerViewModel.ChatMessage(role: "user", text: "Use \(token) for this task")

        #expect(!message.text.contains(token))
        #expect(message.text.contains("<redacted>"))
    }

    @Test func computesSHA256ForDownloadedInstaller() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("localclaw-sha-test-\(UUID().uuidString)")
        try "LocalClaw".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let hash = try InstallerViewModel.sha256Hex(for: url)

        #expect(hash == "a1c2aaf18a271d28ac8433e25331c5ae53b09ff48b1db8b960c65e243545aea0")
    }

    @Test func installerDMGSizeHasABoundedSafetyEnvelope() {
        #expect(!InstallerViewModel.installerDMGSizeIsAllowed(0))
        #expect(InstallerViewModel.installerDMGSizeIsAllowed(InstallerViewModel.maxInstallerDMGBytes))
        #expect(!InstallerViewModel.installerDMGSizeIsAllowed(InstallerViewModel.maxInstallerDMGBytes + 1))
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
        #expect(InstallerViewModel.agentThinkingLevel(for: .local) == "off")
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .fast, useDeveloperSession: true) == 180)
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .cloud, useDeveloperSession: true) == 840)
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .deep, useDeveloperSession: true) == 840)
        #expect(InstallerViewModel.goalAgentTimeoutSeconds == 840)
        #expect(InstallerViewModel.wallClockTimeoutSeconds(forAgentTimeout: 840) == 900)
    }

    @Test func largePromptsUseMessageFileTransportWithoutCommandArgumentCopies() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("localclaw-large-prompt-\(UUID().uuidString).txt")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let largeBody = String(repeating: "large prompt content ", count: 12_000)

        try InstallerViewModel.writePromptParts(["context", largeBody], toPath: path)
        let saved = try String(contentsOfFile: path, encoding: .utf8)
        let arguments = InstallerViewModel.openClawAgentArguments(
            sessionID: "large-prompt-session",
            messageFilePath: path,
            model: "openrouter/z-ai/glm-5.2",
            thinking: "medium",
            agentTimeout: 840
        )

        #expect(saved == "context\n\n\(largeBody)")
        #expect(arguments.contains("--message-file"))
        #expect(arguments.contains(path))
        #expect(!arguments.contains("-m"))
        #expect(!arguments.contains(largeBody))
    }

    @Test func largePromptPreviewsStayBounded() {
        let prompt = String(repeating: "abcdefghij", count: 2_000)
        let preview = PromptTextPolicy.compactPreview(prompt, limit: 120)

        #expect(PromptTextPolicy.isLarge(prompt))
        #expect(preview.count == 120)
        #expect(!PromptTextPolicy.isLarge("short prompt"))
        #expect(PromptTextPolicy.hasContent(prompt))
        #expect(!PromptTextPolicy.hasContent("  \n\t"))
    }

    @Test func localModelsAlwaysDisableUnsupportedThinkingLevels() {
        #expect(InstallerViewModel.agentThinkingLevel(
            for: "lmstudio/nvidia/nemotron-3-nano-4b",
            inferenceMode: .local,
            responseMode: .local,
            isSimpleDeveloperEdit: false
        ) == "off")
        #expect(InstallerViewModel.agentThinkingLevel(
            for: "lmstudio/nvidia/nemotron-3-nano-4b",
            inferenceMode: .cloud,
            responseMode: .cloud,
            isSimpleDeveloperEdit: true
        ) == "off")
        #expect(InstallerViewModel.agentThinkingLevel(
            for: "openrouter/openai/gpt-5.4-mini",
            inferenceMode: .cloud,
            responseMode: .cloud,
            isSimpleDeveloperEdit: true
        ) == "low")
        #expect(InstallerViewModel.isUnsupportedThinkingLevelError("Thinking level medium is not supported for lmstudio/test. Use one of: off."))
    }

    @Test func localModelConfigGetsACompatibleToolPolicyWithoutChangingCloudPolicies() {
        let original: [String: Any] = [
            "tools": [
                "byProvider": [
                    "openrouter": ["profile": "coding"],
                    "lmstudio/nvidia/nemotron-3-nano-4b": [
                        "profile": "full",
                        "alsoAllow": ["cron"],
                        "deny": ["exec"],
                    ],
                ],
            ],
        ]
        let updated = InstallerEngine.configByEnsuringLocalModelToolPolicy(
            original,
            modelIdentifier: "lmstudio/nvidia/nemotron-3-nano-4b"
        )
        let tools = updated["tools"] as? [String: Any]
        let byProvider = tools?["byProvider"] as? [String: Any]
        let local = byProvider?["lmstudio/nvidia/nemotron-3-nano-4b"] as? [String: Any]
        let cloud = byProvider?["openrouter"] as? [String: Any]

        #expect(local?["allow"] as? [String] == InstallerEngine.localModelCompatibleTools)
        // This policy is shared by every OpenClaw session using the model. Keep
        // native Goal tools available globally; LocalClaw's scoped Goal prompt
        // and post-turn guards must not disable native OpenClaw workflows.
        #expect(InstallerEngine.localModelCompatibleTools.contains("create_goal"))
        #expect(InstallerEngine.localModelCompatibleTools.contains("update_goal"))
        #expect(InstallerEngine.localModelCompatibleTools.contains("get_goal"))
        #expect(local?["profile"] == nil)
        #expect(local?["alsoAllow"] == nil)
        #expect(local?["deny"] as? [String] == ["exec"])
        #expect(cloud?["profile"] as? String == "coding")
    }

    @Test func semanticOpenClawTimeoutIsNotTreatedAsSuccess() {
        let raw = """
        {
          "status": "ok",
          "summary": "LLM request failed.",
          "result": {
            "payloads": [{"text": "LLM request failed."}],
            "stopReason": "aborted",
            "errorMessage": "Request was aborted"
          }
        }
        """

        let normalized = InstallerViewModel.normalizedAgentResult((0, raw))

        #expect(InstallerViewModel.agentResponseIndicatesFailure(exitCode: 0, raw: raw))
        #expect(normalized.0 == 124)
        #expect(InstallerViewModel.friendlyChatDiagnostic(from: raw)?.contains("model is still selected") == true)
    }

    @Test func successfulOpenClawReplyRemainsSuccessful() {
        let raw = #"{"status":"ok","result":{"payloads":[{"text":"Build completed."}]}}"#

        let normalized = InstallerViewModel.normalizedAgentResult((0, raw))

        #expect(!InstallerViewModel.agentResponseIndicatesFailure(exitCode: 0, raw: raw))
        #expect(normalized.0 == 0)
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

    @MainActor
    @Test func chatMemorySavedInsideProjectStaysInProjectMemory() {
        let vm = InstallerViewModel()
        let project = InstallerViewModel.ChatProject.fresh(index: 1)
        var session = InstallerViewModel.ChatSession.fresh(title: "Project chat")
        session.projectID = project.id
        vm.chatProjects = [project]
        vm.chatSessions = [session]
        vm.selectedChatSessionID = session.id

        vm.saveChatMessageAsNote(InstallerViewModel.ChatMessage(role: "assistant", text: "Use the red API token migration plan."))

        #expect(vm.chatSavedNotes.isEmpty)
        #expect(vm.chatProjectMemories[project.id]?.contains("Use the red API token migration plan.") == true)
        #expect(vm.chatMemoryPreview.contains { $0.contains("red API token") })
    }

    @MainActor
    @Test func creatingAGoalCreatesItsOwnNamedDiscussion() {
        let vm = InstallerViewModel()
        vm.chatSessions = []
        vm.inferenceMode = .local

        let sessionID = vm.createGoalDiscussion(projectName: "  Coastal Speed Level  ")
        let session = vm.normalChatSessions.first { $0.id == sessionID }

        #expect(vm.selectedChatSessionID == sessionID)
        #expect(session?.title == "Coastal Speed Level")
        #expect(session?.subtitle == "Goal · Local LLM")
        #expect(session?.messages.first?.role == "assistant")
    }

    @MainActor
    @Test func projectMemoryIsIsolatedBetweenProjects() {
        let vm = InstallerViewModel()
        let projectA = InstallerViewModel.ChatProject.fresh(index: 1)
        let projectB = InstallerViewModel.ChatProject.fresh(index: 2)
        var sessionA = InstallerViewModel.ChatSession.fresh(title: "A")
        var sessionB = InstallerViewModel.ChatSession.fresh(title: "B")
        sessionA.projectID = projectA.id
        sessionB.projectID = projectB.id
        vm.chatProjects = [projectA, projectB]
        vm.chatSessions = [sessionA, sessionB]

        vm.selectedChatSessionID = sessionA.id
        vm.saveChatMessageAsNote(InstallerViewModel.ChatMessage(role: "assistant", text: "Project A only remembers bananas."))

        vm.selectedChatSessionID = sessionB.id
        #expect(!vm.chatMemoryPreview.contains { $0.contains("bananas") })
        #expect(vm.chatProjectMemories[projectB.id] == nil || vm.chatProjectMemories[projectB.id]?.isEmpty == true)
    }

    @MainActor
    @Test func projectBriefAndPinnedMessagesAreIncludedInContext() {
        let vm = InstallerViewModel()
        var project = InstallerViewModel.ChatProject.fresh(index: 1)
        project.brief = "Ship the activation fix without breaking existing customers."
        var session = InstallerViewModel.ChatSession.fresh(title: "Release plan")
        session.projectID = project.id
        session.messages.append(InstallerViewModel.ChatMessage(role: "user", text: "Keep update safety visible.", pinned: true))
        vm.chatProjects = [project]
        vm.chatSessions = [session]
        vm.selectedChatSessionID = session.id

        let context = vm.chatProjectContext(for: session.id)

        #expect(context.contains("Project brief: Ship the activation fix"))
        #expect(context.contains("Pinned project messages:"))
        #expect(context.contains("Keep update safety visible"))
        #expect(vm.chatMemoryPreview.contains { $0.contains("Pinned") && $0.contains("Keep update safety") })
    }

    @MainActor
    @Test func summarizeCurrentChatSavesProjectMemoryNote() {
        let vm = InstallerViewModel()
        let project = InstallerViewModel.ChatProject.fresh(index: 1)
        var session = InstallerViewModel.ChatSession.fresh(title: "Support issue")
        session.projectID = project.id
        session.messages.append(InstallerViewModel.ChatMessage(role: "user", text: "Client cannot update from 1.0.92."))
        session.messages.append(InstallerViewModel.ChatMessage(role: "assistant", text: "Check the installer manifest and DMG URL."))
        vm.chatProjects = [project]
        vm.chatSessions = [session]
        vm.selectedChatSessionID = session.id

        vm.summarizeCurrentChatIntoProjectMemory()

        #expect(vm.chatProjectMemories[project.id]?.contains { $0.contains("Client cannot update") } == true)
    }

    @MainActor
    @Test func deletingProjectKeepsChatsUnfiledAndRemovesProjectMemory() {
        let vm = InstallerViewModel()
        let project = InstallerViewModel.ChatProject.fresh(index: 1)
        var session = InstallerViewModel.ChatSession.fresh(title: "Customer")
        session.projectID = project.id
        vm.chatProjects = [project]
        vm.chatSessions = [session]
        vm.chatProjectMemories[project.id] = ["Important note"]

        vm.beginDeletingChatProject(project)
        vm.deletePendingChatProject()

        #expect(vm.chatProjects.isEmpty)
        #expect(vm.chatSessions.first?.projectID == nil)
        #expect(vm.chatProjectMemories[project.id] == nil)
    }

    @Test func developerGitStatusParsesGitHubRemoteAndChanges() {
        let output = """
        __BRANCH__main
        __REMOTE__git@github.com:CyrilDieumegard/LocalClaw.git
        __AHEAD_BEHIND__2 1
        __LAST__abc123 Add feature
        __CHANGE__ M Sources/App.swift
        __CHANGE__?? README.md
        """

        let status = InstallerViewModel.parseDeveloperGitStatus(output: output)

        #expect(status.isRepository)
        #expect(status.branch == "main")
        #expect(status.repoSlug == "CyrilDieumegard/LocalClaw")
        #expect(status.behind == 2)
        #expect(status.ahead == 1)
        #expect(status.changedFiles == ["M Sources/App.swift", "?? README.md"])
    }

    @Test func developerGitStatusDetectsMissingRepository() {
        let status = InstallerViewModel.parseDeveloperGitStatus(output: "__LOCALCLAW_NO_REPO__")

        #expect(!status.isRepository)
        #expect(status.message.contains("No Git repository"))
    }

    @Test func developerGitStatusIgnoresParentWorkspaceRepository() {
        let status = InstallerViewModel.parseDeveloperGitStatus(
            output: "__LOCALCLAW_PARENT_REPO__/Users/test/.openclaw/workspace"
        )

        #expect(!status.isRepository)
        #expect(status.message.contains("parent workspace repository"))
    }

    @MainActor
    @Test func developerProjectRenameStyleAndDeleteOnlyAffectList() {
        let vm = InstallerViewModel()
        let project = InstallerViewModel.DeveloperProject(name: "Demo", path: "/tmp/demo")
        let duplicate = InstallerViewModel.DeveloperProject(name: "Demo old", path: "/tmp/demo")
        vm.developerProjects = [project, duplicate]
        vm.selectedDeveloperProjectID = project.id

        vm.beginEditingDeveloperProject(project)
        vm.editingDeveloperProjectName = "Demo renamed"
        vm.commitEditingDeveloperProject()
        vm.updateDeveloperProjectStyle(project.id, icon: "hammer", colorName: "blue")

        #expect(vm.developerProjects.first?.name == "Demo renamed")
        #expect(vm.developerProjects.first?.icon == "hammer")
        #expect(vm.developerProjects.first?.colorName == "blue")

        vm.beginDeletingDeveloperProject(vm.developerProjects[0])
        vm.deletePendingDeveloperProject()

        #expect(vm.developerProjects.isEmpty)
        #expect(vm.selectedDeveloperProjectID.isEmpty)
    }

    @Test func developerProjectsDeduplicateByPath() {
        let first = InstallerViewModel.DeveloperProject(name: "First", path: "/tmp/app", lastOpenedAt: Date(timeIntervalSince1970: 10))
        let latest = InstallerViewModel.DeveloperProject(name: "Latest", path: "/tmp/app", lastOpenedAt: Date(timeIntervalSince1970: 20))

        let projects = InstallerViewModel.deduplicatedDeveloperProjects([first, latest])

        #expect(projects.count == 1)
        #expect(projects.first?.name == "Latest")
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

        let availableIDs = Set(vm.availableChatModels.map(\.id))
        #expect(availableIDs.allSatisfy { $0.hasPrefix("lmstudio/") })
        #expect(availableIDs.contains("lmstudio/google/gemma-4-e2b"))
        #expect(availableIDs.contains("lmstudio/nvidia/nemotron-3-nano-4b"))
        #expect(availableIDs.contains(vm.selectedChatModel))
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
    @Test func cloudModelSelectionSurvivesCatalogRefreshGaps() {
        let vm = InstallerViewModel()
        let selected = "openrouter/moonshotai/kimi-k3"
        vm.inferenceMode = .cloud
        vm.selectedCloudAuthMode = .api
        vm.selectedChatResponseMode = .cloud
        vm.openRouterModelsLive = [
            InstallerViewModel.OpenRouterModel(id: "openrouter/openai/gpt-5.4-mini", displayName: "GPT-5.4 Mini")
        ]
        vm.selectedChatModel = selected

        vm.prepareCloudModelSelection()
        vm.ensureSelectedChatModel()

        #expect(vm.selectedChatModel == selected)
        #expect(vm.selectedOpenRouterModel == selected)
        #expect(vm.availableChatModels.map(\.id).contains(selected))
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

    @Test func guidedSetupFreshLocalPlanRequiresLMStudioAndModelDownload() throws {
        let plan = try #require(InstallerViewModel.guidedSetupModelPlan(
            localInference: true,
            selectedLocalModel: "Qwen Local",
            recommendation: "",
            modelQueries: ["Qwen Local": "qwen-local@q4_k_m"],
            localProviderModelIDs: ["Qwen Local": "qwen/qwen-local"],
            cloudModelIdentifier: "openrouter/auto"
        ))

        #expect(plan.requiresLMStudio)
        #expect(plan.modelQuery == "qwen-local@q4_k_m")
        #expect(plan.modelIdentifier == "lmstudio/qwen/qwen-local")
        #expect(InstallerViewModel.guidedSetupLocalRuntimeIsReady(
            plan: plan,
            lmStudioState: .ok,
            modelState: .skip
        ))
        #expect(!InstallerViewModel.guidedSetupLocalRuntimeIsReady(
            plan: plan,
            lmStudioState: .fail,
            modelState: .skip
        ))
        #expect(!InstallerViewModel.guidedSetupLocalRuntimeIsReady(
            plan: plan,
            lmStudioState: .ok,
            modelState: .fail
        ))
        #expect(InstallerViewModel.guidedSetupModelPlan(
            localInference: true,
            selectedLocalModel: "Unknown",
            recommendation: "",
            modelQueries: [:],
            localProviderModelIDs: [:],
            cloudModelIdentifier: "openrouter/auto"
        ) == nil)
    }

    @Test func lmStudioReadinessRequiresSelectedProviderAndAtLeast16KContext() {
        let response = #"{"data":[{"id":"qwen/qwen-local","object":"model"}]}"#

        #expect(InstallerEngine.lmStudioReadinessIsVerified(
            expectedModelID: "qwen/qwen-local",
            loadedIdentifier: "qwen/qwen-local",
            loadedModel: "qwen/qwen-local",
            context: 16_384,
            providerResponse: response
        ))
        #expect(!InstallerEngine.lmStudioReadinessIsVerified(
            expectedModelID: "qwen/qwen-local",
            loadedIdentifier: "qwen/qwen-local",
            loadedModel: "qwen/qwen-local",
            context: 8_192,
            providerResponse: response
        ))
        #expect(!InstallerEngine.lmStudioReadinessIsVerified(
            expectedModelID: "qwen/qwen-local",
            loadedIdentifier: "qwen/qwen-local",
            loadedModel: "qwen/qwen-local",
            context: 32_768,
            providerResponse: #"{"data":[{"id":"other/model"}]}"#
        ))
    }

    @Test func guidedSetupCloudPlanSkipsLocalRuntime() throws {
        let plan = try #require(InstallerViewModel.guidedSetupModelPlan(
            localInference: false,
            selectedLocalModel: "",
            recommendation: "",
            modelQueries: [:],
            localProviderModelIDs: [:],
            cloudModelIdentifier: "openrouter/openai/gpt-5.5"
        ))

        #expect(!plan.requiresLMStudio)
        #expect(plan.modelQuery == nil)
        #expect(plan.modelIdentifier == "openrouter/openai/gpt-5.5")
        #expect(InstallerViewModel.guidedSetupLocalRuntimeIsReady(
            plan: plan,
            lmStudioState: .fail,
            modelState: .fail
        ))
    }

    @MainActor
    @Test func guidedSetupBlockingStepRunsOutsideMainActor() async {
        let vm = InstallerViewModel()
        let result = await vm.runStep(name: "Concurrency probe") {
            StepResult(
                state: Thread.isMainThread ? .fail : .ok,
                message: Thread.isMainThread ? "ran on main thread" : "ran off main thread"
            )
        }

        #expect(result.state == .ok)
    }

    @MainActor
    @Test func staleRemoteCatalogCannotHideTheLatestVerifiedLocalModel() {
        let vm = InstallerViewModel()
        vm.remoteLocalModelCandidates = [
            .init(name: "Older remote model", query: "older/model", providerId: "older/model", family: "older", summary: "Fixture", fileSizeGB: 1, maxContextK: 32, qualityScore: 1, codingScore: 1, reasoningScore: 1, speedScore: 1, toolUseScore: 1, multimodal: false, badges: [])
        ]

        let latest = vm.localModelCatalog.first { $0.providerId == "qwen/qwen3.8-27b" }
        #expect(latest?.badges.contains("Latest") == true)
        #expect(latest?.query == "lmstudio-community/Qwen3.8-27B-GGUF@Q4_K_M")
        #expect(LocalModelCatalogService.isValidModelQuery(latest?.query ?? ""))
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

    @Test func failedKanbanCronSyncRestoresAutomationPayloadAndKeepsPriority() throws {
        let previous = InstallerViewModel.KanbanCard.fresh(
            title: "Original task",
            detail: "Original detail",
            priority: "Normal",
            agentID: "main",
            reviewSchedule: "1d",
            scheduleTimeZoneID: "Europe/Zurich",
            scheduleKind: "every",
            cronEnabled: true,
            deliveryMode: "channel",
            deliveryChannel: "telegram",
            deliveryTo: "old-destination",
            cronJobID: "job-existing"
        )
        var attempted = previous
        attempted.title = "Edited task"
        attempted.detail = "Edited detail"
        attempted.priority = "High"
        attempted.reviewSchedule = "0 9 * * *"
        attempted.scheduleKind = "cron"
        attempted.cronEnabled = false
        attempted.deliveryTo = "new-destination"

        let restored = try #require(InstallerViewModel.kanbanCardRestoringCronFields(
            current: attempted,
            attempted: attempted,
            previous: previous
        ))

        #expect(restored.title == "Original task")
        #expect(restored.detail == "Original detail")
        #expect(restored.agentID == "main")
        #expect(restored.priority == "High")
        #expect(restored.reviewSchedule == "1d")
        #expect(restored.scheduleKind == "every")
        #expect(restored.cronEnabled == true)
        #expect(restored.deliveryTo == "old-destination")
        #expect(restored.cronJobID == "job-existing")

        var newerEdit = attempted
        newerEdit.reviewSchedule = "2h"
        #expect(InstallerViewModel.kanbanCardRestoringCronFields(
            current: newerEdit,
            attempted: attempted,
            previous: previous
        ) == nil)
    }

    @Test func kanbanCronCommandHasABoundedTimeout() {
        let startedAt = Date()
        let result = InstallerViewModel.runKanbanCronCommand(
            "exec /bin/sleep 3",
            timeoutSeconds: 1
        )

        #expect(result.0 == 124)
        #expect(result.1.contains("Cron command timed out after 1s"))
        #expect(Date().timeIntervalSince(startedAt) < 2.5)
    }

    @MainActor
    @Test func cronManualRunGateRejectsConcurrentDuplicatePerJobAndAllowsAfterRelease() async {
        let vm = InstallerViewModel()

        let first = Task { @MainActor in vm.beginCronManualRun("job-a") }
        let second = Task { @MainActor in vm.beginCronManualRun("job-a") }
        let outcomes = [await first.value, await second.value]
        #expect(outcomes.filter { $0 }.count == 1)
        #expect(vm.cronManualRunInFlightJobIDs == Set(["job-a"]))

        #expect(vm.beginCronManualRun("job-b"))
        #expect(vm.cronManualRunInFlightJobIDs == Set(["job-a", "job-b"]))

        vm.finishCronManualRun("job-a")
        #expect(vm.beginCronManualRun("job-a"))
        vm.finishCronManualRun("job-a")
        vm.finishCronManualRun("job-b")
        #expect(vm.cronManualRunInFlightJobIDs.isEmpty)
    }

    @Test func kanbanCronUnknownStateDoesNotRequireBlindMutationRetry() {
        #expect(InstallerViewModel.kanbanCronMutationStateIsUnknown(
            exitCode: 124,
            expectsNewJobID: false,
            confirmedJobID: "job-existing"
        ))
        #expect(InstallerViewModel.kanbanCronMutationStateIsUnknown(
            exitCode: 0,
            expectsNewJobID: true,
            confirmedJobID: nil
        ))
        #expect(!InstallerViewModel.kanbanCronMutationStateIsUnknown(
            exitCode: 0,
            expectsNewJobID: true,
            confirmedJobID: "job-created"
        ))
        #expect(!InstallerViewModel.kanbanCronMutationStateIsUnknown(
            exitCode: 1,
            expectsNewJobID: true,
            confirmedJobID: nil
        ))
    }

    @Test func kanbanCronInventoryRecoversOnlyExactUniqueCardBindings() {
        let inventory = #"""
        {
          "jobs": [
            {"id":"job-a","description":"Managed by LocalClaw card card-a"},
            {"id":"job-b1","declarationKey":"localclaw-kanban-card-b"},
            {"id":"job-b2","description":"Managed by LocalClaw card card-b"},
            {"id":"job-c","description":"Managed by LocalClaw card card-c","declarationKey":"localclaw-kanban-other-card"},
            {"id":"job-d","declaration_key":"localclaw-kanban-card-d"},
            {"id":"job-e","description":"Not managed by LocalClaw card card-e"}
          ],
          "total": 6,
          "hasMore": false
        }
        """#

        let bindings = InstallerViewModel.kanbanCronInventoryBindings(from: inventory)
        #expect(bindings == ["card-a": "job-a", "card-d": "job-d"])
    }

    @Test func extractsCronJobIDFromJSONOutput() {
        #expect(InstallerViewModel.extractCronJobID(from: #"{"id":"job-123"}"#) == "job-123")
        #expect(InstallerViewModel.extractCronJobID(from: #"{"job":{"id":"job-456"}}"#) == "job-456")
        #expect(InstallerViewModel.extractCronJobID(from: #"""
Created job
{"id":"job-789","name":"Tortue"}
"""#) == "job-789")
    }

    @MainActor
    @Test func missingKanbanOneShotCronRequiresReceiptBeforeCompletion() {
        let vm = InstallerViewModel()
        vm.kanbanAutomationSyncEnabled = false
        let runAt = Date(timeIntervalSince1970: 1_770_000_000)
        let card = InstallerViewModel.KanbanCard.fresh(
            title: "Tortue",
            detail: "Parle moi d'une tortue",
            priority: "Urgent",
            agentID: "localagent",
            reviewSchedule: InstallerViewModel.cronAtDateString(runAt, timeZoneID: "Europe/Zurich"),
            scheduleTimeZoneID: "Europe/Zurich",
            scheduleKind: "at",
            cronEnabled: true,
            deliveryMode: "channel",
            deliveryChannel: "telegram",
            deliveryTo: "1636626469",
            cronJobID: "job-finished"
        )
        vm.kanbanColumns = InstallerViewModel.KanbanColumn.defaults.map { column in
            column.id == "review"
                ? InstallerViewModel.KanbanColumn(id: column.id, title: column.title, icon: column.icon, colorName: column.colorName, cards: [card])
                : column
        }

        vm.reconcileKanbanCompletedAutomations(knownCronJobIDs: [], now: runAt.addingTimeInterval(60))

        let reviewCard = vm.kanbanColumns.first { $0.id == "review" }?.cards.first
        #expect(reviewCard?.title == "Tortue")
        #expect(reviewCard?.cronJobID.isEmpty == true)
        #expect(reviewCard?.cronEnabled == false)
        #expect(vm.kanbanColumns.first { $0.id == "done" }?.cards.isEmpty == true)
        #expect(vm.kanbanStatus.contains("execution receipt"))
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
        let packageData = try Data(contentsOf: root.appendingPathComponent("package.json"))
        let packageJSON = try #require(JSONSerialization.jsonObject(with: packageData) as? [String: Any])
        let dependencies = try #require(packageJSON["dependencies"] as? [String: Any])
        let devDependencies = try #require(packageJSON["devDependencies"] as? [String: Any])
        let index = try String(contentsOf: root.appendingPathComponent("index.html"), encoding: .utf8)
        let main = try String(contentsOf: root.appendingPathComponent("src/main.jsx"), encoding: .utf8)

        #expect(package.contains(#""dev" : "vite --host 127.0.0.1""#) || package.contains(#""dev": "vite --host 127.0.0.1""#))
        #expect(package.contains(#""name" : "cyril-s-app""#) || package.contains(#""name": "cyril-s-app""#))
        #expect(dependencies["react"] != nil)
        #expect(dependencies["react-dom"] != nil)
        #expect(dependencies["vite"] == nil)
        #expect(dependencies["@vitejs/plugin-react"] == nil)
        #expect(devDependencies["vite"] != nil)
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

        let packageURL = root.appendingPathComponent("package.json")
        let package = try String(contentsOf: packageURL, encoding: .utf8)
        let packageData = try Data(contentsOf: packageURL)
        let packageJSON = try #require(JSONSerialization.jsonObject(with: packageData) as? [String: Any])
        let dependencies = try #require(packageJSON["dependencies"] as? [String: Any])
        let devDependencies = try #require(packageJSON["devDependencies"] as? [String: Any])
        #expect(package.contains(#""build" : "vite build""#) || package.contains(#""build": "vite build""#))
        #expect(package.contains(#""dev" : "vite --host 127.0.0.1""#) || package.contains(#""dev": "vite --host 127.0.0.1""#))
        #expect(dependencies["react"] as? String == "18")
        #expect(dependencies["react-dom"] == nil)
        #expect(dependencies["@vitejs/plugin-react"] == nil)
        #expect(devDependencies["vite"] as? String == "latest")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("src/main.jsx").path))
    }

    @Test func preservesExistingThreeJSProjectDependencies() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("localclaw-preview-three-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try #"{"name":"iron-descent","scripts":{"dev":"vite"},"dependencies":{"three":"^0.166.1"},"devDependencies":{"vite":"^5.4.21"}}"#
            .write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "<script type=\"module\" src=\"/src/main.js\"></script>"
            .write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        try InstallerViewModel.createDeveloperPreviewScaffold(at: root, appName: "Renamed in LocalClaw")

        let packageData = try Data(contentsOf: root.appendingPathComponent("package.json"))
        let packageJSON = try #require(JSONSerialization.jsonObject(with: packageData) as? [String: Any])
        let dependencies = try #require(packageJSON["dependencies"] as? [String: Any])
        let devDependencies = try #require(packageJSON["devDependencies"] as? [String: Any])
        #expect(packageJSON["name"] as? String == "iron-descent")
        #expect(dependencies.keys.sorted() == ["three"])
        #expect(devDependencies.keys.sorted() == ["vite"])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("src/main.jsx").path))
    }

    @Test func addsMinimalVitePackageToStaticHTMLProject() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("localclaw-preview-static-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "<h1>Existing static app</h1>"
            .write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        try InstallerViewModel.createDeveloperPreviewScaffold(at: root, appName: "Static App")

        let packageData = try Data(contentsOf: root.appendingPathComponent("package.json"))
        let packageJSON = try #require(JSONSerialization.jsonObject(with: packageData) as? [String: Any])
        let dependencies = try #require(packageJSON["dependencies"] as? [String: Any])
        let devDependencies = try #require(packageJSON["devDependencies"] as? [String: Any])
        #expect(dependencies.isEmpty)
        #expect(devDependencies["vite"] != nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("src/main.jsx").path))
    }

    @Test func developerActivityTracksToolStartAndCompletion() throws {
        let projectPath = "/Users/test/project"
        let call: [String: Any] = [
            "type": "message",
            "message": [
                "role": "assistant",
                "timestamp": 1_784_473_699_681 as Double,
                "content": [[
                    "type": "toolCall",
                    "id": "read_1",
                    "name": "read",
                    "arguments": ["path": "/Users/test/project/src/main.js"]
                ]]
            ]
        ]
        let callData = try JSONSerialization.data(withJSONObject: call)
        let callLine = try #require(String(data: callData, encoding: .utf8))
        var events = DeveloperActivityParser.applying(jsonLine: callLine, to: [], projectPath: projectPath)

        #expect(events.count == 1)
        #expect(events[0].title == "Reading src/main.js")
        #expect(events[0].state == .running)

        let result: [String: Any] = [
            "type": "message",
            "message": [
                "role": "toolResult",
                "toolCallId": "read_1",
                "toolName": "read",
                "isError": false,
                "content": [["type": "text", "text": "hidden"]]
            ]
        ]
        let resultData = try JSONSerialization.data(withJSONObject: result)
        let resultLine = try #require(String(data: resultData, encoding: .utf8))
        events = DeveloperActivityParser.applying(jsonLine: resultLine, to: events, projectPath: projectPath)

        #expect(events[0].state == .succeeded)
    }

    @Test func developerActivitySummarizesCommandsWithoutExposingCommandText() {
        let summary = DeveloperActivityParser.toolSummary(
            name: "exec",
            arguments: ["command": "TOKEN=private-value npm run build"],
            projectPath: "/tmp/project"
        )

        #expect(summary.title == "Building the project")
        #expect(!summary.title.contains("private-value"))
        #expect(!summary.detail.contains("private-value"))
    }

    @Test func developerActivityHumanizesUnknownToolNames() {
        let summary = DeveloperActivityParser.toolSummary(
            name: "custom_project_tool",
            arguments: [:],
            projectPath: "/tmp/project"
        )

        #expect(summary.title == "Using Custom Project Tool")
    }

    @Test @MainActor func developerPreviewAcceptsKeyboardFocus() {
        let preview = InteractiveDeveloperWebView(frame: .zero, configuration: .init())
        #expect(preview.acceptsFirstResponder)
    }

    @Test func goalAdvisorRejectsWeakTinyLocalModels() {
        let readiness = GoalCapabilityAdvisor.local(
            openClawInstalled: true,
            modelName: "Qwen 3.5 2B",
            isLoaded: true,
            fit: .great,
            toolUseScore: 3.5,
            contextTokens: 32_768,
            recommendedModel: "Qwen 3.5 4B"
        )

        #expect(readiness.level == .blocked)
        #expect(!readiness.canStart)
        #expect(readiness.recommendation == "Qwen 3.5 4B")
    }

    @Test func goalAdvisorAcceptsCapableLocalModelsWithHeadroom() {
        let readiness = GoalCapabilityAdvisor.local(
            openClawInstalled: true,
            modelName: "Nemotron 3 Nano 4B",
            isLoaded: true,
            fit: .good,
            toolUseScore: 4.2,
            contextTokens: 32_768,
            recommendedModel: nil
        )

        #expect(readiness.level == .ready)
        #expect(readiness.canStart)
        #expect(readiness.detail.contains("Nemotron 3 Nano 4B"))
    }

    @Test func goalAdvisorRequiresProviderAuthentication() {
        let readiness = GoalCapabilityAdvisor.cloud(
            openClawInstalled: true,
            authReady: false,
            modelID: "openrouter/openai/gpt-5.4-mini",
            modeName: "Cloud LLM"
        )

        #expect(readiness.level == .blocked)
        #expect(!readiness.canStart)
        #expect(readiness.title == "Cloud LLM needs authentication")
    }

    @Test func goalAdvisorNamesTheSelectedCloudModel() {
        let readiness = GoalCapabilityAdvisor.cloud(
            openClawInstalled: true,
            authReady: true,
            modelID: "openrouter/moonshotai/kimi-k3",
            modeName: "Cloud LLM"
        )

        #expect(readiness.level == .ready)
        #expect(readiness.canStart)
        #expect(readiness.detail.contains("openrouter/moonshotai/kimi-k3"))
    }

    @Test @MainActor func goalSessionRemainsStableAcrossWorkTurns() {
        let chatID = "localclaw-ui-chat-ABC-123"
        let first = GoalCenterModel.runtimeSessionID(for: chatID)
        let second = GoalCenterModel.runtimeSessionID(for: chatID)

        #expect(first == second)
        #expect(first.hasSuffix("-goal"))
        #expect(GoalCenterModel.openClawSessionKey(for: chatID) == "agent:main:explicit:\(first)")

        let firstWorkTurn = GoalCenterModel.workRuntimeSessionID(chatSessionID: chatID, stepID: "step-1", turn: 0)
        let retryWorkTurn = GoalCenterModel.workRuntimeSessionID(chatSessionID: chatID, stepID: "step-1", turn: 1)
        #expect(firstWorkTurn == first)
        #expect(retryWorkTurn == first)
    }

    @Test @MainActor func continuousGoalRunsOnlyWhileActiveAndHealthy() {
        #expect(GoalCenterModel.shouldContinueAutomatically(
            enabled: true,
            status: .active,
            latestMessageRole: "assistant"
        ))
        #expect(!GoalCenterModel.shouldContinueAutomatically(
            enabled: true,
            status: .active,
            latestMessageRole: "error"
        ))
        #expect(!GoalCenterModel.shouldContinueAutomatically(
            enabled: true,
            status: .complete,
            latestMessageRole: "assistant"
        ))
        #expect(!GoalCenterModel.shouldContinueAutomatically(
            enabled: true,
            status: .blocked,
            latestMessageRole: nil
        ))
        #expect(!GoalCenterModel.shouldContinueAutomatically(
            enabled: true,
            status: .paused,
            latestMessageRole: nil
        ))
        #expect(!GoalCenterModel.shouldContinueAutomatically(
            enabled: false,
            status: .active,
            latestMessageRole: "assistant"
        ))
    }

    @Test func goalModelIdentityMatchesLMStudioQuantVariants() {
        #expect(GoalModelIdentity.matches("lmstudio/nvidia/nemotron-3-nano-4b@q4_k_m", "nvidia/nemotron-3-nano-4b"))
        #expect(!GoalModelIdentity.matches("google/gemma-4-e2b", "qwen/qwen3.5-4b"))
    }

    @Test func goalWorkPromptAlwaysCarriesTheDurableObjective() {
        var plan = GoalExecutionPlan(
            sessionID: "goal-test",
            objective: "Audit the release pipeline",
            output: GoalOutputContract(
                type: "Technical report",
                format: "Markdown",
                location: "/tmp/release-audit.md",
                launch: "Open the report in LocalClaw",
                completionCriteria: ["Every release stage has evidence"]
            ),
            steps: [
                GoalPlanStep(
                    id: "step-1",
                    title: "Inspect release configuration",
                    outcome: "Document the current release stages",
                    completionCriteria: ["Build and publication paths are listed"],
                    status: .pending,
                    summary: "",
                    evidence: [],
                    attempts: 0,
                    noProgressTurns: 0
                ),
                GoalPlanStep(
                    id: "step-2",
                    title: "Write audit",
                    outcome: "Create the final report",
                    completionCriteria: ["The report exists at the approved location"],
                    status: .pending,
                    summary: "",
                    evidence: [],
                    attempts: 0,
                    noProgressTurns: 0
                )
            ],
            approvedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            version: 1,
            lastCheckpointMessageID: nil
        )
        #expect(plan.isReadyForApproval)
        plan.prepareForApproval()
        let prompt = GoalWorkPrompt.make(plan: plan, starting: false)

        #expect(prompt.contains("Objective:\nAudit the release pipeline"))
        #expect(prompt.contains("Format or technology: Markdown"))
        #expect(prompt.contains("Current step:\nInspect release configuration"))
        #expect(prompt.contains("<localclaw_progress>"))
        #expect(prompt.contains("Do not call create_goal, update_goal"))
        #expect(prompt.contains("Replace it with the strongest deterministic automated smoke test"))
        #expect(prompt.contains("Never invent a tool result"))
    }

    @Test func nativeGoalCannotCompleteOrBlockAheadOfLocalClawPlan() {
        let now = Date()
        var plan = GoalExecutionPlan(
            sessionID: "goal-native-status",
            nativeGoalID: "native-goal",
            nativeAgentID: "main",
            nativeStatePath: "/tmp/state",
            nativeWorkspacePath: "/tmp/workspace",
            objective: "Ship a verified artifact",
            output: GoalOutputContract(type: "Report", format: "Markdown", location: "/tmp/report.md", launch: "Open report", completionCriteria: ["Verified"]),
            steps: [GoalPlanStep(id: "step-1", title: "Verify", outcome: "Proof", completionCriteria: ["Proof exists"], status: .inProgress, summary: "", evidence: [], attempts: 0, noProgressTurns: 0)],
            approvedAt: now, createdAt: now, updatedAt: now, version: 1, lastCheckpointMessageID: nil
        )
        func snapshot(_ status: GoalLifecycleStatus) -> OpenClawGoalSnapshot {
            .init(id: "native-goal", objective: plan.objective, status: status, createdAt: 1, updatedAt: 2, tokensUsed: 0, tokenBudget: nil, continuationTurns: 0, lastStatusNote: nil)
        }

        #expect(GoalCenterModel.nativeGoalStatusIsCompatible(plan: plan, snapshot: snapshot(.active)))
        #expect(!GoalCenterModel.nativeGoalStatusIsCompatible(plan: plan, snapshot: snapshot(.complete)))
        #expect(!GoalCenterModel.nativeGoalStatusIsCompatible(plan: plan, snapshot: snapshot(.blocked)))

        plan.steps[0].status = .blocked
        #expect(GoalCenterModel.nativeGoalStatusIsCompatible(plan: plan, snapshot: snapshot(.blocked)))
        plan.steps[0].status = .complete
        #expect(GoalCenterModel.nativeGoalStatusIsCompatible(plan: plan, snapshot: snapshot(.complete)))
    }

    @Test func goalBlocksOnlyAfterTheSameConditionRecursThreeTimes() {
        var plan = GoalExecutionPlan(
            sessionID: "goal-blocker",
            objective: "Ship a verified artifact",
            output: GoalOutputContract(type: "Report", format: "Markdown", location: "/tmp/report.md", launch: "Open report", completionCriteria: ["Verified"]),
            steps: [
                GoalPlanStep(id: "step-1", title: "Verify", outcome: "Proof", completionCriteria: ["Proof exists"], status: .inProgress, summary: "", evidence: [], attempts: 0, noProgressTurns: 0)
            ],
            approvedAt: Date(), createdAt: Date(), updatedAt: Date(), version: 1, lastCheckpointMessageID: nil
        )

        plan.apply(.init(status: .blocked, summary: "Credentials missing", evidence: [], blockerKey: "credentials-missing"))
        #expect(plan.currentStep?.status == .inProgress)
        plan.apply(.init(status: .blocked, summary: "Different blocker", evidence: [], blockerKey: "different-blocker"))
        #expect(plan.currentStep?.status == .inProgress)
        plan.apply(.init(status: .blocked, summary: "Different blocker", evidence: [], blockerKey: "different-blocker"))
        #expect(plan.currentStep?.status == .inProgress)
        plan.apply(.init(status: .blocked, summary: "Different blocker", evidence: [], blockerKey: "different-blocker"))
        #expect(plan.currentStep?.status == .blocked)
    }

    @Test func goalNeverClaimsADurableBlockerFromChangingProseAlone() {
        var plan = GoalExecutionPlan(
            sessionID: "goal-unkeyed-blocker",
            objective: "Ship a verified artifact",
            output: GoalOutputContract(type: "Report", format: "Markdown", location: "/tmp/report.md", launch: "Open report", completionCriteria: ["Verified"]),
            steps: [
                GoalPlanStep(id: "step-1", title: "Verify", outcome: "Proof", completionCriteria: ["Proof exists"], status: .inProgress, summary: "", evidence: [], attempts: 0, noProgressTurns: 0)
            ],
            approvedAt: Date(), createdAt: Date(), updatedAt: Date(), version: 1, lastCheckpointMessageID: nil
        )

        for turn in 1...4 {
            plan.apply(.init(status: .blocked, summary: "Unidentified blocker \(turn)", evidence: []))
        }
        #expect(plan.currentStep?.status == .inProgress)
        #expect(plan.currentStep?.noProgressTurns == 4)
    }

    @Test func goalNeverCompletesAPlanStepWithoutConcreteEvidence() {
        var plan = GoalExecutionPlan(
            sessionID: "goal-evidence",
            objective: "Ship a verified artifact",
            output: GoalOutputContract(type: "Report", format: "Markdown", location: "/tmp/report.md", launch: "Open report", completionCriteria: ["Verified"]),
            steps: [
                GoalPlanStep(id: "step-1", title: "Inspect", outcome: "Evidence", completionCriteria: ["Inspection recorded"], status: .inProgress, summary: "", evidence: [], attempts: 0, noProgressTurns: 0),
                GoalPlanStep(id: "step-2", title: "Deliver", outcome: "Report", completionCriteria: ["Report exists"], status: .pending, summary: "", evidence: [], attempts: 0, noProgressTurns: 0),
            ],
            approvedAt: Date(), createdAt: Date(), updatedAt: Date(), version: 1, lastCheckpointMessageID: nil
        )

        plan.apply(.init(status: .complete, summary: "Done", evidence: []))

        #expect(plan.currentStep?.id == "step-1")
        #expect(plan.currentStep?.status == .inProgress)
        #expect(plan.currentStep?.summary.contains("did not include concrete evidence") == true)
    }

    @Test func goalResumeResetsOnlyTheCurrentSafetyWindow() throws {
        var plan = GoalExecutionPlan(
            sessionID: "goal-resume",
            objective: "Finish the game",
            output: GoalOutputContract(
                type: "Browser game",
                format: "HTML",
                location: "/tmp/game",
                launch: "Open index.html",
                completionCriteria: ["Automated smoke test passes"]
            ),
            steps: [
                GoalPlanStep(
                    id: "step-1",
                    title: "Verify output",
                    outcome: "A tested game",
                    completionCriteria: ["Smoke test passes"],
                    status: .inProgress,
                    summary: "Waiting for a checkpoint",
                    evidence: [],
                    attempts: 12,
                    noProgressTurns: 3
                )
            ],
            approvedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            version: 1,
            lastCheckpointMessageID: nil
        )

        plan.resetCurrentStepSafetyWindow()

        let step = try #require(plan.currentStep)
        #expect(step.attempts == 12)
        #expect(step.noProgressTurns == 0)
    }

    @Test func goalPlanningPromptRejectsManualBlockingChecks() {
        let prompt = GoalPlanPrompt.make(objective: "Build a game", outputHint: "Playable browser game")

        #expect(prompt.contains("Use 2 to 8 meaningful steps"))
        #expect(prompt.contains("Never make manual user input"))
        #expect(prompt.contains("deterministic automated smoke tests"))
        #expect(prompt.contains("concrete absolute destination"))
        #expect(prompt.contains("use exactly two steps"))
    }

    @Test func localGoalSessionMaintenanceKeepsContextAndUsageBounded() {
        let key = "agent:main:explicit:localclaw-ui-chat-ABC-goal"
        let command = GoalSessionMaintenance.compactCommand(sessionKey: key, maxLines: 12)

        #expect(GoalSessionMaintenance.isLocalModel("lmstudio/qwen3.5-9b"))
        #expect(!GoalSessionMaintenance.isLocalModel("openrouter/openai/gpt-5.4-mini"))
        #expect(command.contains("sessions compact 'agent:main:explicit:localclaw-ui-chat-ABC-goal'"))
        #expect(command.contains("--max-lines 12"))
        #expect(GoalSessionMaintenance.isTimeoutMessage("OpenClaw timed out before the selected model finished"))
        #expect(GoalSessionMaintenance.isContextOverflowMessage("Context overflow: prompt too large for the model"))
        #expect(GoalSessionMaintenance.exceededRunBudget(startTokens: 784_119, currentTokens: 844_119))
        #expect(!GoalSessionMaintenance.exceededRunBudget(startTokens: 784_119, currentTokens: 800_000))
    }

    @MainActor
    @Test func goalPlanningUsesAFreshRuntimeSession() {
        let first = GoalCenterModel.planningRuntimeSessionID(for: "chat-1", nonce: "AAAA")
        let second = GoalCenterModel.planningRuntimeSessionID(for: "chat-1", nonce: "BBBB")

        #expect(first != second)
        #expect(first.contains("chat-1-goal-plan-AAAA"))
        #expect(GoalCenterModel.runtimeSessionID(for: "chat-1") == "chat-1-goal")
    }

    @Test func goalApprovalExplainsWhenAPlanHasTooFewSteps() throws {
        var plan = try #require(GoalPlanParser.parse(
            """
            {"output":{"type":"HTML game","format":"HTML","location":"/tmp/pong.html","launch":"Open file","completionCriteria":["Game is playable"]},"steps":[{"title":"Build Pong","outcome":"Playable game","completionCriteria":["File exists"]}]}
            """,
            sessionID: "pong-plan",
            objective: "Build Pong"
        ))

        #expect(!plan.isReadyForApproval)
        #expect(plan.approvalIssue == "Add at least two concrete plan steps before approval.")

        plan.steps.append(GoalPlanStep(
            id: "step-2",
            title: "Verify Pong",
            outcome: "A tested game",
            completionCriteria: ["Output exists on disk"],
            status: .pending,
            summary: "",
            evidence: [],
            attempts: 0,
            noProgressTurns: 0
        ))

        #expect(plan.isReadyForApproval)
        #expect(plan.approvalIssue == nil)
    }

    @Test func goalCompletionRequiresTheRealOutputOnDisk() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("localclaw-goal-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("game.html")

        var plan = GoalExecutionPlan(
            sessionID: "goal-output-check",
            objective: "Build a game",
            output: GoalOutputContract(
                type: "HTML game",
                format: "HTML",
                location: output.path,
                launch: "Open game.html",
                completionCriteria: ["The game file exists"]
            ),
            steps: [
                GoalPlanStep(
                    id: "step-1",
                    title: "Build and verify",
                    outcome: "A playable game",
                    completionCriteria: ["The file exists on disk"],
                    status: .inProgress,
                    summary: "",
                    evidence: [],
                    attempts: 0,
                    noProgressTurns: 0
                )
            ],
            approvedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            version: 1,
            lastCheckpointMessageID: nil
        )

        plan.apply(GoalStepProgressReport(status: .complete, summary: "PASS", evidence: ["file exists"]))
        #expect(!plan.isComplete)
        #expect(plan.currentStep?.summary.contains("rejected the completion claim") == true)
        #expect(plan.currentStep?.noProgressTurns == 1)

        try "<!doctype html><title>Game</title>".write(to: output, atomically: true, encoding: .utf8)
        plan.apply(GoalStepProgressReport(status: .complete, summary: "Created and tested", evidence: [output.path]))
        #expect(plan.isComplete)
        #expect(GoalOutputVerifier.verify(plan.output).isSatisfied)

        try FileManager.default.removeItem(at: output)
        let recovery = plan.reopenFinalStepWhenOutputIsMissing()
        #expect(recovery?.state == .missing)
        #expect(!plan.isComplete)
        #expect(plan.currentStep?.status == .inProgress)
    }

    @Test func localGoalDirectArtifactAcceptsOnlyApprovedWorkspaceFiles() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("localclaw-goal-home-\(UUID().uuidString)", isDirectory: true)
        let approvedPath = home.appendingPathComponent(".openclaw/workspace/games/sudoku.html").path
        let outsidePath = home.appendingPathComponent("Desktop/sudoku.html").path

        func plan(path: String) -> GoalExecutionPlan {
            GoalExecutionPlan(
                sessionID: "direct-local-goal",
                objective: "Build Sudoku",
                output: GoalOutputContract(
                    type: "Browser game",
                    format: "HTML",
                    location: path,
                    launch: "Open the file",
                    completionCriteria: ["The game is playable"]
                ),
                steps: [
                    GoalPlanStep(id: "1", title: "Create", outcome: "Complete file", completionCriteria: ["File exists"], status: .inProgress, summary: "", evidence: [], attempts: 0, noProgressTurns: 0),
                    GoalPlanStep(id: "2", title: "Verify", outcome: "Verified file", completionCriteria: ["File is not empty"], status: .pending, summary: "", evidence: [], attempts: 0, noProgressTurns: 0),
                ],
                approvedAt: Date(),
                createdAt: Date(),
                updatedAt: Date(),
                version: 1,
                lastCheckpointMessageID: nil
            )
        }

        #expect(LocalGoalArtifactSupport.destination(for: plan(path: approvedPath), homeDirectory: home.path)?.path == approvedPath)
        #expect(LocalGoalArtifactSupport.destination(for: plan(path: outsidePath), homeDirectory: home.path) == nil)

        var threeStepPlan = plan(path: approvedPath)
        threeStepPlan.steps.insert(
            GoalPlanStep(id: "middle", title: "Polish", outcome: "Polished file", completionCriteria: ["File remains complete"], status: .pending, summary: "", evidence: [], attempts: 0, noProgressTurns: 0),
            at: 1
        )
        #expect(LocalGoalArtifactSupport.destination(for: threeStepPlan, homeDirectory: home.path)?.path == approvedPath)
    }

    @Test func localGoalDirectArtifactBudgetsOutputInsideTheLoadedContext() throws {
        let budget = try LocalGoalArtifactSupport.outputTokenBudget(
            prompt: String(repeating: "x", count: 4_000),
            contextTokens: 16_000
        )
        #expect(budget <= 6_400)
        #expect(budget >= 1_024)

        let smallContextBudget = try LocalGoalArtifactSupport.outputTokenBudget(
            prompt: String(repeating: "x", count: 2_000),
            contextTokens: 8_192
        )
        #expect(smallContextBudget <= 3_276)
        #expect(smallContextBudget >= 1_024)

        var rejectedOversizedPrompt = false
        do {
            _ = try LocalGoalArtifactSupport.outputTokenBudget(
                prompt: String(repeating: "x", count: 64_000),
                contextTokens: 16_000
            )
        } catch {
            rejectedOversizedPrompt = true
        }
        #expect(rejectedOversizedPrompt)
    }

    @Test func localGoalDirectArtifactParsesLMStudioOutputAndRejectsPartialHTML() throws {
        let payload: [String: Any] = [
            "output": [[
                "type": "message",
                "content": "```html\n<!doctype html><html><body><script>const game = true;</script></body></html>\n```",
            ]],
            "stats": ["input_tokens": 120, "total_output_tokens": 240],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let response = try LocalGoalArtifactSupport.parseResponse(data)
        let artifact = try LocalGoalArtifactSupport.artifactContent(from: response.content, pathExtension: "html")

        #expect(artifact.hasPrefix("<!doctype html>"))
        #expect(artifact.contains("const game = true"))
        #expect(response.inputTokens == 120)
        #expect(response.outputTokens == 240)

        var rejectedPartialHTML = false
        do {
            _ = try LocalGoalArtifactSupport.artifactContent(from: "<!doctype html><html><body>", pathExtension: "html")
        } catch {
            rejectedPartialHTML = true
        }
        #expect(rejectedPartialHTML)
    }

    @Test func goalPlanParserExtractsAnExplicitOutputContract() throws {
        let response = """
        ```json
        {
          "output": {
            "type": "Playable browser game",
            "format": "HTML, CSS and JavaScript",
            "location": "~/openclaw/workspace/runner",
            "launch": "Open index.html in LocalClaw Preview",
            "completionCriteria": ["The game launches without errors", "Keyboard controls work"]
          },
          "steps": [
            {"title":"Create the game shell","outcome":"A runnable project","completionCriteria":["Preview opens"]},
            {"title":"Implement gameplay","outcome":"A playable level","completionCriteria":["The player can finish the level"]},
            {"title":"Validate output","outcome":"A stable final build","completionCriteria":["No console errors"]}
          ]
        }
        ```
        """
        let plan = try #require(GoalPlanParser.parse(response, sessionID: "session-1", objective: "Build a game"))

        #expect(plan.output.type == "Playable browser game")
        #expect(plan.output.format == "HTML, CSS and JavaScript")
        #expect(plan.steps.count == 3)
        #expect(plan.isReadyForApproval)
        #expect(!plan.isApproved)
    }

    @Test func goalPlanParserAcceptsCompactLocalModelOutput() throws {
        let response = """
        {
          "type":"browserGame",
          "format":"HTML/JS/CSS",
          "location":"/game/localclaw.html",
          "launch":"Open localclaw.html",
          "completionCriteria":"The playable game opens without errors.",
          "steps":[
            {"title":"Create shell","outcome":"Runnable files","completionCriteria":"index.html exists"},
            {"title":"Add gameplay","outcome":"Playable puzzle","completionCriteria":"Controls work"},
            {"title":"Validate","outcome":"Stable result","completionCriteria":"No console errors"}
          ]
        }
        """
        let plan = try #require(GoalPlanParser.parse(response, sessionID: "local-session", objective: "Build a puzzle"))

        #expect(plan.output.type == "browserGame")
        #expect(plan.output.completionCriteria == ["The playable game opens without errors."])
        #expect(plan.steps[0].completionCriteria == ["index.html exists"])
        #expect(plan.isReadyForApproval)
    }

    @Test func goalProgressAdvancesOnlyAfterVerifiableCompletion() throws {
        var plan = try #require(GoalPlanParser.parse(
            """
            {"output":{"type":"Report","format":"Markdown","location":"/tmp/report.md","launch":"Open file","completionCriteria":["Report exists"]},"steps":[{"title":"Research","outcome":"Evidence collected","completionCriteria":["Sources listed"]},{"title":"Write","outcome":"Report created","completionCriteria":["File exists"]}]}
            """,
            sessionID: "session-2",
            objective: "Create a report"
        ))
        plan.prepareForApproval()
        #expect(plan.currentStep?.title == "Research")

        plan.apply(GoalStepProgressReport(status: .working, summary: "Collected one source", evidence: ["source.txt"]))
        #expect(plan.currentStep?.title == "Research")
        #expect(plan.completedStepCount == 0)

        plan.apply(GoalStepProgressReport(status: .complete, summary: "Research finished", evidence: ["sources.md"] ))
        #expect(plan.completedStepCount == 1)
        #expect(plan.currentStep?.title == "Write")
    }

    @Test func goalProgressParserHidesItsMachineMarker() throws {
        let result = GoalProgressParser.parse(
            """
            The playable shell is ready.
            <localclaw_progress>
            {"status":"complete","summary":"Created the shell","evidence":["index.html","npm test passed"]}
            </localclaw_progress>
            """
        )
        let report = try #require(result.report)

        #expect(report.status == .complete)
        #expect(report.evidence == ["index.html", "npm test passed"])
        #expect(result.cleanedText == "The playable shell is ready.")
    }

    @Test func goalControllerResourceLocatorSupportsPackagedAndSwiftPMLayouts() {
        let packaged = GoalControllerResourceLocator.candidateURLs(
            bundleURL: URL(fileURLWithPath: "/Applications/LocalClaw.app"),
            resourceURL: URL(fileURLWithPath: "/Applications/LocalClaw.app/Contents/Resources"),
            executableURL: URL(fileURLWithPath: "/Applications/LocalClaw.app/Contents/MacOS/LocalClaw")
        )
        #expect(packaged.contains(URL(fileURLWithPath: "/Applications/LocalClaw.app/Contents/Resources/localclaw-mac-installer_localclaw-mac-installer.bundle/goal-controller.mjs")))

        let swiftPM = GoalControllerResourceLocator.candidateURLs(
            bundleURL: URL(fileURLWithPath: "/tmp/.build/arm64-apple-macosx/debug"),
            resourceURL: nil,
            executableURL: URL(fileURLWithPath: "/tmp/.build/arm64-apple-macosx/debug/localclaw-mac-installer")
        )
        #expect(swiftPM.contains(URL(fileURLWithPath: "/tmp/.build/arm64-apple-macosx/debug/localclaw-mac-installer_localclaw-mac-installer.bundle/goal-controller.mjs")))
    }

    @Test func goalControllerResourceIsPresentInTheTestBuild() {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = packageRoot
            .appendingPathComponent(".build/debug/localclaw-mac-installer_localclaw-mac-installer.bundle", isDirectory: true)
            .appendingPathComponent("goal-controller.mjs")

        #expect(FileManager.default.fileExists(atPath: script.path))
    }
}
