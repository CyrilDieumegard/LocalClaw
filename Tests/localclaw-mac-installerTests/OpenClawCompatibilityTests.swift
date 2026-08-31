import Foundation
import Testing
@testable import localclaw_mac_installer

struct OpenClawCompatibilityTests {
    @Test func legacyOpenAIModelsMigrateWithoutChangingTheSelectedModel() {
        #expect(OpenClawCompatibility.modelID("openai-codex/gpt-5.5", version: "2026.8.1") == "openai/gpt-5.5")
        #expect(OpenClawCompatibility.modelID("codex/gpt-5.4-mini", version: "2026.8.1") == "openai/gpt-5.4-mini")
        #expect(OpenClawCompatibility.modelID("openai-codex/gpt-5.5", version: "2026.7.1-2") == "openai-codex/gpt-5.5")
        #expect(OpenClawCompatibility.modelID("openrouter/openai/gpt-5.5", version: "2026.8.1") == "openrouter/openai/gpt-5.5")
        #expect(OpenClawCompatibility.modelID("lmstudio/qwen/qwen3.5-9b", version: "2026.8.1") == "lmstudio/qwen/qwen3.5-9b")
        #expect(!OpenClawCompatibility.usesUnifiedOpenAIRoutes(version: "Not installed"))
    }

    @Test @MainActor func agentOwnershipSupportsBothRostersWithoutGuessingAnExplicitFleet() {
        #expect(OpenClawCompatibility.chatAgentID(in: [:]) == "main")
        #expect(OpenClawCompatibility.chatAgentID(in: ["agents": ["list": [["id": "writer"]]]]) == "writer")
        #expect(OpenClawCompatibility.chatAgentID(in: ["agents": ["entries": ["writer": [:]]]]) == "writer")
        #expect(OpenClawCompatibility.chatAgentID(in: ["agents": ["entries": ["writer": [:], "main": [:]]]]) == "main")
        #expect(OpenClawCompatibility.chatAgentID(in: ["agents": ["entries": ["writer": [:], "helper": [:]]]]) == nil)
        #expect(OpenClawCompatibility.chatAgentID(in: ["agents": ["ownership": "explicit", "entries": [:]]]) == nil)
        #expect(OpenClawCompatibility.chatAgentID(in: ["agents": ["entries": ["bad;command": [:]]]]) == nil)
        #expect(GoalCenterModel.openClawSessionKey(for: "abc", agentID: "writer").hasPrefix("agent:writer:explicit:"))
    }

    @Test func unifiedOpenAIHonorsExplicitAuthenticationMode() {
        #expect(OpenClawCompatibility.openAIUsesOAuth(in: [:], oauthAvailable: true))
        #expect(!OpenClawCompatibility.openAIUsesOAuth(in: [:], oauthAvailable: false))
        let keyConfig: [String: Any] = ["models": ["providers": ["openai": ["auth": "api-key"]]]]
        #expect(!OpenClawCompatibility.openAIUsesOAuth(in: keyConfig, oauthAvailable: true))
        let ordered: [String: Any] = ["auth": [
            "order": ["openai": ["openai:key", "openai:oauth"]],
            "profiles": ["openai:key": ["mode": "api_key"], "openai:oauth": ["mode": "oauth"]]
        ]]
        #expect(!OpenClawCompatibility.openAIUsesOAuth(in: ordered, oauthAvailable: true))
        #expect(RuntimeSnapshotResolver.route(for: "openai/gpt-5.5", openAIUsesOAuth: true) == .oauth)
        #expect(RuntimeSnapshotResolver.route(for: "openai/gpt-5.5") == .cloud)
    }

    @Test func statusSummaryLabelsAreNotProviderIdentifiers() {
        let status: [String: Any] = ["auth": [
            "providersWithOAuth": ["openai (1)", "legacy", "not a provider"],
            "missingProvidersInUse": ["legacy"],
            "providers": [["provider": "openai", "profiles": ["count": 1, "oauth": 1, "apiKey": 0]]]
        ]]
        #expect(InstallerEngine.configuredProviders(inModelStatus: status) == ["openai"])
        #expect(OpenClawCompatibility.oauthProviders(inModelStatus: status) == ["openai"])
    }

    @Test func agentTurnsCarryTheExplicitOwner() {
        let args = InstallerViewModel.openClawAgentArguments(
            sessionID: "fixture", messageFilePath: "/tmp/prompt.txt", model: "openai/gpt-5.5",
            thinking: "off", agentTimeout: 420, agentID: "writer"
        )
        #expect(args.contains("--agent"))
        #expect(args[args.firstIndex(of: "--agent")! + 1] == "writer")
    }
}
