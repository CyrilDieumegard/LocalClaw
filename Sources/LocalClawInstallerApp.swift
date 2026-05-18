import SwiftUI
import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class InstallerViewModel: ObservableObject {
    enum Screen { case license, onboarding, home, options, install, ready, updates, controlCenter, commandCenter, uninstallCenter, channelSetup, agents, cronJobs, healthCenter, usageCenter, chat, models, skills, developer }
    enum InstallMode: String {
        case llmOnly = "Install Local LLM only"
        case openClawOnly = "Install OpenClaw only"
        case updateOnly = "Update existing setup"
        case fullInstall = "Full Install"
    }

    enum InferenceMode: String, CaseIterable, Identifiable {
        case cloud = "Cloud LLM"
        case oauth = "OAuth LLM"
        case local = "Local LLM"

        var id: String { rawValue }
    }

    enum ChatResponseMode: String, CaseIterable, Identifiable {
        case fast = "Fast"
        case deep = "Deep"
        case local = "Local"
        case cloud = "Cloud"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .fast: return "bolt.fill"
            case .deep: return "brain.head.profile"
            case .local: return "desktopcomputer"
            case .cloud: return "cloud.fill"
            }
        }
        var detail: String {
            switch self {
            case .fast: return "Shorter, quicker answers"
            case .deep: return "More careful reasoning"
            case .local: return "Prefer LM Studio"
            case .cloud: return "Prefer configured cloud model"
            }
        }
    }

    struct ChatMessage: Identifiable, Codable {
        let id: UUID
        let role: String
        let text: String
        let metadata: String?
        let modelName: String?
        let imagePath: String?
        let createdAt: Date

        init(id: UUID = UUID(), role: String, text: String, metadata: String? = nil, modelName: String? = nil, imagePath: String? = nil, createdAt: Date = Date()) {
            self.id = id
            self.role = role
            self.text = text
            self.metadata = metadata
            self.modelName = modelName
            self.imagePath = imagePath
            self.createdAt = createdAt
        }
    }

    struct ChatSession: Identifiable, Codable {
        let id: String
        var title: String
        var subtitle: String
        var projectID: String?
        var messages: [ChatMessage]
        var updatedAt: Date

        static func fresh(title: String = "New discussion") -> ChatSession {
            ChatSession(
                id: "localclaw-ui-chat-\(UUID().uuidString)",
                title: title,
                subtitle: "OpenClaw assistant",
                projectID: nil,
                messages: [ChatMessage(role: "assistant", text: "Hi, I’m OpenClaw inside LocalClaw. Ask me anything about your setup.")],
                updatedAt: Date()
            )
        }

        static func developerFresh() -> ChatSession {
            ChatSession(
                id: "localclaw-developer-chat-\(UUID().uuidString)",
                title: "Developer workspace",
                subtitle: "AI Developer",
                projectID: nil,
                messages: [],
                updatedAt: Date()
            )
        }
    }

    struct ChatProject: Identifiable, Codable {
        let id: String
        var title: String
        var icon: String
        var colorName: String
        var createdAt: Date

        init(id: String, title: String, icon: String = "folder", colorName: String = "red", createdAt: Date) {
            self.id = id
            self.title = title
            self.icon = icon
            self.colorName = colorName
            self.createdAt = createdAt
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, icon, colorName, createdAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "folder"
            colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? "red"
            createdAt = try container.decode(Date.self, forKey: .createdAt)
        }

        static func fresh(index: Int) -> ChatProject {
            ChatProject(
                id: "localclaw-chat-project-\(UUID().uuidString)",
                title: "Project \(index)",
                icon: "folder",
                colorName: "red",
                createdAt: Date()
            )
        }
    }

    struct ModelUsageRecord: Identifiable, Codable {
        let id: UUID
        let createdAt: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let totalTokens: Int
        let estimatedCostUSD: Double

        init(id: UUID = UUID(), createdAt: Date = Date(), model: String, inputTokens: Int, outputTokens: Int, totalTokens: Int, estimatedCostUSD: Double) {
            self.id = id
            self.createdAt = createdAt
            self.model = model
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.totalTokens = totalTokens
            self.estimatedCostUSD = estimatedCostUSD
        }
    }

    struct SkillMissingRequirements: Codable {
        var bins: [String]?
        var anyBins: [String]?
        var env: [String]?
        var config: [String]?
        var os: [String]?

        var summary: String {
            let parts = [
                bins?.isEmpty == false ? "Missing bins: \(bins!.joined(separator: ", "))" : nil,
                anyBins?.isEmpty == false ? "Needs one of: \(anyBins!.joined(separator: ", "))" : nil,
                env?.isEmpty == false ? "Missing env: \(env!.joined(separator: ", "))" : nil,
                config?.isEmpty == false ? "Missing config: \(config!.joined(separator: ", "))" : nil,
                os?.isEmpty == false ? "OS: \(os!.joined(separator: ", "))" : nil
            ].compactMap { $0 }
            return parts.isEmpty ? "Ready" : parts.joined(separator: " · ")
        }
    }

    struct OpenClawSkill: Identifiable, Codable {
        var id: String { name }
        let name: String
        let description: String?
        let emoji: String?
        let eligible: Bool?
        let disabled: Bool?
        let modelVisible: Bool?
        let userInvocable: Bool?
        let commandVisible: Bool?
        let source: String?
        let bundled: Bool?
        let homepage: String?
        let missing: SkillMissingRequirements?

        var statusLabel: String {
            if disabled == true { return "Needs setup" }
            if eligible == true { return "Ready" }
            return "Limited"
        }

        var isActive: Bool {
            disabled != true && (eligible == true || modelVisible == true || commandVisible == true)
        }

        var installedLabel: String {
            source?.hasPrefix("ClawHub") == true ? "Not installed" : "Installed"
        }

        var activeLabel: String {
            isActive ? "Active" : "Inactive"
        }

        var sourceLabel: String {
            source?.replacingOccurrences(of: "openclaw-", with: "").replacingOccurrences(of: "-", with: " ").capitalized ?? "Unknown"
        }
    }

    struct OpenClawSkillsListResponse: Codable {
        let workspaceDir: String?
        let managedSkillsDir: String?
        let skills: [OpenClawSkill]
    }

    struct OpenClawSkillsSearchResponse: Codable {
        let results: [OpenClawHubSkill]
    }

    struct OpenClawHubSkill: Identifiable, Codable {
        var id: String { slug }
        let slug: String
        let displayName: String?
        let summary: String?
        let version: String?
        let ownerHandle: String?

        var asSkill: OpenClawSkill {
            OpenClawSkill(
                name: slug,
                description: summary,
                emoji: nil,
                eligible: nil,
                disabled: nil,
                modelVisible: nil,
                userInvocable: true,
                commandVisible: nil,
                source: ownerHandle.map { "ClawHub / \($0)" } ?? "ClawHub",
                bundled: false,
                homepage: nil,
                missing: nil
            )
        }
    }

    struct ChannelInfo: Identifiable {
        let id: String
        let label: String
        let detailLabel: String
        let systemImage: String
        let installed: Bool
        let configured: Bool
        let running: Bool
        let connected: Bool
        let accounts: [String]
        let origin: String
        let tokenStatus: String?
        let tokenSource: String?
        let lastError: String?
        let probeOK: Bool?
        let botUsername: String?
        let lastActivity: String?

        var stateLabel: String {
            if connected { return "Connected" }
            if running { return "Running" }
            if configured { return "Configured" }
            if installed { return "Installed" }
            return "Not installed"
        }

        var isActive: Bool {
            connected || running
        }

        var detailSummary: String {
            var parts: [String] = []
            if !accounts.isEmpty { parts.append("Accounts: \(accounts.joined(separator: ", "))") }
            if let tokenStatus { parts.append("Token: \(tokenStatus)") }
            if let tokenSource { parts.append("Source: \(tokenSource)") }
            if let botUsername { parts.append("Bot: \(botUsername)") }
            if let lastActivity { parts.append("Last activity: \(lastActivity)") }
            if let lastError, !lastError.isEmpty { parts.append("Error: \(lastError)") }
            return parts.isEmpty ? "No connection detail yet." : parts.joined(separator: " · ")
        }

        var connectionLabel: String {
            if connected { return "Connected" }
            if running { return "Active" }
            if configured { return "Configured" }
            if installed { return "Ready to connect" }
            return "Not connected"
        }

        var connectionTint: Color {
            if connected || running { return Color(NSColor.systemGreen) }
            if configured { return Color(NSColor.systemBlue) }
            if installed { return UI.accent }
            return UI.muted
        }

        var accountRows: [String] {
            accounts.isEmpty ? ["No account connected yet"] : accounts
        }

        var primaryActionLabel: String {
            if connected || running { return "Add Account" }
            if configured { return "Reconnect" }
            return "Connect"
        }
    }

    private struct ChannelCatalogEntry {
        let id: String
        let label: String
        let detailLabel: String
        let systemImage: String
        let origin: String
    }

    struct ChannelConfigSnapshot {
        let configured: Bool
        let accounts: [String]
        let tokenSource: String?
    }

    struct AgentInfo: Identifiable {
        let id: String
        let identityName: String
        let identityEmoji: String?
        let workspace: String?
        let agentDir: String?
        let model: String?
        let bindings: Int
        let isDefault: Bool

        var displayName: String {
            identityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : identityName
        }

        var roleSummary: String {
            if isDefault { return "Main assistant" }
            if bindings > 0 { return "Routed agent" }
            return "Isolated agent"
        }

        var statusLabel: String {
            isDefault ? "Active default" : (bindings > 0 ? "Active route" : "Available")
        }

        var statusTint: Color {
            isDefault || bindings > 0 ? Color(NSColor.systemGreen) : UI.accent
        }

        var detailSummary: String {
            var parts: [String] = []
            if let model, !model.isEmpty { parts.append("Model: \(model)") }
            parts.append("Bindings: \(bindings)")
            if let workspace, !workspace.isEmpty { parts.append("Workspace: \(workspace)") }
            if let agentDir, !agentDir.isEmpty { parts.append("State: \(agentDir)") }
            return parts.joined(separator: " · ")
        }
    }

    struct CronJobInfo: Identifiable {
        let id: String
        let name: String
        let description: String?
        let enabled: Bool
        let scheduleLabel: String
        let payloadLabel: String
        let sessionTarget: String?
        let nextRun: String?
        let lastRun: String?
        let deliveryLabel: String?

        var statusLabel: String { enabled ? "Active" : "Disabled" }
        var statusTint: Color { enabled ? Color(NSColor.systemGreen) : UI.muted }

        var detailSummary: String {
            var parts: [String] = [scheduleLabel, payloadLabel]
            if let sessionTarget, !sessionTarget.isEmpty { parts.append("Session: \(sessionTarget)") }
            if let deliveryLabel, !deliveryLabel.isEmpty { parts.append("Delivery: \(deliveryLabel)") }
            if let nextRun, !nextRun.isEmpty { parts.append("Next: \(nextRun)") }
            if let lastRun, !lastRun.isEmpty { parts.append("Last: \(lastRun)") }
            return parts.joined(separator: " · ")
        }
    }

    enum CloudAuthMode: String, CaseIterable, Identifiable {
        case api = "API"
        case oauth = "OAuth"

        var id: String { rawValue }
    }

    enum AIProvider: String, CaseIterable, Identifiable {
        case openRouter = "OpenRouter"
        case openAI = "OpenAI"
        case anthropic = "Anthropic"
        case gemini = "Gemini"
        case xAI = "xAI"
        case custom = "Custom / Multi"

        enum OpenAIAuthMethod: String, CaseIterable, Identifiable {
            case apiKey = "API Key"
            case oauth = "OAuth (Codex / ChatGPT)"
            var id: String { rawValue }
        }

        var id: String { rawValue }

        var setupURL: String {
            switch self {
            case .openRouter: return "https://openrouter.ai/keys"
            case .openAI: return "https://platform.openai.com/api-keys"
            case .anthropic: return "https://console.anthropic.com/"
            case .gemini: return "https://aistudio.google.com/app/apikey"
            case .xAI: return "https://console.x.ai/"
            case .custom: return "https://docs.openclaw.ai"
            }
        }

        var requiresApiKey: Bool {
            switch self {
            case .custom: return false
            default: return true
            }
        }

        /// Model identifier for openclaw.json config (Bug 6)
        var modelIdentifier: String {
            switch self {
            case .openRouter: return "openrouter/auto"
            case .openAI: return "openai/gpt-4o-mini"
            case .anthropic: return "anthropic/claude-3-5-haiku-20241022"
            case .gemini: return "google/gemini-2.5-flash-preview"
            case .xAI: return "x-ai/grok-2-1212"
            case .custom: return ""
            }
        }

        /// Provider key for auth profiles in openclaw.json
        var authProvider: String {
            switch self {
            case .openRouter: return "openrouter"
            case .openAI: return "openai"
            case .anthropic: return "anthropic"
            case .gemini: return "google"
            case .xAI: return "xai"
            case .custom: return ""
            }
        }
    }

    struct OpenRouterModel: Identifiable, Hashable {
        let id: String
        let displayName: String
    }

    static let openRouterModels: [OpenRouterModel] = [
        // Recommended / Popular
        OpenRouterModel(id: "openrouter/openai/gpt-5-mini", displayName: "⭐ GPT-5 Mini"),
        OpenRouterModel(id: "openrouter/anthropic/claude-3.5-sonnet", displayName: "⭐ Claude 3.5 Sonnet"),
        OpenRouterModel(id: "openrouter/openai/gpt-4o", displayName: "⭐ GPT-4o"),
        OpenRouterModel(id: "openrouter/openai/gpt-4o-mini", displayName: "⭐ GPT-4o Mini"),
        
        // Claude family
        OpenRouterModel(id: "openrouter/anthropic/claude-3.5-haiku", displayName: "Claude 3.5 Haiku"),
        OpenRouterModel(id: "openrouter/anthropic/claude-3-opus", displayName: "Claude 3 Opus"),
        OpenRouterModel(id: "openrouter/anthropic/claude-3-sonnet", displayName: "Claude 3 Sonnet"),
        OpenRouterModel(id: "openrouter/anthropic/claude-3-haiku", displayName: "Claude 3 Haiku"),
        
        // GPT family
        OpenRouterModel(id: "openrouter/openai/gpt-5.5", displayName: "OpenAI: GPT-5.5"),
        OpenRouterModel(id: "openrouter/openai/gpt-5.4", displayName: "OpenAI: GPT-5.4"),
        OpenRouterModel(id: "openrouter/openai/gpt-5.4-mini", displayName: "OpenAI: GPT-5.4 Mini"),
        OpenRouterModel(id: "openrouter/openai/gpt-4-turbo", displayName: "GPT-4 Turbo"),
        OpenRouterModel(id: "openrouter/openai/gpt-4", displayName: "GPT-4"),
        OpenRouterModel(id: "openrouter/openai/gpt-3.5-turbo", displayName: "GPT-3.5 Turbo"),
        
        // Google/Gemini
        OpenRouterModel(id: "openrouter/google/gemini-2.5-flash-preview", displayName: "Gemini 2.5 Flash"),
        OpenRouterModel(id: "openrouter/google/gemini-2.0-flash-exp", displayName: "Gemini 2.0 Flash"),
        OpenRouterModel(id: "openrouter/google/gemini-1.5-pro", displayName: "Gemini 1.5 Pro"),
        OpenRouterModel(id: "openrouter/google/gemini-1.5-flash", displayName: "Gemini 1.5 Flash"),
        
        // Meta/Llama
        OpenRouterModel(id: "openrouter/meta-llama/llama-3.3-70b-instruct", displayName: "Llama 3.3 70B"),
        OpenRouterModel(id: "openrouter/meta-llama/llama-3.2-90b-vision-instruct", displayName: "Llama 3.2 90B Vision"),
        OpenRouterModel(id: "openrouter/meta-llama/llama-3.2-11b-vision-instruct", displayName: "Llama 3.2 11B Vision"),
        OpenRouterModel(id: "openrouter/meta-llama/llama-3.1-405b-instruct", displayName: "Llama 3.1 405B"),
        OpenRouterModel(id: "openrouter/meta-llama/llama-3.1-70b-instruct", displayName: "Llama 3.1 70B"),
        OpenRouterModel(id: "openrouter/meta-llama/llama-3.1-8b-instruct", displayName: "Llama 3.1 8B"),
        
        // DeepSeek
        OpenRouterModel(id: "openrouter/deepseek/deepseek-chat", displayName: "DeepSeek Chat"),
        OpenRouterModel(id: "openrouter/deepseek/deepseek-coder", displayName: "DeepSeek Coder"),
        
        // Mistral
        OpenRouterModel(id: "openrouter/mistralai/mistral-large", displayName: "Mistral Large"),
        OpenRouterModel(id: "openrouter/mistralai/mistral-medium", displayName: "Mistral Medium"),
        OpenRouterModel(id: "openrouter/mistralai/mistral-small", displayName: "Mistral Small"),
        OpenRouterModel(id: "openrouter/mistralai/codestral", displayName: "Codestral"),
        
        // Qwen
        OpenRouterModel(id: "openrouter/nvidia/nemotron-3-nano-4b", displayName: "Nemotron 3 Nano 4B"),
        OpenRouterModel(id: "openrouter/qwen/qwen3.5-35b-a3b", displayName: "Qwen 3.5 35B-A3B"),
        OpenRouterModel(id: "openrouter/qwen/qwen3.5-27b", displayName: "Qwen 3.5 27B"),
        OpenRouterModel(id: "openrouter/qwen/qwen3.5-122b-a10b", displayName: "Qwen 3.5 122B-A10B"),
        OpenRouterModel(id: "openrouter/qwen/qwen3.5-9b", displayName: "Qwen 3.5 9B"),
        OpenRouterModel(id: "openrouter/qwen/qwen3.5-4b", displayName: "Qwen 3.5 4B"),
        OpenRouterModel(id: "openrouter/qwen/qwen3.5-2b", displayName: "Qwen 3.5 2B"),
        OpenRouterModel(id: "openrouter/qwen/qwen3.5-0.8b", displayName: "Qwen 3.5 0.8B"),
        OpenRouterModel(id: "openrouter/qwen/qwen-2.5-72b-instruct", displayName: "Qwen 2.5 72B"),
        OpenRouterModel(id: "openrouter/qwen/qwen-2.5-32b-instruct", displayName: "Qwen 2.5 32B"),
        OpenRouterModel(id: "openrouter/qwen/qwen-2.5-14b-instruct", displayName: "Qwen 2.5 14B"),
        
        // xAI/Grok
        OpenRouterModel(id: "openrouter/x-ai/grok-2", displayName: "Grok 2"),
        OpenRouterModel(id: "openrouter/x-ai/grok-2-mini", displayName: "Grok 2 Mini"),
        OpenRouterModel(id: "openrouter/x-ai/grok-beta", displayName: "Grok Beta"),
        
        // Cohere
        OpenRouterModel(id: "openrouter/cohere/command-r-plus", displayName: "Command R+"),
        OpenRouterModel(id: "openrouter/cohere/command-r", displayName: "Command R"),
        
        // Other
        OpenRouterModel(id: "openrouter/nousresearch/nous-hermes-2-mixtral-8x7b", displayName: "Nous Hermes 2 Mixtral"),
        OpenRouterModel(id: "openrouter/01-ai/yi-large", displayName: "Yi Large"),
        OpenRouterModel(id: "openrouter/perplexity/sonar", displayName: "Perplexity Sonar")
    ]

    @Published var screen: Screen = .license
    @Published var showHomebrewPrompt: Bool = false

    private let onboardingCompletedKey = "localclaw.onboardingCompleted"

    // Control Center
    @Published var controlCenterLogs: String = ""
    @Published var gatewayIsRunning: Bool = false
    @Published var currentModel: String = "Unknown"
    @Published var selectedControlModel: String = "kimi"
    @Published var mode: InstallMode = .openClawOnly

    @Published var machineCPUPercent: Double = 0
    @Published var machineMemoryUsedGB: Double = 0
    @Published var machineMemoryAvailableGB: Double = 0
    @Published var machineMemoryTotalGB: Double = 0
    @Published var machineSwapUsedGB: Double = 0
    @Published var machineSwapTotalGB: Double = 0
    @Published var machineLMStudioMB: Int = 0
    @Published var machineOpenclawMB: Int = 0
    @Published var machineNodeMB: Int = 0
    @Published var topProcesses: [ProcessUsageItem] = []
    @Published var hasMachineUsageSnapshot: Bool = false
    @Published var isRefreshingHome: Bool = false

    @Published var licenseEmail: String = ""
    @Published var licenseKey: String = ""
    @Published var activationStatus: String = "License required"
    @Published var isActivated: Bool = false
    @Published var isActivating: Bool = false

    @Published var chip: String = ""
    @Published var ram: String = ""
    @Published var machineDetails: String = ""
    @Published var recommendation: String = ""

    @Published var selectedModel: String = ""
    @Published var inferenceMode: InferenceMode = .cloud
    @Published var installLMStudio = true
    @Published var installOpenClaw = true

    @Published var selectedProvider: AIProvider = .openRouter
    @Published var selectedCloudAuthMode: CloudAuthMode = .api
    @Published var openAIAuthMethod: AIProvider.OpenAIAuthMethod = .apiKey
    @Published var selectedOpenRouterModel: String = "openrouter/openai/gpt-5-mini"
    @Published var openRouterModelsLive: [OpenRouterModel] = []
    @Published var skillsSearchQuery: String = ""
    @Published var installedSkills: [OpenClawSkill] = []
    @Published var clawHubSkills: [OpenClawSkill] = []
    @Published var skillsStatus: String = "Not loaded"
    @Published var skillsLog: String = ""
    @Published var skillsIsLoading = false
    @Published var installingSkillName: String = ""
    @Published var openRouterKeyVerified: Bool = false
    @Published var cloudProviderAuthConfigured: Bool = false
    @Published var hasExistingOpenClawSetup = false
    @Published var gatewayToken: String = ""
    @Published private var userGeneratedToken: Bool = false  // Track if user manually generated token
    @Published var openRouterApiKey: String = ""
    @Published var openAIApiKey: String = ""
    @Published var anthropicApiKey: String = ""
    @Published var geminiApiKey: String = ""
    @Published var xAIApiKey: String = ""
    @Published var enableWhatsApp = false
    @Published var whatsappNumber: String = ""

    @Published var statusHomebrew: String = "PENDING"
    @Published var statusLMStudio: String = "PENDING"
    @Published var statusNode: String = "PENDING"
    @Published var statusOpenClaw: String = "PENDING"
    @Published var statusOpenClawCheck: String = "PENDING"
    @Published var statusModel: String = "PENDING"

    @Published var ocStepNode: String = "PENDING"
    @Published var ocStepCli: String = "PENDING"
    @Published var ocStepRepair: String = "PENDING"
    @Published var ocStepVerify: String = "PENDING"

    @Published var openclawInstalledVersion = "Checking..."
    @Published var openclawLatestVersion = "Checking..."
    @Published var openclawUpdateStatus = "Checking..."
    @Published var brewVersion = "Checking..."
    @Published var nodeVersion = "Checking..."
    @Published var lmStudioVersion = "Checking..."
    @Published var installerCurrentVersion = InstallerViewModel.detectAppVersion()
    @Published var installerBuildNumber = InstallerViewModel.detectBuildNumber()
    @Published var installerLatestVersion = "Checking..."
    @Published var installerUpdateStatus = "Checking..."
    @Published var installerDownloadURL = ""
    @Published var installerExpectedSHA256 = ""
    @Published var localClawBuildLabel = "build unknown"
    @Published var brewUpToDate = false
    @Published var nodeUpToDate = false
    @Published var lmStudioUpToDate = false

    @Published var logs: String = ""
    @Published var downloadProgress: Double = 0
    @Published var currentDownloadFile: String = ""
    @Published var isRunning = false

    @Published var chatInput = ""
    @Published var chatImagePath = ""
    @Published var chatProjects: [ChatProject] = [] {
        didSet { persistChatProjects() }
    }
    @Published var expandedChatProjectIDs: Set<String> = []
    @Published var editingChatProjectID = ""
    @Published var editingChatProjectTitle = ""
    @Published var chatSessions: [ChatSession] = [ChatSession.fresh(title: "Main setup")] {
        didSet { persistChatSessions() }
    }
    @Published var selectedChatSessionID: String = "" {
        didSet { UserDefaults.standard.set(selectedChatSessionID, forKey: Self.selectedChatSessionDefaultsKey) }
    }
    var chatMessages: [ChatMessage] {
        get { selectedChatSession?.messages ?? [] }
        set { updateSelectedChatSession { $0.messages = newValue } }
    }
    var selectedChatSession: ChatSession? {
        chatSessions.first { $0.id == activeChatSessionID }
    }
    var activeChatSessionID: String {
        if !selectedChatSessionID.isEmpty, chatSessions.contains(where: { $0.id == selectedChatSessionID }) {
            return selectedChatSessionID
        }
        return chatSessions.first?.id ?? "localclaw-ui-chat"
    }
    @Published var chatIsSending = false
    @Published var chatStatus = "Ready"
    @Published var selectedChatModel = ""
    @Published var selectedChatResponseMode: ChatResponseMode = .cloud {
        didSet {
            UserDefaults.standard.set(selectedChatResponseMode.rawValue, forKey: Self.selectedChatResponseModeDefaultsKey)
            prepareModelListForSelectedMode()
            reconcileSelectedChatModelForCurrentMode()
        }
    }
    @Published var chatMemoryEnabled = true {
        didSet { UserDefaults.standard.set(chatMemoryEnabled, forKey: Self.chatMemoryEnabledDefaultsKey) }
    }
    @Published var chatSavedNotes: [String] = [] {
        didSet { persistChatSavedNotes() }
    }
    @Published var selectedDeveloperChatSessionID = "" {
        didSet { UserDefaults.standard.set(selectedDeveloperChatSessionID, forKey: "localclaw.developer.selectedSession.v1") }
    }
    @Published var developerProjectPath = NSHomeDirectory() + "/.openclaw/workspace"
    @Published var developerProjectName = "My App" {
        didSet { UserDefaults.standard.set(developerProjectName, forKey: Self.developerProjectNameDefaultsKey) }
    }
    @Published var developerPreviewURL = "http://localhost:5173"
    @Published var developerPreviewStatus = "Preview not running"
    @Published var developerPreviewRefreshID = UUID()
    @Published var developerPreviewDevice = "desktop"
    @Published var developerActiveTab = "preview"
    @Published var developerFreshContextEnabled = true {
        didSet { UserDefaults.standard.set(developerFreshContextEnabled, forKey: Self.developerFreshContextDefaultsKey) }
    }
    private var developerPreviewProcess: Process?
    private var chatGatewayPrepared = false
    private var activeChatProcess: Process?
    private var activeChatRequestID: UUID?
    private var chatStopRequested = false
    private var localLMStudioSetupRequestID: UUID?
    @Published var localLMStudioModels: [String] = []
    @Published var selectedLocalLMStudioModel: String = ""
    @Published var activeLocalLMStudioModel: String = ""
    @Published var localLMStudioSetupStatus = ""
    @Published var localLMStudioSetupLog = ""
    @Published var localLMStudioSetupInProgress = false
    @Published var localLMStudioRepairInProgress = false

    // Uninstall Center
    @Published var isUninstalling = false
    @Published var uninstallLogs: String = ""
    @Published var uninstallLMStudioSelected = true
    @Published var uninstallModelsSelected = true
    @Published var uninstallOpenClawSelected = true
    @Published var uninstallNodeSelected = false
    @Published var uninstallHomebrewSelected = false
    @Published var uninstallConfigsSelected = true

    @Published var hasLMStudioInstalled = false
    @Published var hasLocalModelsInstalled = false
    @Published var hasOpenClawInstalled = false
    @Published var hasNodeInstalled = false
    @Published var hasHomebrewInstalled = false
    @Published var hasConfigCacheInstalled = false
    @Published var channels: [ChannelInfo] = []
    @Published var channelsStatus: String = "Not loaded"
    @Published var channelsIsLoading = false
    @Published var channelSetupLogs: String = ""
    @Published var agents: [AgentInfo] = []
    @Published var agentsStatus: String = "Not loaded"
    @Published var agentsIsLoading = false
    @Published var agentLogs: String = ""
    @Published var cronJobs: [CronJobInfo] = []
    @Published var cronJobsStatus: String = "Not loaded"
    @Published var cronJobsIsLoading = false
    @Published var cronJobLogs: String = ""
    @Published var showCronJobCreator = false
    @Published var cronCreateName = ""
    @Published var cronCreateAgentID = "main"
    @Published var cronCreateScheduleKind = "every"
    @Published var cronCreateScheduleValue = "30m"
    @Published var cronCreateMessage = ""
    @Published var cronCreateIsRunning = false
    @Published var cronCreateError = ""
    @Published var healthLogs: String = ""
    @Published var healthStatus: String = "Unknown"
    @Published var usageLogs: String = ""
    @Published var estimatedMonthlyTokensM: Double = 2.0
    @Published var estimatedMonthlyCostUSD: Double = 0
    @Published var costAdvice: String = ""
    @Published var tokenMonitoringEnabled: Bool = false
    @Published var modelUsageRecords: [ModelUsageRecord] = [] {
        didSet { persistModelUsageRecords() }
    }
    @Published var modelsApplyStatus: String = ""
    @Published var modelsApplyInProgress: Bool = false
    @Published var modeSwitchInProgress: Bool = false
    @Published var modeSwitchStatus: String = ""

    private static let chatSessionsDefaultsKey = "localclaw.chat.sessions.v1"
    private static let chatProjectsDefaultsKey = "localclaw.chat.projects.v1"
    private static let selectedChatSessionDefaultsKey = "localclaw.chat.selectedSession.v1"
    private static let selectedChatResponseModeDefaultsKey = "localclaw.chat.responseMode.v1"
    private static let chatMemoryEnabledDefaultsKey = "localclaw.chat.memoryEnabled.v1"
    private static let chatSavedNotesDefaultsKey = "localclaw.chat.savedNotes.v1"
    private static let developerProjectNameDefaultsKey = "localclaw.developer.projectName.v1"
    private static let developerFreshContextDefaultsKey = "localclaw.developer.freshContext.v1"
    private static let modelUsageDefaultsKey = "localclaw.modelUsage.records.v1"
    nonisolated static let simpleDeveloperEditTimeoutSeconds = 60

    init() {
        if let savedMode = UserDefaults.standard.string(forKey: Self.selectedChatResponseModeDefaultsKey),
           let mode = ChatResponseMode(rawValue: savedMode) {
            selectedChatResponseMode = mode
        }
        if UserDefaults.standard.object(forKey: Self.chatMemoryEnabledDefaultsKey) != nil {
            chatMemoryEnabled = UserDefaults.standard.bool(forKey: Self.chatMemoryEnabledDefaultsKey)
        }
        if let savedProjectName = UserDefaults.standard.string(forKey: Self.developerProjectNameDefaultsKey),
           !savedProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            developerProjectName = savedProjectName
        }
        if UserDefaults.standard.object(forKey: Self.developerFreshContextDefaultsKey) != nil {
            developerFreshContextEnabled = UserDefaults.standard.bool(forKey: Self.developerFreshContextDefaultsKey)
        }
        restoreChatSessions()
        restoreChatSavedNotes()
        restoreModelUsageRecords()
        channels = Self.defaultChannelCatalog.map { entry in
            ChannelInfo(
                id: entry.id,
                label: entry.label,
                detailLabel: entry.detailLabel,
                systemImage: entry.systemImage,
                installed: true,
                configured: false,
                running: false,
                connected: false,
                accounts: [],
                origin: entry.origin,
                tokenStatus: nil,
                tokenSource: nil,
                lastError: nil,
                probeOK: nil,
                botUsername: nil,
                lastActivity: nil
            )
        }
    }

    private static let defaultChannelCatalog: [ChannelCatalogEntry] = [
        ChannelCatalogEntry(id: "telegram", label: "Telegram", detailLabel: "Bot token + pairing approve", systemImage: "paperplane.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "discord", label: "Discord", detailLabel: "Bot token from Developer Portal", systemImage: "gamecontroller.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "whatsapp", label: "WhatsApp", detailLabel: "QR login with Linked Devices", systemImage: "phone.bubble.left.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "signal", label: "Signal", detailLabel: "Signal bridge or account login", systemImage: "message.badge.filled.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "slack", label: "Slack", detailLabel: "Workspace bot/app token", systemImage: "number", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "mattermost", label: "Mattermost", detailLabel: "Server URL and bot token", systemImage: "bubble.left.and.bubble.right.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "matrix", label: "Matrix", detailLabel: "Homeserver and access token", systemImage: "square.grid.3x3.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "imessage", label: "iMessage", detailLabel: "macOS Messages bridge", systemImage: "message.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "googlechat", label: "Google Chat", detailLabel: "Google Chat bot credentials", systemImage: "message.badge.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "msteams", label: "Microsoft Teams", detailLabel: "Microsoft Teams bot credentials", systemImage: "person.3.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "feishu", label: "Feishu", detailLabel: "Feishu bot app credentials", systemImage: "paperplane.circle.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "wecom", label: "WeCom", detailLabel: "WeCom app credentials", systemImage: "building.2.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "line", label: "LINE", detailLabel: "LINE channel token", systemImage: "bubble.left.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "zalo", label: "Zalo", detailLabel: "Zalo app credentials", systemImage: "bubble.right.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "nextcloud-talk", label: "Nextcloud Talk", detailLabel: "Nextcloud Talk bot config", systemImage: "cloud.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "twitch", label: "Twitch", detailLabel: "Twitch chat token", systemImage: "play.tv.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "nostr", label: "Nostr", detailLabel: "Nostr relay credentials", systemImage: "network", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "irc", label: "IRC", detailLabel: "Server, nick, and channel config", systemImage: "terminal.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "qqbot", label: "QQ Bot", detailLabel: "QQ bot credentials", systemImage: "q.circle.fill", origin: "OpenClaw channel")
    ]

    private static func channelSortRank(_ id: String) -> Int {
        defaultChannelCatalog.firstIndex { $0.id == id } ?? (defaultChannelCatalog.count + 1)
    }

    private static func humanChannelLabel(_ id: String) -> String {
        let special: [String: String] = [
            "googlechat": "Google Chat",
            "msteams": "Microsoft Teams",
            "nextcloud-talk": "Nextcloud Talk",
            "openclaw-weixin": "Weixin",
            "qqbot": "QQ Bot",
            "synology-chat": "Synology Chat"
        ]
        if let label = special[id] { return label }
        return id
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func channelDetailLabel(id: String, origin: String) -> String {
        switch origin {
        case "configured":
            return "Configured in OpenClaw"
        case "available":
            return "Installed locally, ready to connect"
        case "installable":
            return "Available to install and connect"
        default:
            return origin.isEmpty ? "OpenClaw channel" : origin.capitalized
        }
    }

    nonisolated static func configuredChannelSnapshots(from root: [String: Any]) -> [String: ChannelConfigSnapshot] {
        guard let channels = root["channels"] as? [String: Any] else { return [:] }

        return channels.reduce(into: [String: ChannelConfigSnapshot]()) { result, pair in
            guard let channelConfig = pair.value as? [String: Any] else { return }

            let enabled = channelConfig["enabled"] as? Bool ?? false
            let hasToken = !(channelConfig["token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let accountsDict = channelConfig["accounts"] as? [String: Any] ?? [:]
            let configuredAccounts = accountsDict.compactMap { accountPair -> String? in
                guard let accountConfig = accountPair.value as? [String: Any] else { return nil }
                let accountEnabled = accountConfig["enabled"] as? Bool ?? true
                let accountHasToken = !(accountConfig["token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let accountHasSession = !(accountConfig["session"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let accountHasAuthPath = !(accountConfig["authPath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return (accountEnabled || accountHasToken || accountHasSession || accountHasAuthPath) ? accountPair.key : nil
            }
            .sorted()

            let configured = enabled || hasToken || !configuredAccounts.isEmpty
            guard configured else { return }

            let accounts = configuredAccounts.isEmpty ? ["default"] : configuredAccounts
            result[pair.key] = ChannelConfigSnapshot(
                configured: true,
                accounts: accounts,
                tokenSource: hasToken ? "config" : nil
            )
        }
    }

    nonisolated static func configuredChannelSnapshots(configPath: String = NSHomeDirectory() + "/.openclaw/openclaw.json") -> [String: ChannelConfigSnapshot] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return configuredChannelSnapshots(from: root)
    }

    // Installation status tracking (using existing status variables)
    var statusNodeJS: String {
        get { statusNode }
        set { statusNode = newValue }
    }
    var statusConfig: String = "PENDING"
    var statusService: String = "PENDING"

    var modelOptions: [String] {
        localModelCandidates.map(\.name)
    }

    private var localModelCandidates: [LocalModelCandidate] {
        [
            LocalModelCandidate(name: "Qwen 3.5 35B-A3B Q4_K_M", query: "qwen3.5-35b-a3b@q4_k_m", providerId: "qwen3.5-35b-a3b"),
            LocalModelCandidate(name: "Qwen 3.5 27B Q4_K_M", query: "qwen3.5-27b@q4_k_m", providerId: "qwen3.5-27b"),
            LocalModelCandidate(name: "Qwen 3.5 9B Q4_K_M", query: "qwen3.5-9b@q4_k_m", providerId: "qwen3.5-9b"),
            LocalModelCandidate(name: "Qwen 3.5 4B Q4_K_M", query: "qwen3.5-4b@q4_k_m", providerId: "qwen3.5-4b"),
            LocalModelCandidate(name: "Qwen 3.5 2B Q4_K_M", query: "qwen3.5-2b@q4_k_m", providerId: "qwen3.5-2b"),
            LocalModelCandidate(name: "Qwen 3.5 0.8B Q4_K_M", query: "qwen3.5-0.8b@q4_k_m", providerId: "qwen3.5-0.8b"),
            LocalModelCandidate(name: "Qwen 3 14B Q4_K_M", query: "qwen-3-14b@q4_k_m", providerId: "qwen3-14b"),
            LocalModelCandidate(name: "Qwen 3 8B Q4_K_M", query: "qwen-3-8b@q4_k_m", providerId: "qwen3-8b"),
            LocalModelCandidate(name: "Nemotron 3 Nano 4B Q4_K_M", query: "nemotron-3-nano-4b@q4_k_m", providerId: "nvidia/nemotron-3-nano-4b"),
            LocalModelCandidate(name: "DeepSeek R1 14B Q4_K_M", query: "deepseek-r1-distill-qwen-14b@q4_k_m", providerId: "deepseek-r1-distill-qwen-14b"),
            LocalModelCandidate(name: "Llama 3.3 8B Q4_K_M", query: "llama-3.3-8b-instruct@q4_k_m", providerId: "llama-3.3-8b-instruct")
        ]
    }

    let modelQueries: [String: String] = [
        "Qwen 3.5 35B-A3B Q4_K_M": "qwen3.5-35b-a3b@q4_k_m",
        "Qwen 3.5 27B Q4_K_M": "qwen3.5-27b@q4_k_m",
        "Qwen 3.5 9B Q4_K_M": "qwen3.5-9b@q4_k_m",
        "Qwen 3.5 4B Q4_K_M": "qwen3.5-4b@q4_k_m",
        "Qwen 3.5 2B Q4_K_M": "qwen3.5-2b@q4_k_m",
        "Qwen 3.5 0.8B Q4_K_M": "qwen3.5-0.8b@q4_k_m",
        "Qwen 3 8B Q4_K_M": "qwen-3-8b@q4_k_m",
        "Qwen 3 14B Q4_K_M": "qwen-3-14b@q4_k_m",
        "Qwen 3 32B Q4_K_M": "qwen-3-32b@q4_k_m",
        "Nemotron 3 Nano 4B Q4_K_M": "nemotron-3-nano-4b@q4_k_m",
        "DeepSeek R1 14B Q4_K_M": "deepseek-r1-distill-qwen-14b@q4_k_m",
        "Llama 3.3 8B Q4_K_M": "llama-3.3-8b-instruct@q4_k_m"
    ]

    let localProviderModelIds: [String: String] = [
        "Qwen 3.5 35B-A3B Q4_K_M": "qwen3.5-35b-a3b",
        "Qwen 3.5 27B Q4_K_M": "qwen3.5-27b",
        "Qwen 3.5 9B Q4_K_M": "qwen3.5-9b",
        "Qwen 3.5 4B Q4_K_M": "qwen3.5-4b",
        "Qwen 3.5 2B Q4_K_M": "qwen3.5-2b",
        "Qwen 3.5 0.8B Q4_K_M": "qwen3.5-0.8b",
        "Qwen 3 8B Q4_K_M": "qwen3-8b",
        "Qwen 3 14B Q4_K_M": "qwen3-14b",
        "Qwen 3 32B Q4_K_M": "qwen3-32b",
        "Nemotron 3 Nano 4B Q4_K_M": "nvidia/nemotron-3-nano-4b",
        "DeepSeek R1 14B Q4_K_M": "deepseek-r1-distill-qwen-14b",
        "Llama 3.3 8B Q4_K_M": "llama-3.3-8b-instruct"
    ]

    private let engine = InstallerEngine()

    private struct LocalLicenseRecord: Codable {
        let email: String
        let licenseKey: String
        let token: String
        let machineId: String
        let activatedAt: String
        let expiresAt: String?
    }

    private struct InstallerUpdateManifest: Codable {
        let latestVersion: String
        let dmgUrl: String
        let notesUrl: String?
        let sha256: String?
    }

    private struct LocalModelCandidate {
        let name: String
        let query: String
        let providerId: String
    }

    private var licenseEndpoint: String {
        ProcessInfo.processInfo.environment["LOCALCLAW_LICENSE_ENDPOINT"] ?? "https://localclaw.io/api/license/activate"
    }

    var isMockLicenseEndpoint: Bool {
        licenseEndpoint.contains("127.0.0.1") || licenseEndpoint.contains("localhost")
    }

    private var allowsOfflineLicenses: Bool {
        ProcessInfo.processInfo.environment["LOCALCLAW_ALLOW_OFFLINE_LICENSE"] == "1"
    }

    private var installerUpdateManifestURL: String {
        ProcessInfo.processInfo.environment["LOCALCLAW_INSTALLER_UPDATE_URL"] ?? "https://localclaw.io/downloads/localclaw-installer-latest.json"
    }

    private var localLicenseFile: URL {
        let base = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".localclaw-installer", isDirectory: true)
        return base.appendingPathComponent("license.json")
    }

    // Offline key format for manual subscription renewals:
    // LCW-YYYYMMDD-XXXX-BASE
    // Example: LCW-20260331-0007-BASE
    private func licenseExpiryDate(from key: String) -> Date? {
        let parts = key.uppercased().split(separator: "-")
        guard parts.count >= 4, parts[0] == "LCW" else { return nil }

        let ymd = String(parts[1])
        guard ymd.count == 8, let raw = Int(ymd) else { return nil }
        let year = raw / 10000
        let month = (raw / 100) % 100
        let day = raw % 100

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 23
        comps.minute = 59
        comps.second = 59

        return Calendar(identifier: .gregorian).date(from: comps)
    }

    private func isValidOfflineKey(_ key: String) -> Bool {
        guard let expiry = licenseExpiryDate(from: key) else { return false }
        return expiry >= Date()
    }

    private func isExpiredLicenseDate(_ raw: String?) -> Bool {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if let date = ISO8601DateFormatter().date(from: raw) {
            return date < Date()
        }

        return false
    }

    var progress: Double {
        let states = [statusHomebrew, statusLMStudio, statusNode, statusOpenClaw, statusOpenClawCheck, statusModel]
        let done = states.filter { $0 == "OK" || $0 == "SKIP" }.count
        return Double(done) / 6.0
    }

    private static func detectAppVersion() -> String {
        if let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !short.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return short
        }
        return "1.0.2"
    }

    private static func detectBuildNumber() -> String {
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return build
        }
        return "-"
    }

    private func refreshLocalClawBuildLabel() {
        let defaultRepoDir = NSHomeDirectory() + "/LocalClaw"
        let repoDir = ProcessInfo.processInfo.environment["LOCALCLAW_REPO_DIR"] ?? defaultRepoDir

        let (_, gitLabelRaw) = engine.shell("git -C '\(repoDir)' describe --tags --always --dirty 2>/dev/null || git -C '\(repoDir)' rev-parse --short HEAD 2>/dev/null || true")
        let gitLabel = gitLabelRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        if !gitLabel.isEmpty {
            localClawBuildLabel = gitLabel
        } else {
            localClawBuildLabel = "build unknown"
        }
    }

    func bootstrap() {
        loadLocalLicenseIfPresent()

        if !isActivated,
           licenseEmail.isEmpty,
           licenseKey.isEmpty,
           isMockLicenseEndpoint {
            useTestLicense()
            activationStatus = "Test mode enabled"
        }

        let profile = engine.detectHardware()
        let reco = engine.recommend(for: profile)

        chip = profile.chip
        ram = "\(profile.memoryGB) GB"
        refreshMachineDetails()
        recommendation = "\(reco.model) \(reco.quant)"
        selectedModel = recommendation

        statusHomebrew = engine.hasCommand("brew") ? "SKIP" : "PENDING"
        statusLMStudio = engine.hasLMStudioApp() ? "SKIP" : "PENDING"
        statusNode = engine.hasCommand("node") ? "SKIP" : "PENDING"
        hasExistingOpenClawSetup = engine.hasCommand("openclaw")
        statusOpenClaw = hasExistingOpenClawSetup ? "SKIP" : "PENDING"
        statusOpenClawCheck = "PENDING"

        ocStepNode = engine.hasCommand("node") ? "OK" : "PENDING"
        ocStepCli = engine.hasCommand("openclaw") ? "OK" : "PENDING"
        ocStepRepair = "PENDING"
        ocStepVerify = "PENDING"
        if mode == .openClawOnly {
            statusModel = "SKIP"
        } else if let query = modelQueries[selectedModel], engine.hasModelInstalled(query) {
            statusModel = "SKIP"
        } else {
            statusModel = "PENDING"
        }

        loadExistingConfigIfPresent()
        refreshOpenRouterModels()
        refreshLocalClawBuildLabel()
        refreshVersions()

        // Auto-detect existing token from config
        loadTokenFromConfig()

        // Load OpenRouter model from config if exists
        loadOpenRouterModelFromConfig()
        refreshUninstallInventory()

        if isActivated && !engine.hasCommand("brew") {
            showHomebrewPrompt = true
        }

        if isActivated {
            screen = hasCompletedOnboarding() ? .home : .onboarding
        } else {
            screen = .license
        }
    }

    func hasCompletedOnboarding() -> Bool {
        UserDefaults.standard.bool(forKey: onboardingCompletedKey)
    }

    func refreshMachineDetails() {
        let modelName = engine.shell("/usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | /usr/bin/awk -F': ' '/Model Name/{print $2; exit}'").1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelIdentifier = engine.shell("/usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | /usr/bin/awk -F': ' '/Model Identifier/{print $2; exit}'").1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let macos = engine.shell("/usr/bin/sw_vers -productVersion").1.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = engine.shell("/usr/bin/sw_vers -buildVersion").1.trimmingCharacters(in: .whitespacesAndNewlines)
        let boot = engine.shell("/usr/sbin/sysctl -n kern.boottime | /usr/bin/awk -F'\\} ' '{print $2}'").1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let year = String(Calendar.current.component(.year, from: Date()))

        var lines: [String] = []
        if !modelName.isEmpty { lines.append("Model: \(modelName)") }
        if !modelIdentifier.isEmpty { lines.append("ID: \(modelIdentifier)") }
        if !macos.isEmpty { lines.append("macOS \(macos) (\(build))") }
        if !boot.isEmpty { lines.append("Boot: \(boot)") }
        lines.append("Year: \(year)")

        machineDetails = lines.joined(separator: "\n")
    }

    func copyMachineDetails() {
        let payload = machineDetails.isEmpty
            ? "Machine\n\(chip)\n\(ram)"
            : "Machine\n\(chip)\n\(ram)\n\n\(machineDetails)"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        modeSwitchStatus = "Machine info copied"
    }

    func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
    }

    func completeOnboarding() {
        markOnboardingCompleted()
        screen = .home
    }

    func restartOnboarding() {
        UserDefaults.standard.set(false, forKey: onboardingCompletedKey)
        screen = .onboarding
    }

    private func loadOpenRouterModelFromConfig() {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agents = json["agents"] as? [String: Any],
              let defaults = agents["defaults"] as? [String: Any],
              let model = defaults["model"] as? [String: Any],
              let configuredPrimary = model["primary"] as? String else {
            return
        }
        let primary = Self.repairedLegacyCloudModelID(configuredPrimary)
        if primary != configuredPrimary {
            _ = engine.writeModelToConfig(modelIdentifier: primary)
        }

        if primary.hasPrefix("openrouter/") {
            inferenceMode = .cloud
            selectedOpenRouterModel = primary
            selectedProvider = .openRouter
        } else if primary.hasPrefix("lmstudio/") {
            inferenceMode = .local
            let localId = primary.replacingOccurrences(of: "lmstudio/", with: "")
            selectedLocalLMStudioModel = localId
            if let mapped = localProviderModelIds.first(where: { $0.value == localId })?.key {
                selectedModel = mapped
            }
        }
    }
    
    private func loadTokenFromConfig() {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = json["gateway"] as? [String: Any],
              let auth = gateway["auth"] as? [String: Any],
              let token = auth["token"] as? String else {
            return
        }
        gatewayToken = token
    }

    func installHomebrewWithUserConsent() {
        showHomebrewPrompt = false
        append("Installing Homebrew with administrator privileges...")
        let result = engine.installHomebrewIfNeeded()
        append("[\(result.state.rawValue)] Homebrew")
        append("  \(result.message)")
        if result.state == .ok {
            statusHomebrew = "OK"
        } else {
            statusHomebrew = "FAIL"
        }
    }

    // MARK: - Control Center

    func refreshControlCenter() {
        let status = engine.getGatewayStatus()
        gatewayIsRunning = status.isRunning
        currentModel = engine.getCurrentModel()

        if currentModel.hasPrefix("openrouter/") {
            selectedControlModel = currentModel
        }

        refreshOpenRouterModels()

        let usage = engine.getSystemUsage()
        machineCPUPercent = usage.cpuPercent
        machineMemoryUsedGB = usage.memoryUsedGB
        machineMemoryAvailableGB = usage.memoryAvailableGB
        machineMemoryTotalGB = usage.memoryTotalGB
        machineSwapUsedGB = usage.swapUsedGB
        machineSwapTotalGB = usage.swapTotalGB
        machineLMStudioMB = usage.lmStudioMemoryMB
        machineOpenclawMB = usage.openclawMemoryMB
        machineNodeMB = usage.nodeMemoryMB
        topProcesses = engine.topProcesses(limit: 10)
    }

    func refreshHomeDashboard() {
        guard !isRefreshingHome else { return }
        isRefreshingHome = true
        let status = engine.getGatewayStatus()
        gatewayIsRunning = status.isRunning
        currentModel = engine.getCurrentModel()
        if currentModel.hasPrefix("openrouter/") {
            selectedControlModel = currentModel
        }
        if channelsStatus == "Not loaded" { refreshChannels() }
        if skillsStatus == "Not loaded" { refreshSkills() }
        if cronJobsStatus == "Not loaded" { refreshCronJobs() }
        isRefreshingHome = false
    }

    func refreshMachineUsageSnapshot() {
        hasMachineUsageSnapshot = true
        let usage = engine.getSystemUsage()
        machineCPUPercent = usage.cpuPercent
        machineMemoryUsedGB = usage.memoryUsedGB
        machineMemoryAvailableGB = usage.memoryAvailableGB
        machineMemoryTotalGB = usage.memoryTotalGB
        machineSwapUsedGB = usage.swapUsedGB
        machineSwapTotalGB = usage.swapTotalGB
        machineLMStudioMB = usage.lmStudioMemoryMB
        machineOpenclawMB = usage.openclawMemoryMB
        machineNodeMB = usage.nodeMemoryMB
    }

    func stopHomePerformanceMonitoring() {
        hasMachineUsageSnapshot = false
        machineCPUPercent = 0
        machineMemoryUsedGB = 0
        machineMemoryAvailableGB = 0
        machineMemoryTotalGB = 0
        machineSwapUsedGB = 0
        machineSwapTotalGB = 0
        machineLMStudioMB = 0
        machineOpenclawMB = 0
        machineNodeMB = 0
    }

    func killHeavyProcess(_ pid: Int) {
        guard confirmProcessAction(
            title: "Kill process?",
            message: "This will send TERM to PID \(pid). Unsaved work in that process may be lost."
        ) else { return }

        let result = engine.killProcess(pid: pid)
        controlCenterLogs += "[\(result.state.rawValue)] \(result.message)\n"
        refreshControlCenter()
    }

    func emergencyCleanupAction() {
        guard confirmProcessAction(
            title: "Run emergency cleanup?",
            message: "This will stop LocalClaw, LM Studio, and OpenClaw helper processes to recover memory. Active local model sessions may close."
        ) else { return }

        let result = engine.emergencyCleanup()
        controlCenterLogs += "[\(result.state.rawValue)] \(result.message)\n"
        refreshControlCenter()
    }

    private func confirmProcessAction(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func runDoctor() {
        controlCenterLogs = "Running doctor repair...\n"
        let result = engine.runDoctorRepair()
        controlCenterLogs += "[\(result.state.rawValue)] \(result.message)\n"
        refreshControlCenter()
    }

    func restartGatewayAction() {
        controlCenterLogs = "Restarting gateway...\n"
        let result = engine.restartGateway()
        controlCenterLogs += "[\(result.state.rawValue)] \(result.message)\n"
        refreshControlCenter()
    }

    func applyModelChange() {
        controlCenterLogs = "Changing model to \(selectedControlModel)...\n"
        let result = engine.changeModel(selectedControlModel)
        controlCenterLogs += "[\(result.state.rawValue)] \(result.message)\n"
        refreshControlCenter()
    }

    func applyModelsTabSelection() {
        if modelsApplyInProgress { return }
        if inferenceMode == .local {
            guard !selectedLocalLMStudioModel.isEmpty else {
                modelsApplyStatus = "Select a local LM Studio model first."
                return
            }
            let modelId = selectedLocalLMStudioModel
            modelsApplyInProgress = true
            modelsApplyStatus = "Setting up LM Studio model \(modelId)..."
            Task.detached {
                let result = InstallerEngine().autoSetupLMStudioModel(modelId: modelId, contextLength: 32768) { message in
                    DispatchQueue.main.async {
                        self.modelsApplyStatus = message
                    }
                }
                let activeLocal = InstallerEngine().loadedLMStudioModelInfo()?.model
                await MainActor.run {
                    if result.state == .ok {
                        self.currentModel = "lmstudio/\(activeLocal ?? modelId)"
                        self.selectedChatModel = self.currentModel
                    }
                    self.activeLocalLMStudioModel = activeLocal ?? self.activeLocalLMStudioModel
                    self.selectedChatResponseMode = .local
                    self.reconcileSelectedChatModelForCurrentMode()
                    self.modelsApplyStatus = "[\(result.state.rawValue)] \(result.message)"
                    self.modelsApplyInProgress = false
                }
            }
            return
        } else {
            if inferenceMode == .oauth {
                selectedProvider = .openAI
                selectedCloudAuthMode = .oauth
                openAIAuthMethod = .oauth
            } else {
                prepareCloudModelSelection()
            }
            guard inferenceMode == .oauth || !selectedOpenRouterModel.isEmpty else {
                modelsApplyStatus = "Select a cloud model first."
                return
            }
        }

        let targetModel = inferenceMode == .oauth ? effectiveModelIdentifier() : selectedOpenRouterModel
        modelsApplyInProgress = true
        modelsApplyStatus = "Applying \(targetModel)..."
        Task.detached {
            let result = InstallerEngine().changeModel(targetModel)
            await MainActor.run {
                self.currentModel = targetModel
                self.selectedChatResponseMode = .cloud
                self.selectedChatModel = targetModel
                self.modelsApplyStatus = "[\(result.state.rawValue)] \(result.message)"
                self.modelsApplyInProgress = false
            }
        }
    }

    func openControlDashboard() {
        _ = engine.openDashboard()
    }

    func chooseMode(_ mode: InstallMode) {
        guard isActivated else {
            activationStatus = "Activate license first"
            screen = .license
            return
        }
        self.mode = mode
        switch mode {
        case .llmOnly:
            installLMStudio = true
            installOpenClaw = false
            statusModel = "PENDING"
            statusOpenClawCheck = "SKIP"
            screen = .options
        case .openClawOnly:
            installLMStudio = false
            installOpenClaw = true
            statusModel = "SKIP"
            statusOpenClawCheck = "PENDING"
            hasExistingOpenClawSetup = engine.hasCommand("openclaw")
            ocStepNode = engine.hasCommand("node") ? "OK" : "PENDING"
            ocStepCli = hasExistingOpenClawSetup ? "SKIP" : "PENDING"
            ocStepRepair = "PENDING"
            ocStepVerify = "PENDING"
            screen = .options
        case .updateOnly:
            screen = .updates
        case .fullInstall:
            installLMStudio = true
            installOpenClaw = true
            statusModel = "PENDING"
            statusOpenClawCheck = "PENDING"
            hasExistingOpenClawSetup = engine.hasCommand("openclaw")
            ocStepNode = engine.hasCommand("node") ? "OK" : "PENDING"
            ocStepCli = hasExistingOpenClawSetup ? "SKIP" : "PENDING"
            ocStepRepair = "PENDING"
            ocStepVerify = "PENDING"
            screen = .options
        }
    }

    var setupValidationErrors: [String] {
        var errors: [String] = []

        // Gateway token is auto-generated during installation, not required here
        if isCloudLikeInferenceMode && providerNeedsApiKey() && requiredProviderKey().isEmpty {
            errors.append("Add API key for \(selectedProvider.rawValue)")
        }

        if inferenceMode == .local && selectedModel.isEmpty {
            errors.append("Select a local model")
        }
        
        // OpenRouter specific validation
        if isCloudLikeInferenceMode && selectedProvider == .openRouter {
            let key = openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.hasPrefix("sk-or-") {
                errors.append("OpenRouter key should start with 'sk-or-'")
            }
            if key.count < 20 {
                errors.append("OpenRouter key seems too short")
            }
        }

        return errors
    }

    var canStartInstall: Bool {
        !isRunning && setupValidationErrors.isEmpty
    }

    var isCloudLikeInferenceMode: Bool {
        inferenceMode == .cloud || inferenceMode == .oauth
    }

    var isOpenAIOAuthMode: Bool {
        inferenceMode == .oauth || selectedCloudAuthMode == .oauth
    }

    func effectiveModelIdentifier() -> String {
        if isOpenAIOAuthMode { return "openai-codex/gpt-5.4" }
        return selectedProvider.modelIdentifier
    }

    func effectiveAuthProvider() -> String {
        if isOpenAIOAuthMode { return "openai-codex" }
        return selectedProvider.authProvider
    }

    func providerNeedsApiKey() -> Bool {
        if isOpenAIOAuthMode { return false }
        return selectedProvider.requiresApiKey
    }

    func requiredProviderKey() -> String {
        if isOpenAIOAuthMode { return "" }
        switch selectedProvider {
        case .openRouter: return openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openAI: return openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .anthropic: return anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .gemini: return geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .xAI: return xAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .custom:
            let keys = [openRouterApiKey, openAIApiKey, anthropicApiKey, geminiApiKey, xAIApiKey]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return keys.first(where: { !$0.isEmpty }) ?? ""
        }
    }

    func refreshOpenRouterModels() {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return }
        let key = openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        Task.detached {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("https://localclaw.io", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("LocalClaw", forHTTPHeaderField: "X-Title")

                if key.hasPrefix("sk-or-") {
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                }

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    await MainActor.run {
                        self.openRouterModelsLive = []
                        self.append("OpenRouter model list unavailable")
                    }
                    return
                }

                struct ORModels: Decodable {
                    struct Item: Decodable {
                        let id: String
                        let name: String?
                    }
                    let data: [Item]
                }

                let decoded = try JSONDecoder().decode(ORModels.self, from: data)
                let mapped = decoded.data
                    .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .map { item in
                        OpenRouterModel(id: "openrouter/\(item.id)", displayName: item.name ?? item.id)
                    }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

                await MainActor.run {
                    self.openRouterModelsLive = mapped
                    if !self.openRouterModelsLive.contains(where: { $0.id == self.selectedOpenRouterModel }) {
                        self.selectedOpenRouterModel = self.openRouterModelsLive.first?.id ?? ""
                    }
                    if self.selectedChatResponseMode != .local {
                        self.reconcileSelectedChatModelForCurrentMode()
                    }
                    self.append("✓ Loaded \(mapped.count) OpenRouter models")
                }
            } catch {
                await MainActor.run {
                    self.openRouterModelsLive = []
                    self.append("OpenRouter model list refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func verifyOpenRouterKey() {
        let key = openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20 else {
            openRouterKeyVerified = false
            return
        }
        
        // Basic format check
        if !key.hasPrefix("sk-or-") {
            openRouterKeyVerified = false
            append("Warning: OpenRouter key should start with 'sk-or-'")
            return
        }
        
        // Real API verification
        append("Verifying OpenRouter key...")
        Task.detached {
            do {
                guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else {
                    await MainActor.run {
                        self.openRouterKeyVerified = false
                        self.append("Error: Invalid verification URL")
                    }
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                await MainActor.run {
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        self.openRouterKeyVerified = true
                        self.append("✓ OpenRouter key verified successfully")
                        self.refreshOpenRouterModels()
                    } else {
                        self.openRouterKeyVerified = false
                        self.append("✗ OpenRouter key verification failed")
                    }
                }
            } catch {
                await MainActor.run {
                    self.openRouterKeyVerified = false
                    self.append("✗ OpenRouter verification error: \(error.localizedDescription)")
                }
            }
        }
    }

    func openProviderURL() {
        guard let url = URL(string: selectedProvider.setupURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func openOpenClawDocs() {
        guard let url = URL(string: "https://docs.openclaw.ai") else { return }
        NSWorkspace.shared.open(url)
    }

    func generateGatewayToken() {
        gatewayToken = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        userGeneratedToken = true
        append("Generated secure gateway token (user-defined)")
    }

    var setupModeLabel: String {
        hasExistingOpenClawSetup ? "Modify existing OpenClaw" : "Fresh OpenClaw install"
    }

    func loadExistingConfigIfPresent() {
        let candidates = [
            FileManager.default.currentDirectoryPath + "/.env",
            NSHomeDirectory() + "/.openclaw/.env",
            NSHomeDirectory() + "/.openclaw/.env.local"
        ]

        var loadedAny = false

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            guard let raw = try? String(contentsOfFile: path, encoding: String.Encoding.utf8) else { continue }
            let env = parseEnv(raw)
            if env.isEmpty { continue }

            if gatewayToken.isEmpty && !userGeneratedToken { gatewayToken = env["OPENCLAW_GATEWAY_TOKEN"] ?? gatewayToken }
            if whatsappNumber.isEmpty { whatsappNumber = env["WHATSAPP_NUMBER"] ?? whatsappNumber }

            openRouterApiKey = env["OPENROUTER_API_KEY"] ?? openRouterApiKey
            openAIApiKey = env["OPENAI_API_KEY"] ?? openAIApiKey
            anthropicApiKey = env["ANTHROPIC_API_KEY"] ?? anthropicApiKey
            geminiApiKey = env["GEMINI_API_KEY"] ?? geminiApiKey
            xAIApiKey = env["XAI_API_KEY"] ?? xAIApiKey

            if !whatsappNumber.isEmpty { enableWhatsApp = true }
            loadedAny = true
        }

        if !openRouterApiKey.isEmpty { selectedProvider = .openRouter }
        else if !openAIApiKey.isEmpty { selectedProvider = .openAI }
        else if !anthropicApiKey.isEmpty { selectedProvider = .anthropic }
        else if !geminiApiKey.isEmpty { selectedProvider = .gemini }
        else if !xAIApiKey.isEmpty { selectedProvider = .xAI }

        if loadedAny {
            append("Loaded existing .env values")
        }
        cloudProviderAuthConfigured = engine.hasProviderAuth(provider: effectiveAuthProvider()) || !requiredProviderKey().isEmpty
    }

    private func parseEnv(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    func copyEnvTemplate() {
        var lines = [
            "# OpenClaw quick config",
            "OPENCLAW_GATEWAY_TOKEN=\(gatewayToken)"
        ]

        if enableWhatsApp {
            lines.append("WHATSAPP_NUMBER=\(whatsappNumber)")
        }

        if !openRouterApiKey.isEmpty { lines.append("OPENROUTER_API_KEY=\(openRouterApiKey)") }
        if !openAIApiKey.isEmpty { lines.append("OPENAI_API_KEY=\(openAIApiKey)") }
        if !anthropicApiKey.isEmpty { lines.append("ANTHROPIC_API_KEY=\(anthropicApiKey)") }
        if !geminiApiKey.isEmpty { lines.append("GEMINI_API_KEY=\(geminiApiKey)") }
        if !xAIApiKey.isEmpty { lines.append("XAI_API_KEY=\(xAIApiKey)") }

        let payload = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        append("Copied env template to clipboard")
    }

    var visibleInstalledSkills: [OpenClawSkill] {
        let query = skillsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return installedSkills }
        return installedSkills.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description ?? "").lowercased().contains(query) ||
            ($0.source ?? "").lowercased().contains(query)
        }
    }

    func refreshSkills() {
        guard !skillsIsLoading else { return }
        skillsIsLoading = true
        skillsStatus = "Loading skills..."
        skillsLog = "Running openclaw skills list..."

        Task.detached {
            let engine = InstallerEngine()
            let (code, output) = engine.shell("openclaw --no-color skills list --json 2>&1")

            await MainActor.run {
                self.skillsIsLoading = false
                guard code == 0, let data = output.data(using: .utf8) else {
                    self.skillsStatus = "Unable to load skills"
                    self.skillsLog = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(OpenClawSkillsListResponse.self, from: data)
                    self.installedSkills = decoded.skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    let readyCount = decoded.skills.filter { $0.eligible == true }.count
                    self.skillsStatus = "\(decoded.skills.count) skills found · \(readyCount) ready"
                    self.skillsLog = "Workspace: \(decoded.workspaceDir ?? "unknown")\nManaged skills: \(decoded.managedSkillsDir ?? "unknown")"
                } catch {
                    self.skillsStatus = "Skills JSON parse failed"
                    self.skillsLog = "\(error.localizedDescription)\n\n\(output.prefix(1200))"
                }
            }
        }
    }

    func searchClawHubSkills() {
        let query = skillsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clawHubSkills = []
            return
        }

        skillsStatus = "Searching ClawHub..."
        let safeQuery = shellSingleQuote(query)
        Task.detached {
            let engine = InstallerEngine()
            let (code, output) = engine.shell("openclaw --no-color skills search --json --limit 12 \(safeQuery) 2>&1")

            await MainActor.run {
                guard code == 0, let data = output.data(using: .utf8) else {
                    self.skillsStatus = "ClawHub search failed"
                    self.skillsLog = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(OpenClawSkillsSearchResponse.self, from: data)
                    self.clawHubSkills = decoded.results.map { $0.asSkill }
                    self.skillsStatus = self.clawHubSkills.isEmpty ? "No ClawHub result" : "\(self.clawHubSkills.count) ClawHub results"
                } catch {
                    self.skillsStatus = "ClawHub JSON parse failed"
                    self.skillsLog = "\(error.localizedDescription)\n\n\(output.prefix(1200))"
                }
            }
        }
    }

    func installSkill(_ skill: OpenClawSkill) {
        let slug = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, installingSkillName.isEmpty else { return }

        installingSkillName = slug
        skillsStatus = "Installing \(slug)..."
        skillsLog = "Running openclaw skills install \(slug)"
        let safeSlug = shellSingleQuote(slug)

        Task.detached {
            let engine = InstallerEngine()
            let (code, output) = engine.shell("openclaw --no-color skills install \(safeSlug) 2>&1")

            await MainActor.run {
                self.installingSkillName = ""
                self.skillsLog = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.skillsStatus = code == 0 ? "Installed \(slug)" : "Install failed for \(slug)"
                if code == 0 {
                    self.refreshSkills()
                }
            }
        }
    }

    func useTestLicense() {
        licenseEmail = "cyril@test.local"
        licenseKey = "LOCALCLAW-V1-TEST"
    }

    func activateLicense() {
        if isActivating { return }

        let email = licenseEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard email.contains("@"), key.count >= 10 else {
            activationStatus = "Invalid email or license key"
            return
        }

        let machineId = engine.machineIdentifier()

        if allowsOfflineLicenses && key.hasPrefix("LCW-") && !isValidOfflineKey(key) {
            activationStatus = "License expired or invalid format"
            return
        }

        if allowsOfflineLicenses && isValidOfflineKey(key) {
            let record = LocalLicenseRecord(
                email: email,
                licenseKey: key,
                token: "offline-token",
                machineId: machineId,
                activatedAt: ISO8601DateFormatter().string(from: Date()),
                expiresAt: nil
            )
            do {
                try persistLicenseRecord(record)
                isActivated = true
                activationStatus = "License activated (offline)"
                screen = .home
                append("Offline license activated for \(email)")
            } catch {
                activationStatus = "Activation save failed: \(error.localizedDescription)"
            }
            return
        }

        guard let endpoint = URL(string: licenseEndpoint) else {
            activationStatus = "License server URL invalid"
            return
        }

        isActivating = true
        activationStatus = "Activating..."
        let payload = LicenseActivationPayload(email: email, licenseKey: key, machineId: machineId, appVersion: installerCurrentVersion)

        Task.detached {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 20
                request.httpBody = try JSONEncoder().encode(payload)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    await MainActor.run {
                        self.activationStatus = "Activation failed: no server response"
                        self.isActivating = false
                    }
                    return
                }

                let decoded = try? JSONDecoder().decode(LicenseActivationResponse.self, from: data)
                if http.statusCode == 200, (decoded?.ok == true || decoded?.token != nil) {
                    let token = decoded?.token ?? "ok"
                    let record = LocalLicenseRecord(
                        email: email,
                        licenseKey: key,
                        token: token,
                        machineId: machineId,
                        activatedAt: ISO8601DateFormatter().string(from: Date()),
                        expiresAt: decoded?.expiresAt
                    )
                    do {
                        try await MainActor.run { try self.persistLicenseRecord(record) }
                    } catch {
                        await MainActor.run {
                            self.activationStatus = "Activation saved failed: \(error.localizedDescription)"
                            self.isActivating = false
                        }
                        return
                    }

                    await MainActor.run {
                        self.isActivated = true
                        self.activationStatus = "License activated"
                        self.isActivating = false
                        self.screen = .home
                        self.append("License activated for \(email)")
                    }
                } else {
                    let msg = decoded?.message ?? "Activation refused (\(http.statusCode))"
                    await MainActor.run {
                        self.activationStatus = msg
                        self.isActivating = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.activationStatus = "Activation error: \(error.localizedDescription)"
                    self.isActivating = false
                }
            }
        }
    }

    func clearLicense() {
        try? FileManager.default.removeItem(at: localLicenseFile)
        isActivated = false
        activationStatus = "License required"
        screen = .license
    }

    private func loadLocalLicenseIfPresent() {
        guard let data = try? Data(contentsOf: localLicenseFile),
              let record = try? JSONDecoder().decode(LocalLicenseRecord.self, from: data) else {
            isActivated = false
            return
        }

        licenseEmail = record.email
        licenseKey = record.licenseKey
        let currentMachineId = engine.machineIdentifier()
        let isSameMachine = record.machineId == currentMachineId
        let hasServerActivation = !record.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasValidOnlineActivation = isSameMachine && hasServerActivation && !isExpiredLicenseDate(record.expiresAt)
        let hasValidOfflineActivation = allowsOfflineLicenses && isSameMachine && isValidOfflineKey(record.licenseKey)

        if hasValidOnlineActivation || hasValidOfflineActivation {
            isActivated = true
            activationStatus = "Activated on this Mac"
        } else {
            isActivated = false
            activationStatus = isSameMachine ? "License expired, renew required" : "License belongs to another Mac"
            try? FileManager.default.removeItem(at: localLicenseFile)
        }
    }

    private func persistLicenseRecord(_ record: LocalLicenseRecord) throws {
        let dir = localLicenseFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        try data.write(to: localLicenseFile, options: [.atomic])
    }

    func runInstall() {
        if isRunning { return }
        isRunning = true
        screen = .install

        downloadProgress = 0
        currentDownloadFile = "Preparing download..."
        append("Starting setup: \(mode.rawValue)")
        append("Model: \(selectedModel)")

        let installLMStudio = self.installLMStudio
        let installOpenClaw = self.installOpenClaw
        let installMode = self.mode
        let selectedModel = self.selectedModel
        let modelQuery = self.modelQueries[selectedModel] ?? ""
        let engine = self.engine
        let token = self.gatewayToken
        let modelId = self.effectiveModelIdentifier()

        Task.detached {
            let clt = await self.runStep(name: "Xcode CLI Tools") { engine.ensureXcodeCLITools() }
            if clt.state == .fail {
                await MainActor.run {
                    self.isRunning = false
                    self.screen = .install
                    self.append("Preflight bloqué: Xcode CLI Tools requis avant l'installation.")
                }
                return
            }

            let brew = await self.runStep(name: "Homebrew") { engine.installHomebrewIfNeeded() }
            if brew.state == .fail {
                await MainActor.run {
                    self.isRunning = false
                    self.screen = .install
                    self.append("Preflight bloqué: Homebrew doit être installé avant la suite.")
                }
                return
            }

            let brewDoctor = await self.runStep(name: "Brew Doctor") { engine.runBrewDoctorCheck() }
            if brewDoctor.state == .fail {
                await MainActor.run {
                    self.isRunning = false
                    self.screen = .install
                    self.append("Preflight bloqué: corrige brew doctor avant OpenClaw/OAuth.")
                }
                return
            }

            if installLMStudio {
                _ = await self.runStep(name: "LM Studio") { engine.installLMStudioIfNeeded() }
            } else {
                await MainActor.run { self.statusLMStudio = "SKIP" }
            }

            if installMode == .llmOnly {
                await self.runModelStep(engine: engine, query: modelQuery)
            } else {
                await MainActor.run { self.statusModel = "SKIP" }
            }

            _ = await self.runStep(name: "Node") { engine.installNodeIfNeeded() }
            if installOpenClaw {
                let openclawInstall = await self.runStep(name: "OpenClaw") { engine.installOpenClawIfNeeded() }
                if openclawInstall.state == .fail {
                    await MainActor.run {
                        self.isRunning = false
                        self.screen = .install
                        self.append("Installation OpenClaw échouée. OAuth bloqué tant que OpenClaw n'est pas installé.")
                    }
                    return
                }
                // Bug 5: Write gateway config before verify
                _ = await self.runStep(name: "Config") { engine.writeOpenClawConfig(gatewayToken: token) }
                // Bug 6: Write model config
                _ = await self.runStep(name: "Model Config") { engine.writeModelToConfig(modelIdentifier: modelId) }
                // Install gateway service and create agent
                _ = await self.runStep(name: "Gateway Service") { engine.installGatewayService() }
                _ = await self.runStep(name: "Default Agent") { engine.createDefaultAgent() }
                _ = await self.runStep(name: "Start Gateway") { engine.startGateway() }
                _ = await self.runStep(name: "OpenClaw Check") { engine.verifyOpenClawSetup() }
            } else {
                await MainActor.run {
                    self.statusOpenClaw = "SKIP"
                    self.statusOpenClawCheck = "SKIP"
                }
            }
            await MainActor.run {
                self.isRunning = false
                self.refreshVersions()
                self.screen = .ready
                self.append("Setup finished")
            }
        }
    }

    func refreshVersions() {
        let info = engine.openClawVersionInfo()
        openclawInstalledVersion = info.installed
        openclawLatestVersion = info.latest

        if info.installed == "Not installed" {
            openclawUpdateStatus = "Not installed"
        } else if info.latest == "Unknown" {
            openclawUpdateStatus = "Unknown"
        } else {
            openclawUpdateStatus = info.updateAvailable ? "Needs update" : "Up to date"
        }

        brewVersion = engine.installedVersion(for: "brew")
        nodeVersion = engine.installedVersion(for: "node")
        lmStudioVersion = engine.installedLMStudioVersion()

        brewUpToDate = brewVersion != "Not installed"
        nodeUpToDate = nodeVersion != "Not installed"
        lmStudioUpToDate = lmStudioVersion != "Not installed"

        refreshInstallerManifest()
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> Int {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av > bv ? 1 : -1 }
        }
        return 0
    }

    func refreshInstallerManifest() {
        installerUpdateStatus = "Checking..."
        guard let url = URL(string: installerUpdateManifestURL) else {
            installerUpdateStatus = "Manifest URL invalid"
            return
        }

        Task.detached {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    await MainActor.run { self.installerUpdateStatus = "Manifest unavailable" }
                    return
                }

                let manifest = try JSONDecoder().decode(InstallerUpdateManifest.self, from: data)
                await MainActor.run {
                    self.installerLatestVersion = manifest.latestVersion
                    var normalizedURL = manifest.dmgUrl
                    if normalizedURL.contains("/LocalClawInstaller.dmg") {
                        normalizedURL = normalizedURL.replacingOccurrences(of: "/LocalClawInstaller.dmg", with: "/localclaw.dmg")
                    }
                    self.installerDownloadURL = normalizedURL
                    self.installerExpectedSHA256 = manifest.sha256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

                    let cmp = self.compareVersion(manifest.latestVersion, self.installerCurrentVersion)
                    if cmp > 0 {
                        self.installerUpdateStatus = "Update available"
                    } else {
                        self.installerUpdateStatus = "Up to date"
                    }
                }
            } catch {
                await MainActor.run {
                    self.installerUpdateStatus = "Manifest unavailable"
                }
            }
        }
    }

    func downloadLatestInstaller() {
        guard let url = URL(string: installerDownloadURL), !installerDownloadURL.isEmpty else {
            append("No installer download URL found in manifest")
            return
        }
        NSWorkspace.shared.open(url)
        append("Opened installer download: \(installerDownloadURL)")
    }

    nonisolated static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func shellSingleQuote(_ value: String) -> String {
        Self.shellSingleQuote(value)
    }

    nonisolated static func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func updateLocalClawFromDMG() {
        if isRunning { return }
        guard let url = URL(string: installerDownloadURL), !installerDownloadURL.isEmpty else {
            append("No installer download URL found in manifest. Click CHECK, then retry.")
            return
        }
        let expectedSHA256 = installerExpectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard expectedSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            installerUpdateStatus = "Using Git update..."
            append("DMG update unavailable: manifest is missing a valid SHA256 checksum.")
            append("Falling back to Advanced Git Update.")
            updateLocalClaw()
            return
        }

        isRunning = true
        installerUpdateStatus = "Downloading update..."
        append("Starting LocalClaw app update from DMG")

        let runningBundlePath = Bundle.main.bundlePath
        let runningAppPath = runningBundlePath.hasSuffix(".app") ? runningBundlePath : ""
        let targetApp: String = {
            if runningAppPath == "/Applications/LocalClaw.app" || runningAppPath == NSHomeDirectory() + "/Applications/LocalClaw.app" {
                return runningAppPath
            }
            if FileManager.default.fileExists(atPath: "/Applications/LocalClaw.app") {
                return "/Applications/LocalClaw.app"
            }
            return NSHomeDirectory() + "/Applications/LocalClaw.app"
        }()

        Task.detached {
            do {
                let (downloadedURL, response) = try await URLSession.shared.download(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw NSError(domain: "LocalClawUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
                }

                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("localclaw-update-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let dmgPath = tempDir.appendingPathComponent("localclaw.dmg")
                try? FileManager.default.removeItem(at: dmgPath)
                try FileManager.default.moveItem(at: downloadedURL, to: dmgPath)

                let actualSHA256 = try InstallerViewModel.sha256Hex(for: dmgPath)
                guard actualSHA256 == expectedSHA256 else {
                    throw NSError(
                        domain: "LocalClawUpdate",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Downloaded DMG checksum mismatch. Expected \(expectedSHA256), got \(actualSHA256)."]
                    )
                }

                let scriptPath = tempDir.appendingPathComponent("install-localclaw-update.sh")
                let quotedDMG = await MainActor.run { self.shellSingleQuote(dmgPath.path) }
                let quotedTarget = await MainActor.run { self.shellSingleQuote(targetApp) }
                let script = """
                #!/bin/zsh
                set -euo pipefail
                DMG=\(quotedDMG)
                TARGET=\(quotedTarget)
                MOUNT_DIR="$(dirname "$DMG")/mount"

                cleanup() {
                  hdiutil detach "$MOUNT_DIR" -quiet || true
                }
                trap cleanup EXIT

                rm -rf "$MOUNT_DIR"
                mkdir -p "$MOUNT_DIR"
                hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MOUNT_DIR"
                APP_SOURCE="$MOUNT_DIR/LocalClaw.app"
                if [ ! -d "$APP_SOURCE" ]; then
                  echo "LocalClaw.app not found in DMG"
                  exit 1
                fi

                if [[ "$TARGET" == /Applications/* ]]; then
                  /usr/bin/osascript -e "do shell script \"rm -rf '$TARGET' && cp -R '$APP_SOURCE' '$TARGET'\" with administrator privileges"
                else
                  mkdir -p "$(dirname "$TARGET")"
                  rm -rf "$TARGET"
                  cp -R "$APP_SOURCE" "$TARGET"
                fi

                /usr/bin/osascript -e 'tell application "LocalClaw" to quit' >/dev/null 2>&1 || true
                sleep 1
                /usr/bin/open "$TARGET" || true
                """
                try script.write(to: scriptPath, atomically: true, encoding: .utf8)
                _ = await MainActor.run { self.engine.shell("chmod +x \(self.shellSingleQuote(scriptPath.path))") }

                await MainActor.run {
                    self.append("Downloaded update DMG. SHA256 verified. Installing LocalClaw to \(targetApp)...")
                    self.installerUpdateStatus = "Installing update..."
                }

                let result = await MainActor.run { self.engine.shell("nohup \(self.shellSingleQuote(scriptPath.path)) >/tmp/localclaw-update.log 2>&1 &") }
                await MainActor.run {
                    if result.0 == 0 {
                        self.append("Installer started in background. LocalClaw will restart automatically.")
                        self.installerUpdateStatus = "Restarting..."
                    } else {
                        self.append("Failed to start background installer: \(result.1)")
                        self.installerUpdateStatus = "Update failed"
                        self.isRunning = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.append("LocalClaw DMG update failed: \(error.localizedDescription)")
                    self.append("Fallback available: use ADVANCED GIT UPDATE.")
                    self.installerUpdateStatus = "Update failed"
                    self.isRunning = false
                }
            }
        }
    }

    func updateLocalClaw() {
        let defaultRepoDir = NSHomeDirectory() + "/LocalClaw"
        let repoDir = ProcessInfo.processInfo.environment["LOCALCLAW_REPO_DIR"] ?? defaultRepoDir
        let repoURL = ProcessInfo.processInfo.environment["LOCALCLAW_GITHUB_REPO"] ?? "https://github.com/CyrilDieumegard/LocalClaw.git"
        let runningBundlePath = Bundle.main.bundlePath
        let runningAppPath = runningBundlePath.hasSuffix(".app") ? runningBundlePath : ""

        let script = """
        #!/bin/zsh
        clear
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

        REPO_DIR="\(repoDir)"
        REPO_URL="\(repoURL)"

        echo "=========================================="
        echo "  LocalClaw Update"
        echo "=========================================="
        echo ""

        if [ ! -d "$REPO_DIR/.git" ]; then
          echo "Repo not found at: $REPO_DIR"
          echo "Cloning from: $REPO_URL"
          git clone "$REPO_URL" "$REPO_DIR" || exit 1
        fi

        cd "$REPO_DIR" || exit 1

        echo "Fetching remote..."
        git fetch origin main || exit 1

        # Client-safe update path: always align local repo to origin/main
        git checkout main >/dev/null 2>&1 || git checkout -B main origin/main || exit 1

        LOCAL_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
        REMOTE_SHA=$(git rev-parse origin/main 2>/dev/null || echo "")

        if [ -n "$LOCAL_SHA" ] && [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
          echo "Already up to date."
        else
          echo "Updating to latest main..."
          git reset --hard origin/main || exit 1
        fi

        echo ""
        echo "Building app bundle..."
        bash scripts/build-dmg.sh || exit 1

        APP_SOURCE="$REPO_DIR/dist/LocalClaw.app"
        if [ ! -d "$APP_SOURCE" ]; then
          echo "Build did not produce LocalClaw.app"
          exit 1
        fi

        TARGET_APP=""
        RUNNING_APP="\(runningAppPath)"

        # Never target transient paths (DMG mount, AppTranslocation, tmp copies)
        if [ -n "$RUNNING_APP" ] && [ -d "$RUNNING_APP" ]; then
          case "$RUNNING_APP" in
            /Applications/LocalClaw.app|$HOME/Applications/LocalClaw.app)
              TARGET_APP="$RUNNING_APP"
              ;;
            *)
              echo "Running app path is transient: $RUNNING_APP"
              echo "Will install to a stable Applications location instead."
              ;;
          esac
        fi

        if [ -z "$TARGET_APP" ] && [ -d "/Applications/LocalClaw.app" ]; then
          TARGET_APP="/Applications/LocalClaw.app"
        fi
        if [ -z "$TARGET_APP" ]; then
          TARGET_APP="$HOME/Applications/LocalClaw.app"
        fi

        echo ""
        echo "Installing updated app..."
        INSTALLED_TO=""

        if [[ "$TARGET_APP" == /Applications/* ]]; then
          echo "Target: $TARGET_APP (admin)"
          if sudo rm -rf "$TARGET_APP" && sudo cp -R "$APP_SOURCE" "$TARGET_APP"; then
            INSTALLED_TO="$TARGET_APP"
          else
            echo "Could not write $TARGET_APP (permission denied or sudo cancelled)."
          fi
        else
          echo "Target: $TARGET_APP (user)"
          mkdir -p "$(dirname "$TARGET_APP")"
          if rm -rf "$TARGET_APP" && cp -R "$APP_SOURCE" "$TARGET_APP"; then
            INSTALLED_TO="$TARGET_APP"
          fi
        fi

        if [ -z "$INSTALLED_TO" ] && [ "$TARGET_APP" != "$HOME/Applications/LocalClaw.app" ]; then
          echo "Falling back to user install..."
          mkdir -p "$HOME/Applications"
          rm -rf "$HOME/Applications/LocalClaw.app"
          cp -R "$APP_SOURCE" "$HOME/Applications/LocalClaw.app" || exit 1
          INSTALLED_TO="$HOME/Applications/LocalClaw.app"
        fi

        if [ -z "$INSTALLED_TO" ] || [ ! -d "$INSTALLED_TO" ]; then
          echo "Install failed: no destination app bundle found"
          exit 1
        fi

        INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED_TO/Contents/Info.plist" 2>/dev/null || echo "?")
        INSTALLED_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED_TO/Contents/Info.plist" 2>/dev/null || echo "?")

        echo "Installed to: $INSTALLED_TO"
        echo "Installed version: $INSTALLED_VERSION (build $INSTALLED_BUILD)"

        echo ""
        echo "Restarting LocalClaw..."
        osascript -e 'tell application "LocalClaw" to quit' >/dev/null 2>&1 || true
        sleep 1
        open "$INSTALLED_TO" || true

        echo ""
        echo "Done. LocalClaw was rebuilt and reinstalled."
        echo ""
        read -r "REPLY?Press Enter to close..."
        """

        let scriptPath = "/tmp/localclaw_update.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            _ = engine.shell("chmod +x \(scriptPath)")
            _ = engine.shell("osascript -e 'tell application \"Terminal\" to do script \"\(scriptPath)\"'")
            append("Opened Terminal for advanced Git update fallback")
        } catch {
            append("Failed to start GitHub update flow: \(error.localizedDescription)")
        }
    }

    func updateAll() {
        if isRunning { return }
        isRunning = true
        append("Running update all")
        let engine = self.engine
        Task.detached {
            _ = await self.runStep(name: "Homebrew") { engine.updateHomebrew() }
            _ = await self.runStep(name: "LM Studio") { engine.upgradeLMStudioIfInstalled() }
            _ = await self.runStep(name: "Node") { engine.upgradeNodeIfInstalled() }
            _ = await self.runStep(name: "OpenClaw") { engine.updateOpenClawIfInstalled() }
            await MainActor.run {
                self.isRunning = false
                self.refreshVersions()
                self.append("Update finished")
            }
        }
    }

    func updateOpenClawRuntime() {
        if isRunning { return }
        isRunning = true
        append("Updating OpenClaw runtime")
        let engine = self.engine
        Task.detached {
            _ = await self.runStep(name: "OpenClaw") { engine.updateOpenClawIfInstalled() }
            _ = await self.runStep(name: "Gateway Service") { engine.installGatewayService() }
            _ = await self.runStep(name: "Start Gateway") { engine.startGateway() }
            _ = await self.runStep(name: "OpenClaw Check") { engine.verifyOpenClawSetup() }
            await MainActor.run {
                self.isRunning = false
                self.refreshVersions()
                self.append("OpenClaw runtime update finished")
            }
        }
    }

    func updateDependenciesOnly() {
        if isRunning { return }
        isRunning = true
        append("Updating dependencies")
        let engine = self.engine
        Task.detached {
            _ = await self.runStep(name: "Homebrew") { engine.updateHomebrew() }
            _ = await self.runStep(name: "Node") { engine.upgradeNodeIfInstalled() }
            _ = await self.runStep(name: "LM Studio") { engine.upgradeLMStudioIfInstalled() }
            await MainActor.run {
                self.isRunning = false
                self.refreshVersions()
                self.append("Dependencies update finished")
            }
        }
    }

    func openLMStudio() { _ = engine.shell("open -a 'LM Studio' || true") }
    func openOpenClaw() { _ = engine.shell("openclaw || true") }

    func openChannelDocs() {
        _ = engine.shell("open 'https://docs.openclaw.ai/channels' || true")
    }

    func openAgentsDocs() {
        _ = engine.shell("open 'https://docs.openclaw.ai/cli/agents' || true")
    }

    func openCronDocs() {
        _ = engine.shell("open 'https://docs.openclaw.ai/cli/cron' || true")
    }

    func refreshCronJobs() {
        guard !cronJobsIsLoading else { return }
        cronJobsIsLoading = true
        cronJobsStatus = "Checking cron jobs..."
        cronJobLogs = cronJobLogs.isEmpty ? "Running cron inventory..." : cronJobLogs + "\nRunning cron inventory..."

        Task.detached {
            let engine = InstallerEngine()
            let result = engine.shell(Self.cronListInventoryCommand + " 2>&1")

            await MainActor.run {
                self.cronJobsIsLoading = false

                guard result.0 == 0,
                      let data = result.1.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.cronJobsStatus = "Could not load cron jobs"
                    self.cronJobLogs += "\nFailed to load cron jobs: \(result.1.trimmingCharacters(in: .whitespacesAndNewlines))"
                    return
                }

                let jobs = root["jobs"] as? [[String: Any]] ?? []
                let total = root["total"] as? Int ?? jobs.count
                let hasMore = root["hasMore"] as? Bool ?? false
                self.cronJobs = jobs.compactMap { Self.parseCronJob($0) }
                    .sorted {
                        if $0.enabled != $1.enabled { return $0.enabled && !$1.enabled }
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }

                let activeCount = self.cronJobs.filter(\.enabled).count
                self.cronJobsStatus = "\(activeCount) active · \(self.cronJobs.count) jobs"
                if hasMore || total > self.cronJobs.count {
                    self.cronJobLogs += "\nCron inventory refreshed, but OpenClaw returned \(self.cronJobs.count) of \(total) jobs."
                } else {
                    self.cronJobLogs += "\nCron inventory refreshed."
                }
            }
        }
    }

    nonisolated static let cronListInventoryCommand = "openclaw --no-color cron list --all --json"

    nonisolated private static func parseCronJob(_ row: [String: Any]) -> CronJobInfo? {
        guard let id = row["id"] as? String ?? row["jobId"] as? String else { return nil }
        let schedule = row["schedule"] as? [String: Any] ?? [:]
        let payload = row["payload"] as? [String: Any] ?? [:]
        let delivery = row["delivery"] as? [String: Any] ?? [:]

        let scheduleLabel: String = {
            let kind = schedule["kind"] as? String ?? row["scheduleKind"] as? String ?? "schedule"
            if let expr = schedule["expr"] as? String {
                let tz = schedule["tz"] as? String
                return tz == nil || tz == "" ? "Cron: \(expr)" : "Cron: \(expr) · \(tz!)"
            }
            if let everyMs = (schedule["everyMs"] as? Double) ?? (schedule["everyMs"] as? Int).map(Double.init) {
                return "Every \(Self.durationLabel(milliseconds: everyMs))"
            }
            if let at = schedule["at"] as? String { return "At \(at)" }
            return kind.capitalized
        }()

        let payloadLabel: String = {
            let kind = payload["kind"] as? String ?? "payload"
            if let message = payload["message"] as? String, !message.isEmpty {
                return "\(kind): \(message)"
            }
            if let text = payload["text"] as? String, !text.isEmpty {
                return "\(kind): \(text)"
            }
            return kind
        }()

        let deliveryLabel: String? = {
            guard !delivery.isEmpty else { return nil }
            let mode = delivery["mode"] as? String ?? "delivery"
            let channel = delivery["channel"] as? String
            let to = delivery["to"] as? String
            return [mode, channel, to].compactMap { $0 }.joined(separator: " / ")
        }()

        return CronJobInfo(
            id: id,
            name: row["name"] as? String ?? id,
            description: row["description"] as? String,
            enabled: row["enabled"] as? Bool ?? true,
            scheduleLabel: scheduleLabel,
            payloadLabel: payloadLabel,
            sessionTarget: row["sessionTarget"] as? String,
            nextRun: row["nextRunAt"] as? String ?? row["nextRun"] as? String,
            lastRun: row["lastRunAt"] as? String ?? row["lastRun"] as? String,
            deliveryLabel: deliveryLabel
        )
    }

    nonisolated private static func durationLabel(milliseconds: Double) -> String {
        let seconds = Int(milliseconds / 1000)
        if seconds % 86400 == 0 { return "\(seconds / 86400)d" }
        if seconds % 3600 == 0 { return "\(seconds / 3600)h" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    func resetCronJobCreator() {
        cronCreateName = ""
        cronCreateAgentID = agents.first(where: { $0.isDefault })?.id ?? "main"
        cronCreateScheduleKind = "every"
        cronCreateScheduleValue = "30m"
        cronCreateMessage = ""
        cronCreateError = ""
    }

    func prepareCronJobCreator() {
        cronCreateAgentID = agents.first(where: { $0.id == cronCreateAgentID })?.id ?? agents.first(where: { $0.isDefault })?.id ?? "main"
        showCronJobCreator = true
        if agents.isEmpty || agentsStatus == "Not loaded" {
            refreshAgents()
        }
    }

    func createCronJobFromForm() {
        let name = cronCreateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawScheduleValue = cronCreateScheduleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheduleValue = Self.normalizedCronScheduleValue(rawScheduleValue, kind: cronCreateScheduleKind)
        let message = cronCreateMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !rawScheduleValue.isEmpty, !message.isEmpty else {
            cronCreateError = "Name, schedule and message are required."
            return
        }

        cronCreateIsRunning = true
        cronCreateError = ""
        cronJobLogs = cronJobLogs.isEmpty ? "Creating cron job \(name)..." : cronJobLogs + "\nCreating cron job \(name)..."

        let scheduleFlag: String
        switch cronCreateScheduleKind {
        case "cron": scheduleFlag = "--cron"
        case "at": scheduleFlag = "--at"
        default: scheduleFlag = "--every"
        }

        let command = [
            "openclaw --no-color cron add",
            "--name \(Self.shellSingleQuote(name))",
            "--agent \(Self.shellSingleQuote(cronCreateAgentID))",
            "--message \(Self.shellSingleQuote(message))",
            "--session isolated",
            "\(scheduleFlag) \(Self.shellSingleQuote(scheduleValue))",
            "--json",
            "2>&1"
        ].joined(separator: " ")

        Task.detached {
            let engine = InstallerEngine()
            let result = engine.shell(command)
            await MainActor.run {
                self.cronCreateIsRunning = false
                let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.0 == 0 {
                    self.showCronJobCreator = false
                    self.resetCronJobCreator()
                    self.cronJobLogs += "\nCreated cron job \(name)."
                    if !output.isEmpty { self.cronJobLogs += "\n\(output)" }
                    self.refreshCronJobs()
                } else {
                    self.cronCreateError = output.isEmpty ? "Cron job creation failed." : output
                    self.cronJobLogs += "\nFailed to create cron job \(name): \(self.cronCreateError)"
                }
            }
        }
    }

    nonisolated private static func normalizedCronScheduleValue(_ value: String, kind: String) -> String {
        guard kind == "at", value.hasPrefix("+") else { return value }
        return String(value.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func openTerminalCronRemove(_ jobID: String) {
        let script = """
        #!/bin/zsh
        clear
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
        OPENCLAW_BIN="$(command -v openclaw 2>/dev/null || true)"

        echo "Remove cron job: \(jobID)"
        echo ""
        read -r "CONFIRM?Type DELETE to confirm: "
        if [ "$CONFIRM" = "DELETE" ] && [ -n "$OPENCLAW_BIN" ]; then
            "$OPENCLAW_BIN" cron rm "\(jobID)" --json
        else
            echo "Canceled."
        fi

        echo ""
        read -r "REPLY?Press Enter to close..."
        """
        let safeID = jobID.replacingOccurrences(of: "/", with: "_")
        let path = "/tmp/localclaw_cron_remove_\(safeID).sh"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        _ = engine.shell("chmod +x \(path)")
        _ = engine.shell("open -a Terminal \(path)")
        cronJobLogs = cronJobLogs.isEmpty ? "Started remove flow for \(jobID)" : cronJobLogs + "\nStarted remove flow for \(jobID)"
    }

    func runCronJobNow(_ jobID: String) {
        cronJobLogs = cronJobLogs.isEmpty ? "Running cron job \(jobID)..." : cronJobLogs + "\nRunning cron job \(jobID)..."
        let quotedID = Self.shellSingleQuote(jobID)
        Task.detached {
            let engine = InstallerEngine()
            let result = engine.shell("openclaw --no-color cron run \(quotedID) 2>&1")
            await MainActor.run {
                self.cronJobLogs += "\n\(result.1.trimmingCharacters(in: .whitespacesAndNewlines))"
                self.refreshCronJobs()
            }
        }
    }

    func refreshAgents() {
        guard !agentsIsLoading else { return }
        agentsIsLoading = true
        agentsStatus = "Checking agents..."
        agentLogs = agentLogs.isEmpty ? "Running agent inventory..." : agentLogs + "\nRunning agent inventory..."

        Task.detached {
            let engine = InstallerEngine()
            let result = engine.shell("openclaw --no-color agents list --json 2>&1")

            await MainActor.run {
                self.agentsIsLoading = false

                guard result.0 == 0,
                      let data = result.1.data(using: .utf8),
                      let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    self.agentsStatus = "Could not load agents"
                    self.agentLogs += "\nFailed to load agents: \(result.1.trimmingCharacters(in: .whitespacesAndNewlines))"
                    return
                }

                self.agents = rows.compactMap { row in
                    guard let id = row["id"] as? String else { return nil }
                    return AgentInfo(
                        id: id,
                        identityName: row["identityName"] as? String ?? id,
                        identityEmoji: row["identityEmoji"] as? String,
                        workspace: row["workspace"] as? String,
                        agentDir: row["agentDir"] as? String,
                        model: row["model"] as? String,
                        bindings: row["bindings"] as? Int ?? 0,
                        isDefault: row["isDefault"] as? Bool ?? false
                    )
                }
                .sorted {
                    if $0.isDefault != $1.isDefault { return $0.isDefault && !$1.isDefault }
                    if $0.bindings != $1.bindings { return $0.bindings > $1.bindings }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }

                let activeCount = self.agents.filter { $0.isDefault || $0.bindings > 0 }.count
                self.agentsStatus = "\(activeCount) active · \(self.agents.count) agents"
                self.agentLogs += "\nAgent inventory refreshed."
            }
        }
    }

    func openTerminalAgentCreate() {
        let script = """
        #!/bin/zsh
        clear
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
        OPENCLAW_BIN="$(command -v openclaw 2>/dev/null || true)"

        echo "=========================================="
        echo "  LocalClaw Agent Setup"
        echo "=========================================="
        echo ""

        if [ -z "$OPENCLAW_BIN" ]; then
            echo "[ERROR] openclaw command not found in PATH"
            echo "Try reinstalling OpenClaw from LocalClaw first."
        else
            read -r "AGENT_ID?Agent id, ex: sales, support, dev: "
            if [ -z "$AGENT_ID" ]; then
                echo "[ERROR] No agent id provided. Setup canceled."
            else
                DEFAULT_WORKSPACE="$HOME/.openclaw/workspaces/$AGENT_ID"
                read -r "WORKSPACE?Workspace path [$DEFAULT_WORKSPACE]: "
                WORKSPACE="${WORKSPACE:-$DEFAULT_WORKSPACE}"
                read -r "MODEL?Model id, optional: "

                mkdir -p "$WORKSPACE"
                echo ""
                if [ -n "$MODEL" ]; then
                    echo "Running: $OPENCLAW_BIN agents add $AGENT_ID --workspace $WORKSPACE --model $MODEL --non-interactive"
                    "$OPENCLAW_BIN" agents add "$AGENT_ID" --workspace "$WORKSPACE" --model "$MODEL" --non-interactive
                else
                    echo "Running: $OPENCLAW_BIN agents add $AGENT_ID --workspace $WORKSPACE --non-interactive"
                    "$OPENCLAW_BIN" agents add "$AGENT_ID" --workspace "$WORKSPACE" --non-interactive
                fi
            fi
        fi

        echo ""
        read -r "REPLY?Press Enter to close..."
        """

        let path = "/tmp/localclaw_agent_create.sh"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        _ = engine.shell("chmod +x \(path)")
        _ = engine.shell("open -a Terminal \(path)")
        agentLogs = agentLogs.isEmpty ? "Started agent creation in Terminal" : agentLogs + "\nStarted agent creation in Terminal"
    }

    func openTerminalAgentIdentity(_ agentID: String) {
        let script = """
        #!/bin/zsh
        clear
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
        OPENCLAW_BIN="$(command -v openclaw 2>/dev/null || true)"

        echo "=========================================="
        echo "  LocalClaw Agent Identity: \(agentID)"
        echo "=========================================="
        echo ""

        if [ -z "$OPENCLAW_BIN" ]; then
            echo "[ERROR] openclaw command not found in PATH"
        else
            read -r "NAME?Display name, optional: "
            read -r "EMOJI?Emoji, optional: "

            ARGS=(agents set-identity --agent "\(agentID)")
            if [ -n "$NAME" ]; then ARGS+=(--name "$NAME"); fi
            if [ -n "$EMOJI" ]; then ARGS+=(--emoji "$EMOJI"); fi

            if [ -z "$NAME" ] && [ -z "$EMOJI" ]; then
                echo "Nothing to update."
            else
                echo "Running: $OPENCLAW_BIN ${ARGS[*]}"
                "$OPENCLAW_BIN" "${ARGS[@]}"
            fi
        fi

        echo ""
        read -r "REPLY?Press Enter to close..."
        """

        let safeID = agentID.replacingOccurrences(of: "/", with: "_")
        let path = "/tmp/localclaw_agent_identity_\(safeID).sh"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        _ = engine.shell("chmod +x \(path)")
        _ = engine.shell("open -a Terminal \(path)")
        agentLogs = agentLogs.isEmpty ? "Started identity edit for \(agentID)" : agentLogs + "\nStarted identity edit for \(agentID)"
    }

    func refreshChannels() {
        guard !channelsIsLoading else { return }
        channelsIsLoading = true
        channelsStatus = "Checking channels..."
        channelSetupLogs = channelSetupLogs.isEmpty ? "Running channel inventory..." : channelSetupLogs + "\nRunning channel inventory..."

        Task.detached {
            let engine = InstallerEngine()
            let listResult = engine.shell("openclaw --no-color channels list --all --json 2>&1")
            let statusResult = engine.shell("openclaw --no-color channels status --json --probe --timeout 5000 2>&1")
            let configSnapshots = Self.configuredChannelSnapshots()

            await MainActor.run {
                self.channelsIsLoading = false

                let listRoot: [String: Any] = {
                    guard listResult.0 == 0,
                          let listData = listResult.1.data(using: .utf8),
                          let root = try? JSONSerialization.jsonObject(with: listData) as? [String: Any] else {
                        return [:]
                    }
                    return root
                }()
                let chat = listRoot["chat"] as? [String: Any] ?? [:]

                let statusRoot: [String: Any] = {
                    guard statusResult.0 == 0,
                          let data = statusResult.1.data(using: .utf8),
                          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return [:]
                    }
                    return root
                }()

                let channelLabels = statusRoot["channelLabels"] as? [String: String] ?? [:]
                let detailLabels = statusRoot["channelDetailLabels"] as? [String: String] ?? [:]
                let images = statusRoot["channelSystemImages"] as? [String: String] ?? [:]
                let channelsStatus = statusRoot["channels"] as? [String: Any] ?? [:]
                let accountStatus = statusRoot["channelAccounts"] as? [String: Any] ?? [:]

                let catalog = Dictionary(uniqueKeysWithValues: Self.defaultChannelCatalog.map { ($0.id, $0) })
                let allChannelIDs = Set(Self.defaultChannelCatalog.map(\.id))
                    .union(chat.keys)
                    .union(channelsStatus.keys)
                    .union(accountStatus.keys)
                    .union(configSnapshots.keys)

                self.channels = allChannelIDs.compactMap { key in
                    let item = chat[key] as? [String: Any] ?? [:]
                    let catalogItem = catalog[key]
                    let configSnapshot = configSnapshots[key]
                    let listAccounts = item["accounts"] as? [String] ?? []
                    let installed = item["installed"] as? Bool ?? false
                    let origin = item["origin"] as? String ?? catalogItem?.origin ?? "OpenClaw channel"
                    let status = channelsStatus[key] as? [String: Any] ?? [:]
                    let running = status["running"] as? Bool ?? false
                    let channelLastError = status["lastError"] as? String
                    let probe = status["probe"] as? [String: Any]

                    let accountItems = accountStatus[key] as? [[String: Any]] ?? []
                    let primaryAccount = accountItems.first
                    let statusConfigured = status["configured"] as? Bool
                    let accountConfigured = primaryAccount?["configured"] as? Bool
                    let accounts = listAccounts.isEmpty ? (configSnapshot?.accounts ?? []) : listAccounts
                    let configured = statusConfigured ?? accountConfigured ?? (configSnapshot?.configured ?? !accounts.isEmpty)
                    let connected = primaryAccount?["connected"] as? Bool ?? false
                    let tokenStatus = primaryAccount?["tokenStatus"] as? String
                    let tokenSource = (primaryAccount?["tokenSource"] as? String) ?? (status["tokenSource"] as? String) ?? configSnapshot?.tokenSource
                    let lastError = (primaryAccount?["lastError"] as? String) ?? channelLastError
                    let accountProbe = primaryAccount?["probe"] as? [String: Any]
                    let probeOK = (accountProbe?["ok"] as? Bool) ?? (probe?["ok"] as? Bool)
                    let bot = (primaryAccount?["bot"] as? [String: Any]) ?? (probe?["bot"] as? [String: Any])
                    let botUsername = bot?["username"] as? String
                    let lastActivityRaw = (primaryAccount?["lastTransportActivityAt"] as? Double) ?? (primaryAccount?["lastEventAt"] as? Double)

                    return ChannelInfo(
                        id: key,
                        label: channelLabels[key] ?? catalogItem?.label ?? Self.humanChannelLabel(key),
                        detailLabel: detailLabels[key] ?? catalogItem?.detailLabel ?? Self.channelDetailLabel(id: key, origin: origin),
                        systemImage: images[key] ?? catalogItem?.systemImage ?? "bubble.left.and.bubble.right",
                        installed: installed || configured,
                        configured: configured,
                        running: running,
                        connected: connected,
                        accounts: accounts,
                        origin: origin,
                        tokenStatus: tokenStatus,
                        tokenSource: tokenSource,
                        lastError: lastError,
                        probeOK: probeOK,
                        botUsername: botUsername,
                        lastActivity: Self.relativeMillis(lastActivityRaw)
                    )
                }
                .sorted {
                    if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
                    if $0.configured != $1.configured { return $0.configured && !$1.configured }
                    let leftRank = Self.channelSortRank($0.id)
                    let rightRank = Self.channelSortRank($1.id)
                    if leftRank != rightRank { return leftRank < rightRank }
                    if $0.installed != $1.installed { return $0.installed && !$1.installed }
                    return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
                }

                let activeCount = self.channels.filter { $0.isActive }.count
                let configuredCount = self.channels.filter { $0.configured }.count
                self.channelsStatus = "\(activeCount) active · \(configuredCount) configured · \(self.channels.count) available"
                self.channelSetupLogs += "\nChannel inventory refreshed."
            }
        }
    }

    nonisolated private static func relativeMillis(_ millis: Double?) -> String? {
        guard let millis, millis > 0 else { return nil }
        let date = Date(timeIntervalSince1970: millis / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func openTerminalChannelLogin(_ channel: String) {
        let setupFlow: String

        if channel == "telegram" {
            setupFlow = """
            echo "Telegram setup has 2 required steps:"
            echo "  1) Add the bot token from @BotFather."
            echo "  2) Approve your Telegram user with OpenClaw pairing."
            echo ""
            echo "Step 1/2 - Bot token"
            echo "Enabling Telegram plugin..."
            "$OPENCLAW_BIN" plugins enable telegram >/dev/null 2>&1 || "$OPENCLAW_BIN" plugins enable @openclaw/telegram >/dev/null 2>&1 || true
            echo ""
            read -r "TELEGRAM_TOKEN?Paste Telegram bot token: "
            echo ""

            if [ -z "$TELEGRAM_TOKEN" ]; then
                echo "[ERROR] No token provided. Setup canceled."
            else
                echo "Running: $OPENCLAW_BIN channels add --channel telegram --token <hidden>"
                echo ""
                "$OPENCLAW_BIN" channels add --channel telegram --token "$TELEGRAM_TOKEN"
                ADD_EXIT=$?
                echo ""
                if [ "$ADD_EXIT" -eq 0 ]; then
                    echo "Restarting OpenClaw Gateway so Telegram starts listening..."
                    "$OPENCLAW_BIN" gateway restart || true
                    sleep 3
                    echo ""
                    echo "Checking Telegram channel status..."
                    "$OPENCLAW_BIN" channels status --channel telegram --probe --timeout 5000 || "$OPENCLAW_BIN" channels status --probe --timeout 5000 || true
                    echo ""
                    echo "Step 2/2 - Pairing approve"
                    echo "In Telegram, send /start to your bot. OpenClaw should reply with a pairing code."
                    echo "Paste that pairing code here to approve this Telegram user."
                    echo ""
                    "$OPENCLAW_BIN" pairing list --channel telegram || true
                    echo ""
                    read -r "PAIRING_CODE?Paste Telegram pairing code (or press Enter to skip for now): "
                    echo ""
                    if [ -z "$PAIRING_CODE" ]; then
                        echo "[WARNING] Pairing approval skipped."
                        echo "Telegram is configured, but OpenClaw may ignore messages until you approve pairing."
                        echo "Later command: $OPENCLAW_BIN pairing approve --channel telegram <code> --notify"
                    else
                        echo "Approving Telegram pairing code..."
                        "$OPENCLAW_BIN" pairing approve --channel telegram "$PAIRING_CODE" --notify
                        APPROVE_EXIT=$?
                        echo ""
                        if [ "$APPROVE_EXIT" -eq 0 ]; then
                            echo "Telegram pairing approved. Send another message to the bot to test replies."
                        else
                            echo "[ERROR] Pairing approval failed with exit code $APPROVE_EXIT."
                            exit "$APPROVE_EXIT"
                        fi
                    fi
                else
                    echo "[ERROR] Telegram setup failed with exit code $ADD_EXIT."
                    exit "$ADD_EXIT"
                fi
            fi
            """
        } else if channel == "discord" {
            setupFlow = """
            echo "Discord setup requires your bot token (from Discord Developer Portal)."
            echo ""
            echo "Enabling Discord plugin..."
            "$OPENCLAW_BIN" plugins enable discord >/dev/null 2>&1 || "$OPENCLAW_BIN" plugins enable @openclaw/discord >/dev/null 2>&1 || true
            echo ""
            read -r "DISCORD_TOKEN?Paste Discord bot token: "
            echo ""

            if [ -z "$DISCORD_TOKEN" ]; then
                echo "[ERROR] No token provided. Setup canceled."
            else
                echo "Running: $OPENCLAW_BIN channels add --channel discord --token <hidden>"
                echo ""
                "$OPENCLAW_BIN" channels add --channel discord --token "$DISCORD_TOKEN"
                ADD_EXIT=$?
                echo ""
                if [ "$ADD_EXIT" -eq 0 ]; then
                    echo "Restarting OpenClaw Gateway so Discord starts listening..."
                    "$OPENCLAW_BIN" gateway restart || true
                    sleep 3
                    echo ""
                    echo "Checking Discord channel status..."
                    "$OPENCLAW_BIN" channels status --channel discord --probe --timeout 5000 || "$OPENCLAW_BIN" channels status --probe --timeout 5000 || true
                else
                    echo "[ERROR] Discord setup failed with exit code $ADD_EXIT."
                    exit "$ADD_EXIT"
                fi
            fi
            """
        } else if channel == "whatsapp" {
            setupFlow = """
            echo "WhatsApp setup opens QR login."
            echo "In WhatsApp mobile: Settings > Linked Devices > Link a Device."
            echo ""

            WHATSAPP_PLUGIN_PATH="/opt/homebrew/lib/node_modules/openclaw/dist/extensions/whatsapp"
            if [ -d "$WHATSAPP_PLUGIN_PATH" ]; then
                echo "Installing WhatsApp plugin from local path (non-interactive)..."
                "$OPENCLAW_BIN" plugins install "$WHATSAPP_PLUGIN_PATH" >/dev/null 2>&1 || true
                echo ""
            fi
            "$OPENCLAW_BIN" plugins enable whatsapp >/dev/null 2>&1 || "$OPENCLAW_BIN" plugins enable @openclaw/whatsapp >/dev/null 2>&1 || true

            echo "Running: $OPENCLAW_BIN channels add --channel whatsapp"
            "$OPENCLAW_BIN" channels add --channel whatsapp >/dev/null 2>&1 || true
            echo ""
            echo "Running: $OPENCLAW_BIN channels login --channel whatsapp"
            echo ""
            "$OPENCLAW_BIN" channels login --channel whatsapp
            echo ""
            echo "Restarting OpenClaw Gateway so WhatsApp starts listening..."
            "$OPENCLAW_BIN" gateway restart || true
            sleep 3
            "$OPENCLAW_BIN" channels status --channel whatsapp --probe --timeout 5000 || "$OPENCLAW_BIN" channels status --probe --timeout 5000 || true
            """
        } else {
            setupFlow = """
            echo "Opening guided setup for \(channel)."
            echo "If this channel is not installed yet, OpenClaw will prepare the connector first."
            echo ""
            echo "Enabling plugin for \(channel) if available..."
            "$OPENCLAW_BIN" plugins enable \(channel) >/dev/null 2>&1 || true
            echo ""
            echo "Running: $OPENCLAW_BIN channels add --channel \(channel)"
            echo ""
            "$OPENCLAW_BIN" channels add --channel \(channel)
            ADD_EXIT=$?
            echo ""
            if [ "$ADD_EXIT" -eq 0 ]; then
                echo "Checking whether this channel has a login flow..."
                "$OPENCLAW_BIN" channels login --channel \(channel) || true
                echo ""
                echo "Restarting OpenClaw Gateway so \(channel) starts listening..."
                "$OPENCLAW_BIN" gateway restart || true
                sleep 3
                "$OPENCLAW_BIN" channels status --channel \(channel) --probe --timeout 5000 || "$OPENCLAW_BIN" channels status --probe --timeout 5000 || true
            else
                echo "[ERROR] Channel setup failed with exit code $ADD_EXIT."
                exit "$ADD_EXIT"
            fi
            """
        }

        let script = """
        #!/bin/zsh
        clear

        # Ensure common Homebrew + user paths are available in non-login shells
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

        OPENCLAW_BIN="$(command -v openclaw 2>/dev/null || true)"

        echo "=========================================="
        echo "  LocalClaw Channel Setup: \(channel.capitalized)"
        echo "=========================================="
        echo ""

        if [ -z "$OPENCLAW_BIN" ]; then
            echo "[ERROR] openclaw command not found in PATH"
            echo "Try restarting Terminal or reinstalling OpenClaw from Install tab."
            echo ""
        else
        \(setupFlow)
            echo ""
            echo "If setup is done, test with:"
            echo "$OPENCLAW_BIN message send --channel \(channel) --message \"LocalClaw test\""
            echo ""
        fi

        read -r "REPLY?Press Enter to close..."
        """

        let path = "/tmp/localclaw_channel_\(channel).sh"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        _ = engine.shell("chmod +x \(path)")
        _ = engine.shell("open -a Terminal \(path)")

        channelSetupLogs = channelSetupLogs.isEmpty ? "Started \(channel) setup in Terminal" : channelSetupLogs + "\nStarted \(channel) setup in Terminal"
    }

    func applyAgentTemplate(_ template: String) {
        switch template {
        case "founder":
            inferenceMode = .cloud
            selectedProvider = .openRouter
            selectedOpenRouterModel = "openrouter/openai/gpt-5-mini"
            _ = engine.writeModelToConfig(modelIdentifier: selectedOpenRouterModel)
            agentLogs = "Applied legacy Founder preset: GPT-5 Mini + Cloud LLM"
        case "support":
            inferenceMode = .cloud
            selectedProvider = .openRouter
            selectedOpenRouterModel = "openrouter/google/gemini-2.5-flash-preview"
            _ = engine.writeModelToConfig(modelIdentifier: selectedOpenRouterModel)
            agentLogs = "Applied legacy Support preset: Gemini 2.5 Flash + Cloud LLM"
        case "growth":
            inferenceMode = .cloud
            selectedProvider = .openRouter
            selectedOpenRouterModel = "openrouter/openai/gpt-4o-mini"
            _ = engine.writeModelToConfig(modelIdentifier: selectedOpenRouterModel)
            agentLogs = "Applied legacy Growth preset: GPT-4o Mini + Cloud LLM"
        case "dev":
            inferenceMode = .local
            selectedModel = !recommendation.isEmpty ? recommendation : (modelOptions.first ?? "")
            if let localId = localProviderModelIds[selectedModel] {
                _ = engine.writeModelToConfig(modelIdentifier: "lmstudio/\(localId)")
            }
            agentLogs = "Applied legacy Dev preset: local \(selectedModel)"
        default:
            agentLogs = "Unknown legacy preset"
        }

        _ = engine.shell("openclaw gateway restart --preserve-token 2>/dev/null || openclaw gateway restart 2>/dev/null || true")
        refreshControlCenter()
    }

    private func ensureLMStudioAuthProfileForMainAgent() {
        let path = NSHomeDirectory() + "/.openclaw/agents/main/agent/auth-profiles.json"
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var root: [String: Any] = ["version": 1, "profiles": [:]]
        if let data = FileManager.default.contents(atPath: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        }

        var profiles = root["profiles"] as? [String: Any] ?? [:]
        profiles["lmstudio"] = ["provider": "lmstudio", "type": "api_key", "key": "lm-studio"]
        root["profiles"] = profiles
        if root["version"] == nil { root["version"] = 1 }

        if let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    private func detectLiveLMStudioModelId() -> String {
        let cmd = "curl -s http://127.0.0.1:1234/v1/models 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); m=(d.get('data') or []); print((m[0].get('id') if m else ''))\" 2>/dev/null || true"
        let (_, out) = engine.shell(cmd)
        return out.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private func localModelMatch(_ rawId: String, in models: [String]) -> String {
        var id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("lmstudio/") {
            id = String(id.dropFirst("lmstudio/".count))
        }
        guard !id.isEmpty else { return "" }
        if models.contains(id) { return id }
        if let match = models.first(where: { $0.hasSuffix("/\(id)") || $0.hasSuffix(id) }) {
            return match
        }
        return ""
    }

    private func resolveLocalLMStudioModelId(preferLive: Bool = true) -> String {
        refreshLocalLMStudioModels()
        let models = localLMStudioModels

        if preferLive {
            let live = localModelMatch(detectLiveLMStudioModelId(), in: models)
            if !live.isEmpty { return live }
        }

        let selectedLocal = localModelMatch(selectedLocalLMStudioModel, in: models)
        if !selectedLocal.isEmpty { return selectedLocal }

        if currentModel.hasPrefix("lmstudio/") {
            let configured = localModelMatch(currentModel, in: models)
            if !configured.isEmpty { return configured }
        }

        if selectedModel.isEmpty {
            selectedModel = !recommendation.isEmpty ? recommendation : (modelOptions.first ?? "")
        }
        let recommended = localModelMatch(localProviderModelIds[selectedModel] ?? "", in: models)
        if !recommended.isEmpty { return recommended }

        return models.first ?? ""
    }

    private func resetMainAgentSessions() {
        let sessionsPath = NSHomeDirectory() + "/.openclaw/agents/main/sessions"
        _ = engine.shell("mkdir -p '\(sessionsPath)' && find '\(sessionsPath)' -name '*.jsonl' -type f -delete 2>/dev/null || true")
        controlCenterLogs += "[OK] Reset main agent sessions after mode switch\n"
    }

    private func writePrimaryAndSecondaryModel(primary: String, secondary: String?) {
        let path = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = FileManager.default.contents(atPath: path),
              var json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) else {
            _ = engine.writeModelToConfig(modelIdentifier: primary)
            return
        }

        var agents = json["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]
        var model = defaults["model"] as? [String: Any] ?? [:]
        model["primary"] = primary
        if let secondary, !secondary.isEmpty {
            model["secondary"] = secondary
        } else {
            model.removeValue(forKey: "secondary")
        }
        defaults["model"] = model
        agents["defaults"] = defaults
        json["agents"] = agents

        if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    func applyInferenceModeSwitch() {
        modeSwitchInProgress = true
        modeSwitchStatus = "Applying switch..."

        if inferenceMode == .local {
            selectedChatResponseMode = .local
            selectedProvider = .custom
            ensureLMStudioAuthProfileForMainAgent()
            let localId = resolveLocalLMStudioModelId()

            guard !localId.isEmpty else {
                controlCenterLogs += "[FAIL] Local switch failed: no model found in LM Studio\n"
                modeSwitchInProgress = false
                modeSwitchStatus = "No local model found"
                return
            }

            selectedLocalLMStudioModel = localId
            modeSwitchStatus = "Setting up LM Studio model..."
            controlCenterLogs += "[INFO] Setting up Local LLM: lmstudio/\(localId)\n"

            let modelId = localId
            Task.detached {
                let result = InstallerEngine().autoSetupLMStudioModel(modelId: modelId, contextLength: 32768) { message in
                    DispatchQueue.main.async {
                        self.modeSwitchStatus = message
                        self.controlCenterLogs += "[INFO] \(message)\n"
                    }
                }
                let loaded = InstallerEngine().loadedLMStudioModelInfo()?.model
                await MainActor.run {
                    if result.state == .ok {
                        let active = loaded ?? modelId
                        self.currentModel = "lmstudio/\(active)"
                        self.activeLocalLMStudioModel = active
                        self.selectedChatModel = "lmstudio/\(active)"
                        self.controlCenterLogs += "[OK] Switched to Local LLM: lmstudio/\(active)\n"
                    } else {
                        self.controlCenterLogs += "[FAIL] Local switch failed: \(result.message)\n"
                    }
                    self.resetMainAgentSessions()
                    self.refreshControlCenter()
                    self.modeSwitchInProgress = false
                    self.modeSwitchStatus = result.state == .ok ? "Switched to Local LLM" : "Local setup failed"
                }
            }
            return
        } else {
            if inferenceMode == .oauth {
                selectedProvider = .openAI
                selectedCloudAuthMode = .oauth
                openAIAuthMethod = .oauth
                writePrimaryAndSecondaryModel(primary: effectiveModelIdentifier(), secondary: nil)
                controlCenterLogs += "[OK] Switched to OAuth LLM: \(effectiveModelIdentifier())\n"
            } else {
                prepareCloudModelSelection()
                selectedProvider = .openRouter
                selectedCloudAuthMode = .api
                writePrimaryAndSecondaryModel(primary: selectedOpenRouterModel, secondary: nil)
                controlCenterLogs += "[OK] Switched to Cloud LLM: \(selectedOpenRouterModel)\n"
            }
        }

        resetMainAgentSessions()
        _ = engine.shell("openclaw gateway restart --preserve-token 2>/dev/null || openclaw gateway restart 2>/dev/null || true")
        controlCenterLogs += "[OK] Gateway restarted after mode switch\n"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.refreshControlCenter()
            self.modeSwitchInProgress = false
            switch self.inferenceMode {
            case .local:
                self.modeSwitchStatus = "Switched to Local LLM"
            case .oauth:
                self.modeSwitchStatus = "Switched to OAuth LLM"
            case .cloud:
                self.modeSwitchStatus = "Switched to Cloud LLM"
            }
        }
    }

    func runHealthCheck() {
        healthLogs = "Running health check...\n"

        let gateway = engine.getGatewayStatus()
        healthLogs += "Gateway: \(gateway.isRunning ? "Online" : "Offline")\n"

        let verify = engine.verifyOpenClawSetup()
        healthLogs += "Verify: [\(verify.state.rawValue)] \(verify.message)\n"

        let usage = engine.getSystemUsage()
        healthLogs += String(format: "CPU: %.1f%% | RAM: %.1f/%.1f GB | Swap: %.2f/%.2f GB\n", usage.cpuPercent, usage.memoryUsedGB, usage.memoryTotalGB, usage.swapUsedGB, usage.swapTotalGB)

        if verify.state == .ok && gateway.isRunning && usage.swapUsedGB < 2 {
            healthStatus = "Healthy"
        } else if usage.swapUsedGB >= 4 || verify.state == .fail {
            healthStatus = "Critical"
        } else {
            healthStatus = "Warning"
        }
    }

    func runQuickRepair() {
        healthLogs += "\nRunning quick repair...\n"
        let doctor = engine.runDoctorRepair()
        healthLogs += "Doctor: [\(doctor.state.rawValue)] \(doctor.message)\n"
        let restart = engine.restartGateway()
        healthLogs += "Gateway restart: [\(restart.state.rawValue)] \(restart.message)\n"
        runHealthCheck()
    }

    func backupOpenClawConfig() {
        let ts = Int(Date().timeIntervalSince1970)
        let src = NSHomeDirectory() + "/.openclaw/openclaw.json"
        let dst = NSHomeDirectory() + "/.openclaw/openclaw.backup.\(ts).json"
        let result = engine.shell("[ -f '\(src)' ] && cp '\(src)' '\(dst)' && echo '\(dst)' || echo 'missing config'")
        healthLogs += "Backup: \(result.1)\n"
    }

    func refreshUsageCostEstimate() {
        // Simple blended estimate ($ per 1M tokens) by current model family
        let model = selectedOpenRouterModel.lowercased()
        let ratePerMillion: Double
        if model.contains("gpt-4") || model.contains("claude") { ratePerMillion = 8.0 }
        else if model.contains("gemini") || model.contains("kimi") || model.contains("qwen") { ratePerMillion = 2.5 }
        else { ratePerMillion = 1.5 }

        estimatedMonthlyCostUSD = estimatedMonthlyTokensM * ratePerMillion

        if estimatedMonthlyCostUSD <= 10 {
            costAdvice = "Cost is low. Current setup is efficient."
        } else if estimatedMonthlyCostUSD <= 50 {
            costAdvice = "Cost is moderate. Consider cheaper model for low-value tasks."
        } else {
            costAdvice = "Cost is high. Route routine tasks to a cheaper model and keep premium models for high-value prompts."
        }

        usageLogs = String(format: "Estimated %.1fM tokens/month at $%.2f/M => $%.2f", estimatedMonthlyTokensM, ratePerMillion, estimatedMonthlyCostUSD)
    }

    func openDashboard() { 
        // Reload token from config first to ensure we have the latest (gateway install may have regenerated it)
        loadTokenFromConfig()
        _ = engine.openDashboard() 
    }

    func openOpenClawChat() {
        if selectedChatSessionID.isEmpty, let first = chatSessions.first?.id {
            selectedChatSessionID = first
        }
        screen = .chat
    }

    func restoreChatSessions() {
        restoreChatProjects()
        if let data = UserDefaults.standard.data(forKey: Self.chatSessionsDefaultsKey),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data),
           !decoded.isEmpty {
            chatSessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
        let savedID = UserDefaults.standard.string(forKey: Self.selectedChatSessionDefaultsKey) ?? ""
        selectedChatSessionID = chatSessions.contains(where: { $0.id == savedID }) ? savedID : (chatSessions.first?.id ?? "")
    }

    func persistChatSessions() {
        guard let data = try? JSONEncoder().encode(chatSessions) else { return }
        UserDefaults.standard.set(data, forKey: Self.chatSessionsDefaultsKey)
    }

    func restoreChatProjects() {
        guard let data = UserDefaults.standard.data(forKey: Self.chatProjectsDefaultsKey),
              let decoded = try? JSONDecoder().decode([ChatProject].self, from: data) else { return }
        chatProjects = decoded.sorted { $0.createdAt < $1.createdAt }
        expandedChatProjectIDs = Set(chatProjects.map(\.id))
    }

    func persistChatProjects() {
        guard let data = try? JSONEncoder().encode(chatProjects) else { return }
        UserDefaults.standard.set(data, forKey: Self.chatProjectsDefaultsKey)
    }

    func restoreChatSavedNotes() {
        guard let data = UserDefaults.standard.data(forKey: Self.chatSavedNotesDefaultsKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        chatSavedNotes = decoded
    }

    func persistChatSavedNotes() {
        guard let data = try? JSONEncoder().encode(chatSavedNotes) else { return }
        UserDefaults.standard.set(data, forKey: Self.chatSavedNotesDefaultsKey)
    }

    func restoreModelUsageRecords() {
        guard let data = UserDefaults.standard.data(forKey: Self.modelUsageDefaultsKey),
              let decoded = try? JSONDecoder().decode([ModelUsageRecord].self, from: data) else { return }
        modelUsageRecords = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    func persistModelUsageRecords() {
        guard let data = try? JSONEncoder().encode(modelUsageRecords) else { return }
        UserDefaults.standard.set(data, forKey: Self.modelUsageDefaultsKey)
    }

    func recordModelUsage(model: String, input: Int?, output: Int?, total: Int?) {
        guard tokenMonitoringEnabled else { return }
        let inputTokens = input ?? 0
        let outputTokens = output ?? 0
        let totalTokens = total ?? inputTokens + outputTokens
        guard totalTokens > 0 else { return }
        let cost = Self.estimateUsageCostUSD(model: model, totalTokens: totalTokens)
        modelUsageRecords.insert(ModelUsageRecord(model: model, inputTokens: inputTokens, outputTokens: outputTokens, totalTokens: totalTokens, estimatedCostUSD: cost), at: 0)
        modelUsageRecords = Array(modelUsageRecords.prefix(200))
    }

    nonisolated private static func estimateUsageCostUSD(model: String, totalTokens: Int) -> Double {
        let lower = model.lowercased()
        let ratePerMillion: Double
        if lower.contains("lmstudio") || lower.contains("local") { ratePerMillion = 0 }
        else if lower.contains("kimi") || lower.contains("haiku") || lower.contains("mini") { ratePerMillion = 2.5 }
        else if lower.contains("opus") || lower.contains("gpt-4") { ratePerMillion = 15 }
        else { ratePerMillion = 5 }
        return Double(totalTokens) / 1_000_000 * ratePerMillion
    }

    func updateSelectedChatSession(_ mutate: (inout ChatSession) -> Void) {
        let id = activeChatSessionID
        guard let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&chatSessions[index])
        chatSessions[index].updatedAt = Date()
    }

    var activeDeveloperChatSessionID: String {
        if !selectedDeveloperChatSessionID.isEmpty, chatSessions.contains(where: { $0.id == selectedDeveloperChatSessionID }) {
            return selectedDeveloperChatSessionID
        }
        return chatSessions.first(where: { $0.id.hasPrefix("localclaw-developer-chat-") })?.id ?? ""
    }

    var developerChatMessages: [ChatMessage] {
        get {
            guard let session = chatSessions.first(where: { $0.id == activeDeveloperChatSessionID }) else { return [] }
            return session.messages
        }
        set {
            ensureDeveloperChatSession()
            let id = activeDeveloperChatSessionID
            guard let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
            chatSessions[index].messages = newValue
            chatSessions[index].updatedAt = Date()
        }
    }

    func ensureDeveloperChatSession() {
        if !activeDeveloperChatSessionID.isEmpty {
            if selectedDeveloperChatSessionID.isEmpty { selectedDeveloperChatSessionID = activeDeveloperChatSessionID }
            return
        }
        let session = ChatSession.developerFresh()
        chatSessions.insert(session, at: 0)
        selectedDeveloperChatSessionID = session.id
    }

    func updateDeveloperChatSession(_ mutate: (inout ChatSession) -> Void) {
        ensureDeveloperChatSession()
        let id = activeDeveloperChatSessionID
        guard let index = chatSessions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&chatSessions[index])
        chatSessions[index].updatedAt = Date()
    }

    func newChatSession() {
        var session = ChatSession.fresh()
        session.title = "Discussion \(chatSessions.count + 1)"
        chatSessions.insert(session, at: 0)
        selectedChatSessionID = session.id
        chatInput = ""
        chatStatus = "Ready"
    }

    func newChatProject() {
        let project = ChatProject.fresh(index: chatProjects.count + 1)
        chatProjects.append(project)
        expandedChatProjectIDs.insert(project.id)
        editingChatProjectID = project.id
        editingChatProjectTitle = project.title
    }

    func toggleChatProject(_ project: ChatProject) {
        if expandedChatProjectIDs.contains(project.id) {
            expandedChatProjectIDs.remove(project.id)
        } else {
            expandedChatProjectIDs.insert(project.id)
        }
    }

    func chatSessions(in project: ChatProject) -> [ChatSession] {
        chatSessions.filter { $0.projectID == project.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var unfiledChatSessions: [ChatSession] {
        chatSessions.filter { session in
            guard let projectID = session.projectID, !projectID.isEmpty else { return true }
            return !chatProjects.contains { $0.id == projectID }
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func moveChatSession(_ sessionID: String, toProjectID projectID: String?) {
        guard let index = chatSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        chatSessions[index].projectID = projectID
        chatSessions[index].updatedAt = Date()
        if let projectID {
            expandedChatProjectIDs.insert(projectID)
        }
    }

    func beginEditingChatProject(_ project: ChatProject) {
        editingChatProjectID = project.id
        editingChatProjectTitle = project.title
    }

    func commitEditingChatProject() {
        let title = editingChatProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !editingChatProjectID.isEmpty, !title.isEmpty,
              let index = chatProjects.firstIndex(where: { $0.id == editingChatProjectID }) else {
            editingChatProjectID = ""
            editingChatProjectTitle = ""
            return
        }
        chatProjects[index].title = String(title.prefix(40))
        editingChatProjectID = ""
        editingChatProjectTitle = ""
    }

    func updateChatProjectStyle(_ projectID: String, icon: String? = nil, colorName: String? = nil) {
        guard let index = chatProjects.firstIndex(where: { $0.id == projectID }) else { return }
        if let icon { chatProjects[index].icon = icon }
        if let colorName { chatProjects[index].colorName = colorName }
    }

    func chatProjectContext(for sessionID: String) -> String {
        guard let session = chatSessions.first(where: { $0.id == sessionID }),
              let projectID = session.projectID,
              let project = chatProjects.first(where: { $0.id == projectID }) else { return "" }

        let siblings = chatSessions
            .filter { $0.projectID == projectID && $0.id != sessionID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)

        var lines = [
            "Project context: \(project.title)",
            "The current chat belongs to this LocalClaw project. Treat chats in the same project as related work."
        ]

        for sibling in siblings {
            let lastUseful = sibling.messages.reversed().first { $0.role == "user" || $0.role == "assistant" }?.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if lastUseful.isEmpty {
                lines.append("- \(sibling.title)")
            } else {
                lines.append("- \(sibling.title): \(String(lastUseful.prefix(180)))")
            }
        }

        return lines.joined(separator: "\n")
    }

    var chatMemoryPreview: [String] {
        var notes = chatSavedNotes
        if let session = selectedChatSession {
            let recent = session.messages
                .filter { $0.role == "user" || $0.role == "assistant" }
                .suffix(4)
                .map { message in
                    let cleaned = message.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    return "\(message.role == "user" ? "You" : "OpenClaw"): \(String(cleaned.prefix(110)))"
                }
            notes.append(contentsOf: recent)
        }
        return Array(notes.suffix(6))
    }

    var developerMemoryPreview: [String] {
        let recent = developerChatMessages
            .filter { $0.role == "user" || $0.role == "assistant" }
            .suffix(4)
            .map { message in
                let cleaned = message.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(message.role == "user" ? "User" : "OpenClaw"): \(String(cleaned.prefix(140)))"
            }
        return Array(recent)
    }

    func chatModeInstruction() -> String {
        switch selectedChatResponseMode {
        case .fast:
            return "Reply in Fast mode: be concise, prioritize direct next actions, avoid long explanations unless necessary."
        case .deep:
            return "Reply in Deep mode: reason carefully, surface tradeoffs, and verify assumptions before giving a final recommendation."
        case .local:
            return "Reply in Local mode: prefer local/offline-safe guidance and avoid recommending cloud-only steps unless needed."
        case .cloud:
            return "Reply in Cloud mode: use the configured cloud model and optimize for answer quality."
        }
    }

    func retryChatMessage(_ message: ChatMessage) {
        guard !chatIsSending else { return }
        if message.role == "assistant" || message.role == "error" {
            chatMessages.removeAll { $0.id == message.id }
            guard let lastUser = chatMessages.last(where: { $0.role == "user" }) else { return }
            chatInput = lastUser.text
            chatImagePath = lastUser.imagePath ?? ""
            chatMessages.removeAll { $0.id == lastUser.id }
            sendChatMessage()
        } else {
            chatInput = message.text
            chatImagePath = message.imagePath ?? ""
        }
    }

    func editChatMessage(_ message: ChatMessage) {
        guard !chatIsSending else { return }
        chatInput = message.text
        chatImagePath = message.imagePath ?? ""
    }

    func saveChatMessageAsNote(_ message: ChatMessage) {
        let cleaned = message.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let note = String(cleaned.prefix(220))
        if !chatSavedNotes.contains(note) {
            chatSavedNotes.append(note)
        }
        appendChatSystemMessageOnce("Saved to chat memory.")
    }

    func forgetChatMemory() {
        chatSavedNotes.removeAll()
        appendChatSystemMessageOnce("Chat memory notes cleared.")
    }

    func sendChatMessageToChannel(_ message: ChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        screen = .channelSetup
        appendChatSystemMessageOnce("Message copied. Pick a connected channel to send it.")
    }

    func selectChatSession(_ session: ChatSession) {
        selectedChatSessionID = session.id
        chatInput = ""
        chatStatus = "Ready"
    }

    func deleteSelectedChatSession() {
        let id = activeChatSessionID
        guard chatSessions.count > 1 else {
            chatSessions = [ChatSession.fresh(title: "Main setup")]
            selectedChatSessionID = chatSessions[0].id
            return
        }
        chatSessions.removeAll { $0.id == id }
        selectedChatSessionID = chatSessions.first?.id ?? ""
    }

    func renameSelectedChatSession(from firstUserMessage: String) {
        updateSelectedChatSession { session in
            if session.title.hasPrefix("Discussion") || session.title == "New discussion" || session.title == "Main setup" {
                let compact = firstUserMessage.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                session.title = String(compact.prefix(34)) + (compact.count > 34 ? "…" : "")
                session.subtitle = openClawChatModeLabel
            }
        }
    }

    func sendChatMessage() {
        sendChatMessage(sessionID: activeChatSessionID, useDeveloperSession: false)
    }

    func sendDeveloperChatMessage() {
        ensureDeveloperChatSession()
        sendChatMessage(sessionID: activeDeveloperChatSessionID, useDeveloperSession: true)
    }

    private func sendChatMessage(sessionID: String, useDeveloperSession: Bool) {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagePath = chatImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if (text.isEmpty && imagePath.isEmpty) || chatIsSending { return }

        chatInput = ""
        chatImagePath = ""
        chatStopRequested = false
        let requestID = UUID()
        activeChatRequestID = requestID
        let userText = text.isEmpty ? "Image attached" : text
        let targetSessionID = useDeveloperSession ? sessionID : activeChatSessionID
        let projectContext = chatProjectContext(for: targetSessionID)
        var agentTextParts: [String] = []
        if !projectContext.isEmpty {
            agentTextParts.append("""
            [LocalClaw project context]
            \(projectContext)
            [/LocalClaw project context]
            """)
        }
        if useDeveloperSession {
            agentTextParts.append("""
            [LocalClaw developer workspace]
            You are coding inside this local project folder:
            \(developerProjectPath)

            Make concrete file edits in that folder when the user asks to build, fix, or improve the app.
            Keep the app runnable from this folder and make sure the preview can be served by the existing package scripts.
            After code changes, mention the changed files and any command needed only if LocalClaw cannot run it automatically.
            [/LocalClaw developer workspace]
            """)
            if Self.isSimpleDeveloperEdit(text) {
                agentTextParts.append("""
                [LocalClaw developer speed rule]
                This is a small targeted edit. Inspect only the likely files, make the smallest change, skip broad project scans, and do not run package installs or long dev servers unless the user explicitly asks.
                [/LocalClaw developer speed rule]
                """)
            }
        }
        agentTextParts.append("""
        [LocalClaw chat mode]
        \(chatModeInstruction())
        [/LocalClaw chat mode]
        """)
        if chatMemoryEnabled {
            let memory = (useDeveloperSession ? developerMemoryPreview : chatMemoryPreview).joined(separator: "\n")
            if !memory.isEmpty {
                agentTextParts.append("""
                [LocalClaw visible memory]
                \(memory)
                [/LocalClaw visible memory]
                """)
            }
        }
        agentTextParts.append(imagePath.isEmpty ? text : "\(userText)\n\n[Attached image: \(imagePath)]")
        let agentText = agentTextParts.joined(separator: "\n\n")
        if useDeveloperSession {
            developerChatMessages.append(ChatMessage(role: "user", text: userText, imagePath: imagePath.isEmpty ? nil : imagePath))
            updateDeveloperChatSession { session in
                if session.title == "Developer workspace" {
                    let compact = userText.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    session.title = String(compact.prefix(34)) + (compact.count > 34 ? "…" : "")
                }
            }
        } else {
            chatMessages.append(ChatMessage(role: "user", text: userText, imagePath: imagePath.isEmpty ? nil : imagePath))
            renameSelectedChatSession(from: userText)
        }
        if useDeveloperSession,
           imagePath.isEmpty,
           let quickEdit = Self.applyQuickDeveloperColorEdit(projectPath: developerProjectPath, requestText: text) {
            let files = quickEdit.changedFiles.prefix(5).joined(separator: ", ")
            let suffix = quickEdit.changedFiles.count > 5 ? " and \(quickEdit.changedFiles.count - 5) more" : ""
            let reply = "Applied the \(quickEdit.colorName) theme directly in \(quickEdit.changedFiles.count) file\(quickEdit.changedFiles.count == 1 ? "" : "s"): \(files)\(suffix)."
            developerChatMessages.append(ChatMessage(role: "assistant", text: reply, metadata: "local quick edit • no model call", modelName: "LocalClaw"))
            developerPreviewRefreshID = UUID()
            developerActiveTab = "preview"
            if developerPreviewProcess != nil {
                developerPreviewStatus = "Preview refreshed after quick edit"
            } else {
                developerPreviewStatus = "Quick edit applied. Run preview to view it."
            }
            chatStatus = "Ready"
            return
        }
        chatIsSending = true
        chatStatus = "Thinking..."
        let shouldPrepareGateway = !chatGatewayPrepared
        chatGatewayPrepared = true
        var selectedModelForRequest = selectedChatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedChatResponseMode == .fast, inferenceMode == .cloud {
            selectedModelForRequest = "openrouter/openai/gpt-5.4-mini"
        } else if selectedChatResponseMode == .deep, inferenceMode == .cloud {
            selectedModelForRequest = "openrouter/openai/gpt-5.4"
        } else if selectedChatResponseMode == .local {
            if selectedModelForRequest.hasPrefix("lmstudio/") || localLMStudioModels.contains(selectedModelForRequest) {
                // Keep the local model chosen in the picker.
            } else if let firstLocal = localLMStudioModels.first, !firstLocal.isEmpty {
                selectedModelForRequest = "lmstudio/\(firstLocal)"
            }
        }
        let selectedModelLooksLocal = selectedModelForRequest.hasPrefix("lmstudio/") || localLMStudioModels.contains(selectedModelForRequest)
        let selectedModelLooksCloud = selectedModelForRequest.hasPrefix("openrouter/")
        let requestInferenceMode: InferenceMode
        if selectedModelLooksLocal {
            requestInferenceMode = .local
        } else if selectedModelLooksCloud {
            requestInferenceMode = .cloud
        } else {
            requestInferenceMode = selectedChatResponseMode == .local ? .local : (selectedChatResponseMode == .cloud ? .cloud : inferenceMode)
        }
        let modelOverride = Self.canonicalChatRuntimeModelID(Self.normalizedChatModelID(
            selectedModelForRequest,
            inferenceMode: requestInferenceMode,
            localModels: localLMStudioModels
        ))
        if selectedModelLooksLocal && !localLMStudioModelIsReady(modelOverride) {
            let localModel = Self.localLMStudioModelID(from: modelOverride)
            if !localModel.isEmpty {
                selectedLocalLMStudioModel = localModel
                autoSetupLocalLMStudioModel(modelId: localModel, source: useDeveloperSession ? .developer : .chat)
            }
            let setupText = localLMStudioSetupInProgress
                ? "Local model setup is already running. Send again when the status is Ready."
                : "Local model setup started. Send again when the status is Ready."
            let setupMessage = ChatMessage(role: "assistant", text: setupText, metadata: "local setup • no model call", modelName: "LocalClaw")
            if useDeveloperSession { developerChatMessages.append(setupMessage) } else { chatMessages.append(setupMessage) }
            chatStatus = "Setting up local model..."
            return
        }
        let developerWorkdir = developerProjectPath
        let useFreshDeveloperContext = useDeveloperSession && developerFreshContextEnabled
        let isSimpleDeveloperEdit = useDeveloperSession && Self.isSimpleDeveloperEdit(text)
        let agentThinking = isSimpleDeveloperEdit ? "low" : Self.agentThinkingLevel(for: selectedChatResponseMode)
        let agentTimeout = isSimpleDeveloperEdit ? Self.simpleDeveloperEditTimeoutSeconds : Self.agentTimeoutSeconds(for: selectedChatResponseMode, useDeveloperSession: useDeveloperSession)
        let wallClockTimeout = Self.wallClockTimeoutSeconds(forAgentTimeout: agentTimeout)

        Task.detached {
            let quote: (String) -> String = { value in
                "'" + value.replacingOccurrences(of: "'", with: "'\''") + "'"
            }
            let engine = InstallerEngine()
            if shouldPrepareGateway {
                await MainActor.run {
                    if self.activeChatRequestID == requestID {
                        self.chatStatus = "Preparing OpenClaw..."
                    }
                }
                _ = engine.shell("openclaw gateway status >/dev/null 2>&1 || openclaw gateway start >/dev/null 2>&1 || true")
            }

            let tempMessagePath = NSTemporaryDirectory() + "localclaw-chat-message-\(UUID().uuidString).txt"
            do {
                try agentText.write(toFile: tempMessagePath, atomically: true, encoding: .utf8)
            } catch {
                await MainActor.run {
                    let errorMessage = ChatMessage(role: "error", text: "I couldn’t prepare the message for OpenClaw: \(error.localizedDescription)")
                    if useDeveloperSession { self.developerChatMessages.append(errorMessage) } else { self.chatMessages.append(errorMessage) }
                    self.chatStatus = "Error"
                    self.chatIsSending = false
                }
                return
            }
            defer { try? FileManager.default.removeItem(atPath: tempMessagePath) }

            let runtimeSessionID = Self.runtimeSessionID(
                base: sessionID,
                modelID: modelOverride,
                useDeveloperSession: useDeveloperSession,
                freshDeveloperTurnID: useFreshDeveloperContext ? String(requestID.uuidString.prefix(8)) : nil
            )
            let startedAt = Date()
            await MainActor.run {
                if self.activeChatRequestID == requestID {
                    self.chatStatus = isSimpleDeveloperEdit ? "Applying quick edit..." : "Running OpenClaw..."
                }
            }
            var result = Self.openClawAgentCancellable(
                sessionID: runtimeSessionID,
                message: agentText,
                model: modelOverride,
                thinking: agentThinking,
                agentTimeout: agentTimeout,
                currentDirectory: useDeveloperSession ? developerWorkdir : nil,
                timeoutSeconds: wallClockTimeout
            ) { process in
                Task { @MainActor in
                    if self.activeChatRequestID == requestID {
                        self.activeChatProcess = process
                    }
                }
            }
            if result.0 != 0 && Self.isUnsupportedModelFlagError(result.1) && !modelOverride.isEmpty {
                await MainActor.run {
                    if self.activeChatRequestID == requestID {
                        self.chatStatus = "Retrying without model override..."
                    }
                }
                result = Self.openClawAgentCancellable(
                    sessionID: runtimeSessionID,
                    message: agentText,
                    model: "",
                    thinking: agentThinking,
                    agentTimeout: agentTimeout,
                    currentDirectory: useDeveloperSession ? developerWorkdir : nil,
                    timeoutSeconds: wallClockTimeout
                ) { process in
                    Task { @MainActor in
                        if self.activeChatRequestID == requestID {
                            self.activeChatProcess = process
                        }
                    }
                }
            }
            var repairedPlugin = false
            if result.0 != 0 && Self.isBrokenGlobalWhatsAppPluginError(result.1) {
                let repair = engine.disableBrokenGlobalPlugin(id: "whatsapp")
                repairedPlugin = repair.state == .ok
                if repairedPlugin {
                    await MainActor.run {
                        if self.activeChatRequestID == requestID {
                            self.chatStatus = "Plugin repaired, retrying..."
                        }
                    }
                    result = Self.openClawAgentCancellable(
                        sessionID: runtimeSessionID,
                        message: agentText,
                        model: modelOverride,
                        thinking: agentThinking,
                        agentTimeout: agentTimeout,
                        currentDirectory: useDeveloperSession ? developerWorkdir : nil,
                        timeoutSeconds: wallClockTimeout
                    ) { process in
                        Task { @MainActor in
                            if self.activeChatRequestID == requestID {
                                self.activeChatProcess = process
                            }
                        }
                    }
                }
            }
            let elapsed = Date().timeIntervalSince(startedAt)
            let knownDiagnostic = Self.friendlyChatDiagnostic(from: result.1)
            let reply = knownDiagnostic ?? Self.extractAgentReply(from: result.1)
            let runtimeModel = Self.extractAgentRuntimeModel(from: result.1)
            let usage = Self.extractAgentUsage(from: result.1)
            let metrics = Self.extractAgentMetrics(from: result.1, elapsedSeconds: elapsed, timeoutSeconds: wallClockTimeout, thinking: agentThinking)
            await MainActor.run {
                guard self.activeChatRequestID == requestID else { return }
                self.activeChatProcess = nil
                self.activeChatRequestID = nil
                if self.chatStopRequested {
                    self.chatStopRequested = false
                    self.chatStatus = "Ready"
                    self.chatIsSending = false
                    return
                }
                let responseModel = runtimeModel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? runtimeModel : self.openClawChatModelLabel
                if let runtimeModel, !runtimeModel.isEmpty {
                    self.currentModel = runtimeModel
                }
                if repairedPlugin && result.0 == 0 {
                    let repairMessage = ChatMessage(role: "assistant", text: "I found and disabled an outdated global WhatsApp plugin that was blocking OpenClaw, then retried automatically.", modelName: responseModel)
                    if useDeveloperSession { self.developerChatMessages.append(repairMessage) } else { self.chatMessages.append(repairMessage) }
                }
                let role = (result.0 == 0 || knownDiagnostic != nil) ? "assistant" : "error"
                let responseMessage = ChatMessage(role: role, text: reply, metadata: metrics, modelName: role == "assistant" ? responseModel : nil)
                if useDeveloperSession { self.developerChatMessages.append(responseMessage) } else { self.chatMessages.append(responseMessage) }
                if result.0 == 0 {
                    self.recordModelUsage(model: runtimeModel ?? self.currentModel, input: usage.input, output: usage.output, total: usage.total)
                }
                if useDeveloperSession && result.0 == 0 {
                    self.developerPreviewRefreshID = UUID()
                    self.developerActiveTab = "preview"
                    if self.developerPreviewProcess != nil {
                        self.developerPreviewStatus = "Preview refreshed after code changes"
                    } else {
                        self.developerPreviewStatus = "Code changes applied. Run preview to view them."
                    }
                }
                self.chatStatus = result.0 == 0 ? "Ready" : (knownDiagnostic == nil ? "Error" : "Needs setup")
                self.chatIsSending = false
            }
        }
    }

    func stopChatGeneration() {
        guard chatIsSending else { return }
        chatStopRequested = true
        chatStatus = "Stopping..."
        activeChatProcess?.terminate()
        activeChatProcess = nil
        activeChatRequestID = nil
        appendChatSystemMessageOnce("Generation stopped.")
        chatStatus = "Ready"
        chatIsSending = false
    }

    var availableChatModels: [OpenRouterModel] {
        var models: [OpenRouterModel] = []
        let current = openClawChatModelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let showingLocalModels = selectedChatResponseMode == .local
        if !current.isEmpty && !current.lowercased().contains("not configured") {
            let currentID = Self.normalizedChatModelID(current, inferenceMode: inferenceMode, localModels: localLMStudioModels)
            let currentIsLocal = currentID.hasPrefix("lmstudio/") || localLMStudioModels.contains(currentID)
            if currentIsLocal == showingLocalModels {
                models.append(OpenRouterModel(id: currentID, displayName: Self.readableModelName(currentID)))
            }
        }

        if showingLocalModels {
            for local in localLMStudioModels {
                models.append(OpenRouterModel(id: "lmstudio/\(local)", displayName: "Local · \(local)"))
            }
        } else {
            models.append(contentsOf: openRouterModelsLive.isEmpty ? Self.openRouterModels : openRouterModelsLive)
        }

        var seen = Set<String>()
        return models.filter { model in
            if seen.contains(model.id) { return false }
            seen.insert(model.id)
            return true
        }
    }

    func ensureSelectedChatModel() {
        reconcileSelectedChatModelForCurrentMode()
    }

    func prepareModelListForSelectedMode() {
        if selectedChatResponseMode == .local {
            inferenceMode = .local
            refreshLocalLMStudioModels()
        } else {
            prepareCloudModelSelection()
        }
    }

    func prepareCloudModelSelection() {
        inferenceMode = .cloud
        selectedProvider = .openRouter
        let cloudModels = openRouterModelsLive.isEmpty ? Self.openRouterModels : openRouterModelsLive
        if !cloudModels.contains(where: { $0.id == selectedOpenRouterModel }) {
            selectedOpenRouterModel = cloudModels.first?.id ?? "openrouter/openai/gpt-5-mini"
        }
        if selectedChatModel.isEmpty || !cloudModels.contains(where: { $0.id == selectedChatModel }) {
            selectedChatModel = selectedOpenRouterModel
        }
        if openRouterModelsLive.isEmpty {
            refreshOpenRouterModels()
        }
    }

    func reconcileSelectedChatModelForCurrentMode() {
        let models = availableChatModels
        if !selectedChatModel.isEmpty, models.contains(where: { $0.id == selectedChatModel }) { return }
        selectedChatModel = models.first?.id ?? ""
    }

    func syncChatModelModeWithSelection() {
        let model = selectedChatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        if model.hasPrefix("lmstudio/") || localLMStudioModels.contains(model) {
            selectedChatResponseMode = .local
            inferenceMode = .local
        } else if model.hasPrefix("openrouter/") {
            selectedChatResponseMode = .cloud
            inferenceMode = .cloud
            selectedOpenRouterModel = model
        }
    }

    enum LocalModelSetupSource {
        case chat
        case developer
        case models

        var label: String {
            switch self {
            case .chat: return "OpenClaw Chat"
            case .developer: return "Developer"
            case .models: return "Models"
            }
        }
    }

    func handleChatModelSelectionChanged(useDeveloperSession: Bool) {
        syncChatModelModeWithSelection()
        let model = selectedChatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let localModel = Self.localLMStudioModelID(from: model)
        guard !localModel.isEmpty else { return }
        selectedLocalLMStudioModel = localModel
        autoSetupLocalLMStudioModel(modelId: localModel, source: useDeveloperSession ? .developer : .chat)
    }

    private func localLMStudioModelIsReady(_ modelID: String) -> Bool {
        let localModel = Self.localLMStudioModelID(from: modelID)
        guard !localModel.isEmpty else { return false }
        let active = Self.localLMStudioModelID(from: activeLocalLMStudioModel)
        let current = Self.localLMStudioModelID(from: currentModel)
        return localModel == active && currentModel.hasPrefix("lmstudio/") && current == localModel
    }

    func autoSetupLocalLMStudioModel(modelId rawModelId: String, source: LocalModelSetupSource) {
        let modelId = Self.localLMStudioModelID(from: rawModelId)
        guard !modelId.isEmpty else {
            localLMStudioSetupStatus = "No local model selected"
            return
        }
        if localLMStudioModelIsReady("lmstudio/\(modelId)") {
            selectedChatResponseMode = .local
            selectedChatModel = "lmstudio/\(modelId)"
            selectedLocalLMStudioModel = modelId
            chatStatus = "Ready"
            localLMStudioSetupStatus = "LM Studio already ready with \(modelId)"
            return
        }
        if localLMStudioSetupInProgress {
            localLMStudioSetupStatus = "LM Studio setup already running..."
            chatStatus = "Setting up local model..."
            return
        }

        let requestID = UUID()
        localLMStudioSetupRequestID = requestID
        selectedChatResponseMode = .local
        selectedLocalLMStudioModel = modelId
        localLMStudioSetupInProgress = true
        localLMStudioSetupStatus = "Setting up \(modelId) for \(source.label)..."
        localLMStudioSetupLog = localLMStudioSetupLog.isEmpty
            ? "• Setting up \(modelId) for \(source.label)"
            : localLMStudioSetupLog + "\n• Setting up \(modelId) for \(source.label)"
        chatStatus = "Setting up local model..."

        Task.detached {
            let result = InstallerEngine().autoSetupLMStudioModel(modelId: modelId, contextLength: 32768) { message in
                DispatchQueue.main.async {
                    guard self.localLMStudioSetupRequestID == requestID else { return }
                    let line = "• \(message)"
                    self.localLMStudioSetupStatus = message
                    self.localLMStudioSetupLog = self.localLMStudioSetupLog.isEmpty ? line : self.localLMStudioSetupLog + "\n" + line
                }
            }
            let loaded = InstallerEngine().loadedLMStudioModelInfo()?.model
            await MainActor.run {
                guard self.localLMStudioSetupRequestID == requestID else { return }
                self.localLMStudioSetupRequestID = nil
                self.localLMStudioSetupInProgress = false
                self.localLMStudioSetupStatus = result.message
                if result.state == .ok {
                    let active = loaded ?? modelId
                    self.currentModel = "lmstudio/\(active)"
                    self.activeLocalLMStudioModel = active
                    self.selectedLocalLMStudioModel = active
                    self.selectedChatResponseMode = .local
                    self.selectedChatModel = "lmstudio/\(active)"
                    self.chatGatewayPrepared = false
                    self.resetMainAgentSessions()
                    self.chatStatus = "Ready"
                    let readyMessage = "Local model ready for \(source.label): \(active)."
                    if source == .developer {
                        self.developerChatMessages.append(ChatMessage(role: "assistant", text: readyMessage, metadata: "local setup", modelName: "LocalClaw"))
                    } else if source == .chat {
                        self.appendChatSystemMessageOnce(readyMessage)
                    }
                } else {
                    self.chatStatus = "Needs setup"
                    let failMessage = "Local setup failed for \(source.label): \(result.message)"
                    if source == .developer {
                        self.developerChatMessages.append(ChatMessage(role: "error", text: failMessage, modelName: "LocalClaw"))
                    } else if source == .chat {
                        self.appendChatSystemMessageOnce(failMessage)
                    }
                }
            }
        }
    }

    nonisolated static func readableModelName(_ id: String) -> String {
        let last = id.split(separator: "/").last.map(String.init) ?? id
        return last
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    nonisolated static func normalizedChatModelID(_ id: String, inferenceMode: InferenceMode, localModels: [String]) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("lmstudio/") || trimmed.hasPrefix("openrouter/") { return trimmed }
        if inferenceMode == .local { return "lmstudio/\(trimmed)" }
        if localModels.contains(trimmed) { return "lmstudio/\(trimmed)" }
        return trimmed
    }

    nonisolated static func localLMStudioModelID(from id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("lmstudio/") {
            return String(trimmed.dropFirst("lmstudio/".count))
        }
        if trimmed.hasPrefix("openrouter/") { return "" }
        return trimmed
    }

    nonisolated static func canonicalChatRuntimeModelID(_ id: String) -> String {
        repairedLegacyCloudModelID(id)
    }

    nonisolated static func repairedLegacyCloudModelID(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "openrouter/moonshotai/kimi-k2.5" || lower == "moonshot/kimi-k2.5" || lower == "moonshotai/kimi-k2.5" {
            return "openrouter/openai/gpt-5-mini"
        }
        return trimmed
    }

    nonisolated static func runtimeSessionID(base: String, modelID: String, useDeveloperSession: Bool, freshDeveloperTurnID: String? = nil) -> String {
        guard useDeveloperSession else { return base }
        let cleanModel = modelID
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let suffix = String(String(cleanModel).split(separator: "-").joined(separator: "-").prefix(72))
        let modelScoped = suffix.isEmpty ? base : "\(base)-\(suffix)"
        guard let freshDeveloperTurnID, !freshDeveloperTurnID.isEmpty else { return modelScoped }
        return "\(modelScoped)-turn-\(freshDeveloperTurnID)"
    }

    nonisolated static func agentThinkingLevel(for mode: ChatResponseMode) -> String {
        switch mode {
        case .fast:
            return "low"
        case .deep:
            return "high"
        case .local, .cloud:
            return "medium"
        }
    }

    nonisolated static func agentTimeoutSeconds(for mode: ChatResponseMode, useDeveloperSession: Bool) -> Int {
        if useDeveloperSession {
            switch mode {
            case .fast:
                return 90
            case .deep:
                return 240
            case .local:
                return 180
            case .cloud:
                return 150
            }
        }
        switch mode {
        case .fast:
            return 60
        case .deep:
            return 240
        case .local:
            return 180
        case .cloud:
            return 150
        }
    }

    nonisolated static func wallClockTimeoutSeconds(forAgentTimeout timeout: Int) -> Int {
        min(max(timeout + 20, 45), 260)
    }

    struct QuickDeveloperEditResult {
        let colorName: String
        let changedFiles: [String]
    }

    nonisolated static func quickDeveloperColorPalette(for text: String) -> (name: String, colors: [String])? {
        let clean = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let palettes: [(keys: [String], name: String, colors: [String])] = [
            (["jaune", "yellow"], "yellow", ["#181107", "#fef3c7", "#fde68a", "#facc15", "#eab308", "#ca8a04", "#854d0e"]),
            (["violet", "purple"], "purple", ["#120a24", "#f5f3ff", "#ddd6fe", "#c084fc", "#a855f7", "#7c3aed", "#4c1d95"]),
            (["bleu", "blue"], "blue", ["#07111f", "#eff6ff", "#bfdbfe", "#60a5fa", "#2563eb", "#1d4ed8", "#172554"]),
            (["vert", "green"], "green", ["#06140d", "#ecfdf5", "#bbf7d0", "#4ade80", "#16a34a", "#15803d", "#14532d"]),
            (["rouge", "red"], "red", ["#1f0909", "#fef2f2", "#fecaca", "#f87171", "#ef4444", "#b91c1c", "#7f1d1d"]),
            (["orange"], "orange", ["#1c0f05", "#fff7ed", "#fed7aa", "#fb923c", "#f97316", "#c2410c", "#7c2d12"]),
            (["rose", "pink"], "pink", ["#1f0713", "#fdf2f8", "#fbcfe8", "#f472b6", "#ec4899", "#be185d", "#831843"]),
            (["turquoise", "cyan"], "turquoise", ["#041616", "#ecfeff", "#a5f3fc", "#22d3ee", "#06b6d4", "#0e7490", "#164e63"])
        ]

        for palette in palettes where palette.keys.contains(where: { clean.contains($0) }) {
            return (palette.name, palette.colors)
        }
        return nil
    }

    nonisolated static func applyQuickDeveloperColorEdit(projectPath: String, requestText: String) -> QuickDeveloperEditResult? {
        guard isSimpleDeveloperEdit(requestText),
              let palette = quickDeveloperColorPalette(for: requestText) else { return nil }

        let root = URL(fileURLWithPath: projectPath).standardizedFileURL
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let editableExtensions = Set(["css", "scss", "sass", "less", "html", "htm", "js", "jsx", "ts", "tsx", "vue", "svelte"])
        let skippedDirectories = Set([".git", "node_modules", ".build", "dist", ".next", ".vite", "build", "coverage"])
        var changedFiles: [String] = []

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if skippedDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            if (values?.fileSize ?? 0) > 600_000 { continue }
            if !editableExtensions.contains(url.pathExtension.lowercased()) { continue }

            guard let original = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lower = original.lowercased()
            let looksStyleRelated = url.pathExtension.lowercased().contains("css")
                || ["style", "theme", "global", "app", "index", "main"].contains { name.lowercased().contains($0) }
                || lower.contains("#")
                || lower.contains("color")
                || lower.contains("background")
            if !looksStyleRelated { continue }

            let updated = quickDeveloperColorRewrittenContent(original, palette: palette)
            if updated != original {
                do {
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                    let path = url.standardizedFileURL.path
                    changedFiles.append(path.hasPrefix(root.path + "/") ? String(path.dropFirst(root.path.count + 1)) : url.lastPathComponent)
                } catch {
                    continue
                }
            }
            if changedFiles.count >= 12 { break }
        }

        return changedFiles.isEmpty ? nil : QuickDeveloperEditResult(colorName: palette.name, changedFiles: changedFiles)
    }

    nonisolated static func quickDeveloperColorRewrittenContent(_ content: String, palette: (name: String, colors: [String])) -> String {
        var mappedHex: [String: String] = [:]
        var nextColorIndex = 0
        let hexRegex = try? NSRegularExpression(pattern: #"#[0-9A-Fa-f]{3,8}\b"#)
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let matches = hexRegex?.matches(in: content, range: fullRange).reversed() ?? []
        var result = content

        for match in matches {
            let old = nsContent.substring(with: match.range)
            let key = old.lowercased()
            let replacement: String
            if let mapped = mappedHex[key] {
                replacement = mapped
            } else {
                replacement = palette.colors[nextColorIndex % palette.colors.count]
                mappedHex[key] = replacement
                nextColorIndex += 1
            }
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }

        let namedColors = ["purple", "violet", "yellow", "jaune", "blue", "bleu", "green", "vert", "red", "rouge", "orange", "pink", "rose", "turquoise", "cyan"]
        for color in namedColors where color != palette.name {
            result = result.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: color))\\b", with: palette.name, options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    nonisolated static func isSimpleDeveloperEdit(_ text: String) -> Bool {
        let clean = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let editWords = ["change", "changer", "remplace", "remplacer", "mets", "met", "passer", "update", "modifier", "couleur", "color", "theme", "css", "style", "titre", "title", "texte", "text", "button", "bouton"]
        let heavyWords = ["architecture", "database", "supabase", "auth", "stripe", "payment", "deploy", "migration", "test", "debug", "fix crash", "api", "backend", "refactor", "security"]
        let hasEditSignal = editWords.contains { clean.contains($0) }
        let hasHeavySignal = heavyWords.contains { clean.contains($0) }
        return hasEditSignal && !hasHeavySignal && clean.count <= 280
    }

    func prepareDeveloperWorkspace() {
        ensureDeveloperChatSession()
        if developerProjectPath == NSHomeDirectory() + "/.openclaw/workspace" {
            syncDeveloperProjectFolder()
        }
        refreshOpenClawChatInfo()
        refreshLocalLMStudioModels()
        refreshOpenRouterModels()
        ensureSelectedChatModel()
    }

    func developerNewApp() {
        developerStopPreview()
        let session = ChatSession.developerFresh()
        chatSessions.insert(session, at: 0)
        selectedDeveloperChatSessionID = session.id
        let baseURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".openclaw/workspace/projects", isDirectory: true)
        developerProjectName = Self.nextDeveloperProjectName(in: baseURL)
        syncDeveloperProjectFolder(moveExistingProject: false)
        chatInput = "Create a new web app named \(developerProjectName) in \(developerProjectPath). Set up a minimal runnable project, then tell me how to preview it locally inside LocalClaw."
        screen = .developer
    }

    func syncDeveloperProjectFolder(moveExistingProject: Bool = true) {
        let cleanName = developerProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My App" : developerProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = Self.slugifyProjectName(cleanName)
        let baseURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".openclaw/workspace/projects", isDirectory: true)
        let targetURL = baseURL.appendingPathComponent(slug, isDirectory: true)
        let currentURL = URL(fileURLWithPath: developerProjectPath)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
            if moveExistingProject,
               currentURL.path.hasPrefix(baseURL.path + "/"),
               currentURL.path != targetURL.path,
               fm.fileExists(atPath: currentURL.path),
               !fm.fileExists(atPath: targetURL.path) {
                try fm.moveItem(at: currentURL, to: targetURL)
            } else {
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
            }
            developerProjectPath = targetURL.path
            developerPreviewRefreshID = UUID()
            developerActiveTab = "preview"
            developerPreviewStatus = "Project folder ready: \(slug)"
        } catch {
            developerPreviewStatus = "Could not prepare project folder: \(error.localizedDescription)"
        }
    }

    nonisolated static func slugifyProjectName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let mapped = folded.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped).lowercased().split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "my-app" : collapsed
    }

    nonisolated static func nextDeveloperProjectName(existingSlugs: Set<String>, baseName: String = "My App") -> String {
        let baseSlug = slugifyProjectName(baseName)
        if !existingSlugs.contains(baseSlug) { return baseName }
        for index in 2...999 {
            let candidate = "\(baseName) \(index)"
            if !existingSlugs.contains(slugifyProjectName(candidate)) {
                return candidate
            }
        }
        return "\(baseName) \(Int(Date().timeIntervalSince1970))"
    }

    nonisolated static func nextDeveloperProjectName(in baseURL: URL, baseName: String = "My App") -> String {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let slugs = Set(urls.compactMap { url -> String? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true ? url.lastPathComponent : nil
        })
        return nextDeveloperProjectName(existingSlugs: slugs, baseName: baseName)
    }

    func developerChooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: developerProjectPath)
        if panel.runModal() == .OK, let url = panel.url {
            developerStopPreview()
            developerProjectPath = url.path
            developerProjectName = url.lastPathComponent
            developerPreviewRefreshID = UUID()
            developerActiveTab = "preview"
            developerPreviewStatus = "App opened. Run preview to load it."
            chatInput = "Use this project folder as context: \(url.path). Inspect it and suggest the next development step."
        }
    }

    func developerRunPreview() {
        syncDeveloperProjectFolder()
        developerPreviewRefreshID = UUID()
        developerPreviewStatus = "Starting preview..."
        developerPreviewProcess?.terminate()
        developerPreviewProcess = nil

        let root = developerProjectPath
        let fm = FileManager.default
        let packageURL = URL(fileURLWithPath: root).appendingPathComponent("package.json")
        let packageWasMissing = !fm.fileExists(atPath: packageURL.path)
        do {
            try Self.createDeveloperPreviewScaffold(at: URL(fileURLWithPath: root), appName: developerProjectName)
            if packageWasMissing {
                developerPreviewStatus = "Created a runnable preview project..."
                appendChatSystemMessageOnce("Created a minimal web app scaffold so Preview can run.")
            }
        } catch {
            developerPreviewStatus = "Could not prepare preview project: \(error.localizedDescription)"
            chatInput = "Create or fix a runnable web preview for \(developerProjectPath). Add package.json scripts if needed, then report the preview URL."
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.currentDirectoryURL = URL(fileURLWithPath: root)
        process.arguments = ["-lc", InstallerEngine.shellPathPrefix + "if ! command -v npm >/dev/null 2>&1; then echo 'npm is required to run preview'; exit 127; fi; if [ -d node_modules ]; then npm run dev -- --host 127.0.0.1; else npm install && npm run dev -- --host 127.0.0.1; fi"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            let detectedURL = Self.detectPreviewURL(in: output)
            Task { @MainActor in
                self?.developerPreviewStatus = output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.suffix(2).joined(separator: " ")
                if let detectedURL {
                    self?.developerPreviewURL = detectedURL
                    self?.developerPreviewRefreshID = UUID()
                    self?.developerActiveTab = "preview"
                }
            }
        }
        do {
            try process.run()
            developerPreviewProcess = process
            developerPreviewURL = "http://localhost:5173"
            developerPreviewStatus = "Preview running in LocalClaw"
            developerActiveTab = "preview"
        } catch {
            developerPreviewStatus = "Preview failed: \(error.localizedDescription)"
        }
        chatInput = "Start or verify the local preview for \(developerProjectPath). If a dev server is needed, use the existing project scripts and report the local URL."
    }

    nonisolated static func createDeveloperPreviewScaffold(at root: URL, appName: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let cleanName = appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? root.lastPathComponent : appName
        let packageName = slugifyProjectName(cleanName)
        let appNameLiteralData = try JSONSerialization.data(withJSONObject: cleanName, options: [.fragmentsAllowed])
        let appNameLiteral = String(data: appNameLiteralData, encoding: .utf8) ?? #""My App""#
        let htmlTitle = cleanName
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let files: [(String, String)] = [
            ("package.json", """
            {
              "scripts": {
                "dev": "vite --host 127.0.0.1"
              },
              "dependencies": {
                "@vitejs/plugin-react": "latest",
                "vite": "latest",
                "react": "latest",
                "react-dom": "latest"
              },
              "devDependencies": {}
            }
            """),
            ("index.html", """
            <!doctype html>
            <html lang="en">
              <head>
                <meta charset="UTF-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1.0" />
                <title>\(htmlTitle)</title>
              </head>
              <body>
                <div id="root"></div>
                <script type="module" src="/src/main.jsx"></script>
              </body>
            </html>
            """),
            ("src/main.jsx", """
            import React from 'react';
            import { createRoot } from 'react-dom/client';
            import './styles.css';

            const appName = \(appNameLiteral);

            function App() {
              return (
                <main className="app-shell">
                  <section className="hero">
                    <p className="eyebrow">LocalClaw Preview</p>
                    <h1>{appName}</h1>
                    <p>Start editing this app with OpenClaw. The preview updates from this project folder.</p>
                    <div className="actions">
                      <button>Primary action</button>
                      <button className="secondary">Secondary</button>
                    </div>
                  </section>
                </main>
              );
            }

            createRoot(document.getElementById('root')).render(<App />);
            """),
            ("src/styles.css", """
            :root {
              color: #f6f7f9;
              background: #101113;
              font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }

            * {
              box-sizing: border-box;
            }

            body {
              margin: 0;
              min-width: 320px;
              min-height: 100vh;
            }

            button {
              border: 0;
              border-radius: 8px;
              padding: 12px 16px;
              background: #ff4b42;
              color: white;
              font-weight: 700;
              cursor: pointer;
            }

            button.secondary {
              background: #2b2d31;
              color: #f6f7f9;
            }

            .app-shell {
              min-height: 100vh;
              display: grid;
              place-items: center;
              padding: 32px;
              background:
                radial-gradient(circle at top left, rgba(255, 75, 66, 0.22), transparent 34rem),
                linear-gradient(135deg, #15171b 0%, #0b0c0f 100%);
            }

            .hero {
              width: min(760px, 100%);
              padding: 44px;
              border: 1px solid rgba(255, 255, 255, 0.12);
              border-radius: 14px;
              background: rgba(255, 255, 255, 0.06);
            }

            .eyebrow {
              margin: 0 0 12px;
              color: #ff6b62;
              font-weight: 800;
              text-transform: uppercase;
              font-size: 12px;
            }

            h1 {
              margin: 0;
              font-size: clamp(36px, 6vw, 72px);
              line-height: 1;
            }

            p {
              max-width: 56ch;
              color: #c5c7cc;
              font-size: 18px;
              line-height: 1.5;
            }

            .actions {
              display: flex;
              flex-wrap: wrap;
              gap: 12px;
              margin-top: 24px;
            }
            """)
        ]

        for (relativePath, content) in files {
            let url = root.appendingPathComponent(relativePath)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        }

        let packageURL = root.appendingPathComponent("package.json")
        if var packageData = try? Data(contentsOf: packageURL),
           var packageJSON = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any] {
            packageJSON["name"] = packageName
            var scripts = packageJSON["scripts"] as? [String: Any] ?? [:]
            if (scripts["dev"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                scripts["dev"] = "vite --host 127.0.0.1"
            }
            packageJSON["scripts"] = scripts

            var dependencies = packageJSON["dependencies"] as? [String: Any] ?? [:]
            for dependency in ["@vitejs/plugin-react", "vite", "react", "react-dom"] where dependencies[dependency] == nil {
                dependencies[dependency] = "latest"
            }
            packageJSON["dependencies"] = dependencies

            packageData = try JSONSerialization.data(withJSONObject: packageJSON, options: [.prettyPrinted, .sortedKeys])
            try packageData.write(to: packageURL, options: .atomic)
        }
    }

    func developerStopPreview() {
        developerPreviewProcess?.terminate()
        developerPreviewProcess = nil
        developerPreviewStatus = "Preview stopped"
    }

    nonisolated static func detectPreviewURL(in output: String) -> String? {
        let patterns = ["http://localhost:", "http://127.0.0.1:"]
        for pattern in patterns {
            if let range = output.range(of: pattern) {
                let suffix = output[range.lowerBound...]
                let value = suffix.prefix { char in
                    !char.isWhitespace && char != "\"" && char != "'" && char != ")"
                }
                return String(value)
            }
        }
        return nil
    }

    func developerRefreshPreview() {
        developerPreviewRefreshID = UUID()
    }

    func developerOpenExternalPreview() {
        if let url = URL(string: developerPreviewURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func developerCopyPreviewURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(developerPreviewURL, forType: .string)
        appendChatSystemMessageOnce("Preview URL copied.")
    }

    func developerProjectFiles(limit: Int = 120) -> [URL] {
        let root = URL(fileURLWithPath: developerProjectPath)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if [".git", "node_modules", ".build", "dist", ".next", ".vite"].contains(name) {
                enumerator.skipDescendants()
                continue
            }
            urls.append(url)
            if urls.count >= limit { break }
        }
        return urls.sorted {
            let aDir = ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            let bDir = ((try? $1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            if aDir != bDir { return aDir && !bDir }
            return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    func developerOpenFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func developerRevealFile(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func developerRelativePath(_ url: URL) -> String {
        let root = URL(fileURLWithPath: developerProjectPath).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return url.lastPathComponent
    }

    func developerProjectSummary() -> [String] {
        let root = URL(fileURLWithPath: developerProjectPath)
        let fm = FileManager.default
        let checks = [
            ("package.json", "Node app"),
            ("vite.config.js", "Vite"),
            ("next.config.js", "Next.js"),
            ("index.html", "Static HTML"),
            ("supabase", "Supabase folder"),
            ("prisma", "Prisma folder"),
            (".env", "Environment file")
        ]
        return checks.compactMap { file, label in
            fm.fileExists(atPath: root.appendingPathComponent(file).path) ? label : nil
        }
    }

    nonisolated private static func shellCancellable(_ command: String, timeoutSeconds: Int? = nil, onStart: @escaping (Process) -> Void) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", InstallerEngine.shellPathPrefix + command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            onStart(process)
        } catch {
            return (1, "Failed command: \(command)\n\(error.localizedDescription)")
        }

        let timeoutLock = NSLock()
        var timedOut = false
        let timer: DispatchSourceTimer?
        if let timeoutSeconds, timeoutSeconds > 0 {
            let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            source.schedule(deadline: .now() + .seconds(timeoutSeconds))
            source.setEventHandler {
                timeoutLock.lock()
                timedOut = true
                timeoutLock.unlock()
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            _ = try? Process.run(URL(fileURLWithPath: "/bin/kill"), arguments: ["-9", "\(process.processIdentifier)"])
                        }
                    }
                }
            }
            source.resume()
            timer = source
        } else {
            timer = nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer?.cancel()
        let output = String(data: data, encoding: .utf8) ?? ""
        timeoutLock.lock()
        let didTimeout = timedOut
        timeoutLock.unlock()
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if didTimeout {
            let suffix = "LocalClaw stopped OpenClaw after \(timeoutSeconds ?? 0)s because this request exceeded the Developer time budget."
            return (124, trimmed.isEmpty ? suffix : "\(trimmed)\n\n\(suffix)")
        }
        return (process.terminationStatus, trimmed)
    }

    nonisolated private static func openClawAgentCancellable(
        sessionID: String,
        message: String,
        model: String,
        thinking: String,
        agentTimeout: Int,
        currentDirectory: String?,
        timeoutSeconds: Int? = nil,
        onStart: @escaping (Process) -> Void
    ) -> (Int32, String) {
        var arguments = [
            "openclaw",
            "agent",
            "--session-id", sessionID,
            "-m", message,
            "--json",
            "--timeout", String(agentTimeout)
        ]
        if !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        if !thinking.isEmpty {
            arguments.append(contentsOf: ["--thinking", thinking])
        }
        return processCancellable(
            executable: "/usr/bin/env",
            arguments: arguments,
            currentDirectory: currentDirectory,
            timeoutSeconds: timeoutSeconds,
            onStart: onStart
        )
    }

    nonisolated private static func processCancellable(
        executable: String,
        arguments: [String],
        currentDirectory: String?,
        timeoutSeconds: Int? = nil,
        onStart: @escaping (Process) -> Void
    ) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let launchPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:\(NSHomeDirectory())/.npm-global/bin:\(NSHomeDirectory())/.local/bin"
        environment["PATH"] = launchPath + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment
        if let currentDirectory, !currentDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            onStart(process)
        } catch {
            return (1, "Failed command: \(executable) \(arguments.joined(separator: " "))\n\(error.localizedDescription)")
        }

        let timeoutLock = NSLock()
        var timedOut = false
        let timer: DispatchSourceTimer?
        if let timeoutSeconds, timeoutSeconds > 0 {
            let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            source.schedule(deadline: .now() + .seconds(timeoutSeconds))
            source.setEventHandler {
                timeoutLock.lock()
                timedOut = true
                timeoutLock.unlock()
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            _ = try? Process.run(URL(fileURLWithPath: "/bin/kill"), arguments: ["-9", "\(process.processIdentifier)"])
                        }
                    }
                }
            }
            source.resume()
            timer = source
        } else {
            timer = nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer?.cancel()
        let output = String(data: data, encoding: .utf8) ?? ""
        timeoutLock.lock()
        let didTimeout = timedOut
        timeoutLock.unlock()
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if didTimeout {
            let suffix = "LocalClaw stopped OpenClaw after \(timeoutSeconds ?? 0)s because this request exceeded the time budget."
            return (124, trimmed.isEmpty ? suffix : "\(trimmed)\n\n\(suffix)")
        }
        return (process.terminationStatus, trimmed)
    }

    func attachChatImage() {
        let panel = NSOpenPanel()
        panel.title = "Attach image"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .bmp, .heic, .webP]

        if panel.runModal() == .OK, let url = panel.url {
            chatImagePath = url.path
        }
    }

    func removeChatImage() {
        chatImagePath = ""
    }

    nonisolated private static func isBrokenGlobalWhatsAppPluginError(_ raw: String) -> Bool {
        raw.contains("plugin load failed: whatsapp") && raw.contains(".openclaw/extensions/whatsapp")
    }

    nonisolated private static func isUnsupportedModelFlagError(_ raw: String) -> Bool {
        stripANSI(raw).lowercased().contains("unknown option '--model'")
    }

    nonisolated private static func stripANSI(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }

    nonisolated private static func friendlyChatDiagnostic(from raw: String) -> String? {
        let clean = stripANSI(raw)
        if clean.contains("Model context window too small") || clean.contains("context window too small") {
            let model = clean.range(of: #"lmstudio/[^\s;"]+"#, options: .regularExpression)
                .map { String(clean[$0]) } ?? "your local LM Studio model"
            let ctx = clean.range(of: #"ctx=[0-9]+"#, options: .regularExpression)
                .map { String(clean[$0].dropFirst(4)) } ?? "4096"
            return """
            Local mode is not ready yet. The selected model (\(model)) is loaded with a context window of \(ctx) tokens, but OpenClaw needs at least 16,000 tokens and works best at 32,000+.

            What to do:
            1. Open LM Studio.
            2. Load a model with 16k/32k context, or increase Context Length to 16384+ for this model.
            3. Reload the model/server.
            4. Come back here and retry.

            Fast workaround: switch back to Cloud LLM in the top-right toggle.
            """
        }
        if clean.contains("required option '-m, --message <text>' not specified") {
            return "I couldn’t pass your message to OpenClaw correctly. I’ve patched the chat sender so messages are now handed off safely, including accents and apostrophes. Please retry after updating LocalClaw."
        }
        return nil
    }

    nonisolated private static func extractAgentReply(from raw: String) -> String {
        let clean = stripANSI(raw)
        guard let data = clean.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "No response from OpenClaw." : trimmed
        }

        if let result = json["result"] as? [String: Any] {
            if let value = result["finalAssistantVisibleText"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = result["finalAssistantRawText"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let payloads = result["payloads"] as? [[String: Any]],
               let value = payloads.compactMap({ $0["text"] as? String }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            for key in ["reply", "text", "message", "content", "output"] {
                if let value = result[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        for key in ["reply", "text", "message", "content", "output"] {
            if let value = json[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let value = json["summary"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    nonisolated private static func extractAgentMetrics(from raw: String, elapsedSeconds: TimeInterval, timeoutSeconds: Int? = nil, thinking: String? = nil) -> String {
        var parts = [String(format: "%.1fs", elapsedSeconds)]
        if let timeoutSeconds { parts.append("limit \(timeoutSeconds)s") }
        if let thinking, !thinking.isEmpty { parts.append("thinking \(thinking)") }

        let usage = extractAgentUsage(from: raw)

        if let input = usage.input { parts.append("in \(input)t") }
        if let output = usage.output { parts.append("out \(output)t") }
        if usage.total == nil, usage.input == nil, usage.output == nil {
            parts.append("tokens n/a")
        } else if let total = usage.total {
            parts.append("total \(total)t")
        }
        return parts.joined(separator: " • ")
    }

    nonisolated private static func extractAgentUsage(from raw: String) -> (input: Int?, output: Int?, total: Int?) {
        let clean = stripANSI(raw)

        func regexNumber(_ pattern: String) -> Int? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
            guard let match = regex.firstMatch(in: clean, options: [], range: range), match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: clean) else { return nil }
            return Int(clean[valueRange].replacingOccurrences(of: "_", with: ""))
        }

        func findNumber(_ object: Any, keys: Set<String>) -> Int? {
            if let dict = object as? [String: Any] {
                for (key, value) in dict {
                    if keys.contains(key.lowercased()) {
                        if let int = value as? Int { return int }
                        if let double = value as? Double { return Int(double) }
                        if let string = value as? String, let int = Int(string) { return int }
                    }
                }
                for value in dict.values {
                    if let found = findNumber(value, keys: keys) { return found }
                }
            } else if let array = object as? [Any] {
                for value in array {
                    if let found = findNumber(value, keys: keys) { return found }
                }
            }
            return nil
        }

        var json: [String: Any]? = nil
        if let data = clean.data(using: .utf8) {
            json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        let input = json.flatMap { findNumber($0, keys: ["inputtokens", "input_tokens", "prompttokens", "prompt_tokens"]) }
            ?? regexNumber(#"(?:prompt|input|text)\s*(?:tokens)?\s*[=:]\s*([0-9_]+)"#)
        let output = json.flatMap { findNumber($0, keys: ["outputtokens", "output_tokens", "completiontokens", "completion_tokens"]) }
            ?? regexNumber(#"(?:completion|output|predicted)\s*(?:tokens)?\s*[=:]\s*([0-9_]+)"#)
        let total = json.flatMap { findNumber($0, keys: ["totaltokens", "total_tokens"])}
            ?? regexNumber(#"(?:total|tokens)\s*(?:tokens)?\s*[=:]\s*([0-9_]+)"#)

        return (input, output, total)
    }

    nonisolated private static func extractAgentRuntimeModel(from raw: String) -> String? {
        let clean = stripANSI(raw)
        guard let data = clean.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let meta = result["meta"] as? [String: Any],
              let agentMeta = meta["agentMeta"] as? [String: Any] else { return nil }
        let provider = (agentMeta["provider"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = (agentMeta["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if provider.isEmpty { return model.isEmpty ? nil : model }
        if model.isEmpty { return provider }
        return "\(provider)/\(model)"
    }

    var openClawChatStatus: String {
        if openclawInstalledVersion == "Checking..." { return "Checking..." }
        if openclawInstalledVersion == "Not installed" { return "Setup needed" }
        if openclawUpdateStatus == "Not installed" { return "Setup needed" }
        return "Ready"
    }

    var openClawChatModeLabel: String {
        inferenceMode.rawValue
    }

    var openClawChatModelLabel: String {
        if inferenceMode == .local {
            let activeLocal = activeLocalLMStudioModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !activeLocal.isEmpty {
                return activeLocal
            }
        }

        let current = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty && current != "Unknown" && !current.lowercased().hasPrefix("error:") {
            return current
        }
        if inferenceMode == .oauth {
            return "openai-codex/gpt-5.4"
        }
        if inferenceMode == .cloud {
            return selectedOpenRouterModel.isEmpty ? "Cloud model not configured" : selectedOpenRouterModel
        }
        if !selectedModel.isEmpty {
            return selectedModel
        }
        return recommendation.isEmpty ? "Local model not configured" : recommendation
    }

    func refreshOpenClawChatInfo() {
        chatStatus = "Checking setup..."
        let provider = effectiveAuthProvider()
        let localKeyPresent = !requiredProviderKey().isEmpty
        Task.detached {
            let engine = InstallerEngine()
            let model = engine.getCurrentModel()
            let models = engine.listLMStudioLLMModelIds()
            let loaded = engine.loadedLMStudioModelInfo()?.model
            let authConfigured = engine.hasProviderAuth(provider: provider) || localKeyPresent
            await MainActor.run {
                let repairedModel = Self.repairedLegacyCloudModelID(model)
                if repairedModel != model {
                    _ = engine.writeModelToConfig(modelIdentifier: repairedModel)
                }
                self.currentModel = repairedModel
                self.cloudProviderAuthConfigured = authConfigured
                self.localLMStudioModels = models
                self.activeLocalLMStudioModel = loaded ?? ""
                if self.selectedLocalLMStudioModel.isEmpty {
                    if let loaded, models.contains(loaded) {
                        self.selectedLocalLMStudioModel = loaded
                    } else if model.hasPrefix("lmstudio/") {
                        let configured = String(model.dropFirst("lmstudio/".count))
                        if models.contains(configured) { self.selectedLocalLMStudioModel = configured }
                    } else if let first = models.first {
                        self.selectedLocalLMStudioModel = first
                    }
                }
                self.chatStatus = "Ready"
            }
        }
    }

    func refreshLocalLMStudioModels() {
        let models = engine.listLMStudioLLMModelIds()
        let loaded = engine.loadedLMStudioModelInfo()?.model
        localLMStudioModels = models
        activeLocalLMStudioModel = loaded ?? ""
        let loadedMatch = localModelMatch(loaded ?? "", in: models)
        if !loadedMatch.isEmpty {
            selectedLocalLMStudioModel = loadedMatch
        } else if currentModel.hasPrefix("lmstudio/") {
            let configured = localModelMatch(currentModel, in: models)
            selectedLocalLMStudioModel = configured.isEmpty ? (models.first ?? "") : configured
        } else if selectedLocalLMStudioModel.isEmpty || !models.contains(selectedLocalLMStudioModel) {
            selectedLocalLMStudioModel = models.first ?? ""
        }
    }

    func autoSetupSelectedLocalLMStudioModel() {
        if localLMStudioSetupInProgress { return }
        if selectedLocalLMStudioModel.isEmpty {
            localLMStudioSetupStatus = "No local model found in LM Studio"
            return
        }
        autoSetupLocalLMStudioModel(modelId: selectedLocalLMStudioModel, source: .chat)
    }

    func repairLMStudioRuntimeFromChat() {
        if localLMStudioRepairInProgress { return }
        localLMStudioRepairInProgress = true
        localLMStudioSetupStatus = "Updating LM Studio runtime..."
        chatStatus = "Repairing LM Studio..."
        Task.detached {
            let result = InstallerEngine().repairLMStudioRuntime()
            await MainActor.run {
                self.localLMStudioRepairInProgress = false
                self.localLMStudioSetupStatus = result.message
                self.chatStatus = result.state == .ok ? "Needs setup" : "Error"
                self.appendChatSystemMessageOnce(result.state == .ok
                    ? "LM Studio runtime repair finished. Click AUTO SETUP again to load a compatible local model."
                    : "I couldn’t repair LM Studio automatically: \(result.message)")
                self.refreshLocalLMStudioModels()
            }
        }
    }

    func appendChatSystemMessageOnce(_ text: String) {
        if chatMessages.last?.text == text { return }
        chatMessages.append(ChatMessage(role: "assistant", text: text))
    }

    func openTerminalOpenAIOAuth() {
        let script = """
        #!/bin/zsh
        clear
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

        OPENCLAW_BIN="$(command -v openclaw 2>/dev/null || true)"
        echo "=========================================="
        echo "  OpenAI OAuth Setup (Codex / ChatGPT)"
        echo "=========================================="
        echo ""

        if [ -z "$OPENCLAW_BIN" ]; then
            echo "[ERROR] openclaw command not found in PATH"
            echo "Install OpenClaw first from Install tab."
            echo ""
        else
            echo "Running: $OPENCLAW_BIN models auth login --provider openai-codex --set-default"
            echo ""
            "$OPENCLAW_BIN" models auth login --provider openai-codex --set-default
            echo ""
            echo "If login succeeded, use model: openai-codex/gpt-5.4"
        fi

        echo ""
        read -r "REPLY?Press Enter to close..."
        """

        let scriptPath = "/tmp/localclaw_openai_oauth.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            _ = engine.shell("chmod +x \(scriptPath)")
            _ = engine.shell("osascript -e 'tell application \"Terminal\" to do script \"\(scriptPath)\"'")
            append("Opened Terminal for OpenAI OAuth login")
        } catch {
            append("Failed to open OAuth terminal: \(error.localizedDescription)")
        }
    }

    func openTerminalAndInstall() {
        let script = """
        #!/bin/zsh
        clear
        echo "=========================================="
        echo "  LocalClaw Installation"
        echo "=========================================="
        echo ""
        
        echo "[1/6] Installing Homebrew..."
        if command -v brew &>/dev/null; then
            echo "  ✓ Already installed"
        else
            echo "  → Installing..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        
        echo ""
        echo "[2/6] Installing LM Studio..."
        if [ -d "/Applications/LM Studio.app" ]; then
            echo "  ✓ Already installed"
        else
            echo "  → Installing (this takes 5+ min)..."
            brew install --cask lm-studio
        fi
        
        echo ""
        echo "[3/6] Installing Node.js..."
        if command -v node &>/dev/null; then
            echo "  ✓ Already installed"
        else
            echo "  → Installing..."
            brew install node
        fi
        
        echo ""
        echo "[4/6] Installing OpenClaw..."
        if command -v openclaw &>/dev/null; then
            echo "  ✓ Already installed"
        else
            echo "  → Installing..."
            npm i -g openclaw@latest
        fi
        
        echo ""
        echo "[5/6] Configuring OpenClaw..."
        mkdir -p ~/.openclaw
        echo '{"gateway":{"mode":"local","port":18789,"auth":{"mode":"token","token":"\(gatewayToken)"}},"agents":{"defaults":{"model":{"primary":"\(effectiveModelIdentifier())"}}}}' > ~/.openclaw/openclaw.json
        echo "  ✓ Config saved"
        
        echo ""
        echo "[6/6] Starting Gateway..."
        openclaw gateway start &
        sleep 3
        
        echo ""
        echo "=========================================="
        echo "  Installation Complete!"
        echo "=========================================="
        echo ""
        echo "Gateway URL: http://localhost:18789"
        echo ""
        read -p "Press Enter to close..."
        """
        
        let path = "/tmp/localclaw_install.sh"
        try? script.write(toFile: path, atomically: true, encoding: String.Encoding.utf8)
        _ = engine.shell("chmod +x \(path)")
        _ = engine.shell("open -a Terminal \(path)")
        
        screen = .install
        isRunning = true
        append("Terminal opened! Installation is running in Terminal window.")
        append("Please complete the installation in the Terminal window.")
    }

    func openTerminalAndInstallFull() {
        let validationErrors = setupValidationErrors
        if !validationErrors.isEmpty {
            append("Cannot start installation until setup errors are fixed:")
            for err in validationErrors {
                append("- \(err)")
            }
            return
        }

        let installLMStudio = (inferenceMode == .local)
        let resolvedLocalModel = selectedModel.isEmpty ? recommendation : selectedModel
        let modelQuery = modelQueries[resolvedLocalModel] ?? ""
        let localModelSlug = modelQuery.split(separator: "@").first.map(String.init) ?? "openai"
        let providerModelId = localProviderModelIds[resolvedLocalModel] ?? localModelSlug
        let modelId = installLMStudio ? "lmstudio/\(providerModelId)" : (selectedProvider == .openRouter ? selectedOpenRouterModel : effectiveModelIdentifier())
        let authProvider = effectiveAuthProvider()
        let apiKey = installLMStudio ? "" : requiredProviderKey()
        let dynamicLocalCandidates = ([resolvedLocalModel] + modelOptions)
            .compactMap { name in localModelCandidates.first { $0.name == name } }
            .reduce(into: [LocalModelCandidate]()) { result, candidate in
                if !result.contains(where: { $0.providerId == candidate.providerId }) {
                    result.append(candidate)
                }
            }
        
        // Build script as array then join
        var lines: [String] = []
        lines.append("#!/bin/bash")
        lines.append("clear")
        lines.append("echo \"==========================================\"")
        lines.append("echo \"  LocalClaw Installation\"")
        lines.append("echo \"==========================================\"")
        lines.append("rm -f /tmp/localclaw_status")
        lines.append("touch /tmp/localclaw_status")
        lines.append("")
        lines.append("echo \"\"")
        lines.append("echo \"[1/7] Installing Homebrew...\"")
        lines.append("if command -v brew &>/dev/null; then")
        lines.append("    echo \"  ✓ Already installed\"")
        lines.append("    echo \"homebrew:OK\" >> /tmp/localclaw_status")
        lines.append("else")
        lines.append("    echo \"  → Installing (requires password)...\"")
        lines.append("    /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
        lines.append("    eval \"$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)\"")
        lines.append("    echo \"homebrew:OK\" >> /tmp/localclaw_status")
        lines.append("fi")
        
        if installLMStudio {
            lines.append("")
            lines.append("echo \"\"")
            lines.append("echo \"[2/7] Installing LM Studio...\"")
            lines.append("if [ -d \"/Applications/LM Studio.app\" ]; then")
            lines.append("    echo \"  ✓ Already installed\"")
            lines.append("else")
            lines.append("    echo \"  → Installing (this takes 5+ min)...\"")
            lines.append("    brew install --cask lm-studio")
            lines.append("fi")
            lines.append("echo \"lmstudio:OK\" >> /tmp/localclaw_status")
            lines.append("")
            lines.append("echo \"\"")
            lines.append("echo \"[3/7] Downloading AI Model...\"")
            lines.append("LMS_CMD='lms'")
            lines.append("if ! command -v lms &>/dev/null; then")
            lines.append("  if [ -x \"/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms\" ]; then")
            lines.append("    LMS_CMD=\"/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms\"")
            lines.append("  fi")
            lines.append("fi")
            lines.append("LOCAL_MODEL_ID=\(shellSingleQuote(providerModelId))")
            lines.append("LOCAL_MODEL_NAME=\(shellSingleQuote(resolvedLocalModel))")
            lines.append("download_model_candidate() {")
            lines.append("  local query=\"$1\"")
            lines.append("  local provider_id=\"$2\"")
            lines.append("  local display_name=\"$3\"")
            lines.append("  [ -z \"$query\" ] && return 1")
            lines.append("  echo \"  → Checking LM Studio recommendation: $display_name ($query)\"")
            lines.append("  if $LMS_CMD get \"$query\" --gguf -y; then")
            lines.append("    LOCAL_MODEL_ID=\"$provider_id\"")
            lines.append("    LOCAL_MODEL_NAME=\"$display_name\"")
            lines.append("    return 0")
            lines.append("  fi")
            lines.append("  if [[ \"$query\" == *@* ]]; then")
            lines.append("    local base_query=\"${query%@*}\"")
            lines.append("    echo \"  → Exact quant unavailable. Asking LM Studio for best variant: $base_query\"")
            lines.append("    if $LMS_CMD get \"$base_query\" --gguf -y; then")
            lines.append("      LOCAL_MODEL_ID=\"$provider_id\"")
            lines.append("      LOCAL_MODEL_NAME=\"$display_name\"")
            lines.append("      return 0")
            lines.append("    fi")
            lines.append("  fi")
            lines.append("  return 1")
            lines.append("}")
            lines.append("MODEL_READY=0")
            for candidate in dynamicLocalCandidates {
                lines.append("if [ \"$MODEL_READY\" != \"1\" ]; then")
                lines.append("  download_model_candidate \(shellSingleQuote(candidate.query)) \(shellSingleQuote(candidate.providerId)) \(shellSingleQuote(candidate.name)) && MODEL_READY=1 || true")
                lines.append("fi")
            }
            lines.append("if [ \"$MODEL_READY\" != \"1\" ]; then")
            lines.append("  echo \"  ✕ No compatible LM Studio model could be downloaded\"")
            lines.append("  echo \"model:FAIL\" >> /tmp/localclaw_status")
            lines.append("  exit 1")
            lines.append("fi")
            lines.append("echo \"  ✓ Model ready: $LOCAL_MODEL_NAME\"")
            lines.append("echo \"model:OK\" >> /tmp/localclaw_status")
        } else {
            lines.append("")
            lines.append("echo \"\"")
            lines.append("echo \"[2/7] Skipping LM Studio (Cloud LLM only)\"")
            lines.append("echo \"lmstudio:SKIP\" >> /tmp/localclaw_status")
            lines.append("")
            lines.append("echo \"\"")
            lines.append("echo \"[3/7] Skipping local model (Cloud LLM only)\"")
            lines.append("echo \"model:SKIP\" >> /tmp/localclaw_status")
        }
        
        lines.append("")
        lines.append("echo \"\"")
        lines.append("echo \"[4/7] Installing Node.js...\"")
        lines.append("if command -v node &>/dev/null; then")
        lines.append("    echo \"  ✓ Already installed\"")
        lines.append("    echo \"node:OK\" >> /tmp/localclaw_status")
        lines.append("else")
        lines.append("    echo \"  → Installing...\"")
        lines.append("    brew install node")
        lines.append("    echo \"node:OK\" >> /tmp/localclaw_status")
        lines.append("fi")
        lines.append("")
        lines.append("echo \"\"")
        lines.append("echo \"[5/7] Installing OpenClaw...\"")
        lines.append("if command -v openclaw &>/dev/null; then")
        lines.append("    echo \"  ✓ Already installed\"")
        lines.append("    echo \"openclaw:OK\" >> /tmp/localclaw_status")
        lines.append("else")
        lines.append("    echo \"  → Installing...\"")
        lines.append("    npm i -g openclaw@latest")
        lines.append("    echo \"openclaw:OK\" >> /tmp/localclaw_status")
        lines.append("fi")
        // Generate token in Swift using only alphanumeric characters
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var gatewayTokenValue = ""
        for _ in 0..<64 {
            gatewayTokenValue.append(chars.randomElement()!)
        }
        
        lines.append("")
        lines.append("echo \"\"")
        lines.append("echo \"[6/7] Configuring OpenClaw...\"")
        lines.append("mkdir -p ~/.openclaw")
        lines.append("GATEWAY_TOKEN=\"\(gatewayTokenValue)\"")
        lines.append("echo \"$GATEWAY_TOKEN\" > /tmp/localclaw_token")
        lines.append("cat > ~/.openclaw/openclaw.json << EOF")
        lines.append("{")
        lines.append("  \"gateway\": {")
        lines.append("    \"mode\": \"local\",")
        lines.append("    \"port\": 18789,")
        lines.append("    \"auth\": {")
        lines.append("      \"mode\": \"token\",")
        lines.append("      \"token\": \"\(gatewayTokenValue)\"")
        lines.append("    }")
        lines.append("  },")
        lines.append("  \"agents\": {")
        lines.append("    \"defaults\": {")
        lines.append("      \"model\": {")
        lines.append("        \"primary\": \"\(installLMStudio ? "lmstudio/${LOCAL_MODEL_ID}" : modelId)\"")
        lines.append("      },")
        lines.append("      \"sandbox\": {")
        lines.append("        \"mode\": \"off\"")
        lines.append("      }")
        lines.append("    }")
        lines.append("  }")
        if installLMStudio {
            lines.append("  ,\"models\": {")
            lines.append("    \"mode\": \"merge\",")
            lines.append("    \"providers\": {")
            lines.append("      \"lmstudio\": {")
            lines.append("        \"baseUrl\": \"http://127.0.0.1:1234/v1\",")
            lines.append("        \"apiKey\": \"lmstudio\",")
            lines.append("        \"api\": \"openai-completions\",")
            lines.append("        \"models\": [")
            lines.append("          { \"id\": \"${LOCAL_MODEL_ID}\", \"name\": \"${LOCAL_MODEL_NAME}\", \"reasoning\": false, \"input\": [\"text\"], \"cost\": { \"input\": 0, \"output\": 0, \"cacheRead\": 0, \"cacheWrite\": 0 }, \"contextWindow\": 32768, \"maxTokens\": 4096 }")
            lines.append("        ]")
            lines.append("      }")
            lines.append("    }")
            lines.append("  },")
            lines.append("  \"tools\": {")
            lines.append("    \"deny\": [\"group:web\", \"browser\", \"web_search\", \"web_fetch\"]")
            lines.append("  }")
        }
        lines.append("}")
        lines.append("EOF")
        lines.append("echo \"  ✓ Config saved with token\"")
        lines.append("echo \"config:OK\" >> /tmp/localclaw_status")
        // Create auth file BEFORE starting gateway
        if !apiKey.isEmpty && !authProvider.isEmpty {
            let escapedKey = apiKey.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("")
            lines.append("echo \"\"")
            lines.append("echo \"[6b/7] Configuring API key...\"")
            lines.append("mkdir -p ~/.openclaw/agents/main/agent")
            lines.append("cat > ~/.openclaw/agents/main/agent/auth-profiles.json << 'EOF'")
            lines.append("{")
            lines.append("  \"version\": 1,")
            lines.append("  \"profiles\": {")
            lines.append("    \"\(authProvider):default\": {")
            lines.append("      \"type\": \"api_key\",")
            lines.append("      \"provider\": \"\(authProvider)\",")
            lines.append("      \"key\": \"\(escapedKey)\"")
            lines.append("    }")
            lines.append("  }")
            lines.append("}")
            lines.append("EOF")
            lines.append("chmod 600 ~/.openclaw/agents/main/agent/auth-profiles.json")
            lines.append("echo \"  ✓ API key configured\"")
        }
        lines.append("")
        lines.append("echo \"\"")
        lines.append("echo \"[7/7] Installing Gateway service and starting...\"")
        lines.append("openclaw gateway stop 2>/dev/null || true")
        lines.append("sleep 1")
        lines.append("openclaw gateway uninstall 2>/dev/null || true")
        lines.append("sleep 1")
        lines.append("openclaw gateway install 2>&1")
        lines.append("sleep 2")
        lines.append("openclaw gateway start 2>&1 &")
        lines.append("sleep 6")
        lines.append("")
        lines.append("echo \"\"")
        lines.append("echo \"→ Checking Gateway status...\"")
        lines.append("STATUS=$(openclaw gateway status 2>&1)")
        lines.append("echo \"  $STATUS\"")
        lines.append("if echo \"$STATUS\" | grep -q -E \"(running|Online)\"; then")
        lines.append("    echo \"  ✓ Gateway is running\"")
        lines.append("    echo \"  ✓ Dashboard: http://localhost:18789\"")
        lines.append("    echo \"service:OK\" >> /tmp/localclaw_status")
        lines.append("else")
        lines.append("    echo \"  ✗ Gateway failed to start\"")
        lines.append("fi")
        lines.append("echo \"done\" >> /tmp/localclaw_status")
        lines.append("touch /tmp/localclaw_install_done")
        lines.append("")
        lines.append("echo \"\"")
        lines.append("echo \"==========================================\"")
        lines.append("echo \"  Installation Complete!\"")
        lines.append("echo \"==========================================\"")
        lines.append("echo \"\"")
        lines.append("echo \"Gateway URL: http://localhost:18789\"")
        lines.append("echo \"Dashboard: http://localhost:18789/dashboard\"")
        lines.append("echo \"\"")
        lines.append("read -p \"Press Enter to close...\"")
        
        let script = lines.joined(separator: "\n")
        let path = "/tmp/localclaw_install.sh"
        try? script.write(toFile: path, atomically: true, encoding: String.Encoding.utf8)
        _ = engine.shell("chmod +x \(path)")
        _ = engine.shell("open -a Terminal \(path)")
        
        screen = .install
        isRunning = true
        startPollingForInstallCompletion()
        append("Terminal opened! Installation is running in Terminal window.")
        append("LocalClaw will detect when installation is complete.")
    }
    
    private var installPollTask: Task<Void, Never>?

    private func startPollingForInstallCompletion() {
        installPollTask?.cancel()
        installPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastStatusCount = 0

            while !Task.isCancelled {
                if let statusContent = try? String(contentsOfFile: "/tmp/localclaw_status", encoding: .utf8) {
                    let lines = statusContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    if lines.count > lastStatusCount {
                        let newLines = Array(lines.suffix(from: lastStatusCount))
                        lastStatusCount = lines.count

                        for line in newLines {
                            let parts = line.components(separatedBy: ":")
                            if parts.count == 2 {
                                let component = parts[0]
                                let status = parts[1]
                                self.append("[\(component)] \(status)")

                                if component == "homebrew" { self.statusHomebrew = status }
                                if component == "lmstudio" { self.statusLMStudio = status }
                                if component == "model" { self.statusModel = status }
                                if component == "node" { self.statusNodeJS = status }
                                if component == "openclaw" { self.statusOpenClaw = status }
                                if component == "config" { self.statusConfig = status }
                                if component == "service" { self.statusService = status }
                            }
                        }
                    }
                }

                if FileManager.default.fileExists(atPath: "/tmp/localclaw_install_done") {
                    try? FileManager.default.removeItem(atPath: "/tmp/localclaw_install_done")
                    try? FileManager.default.removeItem(atPath: "/tmp/localclaw_status")
                    try? FileManager.default.removeItem(atPath: "/tmp/localclaw_token")

                    self.loadTokenFromConfig()
                    if !self.gatewayToken.isEmpty {
                        self.append("✓ Token synced from config: \(self.gatewayToken.prefix(16))...")
                    }

                    self.isRunning = false
                    self.refreshVersions()
                    self.screen = .ready
                    self.append("Installation completed!")
                    break
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func runOpenClawGuidedSetup() {
        if isRunning { return }
        let errors = setupValidationErrors
        if !errors.isEmpty {
            append("Setup validation failed")
            errors.forEach { append("  ↳ \($0)") }
            return
        }
        isRunning = true

        let engine = self.engine
        let token = self.gatewayToken
        let modelId = self.effectiveModelIdentifier()
        let authProvider = self.effectiveAuthProvider()
        let apiKey = self.requiredProviderKey()

        Task.detached {
            let clt = engine.ensureXcodeCLITools()
            if clt.state == .fail {
                await MainActor.run {
                    self.ocStepNode = clt.state.rawValue
                    self.statusNode = clt.state.rawValue
                    self.append("[\(clt.state.rawValue)] Preflight - Xcode CLI Tools")
                    self.append("  \(clt.message)")
                    self.append("Setup blocked: Xcode CLI Tools are required before installing OpenClaw.")
                    self.isRunning = false
                }
                return
            }

            let brew = engine.installHomebrewIfNeeded()
            if brew.state == .fail {
                await MainActor.run {
                    self.ocStepNode = brew.state.rawValue
                    self.statusNode = brew.state.rawValue
                    self.append("[\(clt.state.rawValue)] Preflight - Xcode CLI Tools")
                    self.append("  \(clt.message)")
                    self.append("[\(brew.state.rawValue)] Preflight - Homebrew")
                    self.append("  \(brew.message)")
                    self.append("Setup blocked: Homebrew is required before installing Node and OpenClaw.")
                    self.isRunning = false
                }
                return
            }

            let brewDoctor = engine.runBrewDoctorCheck()
            if brewDoctor.state == .fail {
                await MainActor.run {
                    self.ocStepNode = brewDoctor.state.rawValue
                    self.statusNode = brewDoctor.state.rawValue
                    self.append("[\(clt.state.rawValue)] Preflight - Xcode CLI Tools")
                    self.append("  \(clt.message)")
                    self.append("[\(brew.state.rawValue)] Preflight - Homebrew")
                    self.append("  \(brew.message)")
                    self.append("[\(brewDoctor.state.rawValue)] Preflight - Brew Doctor")
                    self.append("  \(brewDoctor.message)")
                    self.append("Setup blocked: fix Homebrew health before installing OpenClaw.")
                    self.isRunning = false
                }
                return
            }

            let node = engine.installNodeIfNeeded()
            let existing = engine.hasCommand("openclaw")
            let cli = existing
                ? StepResult(state: .skip, message: "OpenClaw already installed, switching to modify mode")
                : engine.installOpenClawIfNeeded()

            // Bug 5: Write gateway.mode=local and token BEFORE verify
            let configResult = engine.writeOpenClawConfig(gatewayToken: token)

            // Bug 6: Write selected model to config
            let modelResult = engine.writeModelToConfig(modelIdentifier: modelId)

            // Bug 6: Write API key if provided
            let keyResult = engine.writeApiKeyToConfig(provider: authProvider, apiKey: apiKey == "kimi-free" ? "" : apiKey)

            // Install gateway service and create agent
            let gatewayServiceResult = engine.installGatewayService()
            let agentResult = engine.createDefaultAgent()
            let startGatewayResult = engine.startGateway()

            let repair = engine.repairOpenClawSetupQuiet()
            let verify = engine.verifyOpenClawSetup()

            await MainActor.run {
                self.hasExistingOpenClawSetup = existing || cli.state == .ok
                self.ocStepNode = node.state.rawValue
                self.ocStepCli = cli.state.rawValue
                self.ocStepRepair = repair.state.rawValue
                self.ocStepVerify = verify.state.rawValue

                self.statusNode = node.state.rawValue
                self.statusOpenClaw = cli.state.rawValue
                self.statusOpenClawCheck = verify.state.rawValue

                self.append("[\(clt.state.rawValue)] Preflight - Xcode CLI Tools")
                self.append("  \(clt.message)")
                self.append("[\(brew.state.rawValue)] Preflight - Homebrew")
                self.append("  \(brew.message)")
                self.append("[\(brewDoctor.state.rawValue)] Preflight - Brew Doctor")
                self.append("  \(brewDoctor.message)")
                self.append("[\(node.state.rawValue)] Step 1 - Node")
                self.append("  \(node.message)")
                self.append("[\(cli.state.rawValue)] Step 2 - OpenClaw CLI")
                self.append("  \(cli.message)")
                self.append("[\(configResult.state.rawValue)] Step 2b - Write gateway config")
                self.append("  \(configResult.message)")
                self.append("[\(modelResult.state.rawValue)] Step 2c - Write model config")
                self.append("  \(modelResult.message)")
                if keyResult.state != .skip {
                    self.append("[\(keyResult.state.rawValue)] Step 2d - Write API key")
                    self.append("  \(keyResult.message)")
                }
                self.append("[\(gatewayServiceResult.state.rawValue)] Step 2e - Install gateway service")
                self.append("  \(gatewayServiceResult.message)")
                self.append("[\(agentResult.state.rawValue)] Step 2f - Create default agent")
                self.append("  \(agentResult.message)")
                self.append("[\(startGatewayResult.state.rawValue)] Step 2g - Start gateway")
                self.append("  \(startGatewayResult.message)")
                self.append("[\(repair.state.rawValue)] Step 3 - Apply config changes")
                self.append("  \(repair.message)")
                self.append("[\(verify.state.rawValue)] Step 4 - Verify gateway")
                self.append("  \(verify.message)")

                self.isRunning = false
                self.screen = .ready
            }
        }
    }

    private func runStep(name: String, action: @escaping () -> StepResult) async -> StepResult {
        let result = action()
        await MainActor.run {
            switch name {
            case "Homebrew": self.statusHomebrew = result.state.rawValue
            case "LM Studio": self.statusLMStudio = result.state.rawValue
            case "Model": self.statusModel = result.state.rawValue
            case "Node": self.statusNode = result.state.rawValue
            case "OpenClaw": self.statusOpenClaw = result.state.rawValue
            case "OpenClaw Check": self.statusOpenClawCheck = result.state.rawValue
            default: break
            }
            self.append("[\(result.state.rawValue)] \(name)")
            if !result.message.isEmpty {
                self.append("  ↳ \(result.message)")
            }
        }
        return result
    }

    private func runModelStep(engine: InstallerEngine, query: String) async {
        await MainActor.run {
            self.statusModel = "PENDING"
            self.currentDownloadFile = query
            self.downloadProgress = 0
        }
        let result = engine.installModelStreaming(query) { line in
            Task { @MainActor in
                self.append(line)
            }
        }
        await MainActor.run {
            self.statusModel = result.state.rawValue
            if result.state == .ok || result.state == .skip {
                self.downloadProgress = 1.0
            }
            self.append("[\(result.state.rawValue)] Model")
        }
    }

    func refreshUninstallInventory() {
        hasLMStudioInstalled = engine.hasLMStudioApp()
        hasLocalModelsInstalled = FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.lmstudio/models") ||
            FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.cache/lm-studio/models")
        hasOpenClawInstalled = engine.hasCommand("openclaw") ||
            FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.openclaw")
        hasNodeInstalled = engine.hasCommand("node")
        hasHomebrewInstalled = engine.hasCommand("brew")
        hasConfigCacheInstalled = FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.openclaw") ||
            FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.openclaw-gateway") ||
            FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.cache/openclaw") ||
            FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.cache/lm-studio")
    }

    func runSelectedUninstall() {
        if isUninstalling { return }

        let plan: [(String, Bool, [String])] = [
            ("LM Studio", uninstallLMStudioSelected, [
                "brew uninstall --cask lm-studio 2>/dev/null || true",
                "rm -rf \"/Applications/LM Studio.app\"",
                "rm -rf \"$HOME/.cache/lm-studio\""
            ]),
            ("Local LLM models", uninstallModelsSelected, [
                "rm -rf \"$HOME/.lmstudio/models\"",
                "rm -rf \"$HOME/.cache/lm-studio/models\""
            ]),
            ("OpenClaw", uninstallOpenClawSelected, [
                "npm uninstall -g openclaw 2>/dev/null || true",
                "brew uninstall openclaw 2>/dev/null || true",
                "rm -rf \"$HOME/.openclaw\" \"$HOME/.openclaw-gateway\" \"$HOME/.cache/openclaw\""
            ]),
            ("Node.js", uninstallNodeSelected, [
                "brew uninstall node 2>/dev/null || true",
                "rm -f /opt/homebrew/bin/node /opt/homebrew/bin/npm /opt/homebrew/bin/npx /opt/homebrew/bin/corepack 2>/dev/null || true",
                "rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack 2>/dev/null || true",
                "rm -rf \"$HOME/.npm\" \"$HOME/.nvm\" \"$HOME/.node-gyp\""
            ]),
            ("Homebrew", uninstallHomebrewSelected, [
                "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\" || true"
            ]),
            ("Configs and cache", uninstallConfigsSelected, [
                "rm -rf \"$HOME/.openclaw\" \"$HOME/.openclaw-gateway\" \"$HOME/.cache/openclaw\" \"$HOME/.cache/lm-studio\"",
                "sed -i '' '/openclaw/d' \"$HOME/.zshrc\" 2>/dev/null || true",
                "sed -i '' '/nvm/d' \"$HOME/.zshrc\" 2>/dev/null || true"
            ])
        ]

        uninstallLogs = ""
        isUninstalling = true

        Task.detached { [engine] in
            for (name, selected, commands) in plan {
                if !selected { continue }
                await MainActor.run { self.uninstallAppend("[RUN] \(name)") }
                for cmd in commands {
                    let (code, output) = engine.shell(cmd)
                    await MainActor.run {
                        self.uninstallAppend("$ \(cmd)")
                        if !output.isEmpty { self.uninstallAppend(output) }
                        if code != 0 { self.uninstallAppend("[WARN] Exit code \(code) on \(name)") }
                    }
                }
                await MainActor.run { self.uninstallAppend("[DONE] \(name)") }
            }

            await MainActor.run {
                self.uninstallAppend("✅ Uninstall finished")
                self.isUninstalling = false
                self.refreshUninstallInventory()
            }
        }
    }

    private func uninstallAppend(_ line: String) {
        uninstallLogs = uninstallLogs.isEmpty ? line : uninstallLogs + "\n" + line
    }

    private func append(_ line: String) {
        logs = logs.isEmpty ? line : logs + "\n" + line

        if let fileMatch = line.range(of: #"([A-Za-z0-9._-]+\.gguf)"#, options: .regularExpression) {
            currentDownloadFile = String(line[fileMatch])
        }

        if let pctMatch = line.range(of: #"\b(\d{1,3})%\b"#, options: .regularExpression) {
            let pctString = String(line[pctMatch]).replacingOccurrences(of: "%", with: "")
            if let pct = Double(pctString) {
                downloadProgress = max(0, min(1, pct / 100.0))
            }
        }
    }
}

enum UI {
    static let bg = adaptive(light: NSColor(red: 0.95, green: 0.95, blue: 0.94, alpha: 1), dark: NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
    static let bg2 = adaptive(light: NSColor(red: 0.94, green: 0.94, blue: 0.93, alpha: 1), dark: NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1))
    static let card = adaptive(light: NSColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1), dark: NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1))
    static let cardSoft = adaptive(light: NSColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1), dark: NSColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1))
    static let accent = Color(red: 1.00, green: 0.30, blue: 0.24)
    static let accent2 = Color(red: 1.00, green: 0.42, blue: 0.24)
    static let text = adaptive(light: NSColor(red: 0.12, green: 0.17, blue: 0.28, alpha: 1), dark: NSColor(red: 0.93, green: 0.93, blue: 0.91, alpha: 1))
    static let muted = adaptive(light: NSColor(red: 0.37, green: 0.45, blue: 0.57, alpha: 1), dark: NSColor(red: 0.62, green: 0.62, blue: 0.60, alpha: 1))
    static let line = adaptive(light: NSColor.black.withAlphaComponent(0.10), dark: NSColor.white.withAlphaComponent(0.12))
    static let lineSoft = adaptive(light: NSColor.black.withAlphaComponent(0.06), dark: NSColor.white.withAlphaComponent(0.08))

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            let best = appearance.bestMatch(from: [.darkAqua, .aqua])
            return best == .darkAqua ? dark : light
        })
    }
}

enum AppFont {
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func body(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .default) }
    static func bodySemi(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .default) }
}

struct CTAButton: ButtonStyle {
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.heading(15))
            .kerning(0.6)
            .foregroundStyle(primary ? .white : UI.text)
            .padding(.vertical, 14)
            .padding(.horizontal, 26)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(primary ? UI.accent : UI.cardSoft)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? UI.accent : Color.black.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(primary ? 0.10 : 0.06), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}

struct CompactChatButton: ButtonStyle {
    var primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.bodySemi(12))
            .foregroundStyle(primary ? .white : UI.text)
            .lineLimit(1)
            .padding(.vertical, 8)
            .padding(.horizontal, 13)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(primary ? UI.accent : UI.cardSoft)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? UI.accent : UI.lineSoft, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}

struct CompactGhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.bodySemi(12))
            .foregroundStyle(UI.text)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(UI.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(UI.line, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct ChoiceCard: View {
    let title: String
    let subtitle: String
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(UI.text)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(UI.muted)
                }
                Spacer()
                Image(systemName: highlighted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(highlighted ? UI.accent : UI.muted.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(highlighted ? UI.accent.opacity(0.07) : UI.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(highlighted ? UI.accent : Color.black.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}


struct HomeTile: View {
    let label: String
    let icon: String
    let selected: Bool
    var subtitle: String? = nil
    var status: String? = nil
    let action: () -> Void

    private var iconColor: Color {
        selected ? UI.accent : UI.text
    }

    private var cardFill: AnyShapeStyle {
        selected
            ? AnyShapeStyle(LinearGradient(colors: [UI.accent.opacity(0.18), UI.accent2.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(LinearGradient(colors: [UI.card, UI.cardSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var cardStroke: Color {
        selected ? UI.accent.opacity(0.45) : UI.line
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(cardFill)

                    Image(systemName: icon)
                        .font(.system(size: 64, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(iconColor)
                        .offset(y: -4)
                }
                .frame(width: 180, height: 180)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(cardStroke, lineWidth: selected ? 1.5 : 1))
                .shadow(color: selected ? UI.accent.opacity(0.10) : Color.black.opacity(0.06), radius: selected ? 12 : 8, x: 0, y: 6)

                VStack(spacing: 5) {
                    Text(label)
                        .font(AppFont.bodySemi(18))
                        .foregroundStyle(UI.text)
                        .multilineTextAlignment(.center)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    if let status {
                        Label(status, systemImage: status == "Ready" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(AppFont.bodySemi(11))
                            .foregroundStyle(status == "Ready" ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
                    }
                }
                .frame(width: 180)
            }
            .frame(width: 190)
        }
        .buttonStyle(.plain)
    }
}

struct SheetActionButton: ButtonStyle {
    var primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.bodySemi(14))
            .foregroundStyle(primary ? .white : UI.text)
            .lineLimit(1)
            .frame(minWidth: primary ? 150 : 96, minHeight: 42)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(primary ? UI.accent : UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(primary ? UI.accent : UI.lineSoft, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct PresetPillButton: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.bodySemi(12))
            .foregroundStyle(selected ? .white : UI.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? UI.accent : UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? UI.accent : UI.lineSoft, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct DeveloperWebPreview: NSViewRepresentable {
    let urlString: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        load(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url?.absoluteString != normalizedURL?.absoluteString {
            load(webView)
        }
    }

    private var normalizedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "http://\(trimmed)")
    }

    private func load(_ webView: WKWebView) {
        guard let url = normalizedURL else { return }
        webView.load(URLRequest(url: url))
    }
}

struct ProgressSteps: View {
    let screen: InstallerViewModel.Screen

    private var idx: Int {
        switch screen {
        case .license: return 0
        case .onboarding: return 0
        case .home: return 0
        case .options: return 1
        case .install: return 2
        case .ready: return 3
        case .updates: return 3
        case .controlCenter: return 0
        case .commandCenter: return 0
        case .uninstallCenter: return 0
        case .channelSetup: return 0
        case .agents: return 0
        case .cronJobs: return 0
        case .healthCenter: return 0
        case .usageCenter: return 0
        case .chat: return 0
        case .models: return 0
        case .skills: return 0
        case .developer: return 0
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            step("Choose", 1)
            line
            step("Options", 2)
            line
            step("Install", 3)
            line
            step("Ready", 4)
        }
    }

    private var line: some View {
        RoundedRectangle(cornerRadius: 99)
            .fill(UI.line)
            .frame(height: 3)
    }

    private func step(_ label: String, _ number: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(idx + 1 >= number ? UI.accent : UI.line)
                .frame(width: 18, height: 18)
            Text(label)
                .font(AppFont.bodySemi(12))
                .foregroundStyle(idx + 1 >= number ? UI.text : UI.muted)
        }
    }
}

struct BrandLogoView: View {
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let logoPath = Bundle.main.path(forResource: "localclaw-logo", ofType: "png"),
               let logo = NSImage(contentsOfFile: logoPath) {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(UI.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct ContentView: View {
    enum HelpTab: String, CaseIterable, Identifiable {
        case stepByStep = "Step by step"
        case faq = "FAQ"
        case healthCommands = "Health commands"

        var id: String { rawValue }
    }

    @StateObject private var vm = InstallerViewModel()
    @State private var helpTab: HelpTab = .stepByStep
    @State private var isSidebarVisible = true
    @AppStorage("localclaw.appearance") private var appearance = "dark"

    var body: some View {
        ZStack {
            LinearGradient(colors: [UI.bg, UI.bg2], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            if vm.screen == .license || vm.screen == .onboarding {
                VStack(spacing: 16) {
                    topBar
                    if vm.screen == .license {
                        license
                    } else {
                        onboarding
                    }
                }
                .frame(maxWidth: 1120)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            } else {
                HStack(spacing: 16) {
                    if isSidebarVisible {
                        sidebar
                            .frame(width: 240)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    VStack(spacing: 14) {
                        topBar

                        Group {
                            switch vm.screen {
                            case .license: license
                            case .onboarding: onboarding
                            case .home: home
                            case .options: options
                            case .install: install
                            case .ready: ready
                            case .updates: updates
                            case .controlCenter: controlCenter
                            case .commandCenter: commandCenter
                            case .uninstallCenter: uninstallCenter
                            case .channelSetup: channelSetup
                            case .agents: agentsCenter
                            case .cronJobs: cronJobsCenter
                            case .healthCenter: healthCenter
                            case .usageCenter: usageCenter
                            case .chat: openClawChat
                            case .models: modelsCenter
                            case .skills: skillsCenter
                            case .developer: developerCenter
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReturnToHome"))) { _ in
            vm.screen = .home
        }
        .frame(minWidth: 1100, idealWidth: 1440, maxWidth: .infinity,
               minHeight: 760, idealHeight: 920, maxHeight: .infinity)
        .preferredColorScheme(appearance == "light" ? .light : .dark)
        .onAppear { vm.bootstrap() }
        .sheet(isPresented: $vm.showCronJobCreator) {
            cronJobCreatorSheet
        }
        .alert("Homebrew Required", isPresented: $vm.showHomebrewPrompt) {
            Button("Install Homebrew", role: .none) { vm.installHomebrewWithUserConsent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Homebrew is needed to install LM Studio, Node.js and OpenClaw. Click 'Install Homebrew' and enter your Mac password when prompted.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(UI.text)
            .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
            .help(isSidebarVisible ? "Hide navigation" : "Show navigation")

            BrandLogoView(size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("LocalClaw")
                    .font(AppFont.bodySemi(18))
                    .foregroundStyle(UI.text)
                Text("Version \(vm.installerCurrentVersion) (build \(vm.installerBuildNumber))")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
            }

            Text(vm.inferenceMode.rawValue.uppercased())
                .font(AppFont.bodySemi(10))
                .foregroundStyle(vm.inferenceMode == .local ? Color(NSColor.systemGreen) : UI.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))

            Spacer()

            HStack(alignment: .top, spacing: 10) {
                Picker("", selection: $appearance) {
                    Image(systemName: "moon.fill").tag("dark")
                    Image(systemName: "sun.max.fill").tag("light")
                }
                .pickerStyle(.segmented)
                .tint(UI.accent)
                .frame(width: 82)
                .help("Switch appearance")

                VStack(alignment: .trailing, spacing: 4) {
                Picker("", selection: $vm.inferenceMode) {
                    Text("Cloud LLM").tag(InstallerViewModel.InferenceMode.cloud)
                    Text("OAuth LLM").tag(InstallerViewModel.InferenceMode.oauth)
                    Text("Local LLM").tag(InstallerViewModel.InferenceMode.local)
                }
                .pickerStyle(.segmented)
                .tint(UI.accent)
                .frame(width: 270)
                .onChange(of: vm.inferenceMode) { _ in
                    vm.applyInferenceModeSwitch()
                }

                if !vm.modeSwitchStatus.isEmpty || vm.modeSwitchInProgress {
                    Text(vm.modeSwitchInProgress ? "Switching..." : vm.modeSwitchStatus)
                        .font(AppFont.body(10))
                        .foregroundStyle(vm.modeSwitchInProgress ? UI.accent : Color(NSColor.systemGreen))
                }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAVIGATION")
                .font(AppFont.heading(10))
                .kerning(0.6)
                .foregroundStyle(UI.muted)
                .padding(.bottom, 4)

            sidebarButton("Home", icon: "house", isActive: vm.screen == .home) { vm.screen = .home }
            sidebarButton("Install", icon: "plus.circle", isActive: vm.screen == .options || vm.screen == .install || vm.screen == .ready) {
                vm.chooseMode(.fullInstall)
            }
            sidebarButton("Updates", icon: "arrow.clockwise", isActive: vm.screen == .updates) { vm.screen = .updates }
            sidebarButton("Control Center", icon: "slider.horizontal.3", isActive: vm.screen == .commandCenter) { vm.screen = .commandCenter }
            sidebarButton("OpenClaw Chat", icon: "message.badge.waveform", isActive: vm.screen == .chat, isBeta: true) { vm.screen = .chat }
            sidebarButton("Developer", icon: "curlybraces.square", isActive: vm.screen == .developer, isBeta: true) { vm.screen = .developer }
            sidebarButton("Models", icon: "cpu", isActive: vm.screen == .models) { vm.screen = .models }
            sidebarButton("Skills", icon: "wand.and.stars", isActive: vm.screen == .skills) { vm.screen = .skills }
            sidebarButton("Channels", icon: "bubble.left.and.bubble.right", isActive: vm.screen == .channelSetup, isBeta: true) { vm.screen = .channelSetup }
            sidebarButton("Agents", icon: "person.2.wave.2", isActive: vm.screen == .agents) { vm.screen = .agents }
            sidebarButton("Cron Jobs", icon: "calendar.badge.clock", isActive: vm.screen == .cronJobs, isBeta: true) { vm.screen = .cronJobs }
            sidebarButton("Help", icon: "cross.case", isActive: vm.screen == .healthCenter) { vm.screen = .healthCenter }
            sidebarButton("Uninstall", icon: "trash", isActive: vm.screen == .uninstallCenter) { vm.screen = .uninstallCenter }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("Machine")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                Text("\(vm.chip)")
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                    .lineLimit(2)
                Text(vm.ram)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)

                if !vm.machineDetails.isEmpty {
                    Divider().padding(.vertical, 3)
                    Text(vm.machineDetails)
                        .font(AppFont.body(10))
                        .foregroundStyle(UI.muted)
                        .lineSpacing(2)
                }

                HStack(spacing: 8) {
                    Button {
                        vm.refreshMachineDetails()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .lineLimit(1)
                    }
                    .buttonStyle(CompactGhostButton())

                    Button {
                        vm.copyMachineDetails()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .lineLimit(1)
                    }
                    .buttonStyle(CompactGhostButton())
                }
                .padding(.top, 4)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func sidebarButton(_ title: String, icon: String, isActive: Bool, isBeta: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .font(AppFont.bodySemi(13))
                Spacer()
                if isBeta {
                    betaBadge(isActive: isActive)
                }
            }
            .foregroundStyle(isActive ? .white : UI.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(isActive ? UI.accent : UI.cardSoft))
        }
        .buttonStyle(.plain)
    }

    private func betaBadge(isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? Color.white.opacity(0.9) : Color(NSColor.systemBlue))
                .frame(width: 6, height: 6)
            Text("BETA")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? .white : Color(NSColor.systemBlue))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 3).fill(isActive ? Color.white.opacity(0.13) : Color(NSColor.systemBlue).opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(isActive ? Color.white.opacity(0.35) : Color(NSColor.systemBlue), lineWidth: 1))
        .help("Beta section: this area is still evolving and may contain bugs.")
    }

    var license: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 14) {
                Text("Activate your purchase")
                    .font(AppFont.heading(34))
                    .foregroundStyle(UI.text)

                Text("Enter the same email used at checkout and your unique license key.")
                    .font(AppFont.body(15))
                    .foregroundStyle(UI.muted)

                TextField("Email", text: $vm.licenseEmail)
                    .textFieldStyle(.roundedBorder)
                SecureField("Enter your license key", text: $vm.licenseKey)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button(vm.isActivating ? "ACTIVATING..." : "ACTIVATE") { vm.activateLicense() }
                        .buttonStyle(CTAButton(primary: true))
                        .disabled(vm.isActivating)

                    if vm.isMockLicenseEndpoint {
                        Button("Use test credentials") { vm.useTestLicense() }
                            .buttonStyle(CTAButton(primary: false))
                    }

                    if vm.isActivated {
                        Button("Reset activation") { vm.clearLicense() }
                            .buttonStyle(CTAButton(primary: false))
                    }
                }

                Text(vm.activationStatus)
                    .font(AppFont.body(13))
                    .foregroundStyle(vm.isActivated ? UI.accent : UI.muted)
            }
            .padding(22)
            .frame(maxWidth: 620, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
    }

    var onboarding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to LocalClaw")
                    .font(AppFont.heading(34))
                    .foregroundStyle(UI.text)
                Text("Quick first-run setup. This guide appears only once.")
                    .font(AppFont.body(14))
                    .foregroundStyle(UI.muted)

                VStack(alignment: .leading, spacing: 10) {
                    helpStepCard(number: 1, title: "Choose your mode", detail: "Cloud LLM uses API keys. OAuth LLM uses ChatGPT/Codex login. Local LLM runs offline.", icon: "slider.horizontal.3", tint: UI.accent)
                    helpStepCard(number: 2, title: "Pick provider auth", detail: "Cloud LLM supports OpenRouter/OpenAI/Anthropic/Gemini/xAI. OAuth LLM uses OpenAI.", icon: "person.badge.key", tint: .orange)
                    helpStepCard(number: 3, title: "Run installation", detail: "Go to Install and click Install Everything.", icon: "gearshape.2.fill", tint: .red)
                    helpStepCard(number: 4, title: "Verify success", detail: "Send one test message from Dashboard.", icon: "checkmark.message.fill", tint: .green)
                }

                HStack(spacing: 10) {
                    Button("Start Setup") {
                        vm.markOnboardingCompleted()
                        vm.screen = .options
                    }
                    .buttonStyle(CTAButton(primary: true))

                    Button("Skip to Dashboard") {
                        vm.completeOnboarding()
                    }
                    .buttonStyle(CTAButton(primary: false))
                }

                Text("You can reopen this guide anytime from Help.")
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HOME")
                            .font(AppFont.heading(30))
                            .foregroundStyle(UI.text)
                        Text("Dashboard live de ton installation OpenClaw : santé, consommation, channels, modèle actif et derniers événements.")
                            .font(AppFont.body(13))
                            .foregroundStyle(UI.muted)
                    }
                    Spacer()
                    Button(vm.isRefreshingHome ? "Refreshing..." : "Refresh") { vm.refreshHomeDashboard() }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(vm.isRefreshingHome)
                }

                HStack(spacing: 10) {
                    dashboardKpiCard(
                        title: "Gateway",
                        value: vm.gatewayIsRunning ? "Online" : "Offline",
                        detail: vm.openClawChatModelLabel,
                        icon: "antenna.radiowaves.left.and.right",
                        tint: vm.gatewayIsRunning ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange)
                    )
                    dashboardKpiCard(
                        title: "Health",
                        value: vm.healthStatus,
                        detail: vm.hasMachineUsageSnapshot ? String(format: "CPU %.0f%% · RAM %.1f/%.1f GB", vm.machineCPUPercent, vm.machineMemoryUsedGB, vm.machineMemoryTotalGB) : "Performance check off",
                        icon: "heart.text.square.fill",
                        tint: dashboardHealthTint
                    )
                    dashboardKpiCard(
                        title: "Budget",
                        value: String(format: "$%.2f/mo", vm.estimatedMonthlyCostUSD),
                        detail: String(format: "%.1fM tokens estimated", vm.estimatedMonthlyTokensM),
                        icon: "chart.bar.xaxis",
                        tint: UI.accent
                    )
                    dashboardKpiCard(
                        title: "Channels",
                        value: "\(vm.channels.filter { $0.connected || $0.running }.count) active",
                        detail: "\(vm.channels.count) available · \(vm.channels.reduce(0) { $0 + $1.accounts.count }) accounts",
                        icon: "bubble.left.and.bubble.right.fill",
                        tint: Color(NSColor.systemBlue)
                    )
                }

                dashboardReadinessPanel

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        dashboardPanel(title: "Next best actions", icon: "checklist") {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(dashboardActionItems) { item in
                                    dashboardChecklistRow(item)
                                }
                            }
                        }

                        dashboardPanel(title: "System load", icon: "gauge.with.dots.needle.bottom.50percent") {
                            if vm.hasMachineUsageSnapshot {
                                VStack(alignment: .leading, spacing: 12) {
                                    dashboardMeter("CPU", value: vm.machineCPUPercent / 100, label: String(format: "%.0f%%", vm.machineCPUPercent), tint: UI.accent)
                                    let memoryRatio = vm.machineMemoryTotalGB > 0 ? vm.machineMemoryUsedGB / vm.machineMemoryTotalGB : 0
                                    dashboardMeter("RAM", value: memoryRatio, label: String(format: "%.1f / %.1f GB", vm.machineMemoryUsedGB, vm.machineMemoryTotalGB), tint: Color(NSColor.systemBlue))
                                    let swapRatio = vm.machineSwapTotalGB > 0 ? vm.machineSwapUsedGB / vm.machineSwapTotalGB : 0
                                    dashboardMeter("Swap", value: swapRatio, label: String(format: "%.2f / %.2f GB", vm.machineSwapUsedGB, vm.machineSwapTotalGB), tint: vm.machineSwapUsedGB >= 4 ? Color(NSColor.systemRed) : Color(NSColor.systemOrange))
                                    HStack(spacing: 8) {
                                        dashboardMiniStat("OpenClaw", String(format: "%.0f MB", vm.machineOpenclawMB))
                                        dashboardMiniStat("LM Studio", String(format: "%.0f MB", vm.machineLMStudioMB))
                                        dashboardMiniStat("Node", String(format: "%.0f MB", vm.machineNodeMB))
                                    }
                                    HStack(spacing: 8) {
                                        Button("Refresh performance") { vm.refreshMachineUsageSnapshot() }
                                            .buttonStyle(CTAButton(primary: false))
                                        Button("Stop monitoring") { vm.stopHomePerformanceMonitoring() }
                                            .buttonStyle(CTAButton(primary: false))
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Performance monitoring is paused by default.")
                                        .font(AppFont.bodySemi(13))
                                        .foregroundStyle(UI.text)
                                    Text("Run a manual check when you need CPU, RAM, swap, and process memory details.")
                                        .font(AppFont.body(12))
                                        .foregroundStyle(UI.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button("Check performance") { vm.refreshMachineUsageSnapshot() }
                                        .buttonStyle(CTAButton(primary: false))
                                }
                            }
                        }

                        dashboardPanel(title: "Recent activity", icon: "clock.arrow.circlepath") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(dashboardActivityItems, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(UI.accent)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 6)
                                        Text(item)
                                            .font(AppFont.body(12))
                                            .foregroundStyle(UI.text)
                                            .lineLimit(2)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 14) {
                        dashboardPanel(title: "Working now", icon: "checkmark.seal.fill") {
                            VStack(alignment: .leading, spacing: 9) {
                                dashboardWorkingRow("Chat", value: vm.openClawChatStatus, icon: "message.badge.waveform", healthy: vm.openClawChatStatus == "Ready") {
                                    vm.openOpenClawChat()
                                }
                                dashboardWorkingRow("Channels", value: dashboardChannelsSummary, icon: "bubble.left.and.bubble.right.fill", healthy: dashboardConnectedChannels > 0) {
                                    vm.screen = .channelSetup
                                }
                                dashboardWorkingRow("Skills", value: dashboardSkillsSummary, icon: "wand.and.stars", healthy: dashboardActiveSkills > 0) {
                                    vm.screen = .skills
                                }
                                dashboardWorkingRow("Models", value: vm.openClawChatModelLabel, icon: "cpu.fill", healthy: !dashboardModelNeedsSetup) {
                                    vm.screen = .models
                                }
                                dashboardWorkingRow("Automation", value: dashboardCronSummary, icon: "calendar.badge.clock", healthy: dashboardActiveCronJobs > 0) {
                                    vm.screen = .cronJobs
                                }
                            }
                        }

                        dashboardPanel(title: "Operations", icon: "bolt.horizontal.circle.fill") {
                            VStack(alignment: .leading, spacing: 10) {
                                dashboardActionRow(title: "OpenClaw Chat", detail: vm.openClawChatStatus, icon: "message.badge.waveform") {
                                    vm.openOpenClawChat()
                                }
                                dashboardActionRow(title: "Connect channels", detail: vm.channelsStatus, icon: "plus.message.fill") {
                                    vm.screen = .channelSetup
                                }
                                dashboardActionRow(title: "Manage models", detail: vm.openClawChatModeLabel, icon: "cpu.fill") {
                                    vm.screen = .models
                                }
                                dashboardActionRow(title: "Add skills", detail: vm.skillsStatus, icon: "wand.and.stars") {
                                    vm.screen = .skills
                                }
                            }
                        }

                        dashboardPanel(title: "Configuration", icon: "slider.horizontal.3") {
                            VStack(alignment: .leading, spacing: 10) {
                                dashboardConfigLine("Mode", vm.openClawChatModeLabel, icon: vm.inferenceMode == .local ? "desktopcomputer" : "cloud.fill")
                                dashboardConfigLine("Model", vm.openClawChatModelLabel, icon: "cpu")
                                dashboardConfigLine("LocalClaw", "v\(vm.installerCurrentVersion) · build \(vm.installerBuildNumber)", icon: "app.badge")
                                dashboardConfigLine("OpenClaw", vm.openclawInstalledVersion, icon: "terminal")
                            }
                        }

                        dashboardPanel(title: "Quick actions", icon: "square.grid.2x2.fill") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                dashboardShortcut("Install", icon: "plus.circle.fill") { vm.chooseMode(.fullInstall) }
                                dashboardShortcut("Updates", icon: "arrow.clockwise.circle.fill") { vm.screen = .updates }
                                dashboardShortcut("Health", icon: "cross.case.fill") { vm.screen = .healthCenter }
                                dashboardShortcut("Control", icon: "speedometer") { vm.screen = .commandCenter }
                            }
                        }
                    }
                    .frame(maxWidth: 390, alignment: .topLeading)
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear {
            vm.refreshHomeDashboard()
        }
    }

    private var dashboardHealthTint: Color {
        if vm.healthStatus == "Healthy" { return Color(NSColor.systemGreen) }
        if vm.healthStatus == "Critical" { return Color(NSColor.systemRed) }
        if vm.healthStatus == "Warning" { return Color(NSColor.systemOrange) }
        return UI.muted
    }

    private var dashboardConnectedChannels: Int {
        vm.channels.filter { $0.connected || $0.running }.count
    }

    private var dashboardActiveSkills: Int {
        vm.installedSkills.filter { $0.isActive }.count
    }

    private var dashboardActiveCronJobs: Int {
        vm.cronJobs.filter { $0.enabled }.count
    }

    private var dashboardModelNeedsSetup: Bool {
        let model = vm.openClawChatModelLabel.lowercased()
        return model.contains("not configured") || model == "unknown" || model.hasPrefix("error:")
    }

    private var dashboardChannelsSummary: String {
        if vm.channels.isEmpty { return "Not loaded" }
        return "\(dashboardConnectedChannels) connected · \(vm.channels.count) available"
    }

    private var dashboardSkillsSummary: String {
        if vm.installedSkills.isEmpty { return "Not loaded" }
        return "\(dashboardActiveSkills) active · \(vm.installedSkills.count) installed"
    }

    private var dashboardCronSummary: String {
        if vm.cronJobs.isEmpty { return "No active jobs" }
        return "\(dashboardActiveCronJobs) active · \(vm.cronJobs.count) jobs"
    }

    private var dashboardReadinessChecks: [(String, Bool)] {
        [
            ("Gateway", vm.gatewayIsRunning),
            ("Chat", vm.openClawChatStatus == "Ready"),
            ("Model", !dashboardModelNeedsSetup),
            ("Channel", dashboardConnectedChannels > 0),
            ("Skill", dashboardActiveSkills > 0)
        ]
    }

    private var dashboardReadinessCount: Int {
        dashboardReadinessChecks.filter { $0.1 }.count
    }

    private var dashboardReadinessTitle: String {
        if dashboardReadinessCount == dashboardReadinessChecks.count { return "Ready" }
        if dashboardReadinessCount >= 3 { return "Partially ready" }
        return "Needs setup"
    }

    private var dashboardReadinessTint: Color {
        if dashboardReadinessTitle == "Ready" { return Color(NSColor.systemGreen) }
        if dashboardReadinessTitle == "Partially ready" { return Color(NSColor.systemOrange) }
        return Color(NSColor.systemRed)
    }

    private var dashboardReadinessPanel: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(dashboardReadinessTint)
                        .frame(width: 10, height: 10)
                    Text("OpenClaw readiness")
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.muted)
                }
                Text(dashboardReadinessTitle)
                    .font(AppFont.heading(24))
                    .foregroundStyle(UI.text)
                Text("\(dashboardReadinessCount)/\(dashboardReadinessChecks.count) checks passing")
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
            }
            .frame(width: 220, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(dashboardReadinessChecks, id: \.0) { check in
                    dashboardReadinessChip(check.0, ok: check.1)
                }
            }

            Spacer()

            Button("Fix issues") {
                if !vm.gatewayIsRunning || vm.openClawChatStatus != "Ready" {
                    vm.screen = .healthCenter
                } else if dashboardModelNeedsSetup {
                    vm.screen = .models
                } else if dashboardConnectedChannels == 0 {
                    vm.screen = .channelSetup
                } else if dashboardActiveSkills == 0 {
                    vm.screen = .skills
                } else {
                    vm.screen = .commandCenter
                }
            }
            .buttonStyle(CTAButton(primary: true))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(dashboardReadinessTint.opacity(0.35), lineWidth: 1))
    }

    private func dashboardReadinessChip(_ title: String, ok: Bool) -> some View {
        Label(title, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(AppFont.bodySemi(11))
            .foregroundStyle(ok ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 999).fill(UI.card))
    }

    private struct DashboardActionItem: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let icon: String
        let tint: Color
        let action: () -> Void
    }

    private var dashboardActionItems: [DashboardActionItem] {
        var items: [DashboardActionItem] = []
        if !vm.gatewayIsRunning || vm.openClawChatStatus != "Ready" {
            items.append(DashboardActionItem(title: "Repair OpenClaw health", detail: "Gateway or chat is not fully ready.", icon: "cross.case.fill", tint: Color(NSColor.systemRed)) { vm.screen = .healthCenter })
        }
        if dashboardModelNeedsSetup {
            items.append(DashboardActionItem(title: "Choose a working model", detail: vm.openClawChatModelLabel, icon: "cpu.fill", tint: Color(NSColor.systemOrange)) { vm.screen = .models })
        }
        if dashboardConnectedChannels == 0 {
            items.append(DashboardActionItem(title: "Connect first channel", detail: "Telegram, Discord, WhatsApp, Slack and more.", icon: "plus.message.fill", tint: Color(NSColor.systemBlue)) { vm.screen = .channelSetup })
        }
        if dashboardActiveSkills == 0 {
            items.append(DashboardActionItem(title: "Activate useful skills", detail: "Add tools OpenClaw can use immediately.", icon: "wand.and.stars", tint: UI.accent) { vm.screen = .skills })
        }
        if dashboardActiveCronJobs == 0 {
            items.append(DashboardActionItem(title: "Create first automation", detail: "Schedule recurring checks or reminders.", icon: "calendar.badge.plus", tint: Color(NSColor.systemPurple)) { vm.screen = .cronJobs })
        }
        if items.isEmpty {
            items.append(DashboardActionItem(title: "Open OpenClaw Chat", detail: "Everything essential is ready.", icon: "message.badge.waveform", tint: Color(NSColor.systemGreen)) { vm.openOpenClawChat() })
        }
        return Array(items.prefix(4))
    }

    private func dashboardChecklistRow(_ item: DashboardActionItem) -> some View {
        Button(action: item.action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.text)
                    Text(item.detail)
                        .font(AppFont.body(10))
                        .foregroundStyle(UI.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UI.muted)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
        }
        .buttonStyle(.plain)
    }

    private func dashboardWorkingRow(_ title: String, value: String, icon: String, healthy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(healthy ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
                    .frame(width: 18)
                Text(title)
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.text)
                Spacer()
                Text(value)
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: healthy ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(healthy ? Color(NSColor.systemGreen) : UI.muted)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
        }
        .buttonStyle(.plain)
    }

    private var dashboardActivityItems: [String] {
        var items: [String] = []
        if !vm.channelSetupLogs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(contentsOf: vm.channelSetupLogs.split(separator: "\n").suffix(3).map(String.init))
        }
        if !vm.skillsLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(contentsOf: vm.skillsLog.split(separator: "\n").suffix(3).map(String.init))
        }
        if !vm.healthLogs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(contentsOf: vm.healthLogs.split(separator: "\n").suffix(3).map(String.init))
        }
        if !vm.usageLogs.isEmpty { items.append(vm.usageLogs) }
        if !vm.modelsApplyStatus.isEmpty { items.append(vm.modelsApplyStatus) }
        if items.isEmpty {
            items = [
                "No activity yet. Run Refresh to load OpenClaw status.",
                "Connect channels to start receiving messages.",
                "Open Models to check cloud/local inference setup."
            ]
        }
        return Array(items.suffix(8).reversed())
    }

    private func dashboardKpiCard(title: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }
            Text(value)
                .font(AppFont.bodySemi(19))
                .foregroundStyle(UI.text)
                .lineLimit(1)
            Text(title)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.muted)
            Text(detail)
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .topLeading)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.22), lineWidth: 1))
    }

    private func dashboardPanel<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(UI.accent)
                    .frame(width: 18)
                Text(title)
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                Spacer()
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func dashboardMeter(_ title: String, value: Double, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                Spacer()
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(UI.muted)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(UI.card)
                    RoundedRectangle(cornerRadius: 999)
                        .fill(tint)
                        .frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 8)
        }
    }

    private func dashboardMiniStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.bodySemi(12))
                .foregroundStyle(UI.text)
                .lineLimit(1)
            Text(title)
                .font(AppFont.body(10))
                .foregroundStyle(UI.muted)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
    }

    private func dashboardActionRow(title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(UI.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.text)
                    Text(detail)
                        .font(AppFont.body(10))
                        .foregroundStyle(UI.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UI.muted)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
        }
        .buttonStyle(.plain)
    }

    private func dashboardConfigLine(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UI.muted)
                .frame(width: 18)
            Text(title)
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
            Spacer()
            Text(value)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func dashboardShortcut(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
        }
        .buttonStyle(.plain)
    }

    var developerCenter: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "curlybraces.square.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(UI.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Build with OpenClaw: chat-driven coding on the left, live app preview and project context on the right.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                developerToolbarButton("New app", icon: "plus.square.on.square") { vm.developerNewApp() }
                developerToolbarButton("Open app", icon: "folder") { vm.developerChooseFolder() }
                developerToolbarButton("Sync folder", icon: "folder.badge.gearshape") { vm.syncDeveloperProjectFolder() }
                developerToolbarButton("Run preview", icon: "play.fill", primary: true) { vm.developerRunPreview() }
            }

            HStack(alignment: .top, spacing: 14) {
                developerChatPanel
                    .frame(minWidth: 360, idealWidth: 430, maxWidth: 500)
                developerPreviewPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .onAppear { vm.prepareDeveloperWorkspace() }
    }

    private var developerChatPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Developer")
                        .font(AppFont.bodySemi(15))
                        .foregroundStyle(UI.text)
                    Picker("", selection: $vm.selectedChatModel) {
                        ForEach(vm.availableChatModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                    .onAppear { vm.ensureSelectedChatModel() }
                    .onChange(of: vm.selectedChatModel) { _ in
                        vm.handleChatModelSelectionChanged(useDeveloperSession: true)
                    }
                }
                Spacer()
                Toggle("Fast context", isOn: $vm.developerFreshContextEnabled)
                    .toggleStyle(.switch)
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
                    .help("Use a fresh OpenClaw runtime session for each AI Developer request. This keeps replies fast by avoiding old transcript bloat.")
                Label(vm.chatStatus, systemImage: vm.chatStatus == "Ready" ? "checkmark.circle.fill" : "circle.fill")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(vm.chatStatus == "Ready" ? Color(NSColor.systemGreen) : UI.accent)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if vm.developerChatMessages.isEmpty {
                            developerEmptyState
                        } else {
                            ForEach(vm.developerChatMessages) { message in
                                developerChatBubble(message)
                                    .id(message.id)
                            }
                        }
                        if vm.chatIsSending {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(vm.chatStatus)
                                    .font(AppFont.body(12))
                                    .foregroundStyle(UI.muted)
                            }
                            .padding(.horizontal, 10)
                        }
                        Color.clear
                            .frame(height: 10)
                            .id("developer-chat-bottom")
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(UI.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.lineSoft, lineWidth: 1))
                .onChange(of: vm.developerChatMessages.count) { _ in
                    scrollDeveloperChatToBottom(proxy)
                }
                .onChange(of: vm.chatIsSending) { _ in
                    scrollDeveloperChatToBottom(proxy)
                }
                .onAppear {
                    scrollDeveloperChatToBottom(proxy)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Ask OpenClaw to build, fix, or improve the app...", text: $vm.chatInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(14))
                    .lineLimit(2...5)
                    .onSubmit { vm.sendDeveloperChatMessage() }
                HStack(spacing: 10) {
                    developerIconButton("paperclip") { vm.attachChatImage() }
                    developerIconButton("terminal") { vm.chatInput = "Run the project checks for \(vm.developerProjectPath) and summarize failures with fixes." }
                    developerIconButton("photo") { vm.attachChatImage() }
                    Text("Will send with \(vm.selectedChatModel.isEmpty ? vm.openClawChatModelLabel : vm.selectedChatModel)")
                        .font(AppFont.bodySemi(11))
                        .foregroundStyle(UI.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if vm.developerFreshContextEnabled {
                        Text("Fresh context")
                            .font(AppFont.bodySemi(10))
                            .foregroundStyle(Color(NSColor.systemGreen))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(NSColor.systemGreen).opacity(0.12)))
                    }
                    Spacer()
                    Button(action: { vm.chatIsSending ? vm.stopChatGeneration() : vm.sendDeveloperChatMessage() }) {
                        Label(vm.chatIsSending ? "Stop" : "Send", systemImage: vm.chatIsSending ? "stop.fill" : "arrow.up")
                    }
                    .buttonStyle(SheetActionButton(primary: true))
                    .disabled(!vm.chatIsSending && vm.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && vm.chatImagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(UI.lineSoft, lineWidth: 1))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(UI.cardSoft.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(UI.lineSoft, lineWidth: 1))
    }

    private var developerEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start by describing what you want to build or change.")
                .font(AppFont.bodySemi(13))
                .foregroundStyle(UI.text)
            Text("Messages sent here use the selected model and appear in this panel.")
                .font(AppFont.body(12))
                .foregroundStyle(UI.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func scrollDeveloperChatToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("developer-chat-bottom", anchor: .bottom)
            }
        }
    }

    private var developerPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                developerTab("Preview", icon: "eye.fill", id: "preview")
                developerTab("Files", icon: "doc.text", id: "files")
                developerTab("Database", icon: "cylinder.split.1x2", id: "database")
                developerTab("Deploy", icon: "icloud.and.arrow.up", id: "deploy")
                developerTab("Logs", icon: "terminal", id: "logs")
                Spacer()
                developerIconButton("arrow.clockwise") { vm.developerRefreshPreview() }
                developerIconButton("rectangle.on.rectangle") { vm.developerCopyPreviewURL() }
                developerIconButton("arrow.up.right.square") { vm.developerOpenExternalPreview() }
            }
            .padding(10)
            .background(UI.cardSoft)

            developerTabContent
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(UI.card))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(UI.lineSoft, lineWidth: 1))
    }

    @ViewBuilder
    private var developerTabContent: some View {
        switch vm.developerActiveTab {
        case "files":
            developerFilesPanel
        case "database":
            developerDatabasePanel
        case "deploy":
            developerDeployPanel
        case "logs":
            developerLogsPanel
        default:
            developerPreviewWebPanel
        }
    }

    private var developerPreviewWebPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Project")
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.muted)
                TextField("Project name", text: $vm.developerProjectName)
                    .textFieldStyle(.plain)
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                    .onSubmit { vm.syncDeveloperProjectFolder() }
                developerToolbarButton("Rename folder", icon: "arrow.triangle.2.circlepath") { vm.syncDeveloperProjectFolder() }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .background(UI.card)

            HStack(spacing: 8) {
                TextField("http://localhost:5173", text: $vm.developerPreviewURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(UI.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                    .onSubmit { vm.developerRefreshPreview() }
                developerToolbarButton("Run", icon: "play.fill") { vm.developerRunPreview() }
                developerToolbarButton("Stop", icon: "stop.fill") { vm.developerStopPreview() }
                developerToolbarButton("Desktop", icon: "desktopcomputer") { vm.developerPreviewDevice = "desktop" }
                developerToolbarButton("Mobile", icon: "iphone") { vm.developerPreviewDevice = "mobile" }
                developerToolbarButton("Open", icon: "arrow.up.right.square") { vm.developerOpenExternalPreview() }
            }
            .padding(10)
            .background(UI.card)

            HStack(spacing: 8) {
                Label(vm.developerPreviewStatus, systemImage: vm.developerPreviewStatus.lowercased().contains("running") ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.body(11))
                    .foregroundStyle(vm.developerPreviewStatus.lowercased().contains("running") ? Color(NSColor.systemGreen) : UI.muted)
                    .lineLimit(1)
                Spacer()
                Text(vm.developerProjectPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .background(UI.card)

            HStack {
                if vm.developerPreviewDevice == "mobile" { Spacer(minLength: 0) }
                DeveloperWebPreview(urlString: vm.developerPreviewURL)
                    .id(vm.developerPreviewRefreshID)
                    .frame(width: vm.developerPreviewDevice == "mobile" ? 390 : nil)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: vm.developerPreviewDevice == "mobile" ? 18 : 0).stroke(vm.developerPreviewDevice == "mobile" ? UI.lineSoft : Color.clear, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: vm.developerPreviewDevice == "mobile" ? 18 : 0))
                if vm.developerPreviewDevice == "mobile" { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(vm.developerPreviewDevice == "mobile" ? 0.08 : 0))
        }
    }

    private func developerToolbarButton(_ title: String, icon: String, primary: Bool = false, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(CompactChatButton(primary: primary))
    }

    private func developerIconButton(_ icon: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(UI.muted)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
        }
        .buttonStyle(.plain)
    }

    private func developerTab(_ title: String, icon: String, id: String) -> some View {
        let active = vm.developerActiveTab == id
        return Button(action: { vm.developerActiveTab = id }) {
            Label(title, systemImage: icon)
                .font(AppFont.bodySemi(12))
                .foregroundStyle(active ? UI.accent : UI.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? UI.card : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var developerFilesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            developerPanelHeader(
                title: "Files",
                subtitle: vm.developerProjectPath,
                icon: "doc.text",
                actionTitle: "Change folder",
                action: { vm.developerChooseFolder() }
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let files = vm.developerProjectFiles()
                    if files.isEmpty {
                        developerEmptyPanel("No files found in this project folder.")
                    } else {
                        ForEach(files, id: \.path) { url in
                            developerFileRow(url)
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .background(UI.card)
    }

    private func developerFileRow(_ url: URL) -> some View {
        let isDir = ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        return HStack(spacing: 10) {
            Image(systemName: isDir ? "folder.fill" : "doc.text")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isDir ? Color(NSColor.systemBlue) : UI.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                    .lineLimit(1)
                Text(vm.developerRelativePath(url))
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button("Open") { vm.developerOpenFile(url) }
                .buttonStyle(CompactChatButton(primary: false))
            Button("Reveal") { vm.developerRevealFile(url) }
                .buttonStyle(CompactChatButton(primary: false))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    private var developerDatabasePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            developerPanelHeader(title: "Database", subtitle: "Detect storage setup and ask OpenClaw for schema help.", icon: "cylinder.split.1x2", actionTitle: "Analyze") {
                vm.chatInput = "Inspect database/storage needs for this project and propose the simplest local setup."
            }
            let summary = vm.developerProjectSummary()
            VStack(alignment: .leading, spacing: 10) {
                developerInfoCard("Detected", summary.isEmpty ? "No database framework detected yet." : summary.joined(separator: " · "), icon: "magnifyingglass")
                developerInfoCard("Local options", "SQLite, Supabase local, Prisma, JSON file storage", icon: "externaldrive")
                developerInfoCard("Next step", "Ask OpenClaw to infer entities, schema, auth needs, and seed data.", icon: "sparkles")
            }
            .padding(12)
            Spacer()
        }
        .background(UI.card)
    }

    private var developerDeployPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            developerPanelHeader(title: "Deploy", subtitle: "Prepare build settings and deployment checklist.", icon: "icloud.and.arrow.up", actionTitle: "Prepare") {
                vm.chatInput = "Prepare this project for deployment. Identify the platform, build command, output directory, and missing environment variables."
            }
            VStack(alignment: .leading, spacing: 10) {
                developerInfoCard("Project path", vm.developerProjectPath, icon: "folder")
                developerInfoCard("Project name", vm.developerProjectName, icon: "tag")
                developerInfoCard("Recommended flow", "Run checks, identify build command, verify output directory, then deploy.", icon: "checklist")
                developerInfoCard("Common targets", "Static hosting, Cloudflare Pages, Vercel, Netlify, custom VPS", icon: "network")
            }
            .padding(12)
            Spacer()
        }
        .background(UI.card)
    }

    private var developerLogsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            developerPanelHeader(title: "Logs", subtitle: "Useful local commands for debugging this project.", icon: "terminal", actionTitle: "Ask OpenClaw") {
                vm.chatInput = "Check recent project logs and summarize the actionable errors."
            }
            VStack(alignment: .leading, spacing: 10) {
                developerCodeBlock("cd \(vm.developerProjectPath)\nnpm run dev\nnpm run build\nnpm test")
                developerInfoCard("Preview URL", vm.developerPreviewURL, icon: "link")
                developerInfoCard("Preview status", vm.developerPreviewStatus, icon: "eye")
                developerInfoCard("Tip", "Paste failing logs here and OpenClaw will debug them in the Developer chat.", icon: "lightbulb")
            }
            .padding(12)
            Spacer()
        }
        .background(UI.card)
    }

    private func developerPanelHeader(title: String, subtitle: String, icon: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(UI.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.bodySemi(15))
                    .foregroundStyle(UI.text)
                Text(subtitle)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(CompactChatButton(primary: false))
        }
        .padding(12)
        .background(UI.cardSoft)
    }

    private func developerInfoCard(_ title: String, _ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(UI.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                Text(text)
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func developerEmptyPanel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.body(12))
            .foregroundStyle(UI.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
    }

    private func developerChatBubble(_ message: InstallerViewModel.ChatMessage) -> some View {
        let isUser = message.role == "user"
        let isError = message.role == "error"
        let senderName = isUser ? "You" : (isError ? "Error" : "OpenClaw")
        let bubbleFill = isError ? Color(NSColor.systemRed).opacity(0.08) : (isUser ? UI.accent.opacity(0.15) : UI.card)
        let bubbleStroke = isError ? Color(NSColor.systemRed).opacity(0.35) : (isUser ? UI.accent.opacity(0.28) : UI.lineSoft)
        let modelName = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(senderName)
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(isUser ? UI.accent : (isError ? Color(NSColor.systemRed) : UI.muted))
                if !isUser, let modelName, !modelName.isEmpty {
                    Text(modelName)
                        .font(AppFont.bodySemi(10))
                        .foregroundStyle(UI.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(action: { copyChatMessage(message.text) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(UI.muted)
                }
                .buttonStyle(.plain)
            }
            Text(message.text)
                .font(AppFont.body(13))
                .foregroundStyle(UI.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let metadata = message.metadata, !metadata.isEmpty {
                Text(metadata)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(UI.muted)
                    .lineLimit(2)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(bubbleFill))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(bubbleStroke, lineWidth: 1))
    }

    private func developerMessage(role: String, text: String, isUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(role)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(isUser ? UI.accent : UI.muted)
            Text(text)
                .font(AppFont.body(13))
                .foregroundStyle(UI.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(isUser ? UI.accent.opacity(0.10) : UI.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isUser ? UI.accent.opacity(0.25) : UI.lineSoft, lineWidth: 1))
    }

    private func developerCodeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(UI.text)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.30)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    var openClawChat: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.inferenceMode == .local {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "message.badge.waveform")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(UI.accent)
                    Text("OpenClaw Chat")
                        .font(AppFont.heading(26))
                        .foregroundStyle(UI.text)
                        .lineLimit(1)

                    chatInfoPill(vm.openClawChatModeLabel, icon: vm.inferenceMode == .local ? "desktopcomputer" : "cloud.fill")

                    Text("Model")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)

                    Picker("Local model", selection: $vm.selectedLocalLMStudioModel) {
                        if vm.localLMStudioModels.isEmpty {
                            Text("No LM Studio model found").tag("")
                        } else {
                            ForEach(vm.localLMStudioModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 210, idealWidth: 300, maxWidth: 360)

                    Button(vm.localLMStudioSetupInProgress ? "SETTING UP..." : "AUTO SETUP") {
                        vm.autoSetupSelectedLocalLMStudioModel()
                    }
                    .buttonStyle(CompactChatButton(primary: true))
                    .disabled(vm.localLMStudioSetupInProgress || vm.selectedLocalLMStudioModel.isEmpty)

                    Button("SCAN") { vm.refreshLocalLMStudioModels() }
                        .buttonStyle(CompactChatButton(primary: false))

                    Button(vm.localLMStudioRepairInProgress ? "REPAIRING..." : "REPAIR LM STUDIO") {
                        vm.repairLMStudioRuntimeFromChat()
                    }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(vm.localLMStudioRepairInProgress || vm.localLMStudioSetupInProgress)

                    Spacer(minLength: 0)

                    Label(vm.chatStatus, systemImage: vm.chatStatus == "Ready" ? "checkmark.circle.fill" : "circle.fill")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(vm.chatStatus == "Ready" ? Color(NSColor.systemGreen) : UI.accent)
                        .lineLimit(1)
                }

                if !vm.localLMStudioSetupStatus.isEmpty {
                    Text(vm.localLMStudioSetupStatus)
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                        .lineLimit(2)
                }

                if !vm.localLMStudioSetupLog.isEmpty {
                    DisclosureGroup("Setup details") {
                        ScrollView {
                            Text(vm.localLMStudioSetupLog)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(UI.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .scrollIndicators(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: 90)
                        .background(RoundedRectangle(cornerRadius: 9).fill(UI.cardSoft))
                    }
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "message.badge.waveform")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(UI.accent)
                    Text("OpenClaw Chat")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    HStack(spacing: 8) {
                        chatInfoPill(vm.openClawChatModeLabel, icon: vm.inferenceMode == .local ? "desktopcomputer" : "cloud.fill")
                        chatInfoPill(vm.openClawChatModelLabel, icon: "cpu")
                    }
                    Spacer()
                    Label(vm.chatStatus, systemImage: vm.chatStatus == "Ready" ? "checkmark.circle.fill" : "circle.fill")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(vm.chatStatus == "Ready" ? Color(NSColor.systemGreen) : UI.accent)
                }
            }

            chatControlStrip

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Discussions")
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(UI.text)
                        Spacer()
                        Button(action: { vm.newChatProject() }) {
                            Image(systemName: "folder.badge.plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(UI.accent)
                        .help("New project")
                        Button(action: { vm.newChatSession() }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(UI.accent)
                        .help("New discussion")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(vm.chatProjects) { project in
                                chatProjectSection(project)
                            }

                            if !vm.unfiledChatSessions.isEmpty {
                                Text(vm.chatProjects.isEmpty ? "Chats" : "No project")
                                    .font(AppFont.bodySemi(10))
                                    .foregroundStyle(UI.muted)
                                    .padding(.horizontal, 4)
                                    .padding(.top, vm.chatProjects.isEmpty ? 0 : 4)
                                    .onDrop(of: [.plainText, .text], isTargeted: nil) { providers in
                                        handleChatDrop(providers, projectID: nil)
                                    }
                                ForEach(vm.unfiledChatSessions) { session in
                                    chatSessionRow(session)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    Divider()
                        .padding(.vertical, 2)
                    Button(role: .destructive, action: { vm.deleteSelectedChatSession() }) {
                        Label("Delete", systemImage: "trash")
                            .font(AppFont.bodySemi(11))
                            .foregroundStyle(Color(NSColor.systemRed))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.systemRed).opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.systemRed).opacity(0.16), lineWidth: 1))
                    .disabled(vm.chatIsSending)
                    .help("Delete current discussion")
                }
                .padding(12)
                .frame(width: 230)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 16).fill(UI.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(UI.lineSoft, lineWidth: 1))

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(vm.chatMessages) { message in
                                chatBubble(message)
                                    .id(message.id)
                            }
                            if vm.chatIsSending {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("OpenClaw is thinking...")
                                        .font(AppFont.body(12))
                                        .foregroundStyle(UI.muted)
                                }
                                .padding(.horizontal, 10)
                            }
                            Color.clear
                                .frame(height: 18)
                                .id("chat-bottom-anchor")
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 16).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(UI.lineSoft, lineWidth: 1))
                    .onChange(of: vm.chatMessages.count) { _ in
                        scrollChatToBottom(proxy)
                    }
                    .onChange(of: vm.chatIsSending) { _ in
                        scrollChatToBottom(proxy)
                    }
                    .onChange(of: vm.activeChatSessionID) { _ in
                        scrollChatToBottom(proxy)
                    }
                    .onAppear {
                        scrollChatToBottom(proxy)
                    }
                }

                chatMemoryPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            chatComposer
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .onAppear { vm.refreshOpenClawChatInfo() }
    }

    func scrollChatToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
            }
        }
    }

    var chatControlStrip: some View {
        HStack(spacing: 10) {
            ForEach(InstallerViewModel.ChatResponseMode.allCases) { mode in
                Button {
                    vm.selectedChatResponseMode = mode
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(mode.rawValue, systemImage: mode.icon)
                            .font(AppFont.bodySemi(11))
                            .lineLimit(1)
                        Text(mode.detail)
                            .font(AppFont.body(10))
                            .foregroundStyle(vm.selectedChatResponseMode == mode ? Color.white.opacity(0.72) : UI.muted)
                            .lineLimit(1)
                    }
                    .foregroundStyle(vm.selectedChatResponseMode == mode ? Color.white : UI.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: 132, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(vm.selectedChatResponseMode == mode ? UI.accent : UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(vm.selectedChatResponseMode == mode ? UI.accent.opacity(0.4) : UI.lineSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(vm.chatIsSending)
            }

            Spacer(minLength: 12)

            Toggle(isOn: $vm.chatMemoryEnabled) {
                Label(vm.chatMemoryEnabled ? "Memory on" : "Memory off", systemImage: vm.chatMemoryEnabled ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.bodySemi(11))
            }
            .toggleStyle(.switch)
            .foregroundStyle(UI.text)
            .disabled(vm.chatIsSending)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.lineSoft, lineWidth: 1))
    }

    var chatMemoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Label("Memory", systemImage: "memorychip")
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                Spacer()
                Button("Forget") { vm.forgetChatMemory() }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(vm.chatSavedNotes.isEmpty)
            }

            Text(vm.chatMemoryEnabled ? "Visible context used for this chat." : "Memory is paused for new messages.")
                .font(AppFont.body(10))
                .foregroundStyle(UI.muted)
                .lineLimit(2)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if vm.chatMemoryPreview.isEmpty {
                        Text("No saved notes yet.")
                            .font(AppFont.body(11))
                            .foregroundStyle(UI.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(vm.chatMemoryPreview.enumerated()), id: \.offset) { _, note in
                            Text(note)
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.text)
                                .lineLimit(4)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(UI.lineSoft, lineWidth: 1))
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(UI.lineSoft, lineWidth: 1))
    }

    var chatComposer: some View {
        let hasImage = !vm.chatImagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canSend = !vm.chatIsSending && (!vm.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasImage)

        return VStack(alignment: .leading, spacing: 12) {
            if hasImage {
                chatImagePreview(path: vm.chatImagePath)
            }

            TextField("Message OpenClaw...", text: $vm.chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppFont.body(15))
                .foregroundStyle(UI.text)
                .lineLimit(2...7)
                .onSubmit { vm.sendChatMessage() }

            HStack(spacing: 14) {
                chatComposerIcon("plus", help: "Attach image") { vm.attachChatImage() }
                chatComposerIcon("globe", help: "Web context")
                chatComposerIcon("apps.iphone", help: "Apps")

                Picker("", selection: $vm.selectedChatModel) {
                    ForEach(vm.availableChatModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190)
                .onAppear { vm.ensureSelectedChatModel() }
                .onChange(of: vm.selectedChatModel) { _ in
                    vm.handleChatModelSelectionChanged(useDeveloperSession: false)
                }

                Spacer(minLength: 12)

                Button(action: {
                    vm.chatIsSending ? vm.stopChatGeneration() : vm.sendChatMessage()
                }) {
                    Image(systemName: vm.chatIsSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: vm.chatIsSending ? 14 : 18, weight: .bold))
                        .foregroundStyle(vm.chatIsSending ? Color.white : (canSend ? UI.card : UI.muted))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(vm.chatIsSending ? Color(NSColor.systemRed) : (canSend ? UI.text : UI.lineSoft)))
                }
                .buttonStyle(.plain)
                .disabled(!vm.chatIsSending && !canSend)
                .help(vm.chatIsSending ? "Stop generation" : "Send message")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(minHeight: 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(UI.line, lineWidth: 1))
    }

    func chatComposerIcon(_ systemName: String, help: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(UI.muted)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(systemName != "plus")
        .help(help)
    }

    func chatImagePreview(path: String) -> some View {
        HStack(spacing: 10) {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(UI.muted)
                    .frame(width: 56, height: 42)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                    .lineLimit(1)
                Text("Image attached")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }

            Spacer()

            Button(action: { vm.removeChatImage() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(UI.muted)
            }
            .buttonStyle(.plain)
            .help("Remove image")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    func chatProjectSection(_ project: InstallerViewModel.ChatProject) -> some View {
        let sessions = vm.chatSessions(in: project)
        let isExpanded = vm.expandedChatProjectIDs.contains(project.id)
        let color = chatProjectColor(project.colorName)
        let isEditing = vm.editingChatProjectID == project.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Button(action: { vm.toggleChatProject(project) }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                Image(systemName: project.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)

                if isEditing {
                    TextField("Project name", text: $vm.editingChatProjectTitle)
                        .textFieldStyle(.plain)
                        .font(AppFont.bodySemi(12))
                        .onSubmit { vm.commitEditingChatProject() }
                } else {
                    Button(action: { vm.toggleChatProject(project) }) {
                        Text(project.title)
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(UI.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .onTapGesture(count: 2) { vm.beginEditingChatProject(project) }
                }

                Spacer(minLength: 4)

                Text("\(sessions.count)")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)

                Menu {
                    Button("Rename") { vm.beginEditingChatProject(project) }
                    Divider()
                    ForEach(["folder", "briefcase", "sparkles", "cpu", "hammer", "graduationcap", "paintpalette"], id: \.self) { icon in
                        Button {
                            vm.updateChatProjectStyle(project.id, icon: icon)
                        } label: {
                            Label(icon, systemImage: icon)
                        }
                    }
                    Divider()
                    ForEach(["red", "orange", "yellow", "green", "blue", "purple", "gray"], id: \.self) { colorName in
                        Button(colorName.capitalized) {
                            vm.updateChatProjectStyle(project.id, colorName: colorName)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(UI.muted)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            .foregroundStyle(UI.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.32), lineWidth: 1))

            if isExpanded {
                if sessions.isEmpty {
                    Text("Drop chats here")
                        .font(AppFont.body(10))
                        .foregroundStyle(UI.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    ForEach(sessions) { session in
                        chatSessionRow(session)
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .padding(1)
        .contentShape(Rectangle())
        .onDrop(of: [.plainText, .text], isTargeted: nil) { providers in
            handleChatDrop(providers, projectID: project.id)
        }
    }

    func chatProjectColor(_ name: String) -> Color {
        switch name {
        case "orange": return Color(NSColor.systemOrange)
        case "yellow": return Color(NSColor.systemYellow)
        case "green": return Color(NSColor.systemGreen)
        case "blue": return Color(NSColor.systemBlue)
        case "purple": return Color(NSColor.systemPurple)
        case "gray": return Color(NSColor.systemGray)
        default: return UI.accent
        }
    }

    func handleChatDrop(_ providers: [NSItemProvider], projectID: String?) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) ?? providers.first else { return false }
        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let sessionID = (object as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty else { return }
                DispatchQueue.main.async {
                    vm.moveChatSession(sessionID, toProjectID: projectID)
                }
            }
        } else {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let value: String?
                if let data = item as? Data {
                    value = String(data: data, encoding: .utf8)
                } else {
                    value = item as? String
                }
                guard let sessionID = value?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty else { return }
                DispatchQueue.main.async {
                    vm.moveChatSession(sessionID, toProjectID: projectID)
                }
            }
        }
        return true
    }

    func chatSessionRow(_ session: InstallerViewModel.ChatSession) -> some View {
        let isActive = session.id == vm.activeChatSessionID
        return VStack(alignment: .leading, spacing: 5) {
            Text(session.title)
                .font(AppFont.bodySemi(12))
                .foregroundStyle(isActive ? Color.white : UI.text)
                .lineLimit(1)
            Text("\(session.messages.count) messages • \(session.subtitle)")
                .font(AppFont.body(10))
                .foregroundStyle(isActive ? Color.white.opacity(0.75) : UI.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(RoundedRectangle(cornerRadius: 12).fill(isActive ? UI.accent : UI.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
        .onTapGesture {
            vm.selectChatSession(session)
        }
        .onDrag {
            let provider = NSItemProvider(object: session.id as NSString)
            provider.suggestedName = session.title
            return provider
        } preview: {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                    .lineLimit(1)
                Text("\(session.messages.count) messages • \(session.subtitle)")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(width: 220, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
        }
        .contextMenu {
            if !vm.chatProjects.isEmpty {
                Menu("Move to project") {
                    ForEach(vm.chatProjects) { project in
                        Button(project.title) {
                            vm.moveChatSession(session.id, toProjectID: project.id)
                        }
                    }
                }
            }
            Button("Remove from project") {
                vm.moveChatSession(session.id, toProjectID: nil)
            }
        }
    }

    func chatInfoPill(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(AppFont.bodySemi(11))
            .foregroundStyle(UI.text)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 999).stroke(UI.lineSoft, lineWidth: 1))
    }

    func chatBubble(_ message: InstallerViewModel.ChatMessage) -> some View {
        let isUser = message.role == "user"
        let isError = message.role == "error"
        let senderName = isUser ? "You" : (isError ? "Error" : "OpenClaw")
        let senderIcon = isUser ? "person.fill" : (isError ? "exclamationmark.triangle.fill" : "sparkles")
        let bubbleFill = isError ? Color(NSColor.systemRed).opacity(0.08) : (isUser ? UI.accent.opacity(0.16) : UI.card)
        let bubbleStroke = isError ? Color(NSColor.systemRed).opacity(0.35) : (isUser ? UI.accent.opacity(0.22) : Color.black.opacity(0.06))
        let modelName = message.modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack {
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Label(senderName, systemImage: senderIcon)
                        .font(AppFont.bodySemi(11))
                        .foregroundStyle(isError ? Color(NSColor.systemRed) : UI.muted)
                    if !isUser, let modelName, !modelName.isEmpty {
                        Label(modelName, systemImage: "cpu")
                            .font(AppFont.bodySemi(10))
                            .foregroundStyle(UI.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(UI.cardSoft))
                            .overlay(Capsule().stroke(UI.lineSoft, lineWidth: 1))
                    }
                    Spacer(minLength: 12)
                    Button {
                        copyChatMessage(message.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(UI.muted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Copy message")
                    .background(Circle().fill(UI.cardSoft.opacity(0.9)))
                    .overlay(Circle().stroke(UI.lineSoft, lineWidth: 1))

                    Menu {
                        Button("Copy") { copyChatMessage(message.text) }
                        Button("Save as note") { vm.saveChatMessageAsNote(message) }
                        if isUser {
                            Button("Edit & resend") { vm.editChatMessage(message) }
                        } else {
                            Button("Retry") { vm.retryChatMessage(message) }
                            Button("Send to channel") { vm.sendChatMessageToChannel(message) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(UI.muted)
                            .frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 26)
                    .disabled(vm.chatIsSending)
                    .help("Message actions")
                }
                renderedChatText(message.text)
                    .font(AppFont.body(14))
                    .foregroundStyle(isError ? Color(NSColor.systemRed) : UI.text)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                if let imagePath = message.imagePath, !imagePath.isEmpty {
                    chatMessageImage(path: imagePath)
                }
                if let metadata = message.metadata, !metadata.isEmpty {
                    Label(metadata, systemImage: "speedometer")
                        .font(AppFont.body(10))
                        .foregroundStyle(UI.muted)
                }
            }
            .padding(12)
            .frame(maxWidth: 760, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(bubbleFill))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(bubbleStroke, lineWidth: 1))
            if !isUser { Spacer(minLength: 80) }
        }
    }

    func copyChatMessage(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func renderedChatText(_ text: String) -> Text {
        if let markdown = try? AttributedString(markdown: text) {
            return Text(markdown)
        }
        return Text(text)
    }

    func chatMessageImage(path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
            }

            Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "photo")
                .font(AppFont.body(10))
                .foregroundStyle(UI.muted)
                .lineLimit(1)
        }
        .padding(.top, 4)
    }

    var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install LocalClaw")
                        .font(AppFont.heading(34))
                        .foregroundStyle(UI.text)
                    Text("Configure your installation. Everything will be installed automatically.")
                        .font(AppFont.body(15))
                        .foregroundStyle(UI.muted)
                }

                // Hardware info
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                    Text("Mac detected: \(vm.chip) | \(vm.ram)")
                }
                .font(AppFont.bodySemi(13))
                .foregroundStyle(UI.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))

                installRecommendedPaths

                installPreflightPanel

                // Section 1: Inference mode
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Inference mode")
                        .font(AppFont.bodySemi(14))
                        .foregroundStyle(UI.text)

                    Picker("Mode", selection: $vm.inferenceMode) {
                        ForEach(InstallerViewModel.InferenceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(UI.accent)
                    .onChange(of: vm.inferenceMode) { newValue in
                        if newValue == .local {
                            if vm.selectedModel.isEmpty {
                                vm.selectedModel = vm.recommendation
                            }
                            vm.selectedProvider = .custom
                            vm.selectedCloudAuthMode = .api
                        } else if newValue == .oauth {
                            vm.selectedModel = ""
                            vm.selectedProvider = .openAI
                            vm.selectedCloudAuthMode = .oauth
                            vm.openAIAuthMethod = .oauth
                        } else {
                            vm.selectedModel = ""
                            vm.selectedCloudAuthMode = .api
                            if vm.selectedProvider == .custom {
                                vm.selectedProvider = .openRouter
                            }
                        }
                    }

                    Text(inferenceModeHelpText)
                        .font(AppFont.body(12))
                        .foregroundStyle(UI.muted)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(UI.card))

                if vm.inferenceMode == .local {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("2. Local model")
                            .font(AppFont.bodySemi(14))
                            .foregroundStyle(UI.text)

                        Picker("Model", selection: $vm.selectedModel) {
                            ForEach(vm.modelOptions, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Tip: if chat fails with context error, set LM Studio Context Length to 16384+ and reload model")
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)

                        if !vm.selectedModel.isEmpty {
                            Text(vm.selectedModel == vm.recommendation ? "Recommended for your Mac" : "Compatible with your Mac")
                                .font(AppFont.body(12))
                                .foregroundStyle(UI.accent)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(UI.card))
                }

                if vm.isCloudLikeInferenceMode {
                    // Section 2: AI Provider
                    aiProviderSection
                }

                // Validation errors
                if !vm.setupValidationErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(vm.setupValidationErrors, id: \.self) { err in
                            Text("• \(err)")
                                .font(AppFont.body(12))
                                .foregroundStyle(Color(NSColor.systemRed))
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.systemRed).opacity(0.08)))
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button("Back") { vm.screen = .home }
                        .buttonStyle(CTAButton(primary: false))

                    Button(vm.isRunning ? "Installing in Terminal..." : (installBlockingPreflightCount > 0 ? "Fix preflight first" : "Install Everything")) {
                        vm.openTerminalAndInstallFull()
                    }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(!vm.canStartInstall || installBlockingPreflightCount > 0)
                }
            }
            .padding(22)
            .frame(maxWidth: 600, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private var installRecommendedPaths: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended setup")
                .font(AppFont.bodySemi(14))
                .foregroundStyle(UI.text)
            HStack(spacing: 10) {
                installPathCard(
                    title: "Cloud LLM",
                    detail: "API key mode with OpenRouter and other providers.",
                    icon: "bolt.fill",
                    selected: vm.inferenceMode == .cloud && vm.selectedProvider == .openRouter
                ) {
                    vm.inferenceMode = .cloud
                    vm.selectedProvider = .openRouter
                    vm.selectedCloudAuthMode = .api
                    vm.selectedModel = ""
                }
                installPathCard(
                    title: "OAuth LLM",
                    detail: "OpenAI ChatGPT/Codex login, no API key paste.",
                    icon: "person.badge.key",
                    selected: vm.inferenceMode == .oauth
                ) {
                    vm.inferenceMode = .oauth
                    vm.selectedProvider = .openAI
                    vm.selectedCloudAuthMode = .oauth
                    vm.openAIAuthMethod = .oauth
                    vm.selectedModel = ""
                }
                installPathCard(
                    title: "Local LLM",
                    detail: "LM Studio local models, more private.",
                    icon: "lock.desktopcomputer",
                    selected: vm.inferenceMode == .local
                ) {
                    vm.inferenceMode = .local
                    if vm.selectedModel.isEmpty { vm.selectedModel = vm.recommendation }
                    vm.selectedProvider = .custom
                    vm.selectedCloudAuthMode = .api
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.card))
    }

    private func installPathCard(title: String, detail: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selected ? UI.accent : UI.muted)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? UI.accent : UI.muted)
                }
                Text(title)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                Text(detail)
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? UI.accent.opacity(0.10) : UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? UI.accent.opacity(0.45) : UI.lineSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var installPreflightPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Preflight", systemImage: installBlockingPreflightCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(installBlockingPreflightCount == 0 ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
                Spacer()
                Text(installBlockingPreflightCount == 0 ? "Ready to install" : "\(installBlockingPreflightCount) item(s) to fix")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                installPreflightRow("Homebrew", installComponentInstalled(name: "Homebrew"), detail: vm.brewVersion)
                installPreflightRow("Xcode tools", true, detail: "Checked during install")
                installPreflightRow("Node", installComponentInstalled(name: "Node"), detail: vm.nodeVersion)
                installPreflightRow("OpenClaw", installComponentInstalled(name: "OpenClaw"), detail: vm.openclawInstalledVersion)
                installPreflightRow("LM Studio", vm.isCloudLikeInferenceMode || installComponentInstalled(name: "LM Studio"), detail: vm.isCloudLikeInferenceMode ? "Optional for cloud" : vm.lmStudioVersion)
                installPreflightRow("API key", installApiKeyReady, detail: vm.inferenceMode == .local ? "Not needed for local" : vm.selectedProvider.rawValue)
                installPreflightRow("Disk space", installDiskSpaceReady, detail: installDiskSpaceLabel)
                installPreflightRow("Model", vm.isCloudLikeInferenceMode || !vm.selectedModel.isEmpty, detail: vm.isCloudLikeInferenceMode ? vm.selectedOpenRouterModel : vm.selectedModel)
            }
            HStack(spacing: 8) {
                Button("Refresh checks") { vm.refreshVersions() }
                    .buttonStyle(CTAButton(primary: false))
                if installBlockingPreflightCount > 0 {
                    Button("Fix first issue") { installFixFirstIssue() }
                        .buttonStyle(CTAButton(primary: true))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.card))
    }

    private var installApiKeyReady: Bool {
        vm.inferenceMode == .local || !vm.providerNeedsApiKey() || !vm.requiredProviderKey().isEmpty
    }

    private var installDiskSpaceBytes: Int64? {
        try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    private var installDiskSpaceReady: Bool {
        guard let bytes = installDiskSpaceBytes else { return true }
        let minimum: Int64 = vm.inferenceMode == .local ? 20_000_000_000 : 5_000_000_000
        return bytes >= minimum
    }

    private var installDiskSpaceLabel: String {
        guard let bytes = installDiskSpaceBytes else { return "Unknown" }
        return String(format: "%.0f GB free", Double(bytes) / 1_000_000_000)
    }

    private var installBlockingPreflightCount: Int {
        var count = 0
        if !installApiKeyReady { count += 1 }
        if !installDiskSpaceReady { count += 1 }
        if vm.inferenceMode == .local && vm.selectedModel.isEmpty { count += 1 }
        return count
    }

    private func installComponentInstalled(name: String) -> Bool {
        switch name {
        case "Homebrew": return vm.brewVersion != "Not installed" && vm.brewVersion != "Checking..."
        case "Node": return vm.nodeVersion != "Not installed" && vm.nodeVersion != "Checking..."
        case "OpenClaw": return vm.openclawInstalledVersion != "Not installed" && vm.openclawInstalledVersion != "Checking..."
        case "LM Studio": return vm.lmStudioVersion != "Not installed" && vm.lmStudioVersion != "Checking..."
        default: return false
        }
    }

    private func installPreflightRow(_ title: String, _ ok: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color(NSColor.systemGreen) : UI.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.text)
                Text(detail.isEmpty ? "Pending" : detail)
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
    }

    private func installFixFirstIssue() {
        if !installApiKeyReady {
            vm.openProviderURL()
        } else if vm.inferenceMode == .local && vm.selectedModel.isEmpty {
            vm.selectedModel = vm.recommendation
        } else {
            vm.screen = .healthCenter
        }
    }

    private var inferenceModeHelpText: String {
        switch vm.inferenceMode {
        case .cloud:
            return "Use Cloud LLM models via provider API key"
        case .oauth:
            return "Use OpenAI through ChatGPT/Codex OAuth login"
        case .local:
            return "Run fully local with LM Studio"
        }
    }

    private func bindingForProviderKey() -> Binding<String> {
        switch vm.selectedProvider {
        case .openRouter:
            return $vm.openRouterApiKey
        case .openAI:
            return $vm.openAIApiKey
        case .anthropic:
            return $vm.anthropicApiKey
        case .gemini:
            return $vm.geminiApiKey
        case .xAI:
            return $vm.xAIApiKey
        case .custom:
            return $vm.openRouterApiKey
        }
    }

    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. AI Provider")
                .font(AppFont.bodySemi(14))
                .foregroundStyle(UI.text)

            Text(vm.inferenceMode == .oauth ? "OAuth LLM uses OpenAI OAuth. No API key field is required." : "Cloud LLM uses provider API keys.")
                .font(AppFont.body(12))
                .foregroundStyle(UI.muted)

            Picker("Provider", selection: $vm.selectedProvider) {
                ForEach(InstallerViewModel.AIProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .disabled(vm.inferenceMode == .oauth)

            if vm.inferenceMode == .oauth {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OAuth uses OpenAI (ChatGPT/Codex).")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                }
            }

            providerAuthMatrix

            providerQuickHelp

            openRouterModelPicker
            apiKeySection
            
            if !vm.gatewayToken.isEmpty {
                Text("Token will be auto-generated during installation")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.card))
    }

    private var providerAuthMatrix: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Provider auth methods")
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.text)

            authMatrixRow(provider: "OpenAI", auth: "OAuth available + API key")
            authMatrixRow(provider: "OpenRouter", auth: "API key required")
            authMatrixRow(provider: "Anthropic", auth: "API key required")
            authMatrixRow(provider: "Gemini", auth: "API key required")
            authMatrixRow(provider: "xAI", auth: "API key required")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
    }

    @ViewBuilder
    private var providerQuickHelp: some View {
        if vm.selectedCloudAuthMode == .api {
            VStack(alignment: .leading, spacing: 6) {
                if vm.selectedProvider == .openRouter {
                    Text("What is OpenRouter?")
                        .font(AppFont.bodySemi(11))
                        .foregroundStyle(UI.text)
                    Text("OpenRouter is a single API gateway that gives access to many models with one API key.")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                } else {
                    Text("Need an API key?")
                        .font(AppFont.bodySemi(11))
                        .foregroundStyle(UI.text)
                    Text("Create your key on the provider website, then paste it here and verify.")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                }

                HStack(spacing: 8) {
                    Button(vm.selectedProvider == .openRouter ? "Open OpenRouter" : "Open Provider Site") {
                        vm.openProviderURL()
                    }
                    .buttonStyle(CTAButton(primary: false))

                    Button("Open docs") {
                        vm.openOpenClawDocs()
                    }
                    .buttonStyle(CTAButton(primary: false))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
        }
    }

    private func authMatrixRow(provider: String, auth: String) -> some View {
        HStack {
            Text(provider)
                .font(AppFont.body(11))
                .foregroundStyle(UI.text)
            Spacer()
            Text(auth)
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
        }
    }

    @ViewBuilder
    private var openRouterModelPicker: some View {
        if vm.selectedCloudAuthMode == .api && vm.selectedProvider == .openRouter && vm.openRouterKeyVerified {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("OpenRouter catalog")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                    Spacer()
                    Text("\(vm.openRouterModelsLive.count) models")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                    Button("Refresh") { vm.refreshOpenRouterModels() }
                        .buttonStyle(CTAButton(primary: false))
                }

                if vm.openRouterModelsLive.isEmpty {
                    Text("No OpenRouter models loaded yet. Click Refresh.")
                        .font(AppFont.body(12))
                        .foregroundStyle(UI.muted)
                } else {
                    Picker("Model", selection: $vm.selectedOpenRouterModel) {
                        ForEach(vm.openRouterModelsLive, id: \.self) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .onAppear { vm.refreshOpenRouterModels() }
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        if vm.selectedCloudAuthMode == .oauth {
            VStack(alignment: .leading, spacing: 8) {
                Text("OAuth uses your ChatGPT/Codex account (no API key needed).")
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)

                Button("Sign in with OpenAI (OAuth)") {
                    vm.openTerminalOpenAIOAuth()
                }
                .buttonStyle(CTAButton(primary: false))
            }
        } else if vm.providerNeedsApiKey() {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField(vm.selectedProvider == .openAI ? "OpenAI API Key" : "API Key", text: bindingForProviderKey())
                        .textFieldStyle(.roundedBorder)

                    if vm.selectedProvider == .openRouter {
                        Button("Verify") { vm.verifyOpenRouterKey() }
                            .buttonStyle(CTAButton(primary: false))
                            .disabled(vm.openRouterApiKey.count < 20)
                    }
                }

                openRouterKeyStatus
            }
        }
    }

    @ViewBuilder
    private var openRouterKeyStatus: some View {
        if vm.selectedProvider == .openRouter {
            if vm.openRouterKeyVerified {
                Text("✓ API Key valid")
                    .font(AppFont.body(12))
                    .foregroundStyle(Color(NSColor.systemGreen))
            } else if !vm.openRouterApiKey.isEmpty && vm.openRouterApiKey.count < 20 {
                Text("Key format invalid (should start with sk-or-...)")
                    .font(AppFont.body(12))
                    .foregroundStyle(Color(NSColor.systemRed))
            }
        }
    }

    var install: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Step 3: Installing")
                    .font(AppFont.heading(30)).foregroundStyle(UI.text)
                ProgressView(value: vm.progress).tint(UI.accent)
                VStack(alignment: .leading, spacing: 8) {
                    installTimelineRow("1/7", "Homebrew", vm.statusHomebrew)
                    installTimelineRow("2/7", "LM Studio", vm.statusLMStudio)
                    installTimelineRow("3/7", "Model", vm.statusModel)
                    installTimelineRow("4/7", "Node", vm.statusNode)
                    installTimelineRow("5/7", "OpenClaw", vm.statusOpenClaw)
                    installTimelineRow("6/7", "Gateway + config", vm.statusService == "PENDING" ? vm.statusConfig : vm.statusService)
                    installTimelineRow("7/7", "Final check", vm.statusOpenClawCheck)
                }

                DisclosureGroup("Installation logs") {
                    ScrollView {
                        Text(vm.logs).font(.system(size: 12, design: .monospaced)).foregroundStyle(UI.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: 180)
                }
                .font(AppFont.bodySemi(12))
                .foregroundStyle(UI.text)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading: \(vm.currentDownloadFile.isEmpty ? "Waiting..." : vm.currentDownloadFile)")
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ProgressView(value: vm.downloadProgress, total: 1.0)
                        .tint(UI.accent)
                    Text("\(Int(vm.downloadProgress * 100))%")
                        .font(AppFont.body(12))
                        .foregroundStyle(UI.muted)
                }
                .padding(.top, 4)

                HStack(spacing: 10) {
                    Button("Back to setup") { vm.screen = .options }
                        .buttonStyle(CTAButton(primary: false))
                    if installHasFailedStep {
                        Button("Retry failed step") { vm.openTerminalAndInstallFull() }
                            .buttonStyle(CTAButton(primary: true))
                    }
                }
            }
            .padding(18)
            .frame(width: 600)
            .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var installHasFailedStep: Bool {
        [vm.statusHomebrew, vm.statusLMStudio, vm.statusModel, vm.statusNode, vm.statusOpenClaw, vm.statusOpenClawCheck, vm.statusConfig, vm.statusService]
            .contains { $0.uppercased() == "FAIL" }
    }

    private func installTimelineRow(_ step: String, _ title: String, _ state: String) -> some View {
        let normalized = state.uppercased()
        let isDone = normalized == "OK" || normalized == "SKIP"
        let isFailed = normalized == "FAIL"
        let isRunning = vm.isRunning && !isDone && !isFailed
        let icon = isDone ? "checkmark.circle.fill" : (isFailed ? "xmark.circle.fill" : (isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "circle"))
        let tint: Color = isDone ? Color(NSColor.systemGreen) : (isFailed ? Color(NSColor.systemRed) : (isRunning ? UI.accent : UI.muted))
        let label = isDone ? (normalized == "SKIP" ? "Skipped" : "Done") : (isFailed ? "Failed" : (isRunning ? "Running" : "Pending"))

        return HStack(spacing: 10) {
            Text(step)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(UI.muted)
                .frame(width: 34, alignment: .leading)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(title)
                .font(AppFont.bodySemi(13))
                .foregroundStyle(UI.text)
            Spacer()
            Text(label)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(isDone || isFailed ? 0.28 : 0.12), lineWidth: 1))
    }

    var ready: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

            // Header
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(UI.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installation complete!")
                        .font(AppFont.heading(30)).foregroundStyle(UI.text)
                    Text("Everything is configured and ready to go.")
                        .font(AppFont.body(15)).foregroundStyle(UI.muted)
                }
            }

            // Component status summary (Bug 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT WAS INSTALLED")
                    .font(AppFont.heading(11)).kerning(0.6).foregroundStyle(UI.accent)
                statusRow("Homebrew", vm.statusHomebrew)
                statusRow("LM Studio", vm.selectedModel.isEmpty ? "Skipped" : vm.statusLMStudio)
                statusRow("Model", vm.selectedModel.isEmpty ? "Skipped" : vm.statusModel)
                statusRow("Node.js", vm.statusNodeJS)
                statusRow("OpenClaw", vm.statusOpenClaw)
                statusRow("Config", vm.statusConfig)
                statusRow("Gateway Service", vm.statusService)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))

            // Next steps checklist (Bug 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT STEPS")
                    .font(AppFont.heading(11)).kerning(0.6).foregroundStyle(UI.accent)
                nextStepRow("1", "Open the OpenClaw dashboard", "Open it with the button below")
                nextStepRow("2", "Send your first message", "Type anything — your AI is live")
                if vm.mode != .llmOnly {
                    nextStepRow("3", "Connect a messaging channel", "Discord, Telegram, WhatsApp, Signal...")
                    nextStepRow("4", "Customize your AI personality", "Edit SOUL.md in the workspace")
                } else {
                    nextStepRow("3", "Load your model in LM Studio", "Open LM Studio and select your model")
                    nextStepRow("4", "Connect OpenClaw to LM Studio", "Run Install OpenClaw next")
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))

            // CTA buttons (Bug 4)
            VStack(alignment: .leading, spacing: 10) {
                Text("LAUNCH")
                    .font(AppFont.heading(11)).kerning(0.6).foregroundStyle(UI.accent)
                HStack(spacing: 10) {
                    Button("OPEN OPENCLAW DASHBOARD") { vm.openDashboard() }
                        .buttonStyle(CTAButton(primary: true))
                    if vm.mode == .llmOnly || vm.lmStudioVersion != "Not installed" {
                        Button("Open LM Studio") { vm.openLMStudio() }
                            .buttonStyle(CTAButton(primary: false))
                    }
                    Button("Update center") { vm.screen = .updates }
                        .buttonStyle(CTAButton(primary: false))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))

            // Back button
            HStack {
                Spacer()
                Button("← Back to Home") { vm.screen = .home }
                    .buttonStyle(CTAButton(primary: false))
                Spacer()
            }
        }
        .padding(22)
        .frame(maxWidth: 900, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
        .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    func nextStepRow(_ number: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(UI.accent).frame(width: 26, height: 26)
                Text(number).font(AppFont.heading(12)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(AppFont.bodySemi(13)).foregroundStyle(UI.text)
                Text(subtitle).font(AppFont.body(12)).foregroundStyle(UI.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(UI.muted.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
    }

    var updates: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("UPDATE CENTER")
                    .font(AppFont.heading(28))
                    .foregroundStyle(UI.text)
                Spacer()
                Text(vm.isRunning ? "Updating..." : vm.openclawUpdateStatus)
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(vm.openclawUpdateStatus == "Up to date" ? UI.accent : UI.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(UI.cardSoft))
            }

            updateSafetyPanel

            updateGroupsPanel

            VStack(spacing: 8) {
                versionRow("OpenClaw", vm.openclawInstalledVersion, vm.openclawLatestVersion, isUpToDate: vm.openclawUpdateStatus == "Up to date")
                versionRow("Homebrew", vm.brewVersion, "latest via brew update", isUpToDate: vm.brewUpToDate)
                versionRow("Node", vm.nodeVersion, "latest via brew upgrade", isUpToDate: vm.nodeUpToDate)
                versionRow("LM Studio", vm.lmStudioVersion, "latest via brew cask", isUpToDate: vm.lmStudioUpToDate)
                versionRow("LocalClaw", "\(vm.installerCurrentVersion) (build \(vm.installerBuildNumber))", vm.installerLatestVersion, isUpToDate: vm.installerUpdateStatus == "Up to date")
            }

            updateChangePlanPanel

            HStack(spacing: 10) {
                Button(vm.isRunning ? "UPDATING..." : "UPDATE ALL") { vm.updateAll() }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(vm.isRunning)
                Button("CHECK") { vm.refreshVersions() }.buttonStyle(CTAButton(primary: false))
                Button("BACK") { vm.screen = .home }.buttonStyle(CTAButton(primary: false))
            }

            Divider().overlay(UI.lineSoft)

            Text("Live log")
                .font(AppFont.bodySemi(14))
                .foregroundStyle(UI.muted)

            ScrollView {
                Text(vm.logs.isEmpty ? "No update run yet. Click CHECK or UPDATE ALL." : vm.logs)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(UI.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
    }

    private var updateSafetyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Update safety", systemImage: updateRiskIcon)
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(updateRiskTint)
                Spacer()
                Text(updateRiskLabel)
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(updateRiskTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 999).fill(updateRiskTint.opacity(0.10)))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                updateSafetyRow("Config backup", ok: updateConfigExists, detail: updateConfigExists ? "OpenClaw config found" : "No config found")
                updateSafetyRow("Gateway", ok: vm.gatewayIsRunning, detail: vm.gatewayIsRunning ? "Running" : "Offline")
                updateSafetyRow("LocalClaw app", ok: updateAppInApplications, detail: updateAppInApplications ? "Installed app path" : "Dev or custom path")
                updateSafetyRow("DMG checksum", ok: updateHasValidChecksum, detail: updateHasValidChecksum ? "SHA256 available" : "Missing checksum")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(updateRiskTint.opacity(0.25), lineWidth: 1))
    }

    private var updateGroupsPanel: some View {
        HStack(spacing: 10) {
            updateGroupCard(
                title: "App update",
                detail: "Update LocalClaw only.",
                status: vm.installerUpdateStatus,
                icon: "app.badge",
                primary: vm.installerUpdateStatus == "Update available"
            ) { vm.updateLocalClawFromDMG() }
            updateGroupCard(
                title: "OpenClaw runtime",
                detail: "Update CLI, gateway service, config check.",
                status: vm.openclawUpdateStatus,
                icon: "terminal",
                primary: vm.openclawUpdateStatus == "Needs update"
            ) { vm.updateOpenClawRuntime() }
            updateGroupCard(
                title: "Dependencies",
                detail: "Homebrew, Node, LM Studio.",
                status: updateDependenciesStatus,
                icon: "shippingbox.fill",
                primary: false
            ) { vm.updateDependenciesOnly() }
        }
    }

    private var updateChangePlanPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Update summary", systemImage: "list.bullet.clipboard.fill")
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                Spacer()
                Text(updateSummaryStatus)
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(updateSummaryTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 999).fill(updateSummaryTint.opacity(0.10)))
            }

            if vm.installerUpdateStatus == "Update available" {
                compactUpdatePlanRow(
                    title: "LocalClaw app",
                    detail: "\(vm.installerCurrentVersion) -> \(vm.installerLatestVersion)",
                    status: "Will update",
                    tint: UI.accent
                )
            }

            if vm.openclawUpdateStatus == "Needs update" {
                compactUpdatePlanRow(
                    title: "OpenClaw runtime",
                    detail: "\(vm.openclawInstalledVersion) -> \(vm.openclawLatestVersion)",
                    status: "Will update",
                    tint: UI.accent
                )
            }

            if missingDependencyNames.isEmpty == false {
                compactUpdatePlanRow(
                    title: "Dependencies",
                    detail: missingDependencyNames.joined(separator: ", "),
                    status: "Needs install",
                    tint: Color(NSColor.systemOrange)
                )
            }

            if updateSummaryStatus == "No changes" {
                compactUpdatePlanRow(
                    title: "Everything is current",
                    detail: "LocalClaw, OpenClaw and dependencies look ready.",
                    status: "Up to date",
                    tint: Color(NSColor.systemGreen)
                )
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    private var updateConfigExists: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.openclaw/openclaw.json")
    }

    private var updateAppInApplications: Bool {
        let path = Bundle.main.bundlePath
        return path == "/Applications/LocalClaw.app" || path == NSHomeDirectory() + "/Applications/LocalClaw.app"
    }

    private var updateHasValidChecksum: Bool {
        vm.installerExpectedSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }

    private var updateRiskLabel: String {
        if updateHasValidChecksum && updateAppInApplications && updateConfigExists { return "Safe" }
        if updateConfigExists || updateHasValidChecksum { return "Caution" }
        return "Risky"
    }

    private var updateRiskIcon: String {
        updateRiskLabel == "Safe" ? "checkmark.seal.fill" : (updateRiskLabel == "Caution" ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
    }

    private var updateRiskTint: Color {
        updateRiskLabel == "Safe" ? Color(NSColor.systemGreen) : (updateRiskLabel == "Caution" ? Color(NSColor.systemOrange) : Color(NSColor.systemRed))
    }

    private var updateDependenciesStatus: String {
        let installed = [vm.brewVersion, vm.nodeVersion, vm.lmStudioVersion].filter { $0 != "Not installed" && $0 != "Checking..." }.count
        return "\(installed)/3 installed"
    }

    private var missingDependencyNames: [String] {
        [
            vm.brewVersion == "Not installed" ? "Homebrew" : nil,
            vm.nodeVersion == "Not installed" ? "Node" : nil,
            vm.lmStudioVersion == "Not installed" ? "LM Studio" : nil
        ].compactMap { $0 }
    }

    private var updateSummaryStatus: String {
        if vm.installerUpdateStatus == "Update available" || vm.openclawUpdateStatus == "Needs update" || missingDependencyNames.isEmpty == false {
            return "Changes pending"
        }
        return "No changes"
    }

    private var updateSummaryTint: Color {
        updateSummaryStatus == "No changes" ? Color(NSColor.systemGreen) : UI.accent
    }

    private func updateSafetyRow(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color(NSColor.systemGreen) : UI.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.text)
                Text(detail)
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
    }

    private func updateGroupCard(title: String, detail: String, status: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primary ? UI.accent : UI.muted)
                Spacer()
                Text(status)
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(primary ? UI.accent : UI.muted)
                    .lineLimit(1)
            }
            Text(title)
                .font(AppFont.bodySemi(13))
                .foregroundStyle(UI.text)
            Text(detail)
                .font(AppFont.body(10))
                .foregroundStyle(UI.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Button(primary ? "Update" : "Run") { action() }
                .buttonStyle(CTAButton(primary: primary))
                .disabled(vm.isRunning || status == "Up to date")
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(primary ? UI.accent.opacity(0.35) : UI.lineSoft, lineWidth: 1))
    }

    private func compactUpdatePlanRow(title: String, detail: String, status: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status == "Up to date" ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                Text(detail)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(status)
                .font(AppFont.bodySemi(10))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.card))
    }

    var agentsCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AGENTS")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Manage OpenClaw agents, see who does what, which model they use, and whether they are active or routed.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text(vm.agentsStatus)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(vm.agentsIsLoading ? UI.accent : UI.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
                Button("New Agent") { vm.openTerminalAgentCreate() }
                    .buttonStyle(CTAButton(primary: true))
                Button("Refresh") { vm.refreshAgents() }
                    .buttonStyle(CTAButton(primary: false))
                    .disabled(vm.agentsIsLoading)
                Button("Open docs") { vm.openAgentsDocs() }
                    .buttonStyle(CTAButton(primary: false))
            }

            HStack(spacing: 10) {
                agentMetricCard("Agents", value: "\(vm.agents.count)", icon: "person.2.fill", tint: UI.accent)
                agentMetricCard("Active", value: "\(vm.agents.filter { $0.isDefault || $0.bindings > 0 }.count)", icon: "bolt.fill", tint: Color(NSColor.systemGreen))
                agentMetricCard("Routed", value: "\(vm.agents.filter { $0.bindings > 0 }.count)", icon: "arrow.triangle.branch", tint: Color(NSColor.systemBlue))
                agentMetricCard("Models", value: "\(Set(vm.agents.compactMap { $0.model }).count)", icon: "cpu.fill", tint: Color(NSColor.systemPurple))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if vm.agents.isEmpty {
                        Text(vm.agentsIsLoading ? "Checking agents..." : "No agent inventory loaded yet.")
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                    } else {
                        Text("OpenClaw agents")
                            .font(AppFont.bodySemi(13))
                            .foregroundStyle(UI.muted)
                            .padding(.horizontal, 2)
                        ForEach(vm.agents) { agent in
                            agentRow(agent)
                        }
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)

            if !vm.agentLogs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity")
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.muted)
                    ScrollView {
                        Text(vm.agentLogs)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(UI.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 110)
                    .scrollIndicators(.hidden)
                    .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear {
            if vm.agentsStatus == "Not loaded" {
                vm.refreshAgents()
            }
        }
    }

    private func agentMetricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(AppFont.bodySemi(18))
                    .foregroundStyle(UI.text)
                Text(title)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func agentRow(_ agent: InstallerViewModel.AgentInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(agent.identityEmoji ?? "🤖")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(Circle().fill(UI.cardSoft))
                .overlay(Circle().stroke(UI.lineSoft, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(agent.displayName)
                        .font(AppFont.bodySemi(17))
                        .foregroundStyle(UI.text)
                    Text(agent.id)
                        .font(AppFont.bodySemi(11))
                        .foregroundStyle(UI.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
                    agentBadge(agent.statusLabel, color: agent.statusTint, icon: agent.isDefault ? "star.fill" : (agent.bindings > 0 ? "point.3.connected.trianglepath.dotted" : "circle"))
                }

                Text(agent.roleSummary)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)

                Text(agent.detailSummary)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                vm.openTerminalAgentIdentity(agent.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(CTAButton(primary: false))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(agent.statusTint.opacity(0.35), lineWidth: 1))
    }

    private func agentBadge(_ label: String, color: Color, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(AppFont.bodySemi(10))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 999).stroke(color.opacity(0.25), lineWidth: 1))
    }

    var cronJobsCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CRON JOBS")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("See scheduled OpenClaw jobs, what they run, when they run, and remove or add jobs from one place.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text(vm.cronJobsStatus)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(vm.cronJobsIsLoading ? UI.accent : UI.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
                Button("New Job") { vm.prepareCronJobCreator() }
                    .buttonStyle(CTAButton(primary: true))
                Button("Refresh") { vm.refreshCronJobs() }
                    .buttonStyle(CTAButton(primary: false))
                    .disabled(vm.cronJobsIsLoading)
                Button("Open docs") { vm.openCronDocs() }
                    .buttonStyle(CTAButton(primary: false))
            }

            HStack(spacing: 10) {
                cronMetricCard("Jobs", value: "\(vm.cronJobs.count)", icon: "calendar", tint: UI.accent)
                cronMetricCard("Active", value: "\(vm.cronJobs.filter { $0.enabled }.count)", icon: "checkmark.seal.fill", tint: Color(NSColor.systemGreen))
                cronMetricCard("Disabled", value: "\(vm.cronJobs.filter { !$0.enabled }.count)", icon: "pause.circle.fill", tint: UI.muted)
                cronMetricCard("Scheduled", value: "\(vm.cronJobs.filter { $0.nextRun != nil || $0.scheduleLabel != "Schedule" }.count)", icon: "clock.fill", tint: Color(NSColor.systemBlue))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if vm.cronJobs.isEmpty {
                        Text(vm.cronJobsIsLoading ? "Checking cron jobs..." : "No cron jobs configured yet.")
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                    } else {
                        Text("Scheduled jobs")
                            .font(AppFont.bodySemi(13))
                            .foregroundStyle(UI.muted)
                            .padding(.horizontal, 2)
                        ForEach(vm.cronJobs) { job in
                            cronJobRow(job)
                        }
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)

            if !vm.cronJobLogs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity")
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.muted)
                    ScrollView {
                        Text(vm.cronJobLogs)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(UI.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 110)
                    .scrollIndicators(.hidden)
                    .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear {
            if vm.cronJobsStatus == "Not loaded" {
                vm.refreshCronJobs()
            }
        }
    }

    private func cronMetricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(AppFont.bodySemi(18))
                    .foregroundStyle(UI.text)
                Text(title)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    private var cronJobCreatorSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("New Cron Job")
                        .font(AppFont.heading(24))
                        .foregroundStyle(UI.text)
                    Text("Create a scheduled OpenClaw task without opening Terminal.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Button("Cancel") {
                    vm.showCronJobCreator = false
                    vm.resetCronJobCreator()
                }
                .buttonStyle(SheetActionButton(primary: false))
            }

            VStack(alignment: .leading, spacing: 12) {
                cronFormField("Job name", text: $vm.cronCreateName, prompt: "Daily inbox check")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)
                    Picker("", selection: $vm.cronCreateAgentID) {
                        if vm.agents.isEmpty {
                            Text("Main assistant").tag("main")
                        } else {
                            ForEach(vm.agents) { agent in
                                Text(agent.isDefault ? "\(agent.displayName) · main" : agent.displayName)
                                    .tag(agent.id)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))

                    if let selectedAgent = vm.agents.first(where: { $0.id == vm.cronCreateAgentID }) {
                        Text(selectedAgent.detailSummary)
                            .font(AppFont.body(11))
                            .foregroundStyle(UI.muted)
                            .lineLimit(2)
                    } else if vm.agentsIsLoading {
                        Text("Loading agents...")
                            .font(AppFont.body(11))
                            .foregroundStyle(UI.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Schedule")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)
                    HStack(spacing: 8) {
                        Picker("", selection: $vm.cronCreateScheduleKind) {
                            Text("Every").tag("every")
                            Text("Cron").tag("cron")
                            Text("At").tag("at")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 230)

                        TextField(schedulePrompt, text: $vm.cronCreateScheduleValue)
                            .textFieldStyle(.plain)
                            .font(AppFont.body(13))
                            .foregroundStyle(UI.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                        ForEach(schedulePresets, id: \.label) { preset in
                            Button(preset.label) {
                                vm.cronCreateScheduleKind = preset.kind
                                vm.cronCreateScheduleValue = preset.value
                            }
                            .buttonStyle(PresetPillButton(selected: vm.cronCreateScheduleKind == preset.kind && vm.cronCreateScheduleValue == preset.value))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent message")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)
                    TextEditor(text: $vm.cronCreateMessage)
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 130)
                        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                }

                if !vm.cronCreateError.isEmpty {
                    Text(vm.cronCreateError)
                        .font(AppFont.body(12))
                        .foregroundStyle(Color(NSColor.systemRed))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.systemRed).opacity(0.10)))
                }
            }

            HStack {
                Text(scheduleHelp)
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
                Spacer()
                Button(vm.cronCreateIsRunning ? "Creating..." : "Create Job") {
                    vm.createCronJobFromForm()
                }
                .buttonStyle(SheetActionButton(primary: true))
                .disabled(vm.cronCreateIsRunning)
            }
        }
        .padding(22)
        .frame(width: 680)
        .background(UI.bg)
    }

    private var schedulePrompt: String {
        switch vm.cronCreateScheduleKind {
        case "cron": return "0 9 * * *"
        case "at": return "15m, 1h, or 2026-05-17T12:00:00+02:00"
        default: return "30m, 2h, 1d"
        }
    }

    private var scheduleHelp: String {
        switch vm.cronCreateScheduleKind {
        case "cron": return "Cron format: minute hour day month weekday. Example: 0 9 * * * means every day at 09:00."
        case "at": return "Use 15m, 1h, 2d, or an ISO timestamp for one-shot jobs."
        default: return "Use simple intervals like 30m, 2h, or 1d."
        }
    }

    private var schedulePresets: [(label: String, kind: String, value: String)] {
        switch vm.cronCreateScheduleKind {
        case "cron":
            return [
                ("Every morning", "cron", "0 9 * * *"),
                ("Every weekday", "cron", "0 9 * * 1-5"),
                ("Every Monday", "cron", "0 9 * * 1"),
                ("Every evening", "cron", "0 18 * * *")
            ]
        case "at":
            return [
                ("In 15 min", "at", "15m"),
                ("In 1 hour", "at", "1h"),
                ("Tomorrow", "at", "1d"),
                ("Next week", "at", "7d")
            ]
        default:
            return [
                ("Every 30 min", "every", "30m"),
                ("Every hour", "every", "1h"),
                ("Every 6 hours", "every", "6h"),
                ("Every day", "every", "1d")
            ]
        }
    }

    private func cronFormField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.bodySemi(12))
                .foregroundStyle(UI.muted)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(AppFont.body(13))
                .foregroundStyle(UI.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
        }
    }

    private func cronJobRow(_ job: InstallerViewModel.CronJobInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(job.statusTint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(UI.cardSoft))
                    .overlay(Circle().stroke(UI.lineSoft, lineWidth: 1))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(job.name)
                            .font(AppFont.bodySemi(17))
                            .foregroundStyle(UI.text)
                        cronBadge(job.statusLabel, color: job.statusTint, icon: job.enabled ? "checkmark.circle.fill" : "pause.circle.fill")
                    }
                    Text(job.id)
                        .font(AppFont.bodySemi(11))
                        .foregroundStyle(UI.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let description = job.description, !description.isEmpty {
                        Text(description)
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.text)
                            .lineLimit(2)
                    }
                    Text(job.detailSummary)
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Button("Run") { vm.runCronJobNow(job.id) }
                    .buttonStyle(CTAButton(primary: false))
                Button("Delete") { vm.openTerminalCronRemove(job.id) }
                    .buttonStyle(CTAButton(primary: false))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(job.statusTint.opacity(0.35), lineWidth: 1))
    }

    private func cronBadge(_ label: String, color: Color, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(AppFont.bodySemi(10))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 999).stroke(color.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private func helpStepCard(number: Int, title: String, detail: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Step \(number) - \(title)")
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)
                Text(detail)
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    @ViewBuilder
    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(question, systemImage: "questionmark.circle.fill")
                .font(AppFont.bodySemi(13))
                .foregroundStyle(UI.text)
            Text(answer)
                .font(AppFont.body(12))
                .foregroundStyle(UI.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    var healthCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HELP")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Step by step setup, FAQ, and recovery tools.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Button("Rerun setup guide") {
                    vm.restartOnboarding()
                }
                .buttonStyle(CTAButton(primary: false))

                Text(vm.healthStatus)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(vm.healthStatus == "Healthy" ? .green : (vm.healthStatus == "Critical" ? .red : .orange))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            }

            Picker("Help section", selection: $helpTab) {
                ForEach(HelpTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
                .tint(UI.accent)

            Group {
                switch helpTab {
                case .stepByStep:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recommended flow")
                                .font(AppFont.bodySemi(14))
                                .foregroundStyle(UI.text)

                            Group {
                                helpStepCard(number: 1, title: "Open Install", detail: "Go to Install in the left sidebar.", icon: "play.circle.fill", tint: UI.accent)
                                helpStepCard(number: 2, title: "Choose your mode", detail: "Cloud LLM for fastest setup, Local LLM for offline usage.", icon: "slider.horizontal.3", tint: .blue)
                                helpStepCard(number: 3, title: "Set provider auth", detail: "Cloud LLM mode: choose OpenAI OAuth or API key.", icon: "key.fill", tint: .purple)
                                helpStepCard(number: 4, title: "If API key mode", detail: "Paste key first, then click Verify.", icon: "checkmark.shield.fill", tint: .green)
                                helpStepCard(number: 5, title: "Run installation", detail: "Click Install Everything and keep Terminal open.", icon: "gearshape.2.fill", tint: .orange)
                                helpStepCard(number: 6, title: "Mac password prompt", detail: "If Terminal asks Password, type your Mac password. Input is hidden by macOS.", icon: "lock.fill", tint: .red)
                                helpStepCard(number: 7, title: "Wait for completion", detail: "Stop only when Installation Complete appears.", icon: "hourglass.circle.fill", tint: .mint)
                                helpStepCard(number: 8, title: "Final test", detail: "Open Dashboard and send one test message.", icon: "message.fill", tint: .indigo)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Label("Pro tip", systemImage: "lightbulb.fill")
                                    .font(AppFont.bodySemi(13))
                                    .foregroundStyle(.yellow)
                                Text("If something fails, go to Help > Health commands and run Run Health Check before retrying full install.")
                                    .font(AppFont.body(12))
                                    .foregroundStyle(UI.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)

                case .faq:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Critical setup blockers")
                                .font(AppFont.bodySemi(12))
                                .foregroundStyle(UI.accent)
                            faqRow(question: "Terminal asks for Password. Which password is this?", answer: "Your Mac user password. Nothing is shown while typing, this is normal on macOS.")
                            faqRow(question: "Install says complete, but I get no replies.", answer: "Open Install again, verify provider and key, then run Help > Health commands > Run Health Check.")
                            faqRow(question: "I clicked Update LocalClaw but UI did not change.", answer: "Make sure you are on app version 1.0.1 or newer. Older builds could update repo code without replacing the running app bundle.")

                            Text("Common beginner questions")
                                .font(AppFont.bodySemi(12))
                                .foregroundStyle(UI.accent)
                            faqRow(question: "Where do I put my API key?", answer: "Go to Install, pick your AI provider, paste the key in API Key, then click Verify.")
                            faqRow(question: "Do I need credits to use Cloud LLM mode?", answer: "Yes. API key mode needs active credits. OpenAI OAuth mode can work without manually pasting a key.")
                            faqRow(question: "Cloud LLM or Local LLM: what should I choose first?", answer: "Start with Cloud LLM for fastest setup. Use Local LLM if you want offline and private inference.")
                            faqRow(question: "Can I switch modes after installation?", answer: "Yes. Use the Cloud LLM/Local LLM switch and click Apply. You can switch anytime.")

                            Text("Performance and monitoring")
                                .font(AppFont.bodySemi(12))
                                .foregroundStyle(UI.accent)
                            faqRow(question: "How can I confirm Local LLM mode is really active?", answer: "In top bar, mode should display LOCAL LLM. In Control Center, apply Local LLM mode and run a quick test message.")
                            faqRow(question: "Why is Local mode slower on my machine?", answer: "Large models use more RAM and swap. Pick a smaller model and run Fix My Speed in Control Center.")
                            faqRow(question: "How do I reset safely without losing everything?", answer: "Use Backup Config first in Help > Health commands, then run Quick Repair.")
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)

                case .healthCommands:
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button("Run Health Check") { vm.runHealthCheck() }
                                .buttonStyle(CTAButton(primary: true))
                            Button("Quick Repair") { vm.runQuickRepair() }
                                .buttonStyle(CTAButton(primary: false))
                            Button("Backup Config") { vm.backupOpenClawConfig() }
                                .buttonStyle(CTAButton(primary: false))
                        }

                        Text("Diagnostics log")
                            .font(AppFont.bodySemi(14))
                            .foregroundStyle(UI.muted)

                        ScrollView {
                            Text(vm.healthLogs.isEmpty ? "No diagnostic run yet." : vm.healthLogs)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(UI.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .scrollIndicators(.hidden)
                        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
    }

    var usageCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BUDGET ESTIMATOR (OPTIONAL)")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Use this only if you pay for Cloud LLM API usage and want a rough monthly estimate.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text(String(format: "$%.2f / month", vm.estimatedMonthlyCostUSD))
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("When to use this")
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)
                Text("• You use paid Cloud LLM models (OpenRouter/OpenAI/Anthropic/etc.)\n• You want a rough monthly budget\n• You want to compare cheap vs expensive model usage")
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
                Text("If you run local-only models, you can ignore this page.")
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.accent)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text("Estimated monthly tokens: \(String(format: "%.1f", vm.estimatedMonthlyTokensM))M")
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)
                Slider(value: $vm.estimatedMonthlyTokensM, in: 0.1...50, step: 0.1)
                HStack(spacing: 10) {
                    Button("Refresh estimate") { vm.refreshUsageCostEstimate() }
                        .buttonStyle(CTAButton(primary: true))
                    Text(vm.costAdvice)
                        .font(AppFont.body(12))
                        .foregroundStyle(UI.muted)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))

            Text("Estimator log")
                .font(AppFont.bodySemi(14))
                .foregroundStyle(UI.muted)

            ScrollView {
                Text(vm.usageLogs.isEmpty ? "No estimate run yet." : vm.usageLogs)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(UI.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear { vm.refreshUsageCostEstimate() }
    }

    var skillsCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SKILLS")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Browse OpenClaw skills, check what is ready, and install ClawHub skills.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }

                Spacer()

                Text(vm.skillsStatus)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(vm.skillsIsLoading ? UI.accent : UI.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(UI.muted)
                    TextField("Search installed skills or ClawHub", text: $vm.skillsSearchQuery)
                        .textFieldStyle(.plain)
                        .font(AppFont.body(13))
                        .onSubmit { vm.searchClawHubSkills() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))

                Button("Refresh") { vm.refreshSkills() }
                    .buttonStyle(CTAButton(primary: false))
                    .disabled(vm.skillsIsLoading)

                Button("Search ClawHub") { vm.searchClawHubSkills() }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(vm.skillsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 10) {
                skillMetricCard("Installed", value: "\(vm.installedSkills.count)", icon: "checkmark.seal.fill", tint: Color(NSColor.systemGreen))
                skillMetricCard("Active", value: "\(vm.installedSkills.filter { $0.isActive }.count)", icon: "bolt.fill", tint: UI.accent)
                skillMetricCard("Needs setup", value: "\(vm.installedSkills.filter { $0.disabled == true }.count)", icon: "exclamationmark.triangle.fill", tint: Color(NSColor.systemOrange))
                skillMetricCard("Not installed", value: "\(vm.clawHubSkills.count)", icon: "tray.and.arrow.down.fill", tint: UI.muted)
            }

            HStack(alignment: .top, spacing: 14) {
                skillsListPanel(
                    title: "Installed and bundled",
                    emptyText: vm.skillsIsLoading ? "Loading skills..." : "No skill found.",
                    skills: vm.visibleInstalledSkills,
                    showInstall: false
                )

                skillsListPanel(
                    title: "ClawHub results",
                    emptyText: vm.skillsSearchQuery.isEmpty ? "Search ClawHub to find new skills." : "No ClawHub result yet.",
                    skills: vm.clawHubSkills,
                    showInstall: true
                )
            }

            if !vm.skillsLog.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity")
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.muted)
                    ScrollView {
                        Text(vm.skillsLog)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(UI.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 120)
                    .scrollIndicators(.hidden)
                    .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear {
            if vm.installedSkills.isEmpty {
                vm.refreshSkills()
            }
        }
    }

    private func skillMetricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(AppFont.bodySemi(18))
                    .foregroundStyle(UI.text)
                Text(title)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func skillsListPanel(title: String, emptyText: String, skills: [InstallerViewModel.OpenClawSkill], showInstall: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.bodySemi(14))
                .foregroundStyle(UI.text)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if skills.isEmpty {
                        Text(emptyText)
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        ForEach(skills) { skill in
                            skillRow(skill, showInstall: showInstall)
                        }
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func skillRow(_ skill: InstallerViewModel.OpenClawSkill, showInstall: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(UI.card)
                if let emoji = skill.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 18))
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(UI.accent)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(skill.name)
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }

                HStack(spacing: 6) {
                    skillBadge(skill.installedLabel, color: showInstall ? UI.muted : Color(NSColor.systemGreen), icon: showInstall ? "tray.and.arrow.down" : "checkmark.circle.fill")
                    skillBadge(skill.activeLabel, color: skill.isActive ? UI.accent : UI.muted, icon: skill.isActive ? "bolt.fill" : "pause.circle")
                    skillBadge(skill.statusLabel, color: skill.eligible == true ? Color(NSColor.systemGreen) : (skill.disabled == true ? Color(NSColor.systemOrange) : UI.muted), icon: skill.eligible == true ? "checkmark.seal.fill" : "info.circle")
                }

                Text(skill.description ?? "No description available.")
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
                    .lineLimit(3)

                Text("\(skill.sourceLabel) · \(skill.missing?.summary ?? "Ready")")
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted.opacity(0.85))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if showInstall {
                Button(vm.installingSkillName == skill.name ? "Installing..." : "Install") {
                    vm.installSkill(skill)
                }
                .buttonStyle(CTAButton(primary: false))
                .disabled(!vm.installingSkillName.isEmpty)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func skillBadge(_ label: String, color: Color, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(AppFont.bodySemi(10))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 999).stroke(color.opacity(0.25), lineWidth: 1))
    }

    var modelsCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelsHeader
            modelsSummaryRow
            modelsConfigAndEstimator
            modelsInventoryPanel
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear {
            vm.refreshOpenClawChatInfo()
            vm.refreshOpenRouterModels()
            vm.refreshLocalLMStudioModels()
        }
    }

    var modelsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("MODELS").font(AppFont.heading(28)).foregroundStyle(UI.text)
                Text("Choose the active AI backend, verify what is configured, and switch models cleanly.").font(AppFont.body(13)).foregroundStyle(UI.muted)
            }
            Spacer()
            Button("Refresh") {
                vm.refreshOpenClawChatInfo(); vm.refreshOpenRouterModels(); vm.refreshLocalLMStudioModels()
            }
            .buttonStyle(CTAButton(primary: true))
        }
    }

    var modelsSummaryRow: some View {
        HStack(spacing: 12) {
            modelSummaryCard("Active model", value: vm.openClawChatModelLabel, icon: "cpu")
            modelSummaryCard("Mode", value: vm.openClawChatModeLabel, icon: vm.inferenceMode == .local ? "desktopcomputer" : "cloud.fill")
            modelSummaryCard("Cloud auth", value: vm.cloudProviderAuthConfigured ? "Configured" : "Missing", icon: "key.fill")
            modelSummaryCard("Local models", value: "\(vm.localLMStudioModels.count)", icon: "internaldrive.fill")
        }
    }

    var modelsConfigAndEstimator: some View {
        HStack(alignment: .top, spacing: 14) {
            configuredModelsCard
            currentModelCard
        }
    }

    var configuredModelsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select backend").font(AppFont.bodySemi(15)).foregroundStyle(UI.text)

            HStack(alignment: .center, spacing: 16) {
                Picker("Mode", selection: $vm.inferenceMode) {
                    Text("Cloud LLM").tag(InstallerViewModel.InferenceMode.cloud)
                    Text("OAuth LLM").tag(InstallerViewModel.InferenceMode.oauth)
                    Text("Local LLM").tag(InstallerViewModel.InferenceMode.local)
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
                .onChange(of: vm.inferenceMode) { newValue in
                    if newValue == .cloud {
                        vm.selectedChatResponseMode = .cloud
                        vm.prepareCloudModelSelection()
                        vm.selectedCloudAuthMode = .api
                    } else if newValue == .oauth {
                        vm.selectedChatResponseMode = .cloud
                        vm.selectedProvider = .openAI
                        vm.selectedCloudAuthMode = .oauth
                        vm.openAIAuthMethod = .oauth
                    } else {
                        vm.selectedChatResponseMode = .local
                    }
                }

                if vm.inferenceMode == .oauth {
                    Text("OpenAI OAuth")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if vm.inferenceMode == .cloud {
                    Picker("Cloud model", selection: $vm.selectedOpenRouterModel) {
                        if vm.openRouterModelsLive.isEmpty {
                            ForEach(InstallerViewModel.openRouterModels) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        } else {
                            ForEach(vm.openRouterModelsLive) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Picker("Local model", selection: $vm.selectedLocalLMStudioModel) {
                        if vm.localLMStudioModels.isEmpty {
                            Text("No LM Studio model found").tag("")
                        } else {
                            ForEach(vm.localLMStudioModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if vm.inferenceMode == .oauth {
                modelConfigRow(title: "OAuth model", subtitle: "openai-codex/gpt-5.4", icon: "person.badge.key", status: vm.cloudProviderAuthConfigured ? "Ready" : "Needs login")
            } else if vm.inferenceMode == .cloud {
                modelConfigRow(title: "Cloud model", subtitle: vm.selectedOpenRouterModel.isEmpty ? "No cloud model selected" : vm.selectedOpenRouterModel, icon: "cloud.fill", status: vm.cloudProviderAuthConfigured ? "Ready" : "Needs auth")
                if !vm.openRouterModelsLive.isEmpty {
                    Text("OpenRouter catalog: \(vm.openRouterModelsLive.count) models").font(AppFont.body(11)).foregroundStyle(UI.muted)
                }
            } else {
                modelConfigRow(title: "Local model", subtitle: vm.selectedLocalLMStudioModel.isEmpty ? "No LM Studio model selected" : vm.selectedLocalLMStudioModel, icon: "desktopcomputer", status: vm.localLMStudioModels.isEmpty ? "No model" : "Ready")
            }

            HStack(spacing: 8) {
                Button(vm.modelsApplyInProgress ? "Applying..." : "Apply selected model") { vm.applyModelsTabSelection() }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(vm.modelsApplyInProgress || (vm.inferenceMode == .local && vm.selectedLocalLMStudioModel.isEmpty) || (vm.inferenceMode == .cloud && vm.selectedOpenRouterModel.isEmpty))
                Button("Scan models") {
                    vm.refreshOpenRouterModels()
                    vm.refreshLocalLMStudioModels()
                }
                .buttonStyle(CTAButton(primary: false))
                Button("Open dashboard") { vm.openDashboard() }
                    .buttonStyle(CTAButton(primary: false))
            }
            if !vm.modelsApplyStatus.isEmpty {
                Text(vm.modelsApplyStatus).font(AppFont.body(11)).foregroundStyle(UI.muted).lineLimit(2)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    var currentModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current configuration").font(AppFont.bodySemi(15)).foregroundStyle(UI.text)
            modelConfigRow(title: "Running model", subtitle: vm.openClawChatModelLabel, icon: "cpu", status: vm.openClawChatStatus)
            modelConfigRow(title: "Selected cloud", subtitle: vm.selectedOpenRouterModel.isEmpty ? "None selected" : vm.selectedOpenRouterModel, icon: "cloud.fill", status: vm.cloudProviderAuthConfigured ? "Ready" : "Needs auth")
            modelConfigRow(title: "Selected local", subtitle: vm.selectedLocalLMStudioModel.isEmpty ? "None selected" : vm.selectedLocalLMStudioModel, icon: "desktopcomputer", status: vm.localLMStudioModels.isEmpty ? "Scan needed" : "Ready")
            modelConfigRow(title: "Loaded in LM Studio", subtitle: vm.activeLocalLMStudioModel.isEmpty ? "No model currently loaded" : vm.activeLocalLMStudioModel, icon: "memorychip", status: vm.activeLocalLMStudioModel.isEmpty ? "Not running" : "Active")
            Text("Changes are applied only when you click Apply selected model.")
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
        }
        .padding(12).frame(maxWidth: 380, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    var modelsInventoryPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            if vm.isCloudLikeInferenceMode {
                modelInventoryList(
                    title: vm.inferenceMode == .oauth ? "OAuth backend" : "Cloud catalog",
                    count: vm.inferenceMode == .oauth ? 1 : (vm.openRouterModelsLive.isEmpty ? InstallerViewModel.openRouterModels.count : vm.openRouterModelsLive.count),
                    emptyText: vm.inferenceMode == .oauth ? "OpenAI OAuth model configured." : "No cloud catalog loaded.",
                    rows: vm.inferenceMode == .oauth ? ["openai-codex/gpt-5.4"] : Array((vm.openRouterModelsLive.isEmpty ? InstallerViewModel.openRouterModels.map(\.displayName) : vm.openRouterModelsLive.map(\.displayName)).prefix(8)),
                    icon: vm.inferenceMode == .oauth ? "person.badge.key" : "cloud.fill"
                )
            } else {
                modelInventoryList(
                    title: "Local models",
                    count: vm.localLMStudioModels.count,
                    emptyText: "No local model detected.",
                    rows: Array(vm.localLMStudioModels.prefix(8)),
                    icon: "internaldrive.fill"
                )
            }
        }
    }

    func modelSummaryCard(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(UI.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppFont.body(11)).foregroundStyle(UI.muted)
                Text(value).font(AppFont.bodySemi(12)).foregroundStyle(UI.text).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    func modelConfigRow(title: String, subtitle: String, icon: String, status: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(UI.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppFont.bodySemi(13)).foregroundStyle(UI.text)
                Text(subtitle).font(AppFont.body(11)).foregroundStyle(UI.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(status).font(AppFont.bodySemi(10)).foregroundStyle(UI.muted)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.card))
    }

    func modelInventoryList(title: String, count: Int, emptyText: String, rows: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                Spacer()
                Text("\(count)")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.card))
            }
            if rows.isEmpty {
                Text(emptyText)
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
            } else {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 8) {
                        Circle().fill(UI.accent).frame(width: 6, height: 6)
                        Text(row)
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(UI.card))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
    }

    var channelSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CHANNELS")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Pick a channel, connect it in one click, then see immediately whether it is connected, active, configured, or still waiting.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text(vm.channelsStatus)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(vm.channelsIsLoading ? UI.accent : UI.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
                Button("Refresh") { vm.refreshChannels() }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(vm.channelsIsLoading)
                Button("Open docs") { vm.openChannelDocs() }
                    .buttonStyle(CTAButton(primary: false))
            }

            HStack(spacing: 10) {
                channelMetricCard("Apps", value: "\(vm.channels.count)", icon: "square.grid.2x2.fill", tint: UI.accent)
                channelMetricCard("Connected", value: "\(vm.channels.filter { $0.connected || $0.running }.count)", icon: "checkmark.seal.fill", tint: Color(NSColor.systemGreen))
                channelMetricCard("Accounts", value: "\(vm.channels.reduce(0) { $0 + $1.accounts.count })", icon: "person.2.fill", tint: Color(NSColor.systemBlue))
                channelMetricCard("To connect", value: "\(vm.channels.filter { !$0.configured }.count)", icon: "plus.circle.fill", tint: UI.muted)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if vm.channels.isEmpty {
                        Text(vm.channelsIsLoading ? "Checking channels..." : "No channel inventory loaded yet.")
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                    } else {
                        Text("Available channels")
                            .font(AppFont.bodySemi(13))
                            .foregroundStyle(UI.muted)
                            .padding(.horizontal, 2)
                        ForEach(vm.channels) { channel in
                            channelRow(channel)
                        }
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)

            if !vm.channelSetupLogs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity")
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.muted)
                    ScrollView {
                        Text(vm.channelSetupLogs)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(UI.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 110)
                    .scrollIndicators(.hidden)
                    .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear {
            if vm.channelsStatus == "Not loaded" {
                vm.refreshChannels()
            }
        }
    }

    private func channelMetricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(AppFont.bodySemi(18))
                    .foregroundStyle(UI.text)
                Text(title)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func channelRow(_ channel: InstallerViewModel.ChannelInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: channel.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(channel.connected || channel.running ? Color(NSColor.systemGreen) : UI.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(UI.cardSoft))
                    .overlay(Circle().stroke(UI.lineSoft, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.label)
                        .font(AppFont.bodySemi(17))
                        .foregroundStyle(UI.text)
                    HStack(spacing: 7) {
                        Text(channel.id)
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(UI.muted)
                        Circle()
                            .fill(UI.muted.opacity(0.35))
                            .frame(width: 4, height: 4)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(channel.connectionTint)
                                .frame(width: 8, height: 8)
                            Text(channel.connectionLabel)
                                .font(AppFont.bodySemi(12))
                                .foregroundStyle(channel.connectionTint)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button {
                    vm.openTerminalChannelLogin(channel.id)
                } label: {
                    Label(channel.primaryActionLabel, systemImage: "plus")
                }
                .buttonStyle(CTAButton(primary: !channel.configured))

                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(UI.muted.opacity(channel.configured ? 0.85 : 0.30))
                    .help(channel.configured ? "Remove account from OpenClaw config" : "No account to remove")
            }

            VStack(spacing: 8) {
                if channel.id == "telegram" {
                    telegramSetupSteps(channel)
                }
                ForEach(channel.accountRows, id: \.self) { account in
                    channelAccountRow(channel: channel, account: account)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(channel.isActive ? Color(NSColor.systemGreen).opacity(0.35) : UI.lineSoft, lineWidth: 1))
    }

    private func telegramSetupSteps(_ channel: InstallerViewModel.ChannelInfo) -> some View {
        HStack(spacing: 10) {
            channelBadge(channel.configured ? "1 Bot token OK" : "1 Add bot token", color: channel.configured ? Color(NSColor.systemGreen) : UI.muted, icon: channel.configured ? "checkmark.circle.fill" : "1.circle")
            channelBadge("2 Pairing approve required", color: channel.connected ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange), icon: channel.connected ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
            Text("Send /start to the bot, then approve the pairing code in the LocalClaw terminal.")
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
    }

    private func channelAccountRow(channel: InstallerViewModel.ChannelInfo, account: String) -> some View {
        HStack(spacing: 12) {
            Text(account)
                .font(AppFont.bodySemi(13))
                .foregroundStyle(channel.accounts.isEmpty ? UI.muted : UI.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            channelBadge(channel.stateLabel, color: channel.connectionTint, icon: channel.connected ? "checkmark.circle.fill" : (channel.running ? "bolt.fill" : "circle"))

            if let probeOK = channel.probeOK {
                channelBadge(probeOK ? "Probe OK" : "Probe failed", color: probeOK ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange), icon: probeOK ? "antenna.radiowaves.left.and.right" : "exclamationmark.triangle.fill")
            }

            Text(channel.detailLabel)
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
                .lineLimit(1)
                .truncationMode(.middle)

            Button("Edit") {
                vm.openTerminalChannelLogin(channel.id)
            }
            .buttonStyle(CTAButton(primary: false))
            .disabled(channel.accounts.isEmpty)

            Image(systemName: "trash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(UI.muted.opacity(channel.accounts.isEmpty ? 0.25 : 0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
    }

    private func channelBadge(_ label: String, color: Color, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(AppFont.bodySemi(10))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 999).stroke(color.opacity(0.25), lineWidth: 1))
    }

    var uninstallCenter: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("UNINSTALL CENTER")
                            .font(AppFont.heading(28))
                            .foregroundStyle(UI.text)
                        Text("Remove components cleanly, one by one.")
                            .font(AppFont.body(13))
                            .foregroundStyle(UI.muted)
                    }
                    Spacer()
                    Label(vm.isUninstalling ? "Running" : "Ready", systemImage: vm.isUninstalling ? "hourglass" : "checkmark.circle.fill")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(vm.isUninstalling ? UI.accent : Color(NSColor.systemGreen))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
                }

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        uninstallRow("LM Studio app", isOn: $vm.uninstallLMStudioSelected, installed: vm.hasLMStudioInstalled)
                        uninstallRow("Local LLM models", isOn: $vm.uninstallModelsSelected, installed: vm.hasLocalModelsInstalled)
                        uninstallRow("OpenClaw CLI and services", isOn: $vm.uninstallOpenClawSelected, installed: vm.hasOpenClawInstalled)
                        uninstallRow("Node.js and npm/npx", isOn: $vm.uninstallNodeSelected, installed: vm.hasNodeInstalled)
                        uninstallRow("Homebrew", isOn: $vm.uninstallHomebrewSelected, installed: vm.hasHomebrewInstalled)
                        uninstallRow("Configs and cache", isOn: $vm.uninstallConfigsSelected, installed: vm.hasConfigCacheInstalled)
                    }
                    .padding(12)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Safety")
                            .font(AppFont.bodySemi(13))
                            .foregroundStyle(UI.text)
                        Text("Open apps may respawn background processes. Close LM Studio and browsers first for a cleaner uninstall.")
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider().overlay(UI.lineSoft)

                        Text("Actions")
                            .font(AppFont.bodySemi(13))
                            .foregroundStyle(UI.text)
                        Button(vm.isUninstalling ? "Working..." : "Uninstall Selected") {
                            vm.runSelectedUninstall()
                        }
                        .buttonStyle(CTAButton(primary: true))
                        .disabled(vm.isUninstalling)

                        Button("Back") { vm.screen = .home }
                            .buttonStyle(CTAButton(primary: false))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))
                }

                Text("Live log")
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.muted)

                ScrollView {
                    Text(vm.uninstallLogs.isEmpty ? "No uninstall action started." : vm.uninstallLogs)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(UI.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .scrollIndicators(.hidden)
                .frame(minHeight: 170, maxHeight: 260)
                .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        }
        .scrollIndicators(.hidden)
        .onAppear { vm.refreshUninstallInventory() }
    }

    func uninstallRow(_ title: String, isOn: Binding<Bool>, installed: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)
                    .lineLimit(1)
                Text(installed ? "Installed" : "Not installed")
                    .font(AppFont.body(11))
                    .foregroundStyle(installed ? Color(NSColor.systemGreen) : UI.muted)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!installed)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
        .opacity(installed ? 1 : 0.7)
    }

    func setupStepRow(_ step: String, _ title: String, _ state: String) -> some View {
        let good = state == "OK" || state == "SKIP"
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(step).font(AppFont.bodySemi(12)).foregroundStyle(UI.muted)
                Text(title).font(AppFont.bodySemi(14)).foregroundStyle(UI.text)
            }
            Spacer()
            Image(systemName: good ? "checkmark.circle.fill" : (state == "FAIL" ? "xmark.circle.fill" : "circle.fill"))
                .foregroundStyle(good ? Color(NSColor.systemGreen) : (state == "FAIL" ? Color(NSColor.systemRed) : UI.muted.opacity(0.45)))
            Text(good ? "Done" : (state == "FAIL" ? "Failed" : "Pending"))
                .font(AppFont.bodySemi(12))
                .foregroundStyle(good ? Color(NSColor.systemGreen) : (state == "FAIL" ? Color(NSColor.systemRed) : UI.muted))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
    }

    func versionRow(_ name: String, _ installed: String, _ latest: String, isUpToDate: Bool?) -> some View {
        // Bug 8: Don't show green check for components that are not installed
        let actuallyInstalled = installed != "Not installed" && installed != "Checking..."
        let showGreen = actuallyInstalled && (isUpToDate == true)
        let statusIcon = showGreen ? "checkmark.circle.fill" : (actuallyInstalled ? "arrow.up.circle" : "xmark.circle")
        let statusColor: Color = showGreen ? Color(NSColor.systemGreen) : (actuallyInstalled ? Color(NSColor.systemOrange) : UI.muted.opacity(0.45))
        let statusLabel = !actuallyInstalled ? "Not installed" : (showGreen ? "Up to date" : "Needs update")

        return HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(AppFont.bodySemi(14))
                .foregroundStyle(UI.text)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("Installed: \(installed)")
                    .font(AppFont.body(13))
                    .foregroundStyle(actuallyInstalled ? UI.text : Color(NSColor.systemRed))
                Text("Target: \(latest)")
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(statusLabel)
                    .font(AppFont.body(11))
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(UI.lineSoft, lineWidth: 1))
    }

    func statusRow(_ name: String, _ state: String) -> some View {
        let normalized = state.uppercased()
        let isInstalled = normalized == "OK"
        let isSkipped = normalized == "SKIP"
        let isFail = normalized == "FAIL"

        // Bug 2+8: Determine if component is actually present based on vm state
        let componentActuallyInstalled: Bool = {
            switch name {
            case "Homebrew": return vm.statusHomebrew == "OK" || vm.brewVersion != "Not installed" && vm.brewVersion != "Checking..."
            case "LM Studio": return vm.lmStudioVersion != "Not installed" && vm.lmStudioVersion != "Checking..."
            case "Node": return vm.nodeVersion != "Not installed" && vm.nodeVersion != "Checking..."
            case "OpenClaw": return vm.hasExistingOpenClawSetup || vm.openclawInstalledVersion != "Not installed"
            default: return isInstalled
            }
        }()

        let label: String = {
            switch normalized {
            case "OK": return "Installed"
            case "SKIP":
                return componentActuallyInstalled ? "Already installed" : "Skipped"
            case "PENDING": return "Pending"
            case "FAIL": return "Failed"
            default: return state.capitalized
            }
        }()

        let isGood = isInstalled || (isSkipped && componentActuallyInstalled)

        return HStack {
            Text(name).foregroundStyle(UI.text)
            Spacer()
            Label(label, systemImage: isGood ? "checkmark.circle.fill" : (isFail ? "xmark.circle.fill" : "circle.fill"))
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isGood ? Color(NSColor.systemGreen).opacity(0.12) : (isFail ? Color(NSColor.systemRed).opacity(0.12) : Color(NSColor.secondaryLabelColor).opacity(0.12)))
                .clipShape(Capsule())
                .foregroundStyle(isGood ? Color(NSColor.systemGreen) : (isFail ? Color(NSColor.systemRed) : UI.muted))
        }
    }

    func machineMetricRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
                .font(AppFont.bodySemi(13))
                .foregroundStyle(UI.text)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(UI.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
    }

    func gaugeColor(_ ratio: Double) -> Color {
        if ratio >= 0.85 { return Color(NSColor.systemRed) }
        if ratio >= 0.65 { return Color(NSColor.systemOrange) }
        return Color(NSColor.systemGreen)
    }

    func machineGaugeRow(_ name: String, _ value: String, ratio: Double) -> some View {
        let clamped = min(max(ratio, 0), 1)
        let color = gaugeColor(clamped)

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(AppFont.bodySemi(13))
                    .foregroundStyle(UI.text)
                Spacer()
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(UI.muted)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Color.black.opacity(0.08))
                    RoundedRectangle(cornerRadius: 999)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * clamped))
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
    }

    var controlCenter: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("CONTROL CENTER")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Spacer()
                    Button("Refresh") { vm.refreshControlCenter() }
                        .buttonStyle(CTAButton(primary: false))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("STATUS")
                        .font(AppFont.heading(11))
                        .kerning(0.6)
                        .foregroundStyle(UI.accent)

                    HStack(spacing: 16) {
                        statusIndicator("Gateway", vm.gatewayIsRunning ? "Online" : "Offline", vm.gatewayIsRunning ? .green : .red)
                        statusIndicator("Model", vm.currentModel, .blue)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))

                VStack(alignment: .leading, spacing: 12) {
                    Text("MACHINE USAGE")
                        .font(AppFont.heading(11))
                        .kerning(0.6)
                        .foregroundStyle(UI.accent)

                    VStack(spacing: 8) {
                        machineGaugeRow("CPU", String(format: "%.1f %%", vm.machineCPUPercent), ratio: vm.machineCPUPercent / 100.0)
                        machineGaugeRow(
                            "Memory",
                            String(format: "%.1f / %.1f GB", vm.machineMemoryUsedGB, max(vm.machineMemoryTotalGB, 0.1)),
                            ratio: vm.machineMemoryTotalGB > 0 ? vm.machineMemoryUsedGB / vm.machineMemoryTotalGB : 0
                        )
                        machineMetricRow("Memory available", String(format: "%.1f GB", vm.machineMemoryAvailableGB))
                        machineGaugeRow(
                            "Swap",
                            vm.machineSwapTotalGB > 0 ? String(format: "%.2f / %.2f GB", vm.machineSwapUsedGB, vm.machineSwapTotalGB) : "0 GB",
                            ratio: vm.machineSwapTotalGB > 0 ? vm.machineSwapUsedGB / vm.machineSwapTotalGB : 0
                        )
                        machineMetricRow("LM Studio", "\(vm.machineLMStudioMB) MB")
                        machineMetricRow("OpenClaw", "\(vm.machineOpenclawMB) MB")
                        machineMetricRow("Node", "\(vm.machineNodeMB) MB")
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("HEAVY PROCESSES")
                            .font(AppFont.heading(11))
                            .kerning(0.6)
                            .foregroundStyle(UI.accent)
                        Spacer()
                        Button("Emergency cleanup") { vm.emergencyCleanupAction() }
                            .buttonStyle(CTAButton(primary: false))
                    }

                    VStack(spacing: 8) {
                        ForEach(vm.topProcesses.prefix(8)) { proc in
                            HStack(spacing: 8) {
                                Text("\(proc.pid)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(UI.muted)
                                    .frame(width: 58, alignment: .leading)
                                Text(String(format: "%.1f%%", proc.cpuPercent))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(UI.muted)
                                    .frame(width: 56, alignment: .leading)
                                Text("\(proc.memoryMB) MB")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(UI.muted)
                                    .frame(width: 82, alignment: .leading)
                                Text(proc.command)
                                    .font(AppFont.body(11))
                                    .foregroundStyle(UI.text)
                                    .lineLimit(1)
                                Spacer()
                                Button("Kill") { vm.killHeavyProcess(proc.pid) }
                                    .buttonStyle(CTAButton(primary: false))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))

                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK ACTIONS")
                        .font(AppFont.heading(11))
                        .kerning(0.6)
                        .foregroundStyle(UI.accent)

                    HStack(spacing: 12) {
                        Button("Run Doctor") { vm.runDoctor() }
                            .buttonStyle(CTAButton(primary: true))
                        Button("Restart Gateway") { vm.restartGatewayAction() }
                            .buttonStyle(CTAButton(primary: false))
                        Button("Open Dashboard") { vm.openControlDashboard() }
                            .buttonStyle(CTAButton(primary: false))
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))

                VStack(alignment: .leading, spacing: 12) {
                    Text("CHANGE MODEL")
                        .font(AppFont.heading(11))
                        .kerning(0.6)
                        .foregroundStyle(UI.accent)

                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Model", selection: $vm.selectedControlModel) {
                            if vm.openRouterModelsLive.isEmpty {
                                Text("No OpenRouter catalog loaded").tag(vm.selectedControlModel)
                            } else {
                                ForEach(vm.openRouterModelsLive, id: \.self) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 280)

                        HStack(spacing: 8) {
                            Button("Refresh catalog") { vm.refreshOpenRouterModels() }
                                .buttonStyle(CTAButton(primary: false))
                            Text("\(vm.openRouterModelsLive.count) models")
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.muted)
                        }

                        Button("Apply & Restart Gateway") { vm.applyModelChange() }
                            .buttonStyle(CTAButton(primary: true))
                        
                        Text("Current: \(vm.currentModel)")
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))

                VStack(alignment: .leading, spacing: 8) {
                    Text("OUTPUT")
                        .font(AppFont.heading(11))
                        .kerning(0.6)
                        .foregroundStyle(UI.accent)

                    ScrollView {
                        Text(vm.controlCenterLogs.isEmpty ? "No actions yet. Click a button above." : vm.controlCenterLogs)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(UI.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .scrollIndicators(.hidden)
                    .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
                    .frame(height: 200)
                }

                HStack {
                    Spacer()
                    Button("BACK") { vm.screen = .home }
                        .buttonStyle(CTAButton(primary: false))
                }
            }
            .padding(22)
            .frame(maxWidth: 900, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
            .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .onAppear { vm.refreshControlCenter() }
    }

    func statusIndicator(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.muted)
                Text(value)
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
    }

    // MARK: - Nouveau Command Center (Partie 3 - Advanced)
    
    var commandCenter: some View {
        AdvancedCommandCenterView()
    }
}

@main
struct LocalClawInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1440, height: 920)
    }
}
