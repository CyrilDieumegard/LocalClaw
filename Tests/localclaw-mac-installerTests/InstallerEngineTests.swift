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

    @Test func canonicalChatRuntimeModelMapsOpenAIGPTModels() {
        #expect(InstallerViewModel.canonicalChatRuntimeModelID("openrouter/openai/gpt-5.5") == "openrouter/openai/gpt-5.5")
        #expect(InstallerViewModel.canonicalChatRuntimeModelID("openrouter/openai/gpt-5.4") == "openrouter/openai/gpt-5.4")
        #expect(InstallerViewModel.canonicalChatRuntimeModelID("openrouter/moonshotai/kimi-k2.5") == "openrouter/moonshotai/kimi-k2.5")
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

        let first = InstallerViewModel.runtimeSessionID(base: base, modelID: "openai/gpt-5.5", useDeveloperSession: true, freshDeveloperTurnID: "turn-a")
        let second = InstallerViewModel.runtimeSessionID(base: base, modelID: "openai/gpt-5.5", useDeveloperSession: true, freshDeveloperTurnID: "turn-b")

        #expect(first != second)
        #expect(first.contains("-turn-turn-a"))
        #expect(second.contains("-turn-turn-b"))
    }

    @Test func fastDeveloperRequestsUseLowThinkingAndShortTimeout() {
        #expect(InstallerViewModel.agentThinkingLevel(for: .fast) == "low")
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .fast, useDeveloperSession: true) == 90)
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .cloud, useDeveloperSession: true) == 150)
        #expect(InstallerViewModel.agentTimeoutSeconds(for: .deep, useDeveloperSession: true) == 240)
    }

    @Test func simpleDeveloperEditsUseTightBudget() {
        #expect(InstallerViewModel.isSimpleDeveloperEdit("change the game color to purple"))
        #expect(InstallerViewModel.isSimpleDeveloperEdit("mets le theme en violet"))
        #expect(!InstallerViewModel.isSimpleDeveloperEdit("refactor the backend auth and database migration"))
        #expect(InstallerViewModel.simpleDeveloperEditTimeoutSeconds == 60)
        #expect(InstallerViewModel.wallClockTimeoutSeconds(forAgentTimeout: 60) == 80)
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

        let result = InstallerViewModel.applyQuickDeveloperColorEdit(projectPath: root.path, requestText: "change la couleur du jeu pour du jaune")
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
            InstallerViewModel.OpenRouterModel(id: "openrouter/moonshotai/kimi-k2.5", displayName: "Kimi K2.5")
        ]
        vm.selectedChatModel = "lmstudio/google/gemma-4-e2b"

        vm.ensureSelectedChatModel()

        #expect(vm.availableChatModels.allSatisfy { $0.id.hasPrefix("openrouter/") })
        #expect(vm.availableChatModels.map(\.id) == ["openrouter/openai/gpt-5.5", "openrouter/moonshotai/kimi-k2.5"])
        #expect(vm.selectedChatModel == "openrouter/openai/gpt-5.5")
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
