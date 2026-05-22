import SwiftUI
import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class InstallerViewModel: ObservableObject {
    enum Screen { case license, onboarding, home, options, install, ready, updates, controlCenter, commandCenter, uninstallCenter, channelSetup, agents, cronJobs, kanban, healthCenter, usageCenter, chat, models, skills, developer }
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

    enum AgentModelMode: String, CaseIterable, Identifiable {
        case local = "Local"
        case cloud = "Cloud"
        case oauth = "OAuth"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .local: return "desktopcomputer"
            case .cloud: return "cloud.fill"
            case .oauth: return "person.badge.key"
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

    enum UsageWindow: String, CaseIterable, Identifiable {
        case today = "Today"
        case threeDays = "3 days"
        case sevenDays = "7 days"
        case thirtyDays = "30 days"

        var id: String { rawValue }

        var dayCount: Int {
            switch self {
            case .today: return 1
            case .threeDays: return 3
            case .sevenDays: return 7
            case .thirtyDays: return 30
            }
        }
    }

    struct UsageSummary: Equatable {
        let inputTokens: Int
        let outputTokens: Int
        let totalTokens: Int
        let requestCount: Int
    }

    struct OAuthUsageWindow: Identifiable, Equatable {
        let id: String
        let label: String
        let usedPercent: Int
        let resetAt: Date?

        var resetLabel: String? {
            guard let resetAt else { return nil }
            let seconds = Int(resetAt.timeIntervalSince(Date()))
            if seconds <= 0 { return "resets now" }
            let hours = seconds / 3600
            let minutes = max(1, (seconds % 3600) / 60)
            if hours > 0 { return "resets \(hours)h \(minutes)m" }
            return "resets \(minutes)m"
        }

        var remainingLabel: String {
            "\(max(0, 100 - usedPercent))% left"
        }

        var detailLabel: String {
            [label, resetLabel, remainingLabel].compactMap { $0 }.joined(separator: " · ")
        }
    }

    struct OAuthUsageSnapshot: Equatable {
        let provider: String
        let displayName: String
        let plan: String?
        let windows: [OAuthUsageWindow]
        let error: String?
        let updatedAt: Date?

        var primaryUsedPercent: Int? {
            windows.first?.usedPercent
        }

        var primaryRemainingPercent: Int? {
            primaryUsedPercent.map { max(0, 100 - $0) }
        }

        var buttonLabel: String {
            if let primaryRemainingPercent { return "Usage \(primaryRemainingPercent)% left" }
            if error?.isEmpty == false { return "Usage unavailable" }
            return "Usage"
        }

        var tooltipLabel: String {
            var parts: [String] = [displayName]
            if let plan, !plan.isEmpty { parts.append(plan) }
            parts.append(contentsOf: windows.map(\.detailLabel))
            if let primaryUsedPercent { parts.append("\(primaryUsedPercent)% used") }
            if let error, !error.isEmpty { parts.append(error) }
            return parts.joined(separator: " · ")
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

    struct ChannelCredentialField: Identifiable, Sendable {
        let id: String
        let label: String
        let placeholder: String
        let cliOption: String
        let secure: Bool
        let required: Bool
        let help: String
    }

    struct ChannelCredentialProfile: Sendable {
        let channelID: String
        let title: String
        let subtitle: String
        let primaryButton: String
        let fields: [ChannelCredentialField]
        let needsLoginAfterAdd: Bool

        var hasFields: Bool { !fields.isEmpty }
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
        let goal: String?
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

        var runtimeLabel: String {
            guard let model, !model.isEmpty else { return "Runtime unknown" }
            if model.hasPrefix("lmstudio/") { return "Local LLM" }
            if model.hasPrefix("openrouter/") { return "Cloud LLM" }
            if model.hasPrefix("openai/") || model.hasPrefix("google-gemini-cli/") { return "OAuth LLM" }
            return "Custom runtime"
        }

        var runtimeTint: Color {
            switch runtimeLabel {
            case "Local LLM": return Color(NSColor.systemGreen)
            case "OAuth LLM": return Color(NSColor.systemPurple)
            case "Cloud LLM": return UI.accent
            default: return UI.muted
            }
        }

        var detailSummary: String {
            var parts: [String] = []
            if let goal, !goal.isEmpty { parts.append("Goal: \(goal)") }
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
        let agentID: String?
        let sessionTarget: String?
        let nextRun: String?
        let lastRun: String?
        let deliveryLabel: String?

        var statusLabel: String { enabled ? "Active" : "Disabled" }
        var statusTint: Color { enabled ? Color(NSColor.systemGreen) : UI.muted }

        var detailSummary: String {
            var parts: [String] = [scheduleLabel, payloadLabel]
            if let agentID, !agentID.isEmpty { parts.append("Agent: \(agentID)") }
            if let sessionTarget, !sessionTarget.isEmpty { parts.append("Session: \(sessionTarget)") }
            if let deliveryLabel, !deliveryLabel.isEmpty { parts.append("Delivery: \(deliveryLabel)") }
            if let nextRun, !nextRun.isEmpty { parts.append("Next: \(nextRun)") }
            if let lastRun, !lastRun.isEmpty { parts.append("Last: \(lastRun)") }
            return parts.joined(separator: " · ")
        }
    }

    struct CronDeliveryDestination: Identifiable, Equatable {
        let id: String
        let channel: String
        let destination: String
        let label: String
        let detail: String?

        var displayLabel: String {
            if let detail, !detail.isEmpty {
                return "\(label) · \(detail)"
            }
            return label
        }
    }

    struct KanbanCard: Identifiable, Codable, Equatable {
        let id: String
        var title: String
        var detail: String
        var priority: String
        var agentID: String
        var reviewSchedule: String
        var scheduleTimeZoneID: String
        var scheduleKind: String
        var cronEnabled: Bool
        var deliveryMode: String
        var deliveryChannel: String
        var deliveryAccount: String
        var deliveryTo: String
        var cronJobID: String
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String,
            title: String,
            detail: String,
            priority: String,
            agentID: String,
            reviewSchedule: String,
            scheduleTimeZoneID: String = TimeZone.current.identifier,
            scheduleKind: String = "every",
            cronEnabled: Bool = true,
            deliveryMode: String = "last",
            deliveryChannel: String,
            deliveryAccount: String = "",
            deliveryTo: String = "",
            cronJobID: String = "",
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.title = title
            self.detail = detail
            self.priority = priority
            self.agentID = agentID
            self.reviewSchedule = reviewSchedule
            self.scheduleTimeZoneID = scheduleTimeZoneID
            self.scheduleKind = scheduleKind
            self.cronEnabled = cronEnabled
            self.deliveryMode = deliveryMode
            self.deliveryChannel = deliveryChannel
            self.deliveryAccount = deliveryAccount
            self.deliveryTo = deliveryTo
            self.cronJobID = cronJobID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        static func fresh(
            title: String,
            detail: String,
            priority: String,
            agentID: String,
            reviewSchedule: String,
            scheduleTimeZoneID: String = TimeZone.current.identifier,
            scheduleKind: String = "every",
            cronEnabled: Bool = true,
            deliveryMode: String = "last",
            deliveryChannel: String,
            deliveryAccount: String = "",
            deliveryTo: String = "",
            cronJobID: String = ""
        ) -> KanbanCard {
            KanbanCard(
                id: "kanban-card-\(UUID().uuidString)",
                title: title,
                detail: detail,
                priority: priority,
                agentID: agentID,
                reviewSchedule: reviewSchedule,
                scheduleTimeZoneID: scheduleTimeZoneID,
                scheduleKind: scheduleKind,
                cronEnabled: cronEnabled,
                deliveryMode: deliveryMode,
                deliveryChannel: deliveryChannel,
                deliveryAccount: deliveryAccount,
                deliveryTo: deliveryTo,
                cronJobID: cronJobID,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, detail, priority, agentID, reviewSchedule, scheduleTimeZoneID, scheduleKind, cronEnabled, deliveryMode, deliveryChannel, deliveryAccount, deliveryTo, cronJobID, createdAt, updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
            priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? "Normal"
            agentID = try container.decodeIfPresent(String.self, forKey: .agentID) ?? "main"
            reviewSchedule = try container.decodeIfPresent(String.self, forKey: .reviewSchedule) ?? "1d"
            scheduleTimeZoneID = try container.decodeIfPresent(String.self, forKey: .scheduleTimeZoneID) ?? TimeZone.current.identifier
            scheduleKind = try container.decodeIfPresent(String.self, forKey: .scheduleKind) ?? "every"
            cronEnabled = try container.decodeIfPresent(Bool.self, forKey: .cronEnabled) ?? true
            let decodedDeliveryChannel = try container.decodeIfPresent(String.self, forKey: .deliveryChannel) ?? "last"
            deliveryChannel = decodedDeliveryChannel
            deliveryMode = try container.decodeIfPresent(String.self, forKey: .deliveryMode) ?? {
                if decodedDeliveryChannel == "none" { return "none" }
                if decodedDeliveryChannel == "last" { return "last" }
                return "channel"
            }()
            deliveryAccount = try container.decodeIfPresent(String.self, forKey: .deliveryAccount) ?? ""
            deliveryTo = try container.decodeIfPresent(String.self, forKey: .deliveryTo) ?? ""
            cronJobID = try container.decodeIfPresent(String.self, forKey: .cronJobID) ?? ""
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        }
    }

    struct KanbanColumn: Identifiable, Codable, Equatable {
        let id: String
        var title: String
        var icon: String
        var colorName: String
        var cards: [KanbanCard]

        static let defaults: [KanbanColumn] = [
            KanbanColumn(id: "backlog", title: "Backlog", icon: "tray.full", colorName: "gray", cards: []),
            KanbanColumn(id: "ready", title: "Ready", icon: "checklist", colorName: "blue", cards: []),
            KanbanColumn(id: "doing", title: "In Progress", icon: "bolt.fill", colorName: "red", cards: []),
            KanbanColumn(id: "review", title: "Review", icon: "eye.fill", colorName: "purple", cards: []),
            KanbanColumn(id: "done", title: "Done", icon: "checkmark.seal.fill", colorName: "green", cards: [])
        ]
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

    struct OpenRouterModel: Identifiable, Hashable, Sendable {
        let id: String
        let displayName: String
    }

    struct OAuthProviderOption: Identifiable, Hashable, Sendable {
        let id: String
        let displayName: String
        let detail: String
        let modelIdentifier: String
        let authProvider: String
        let available: Bool
    }

    static let oauthProviderOptions: [OAuthProviderOption] = [
        OAuthProviderOption(
            id: "openai-codex",
            displayName: "ChatGPT / Codex",
            detail: "Connect with your OpenAI account. No API key paste.",
            modelIdentifier: "openai-codex/gpt-5.4",
            authProvider: "openai-codex",
            available: true
        )
    ]

    nonisolated static let oauthFallbackModels: [OpenRouterModel] = [
        OpenRouterModel(id: "openai-codex/gpt-5.5", displayName: "GPT 5.5"),
        OpenRouterModel(id: "openai-codex/gpt-5.4", displayName: "GPT 5.4"),
        OpenRouterModel(id: "openai-codex/gpt-5.4-mini", displayName: "GPT 5.4 Mini")
    ]

    static let openRouterModels: [OpenRouterModel] = [
        // Recommended / Popular
        OpenRouterModel(id: "openrouter/openai/gpt-5.4-mini", displayName: "⭐ GPT-5.4 Mini"),
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
    @Published var selectedOAuthProvider: String = "openai-codex"
    @Published var selectedOpenRouterModel: String = "openrouter/openai/gpt-5.4-mini"
    @Published var openRouterModelsLive: [OpenRouterModel] = []
    @Published var oauthModelsLive: [OpenRouterModel] = []
    @Published var oauthUsageSnapshot: OAuthUsageSnapshot? = nil
    @Published var oauthUsageIsLoading: Bool = false
    @Published var showOAuthSetupAssistant: Bool = false
    @Published var oauthSetupStatus: String = "Not connected"
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
    @Published var activeLocalLMStudioContext: Int? = nil
    @Published var localLMStudioSetupStatus = ""
    @Published var localLMStudioSetupLog = ""
    @Published var localLMStudioSetupInProgress = false
    @Published var localLMStudioRepairInProgress = false

    // Uninstall Center
    @Published var isUninstalling = false
    @Published var uninstallLogs: String = ""
    @Published var uninstallLMStudioSelected = false
    @Published var uninstallModelsSelected = false
    @Published var uninstallOpenClawSelected = false
    @Published var uninstallNodeSelected = false
    @Published var uninstallHomebrewSelected = false
    @Published var uninstallConfigsSelected = false

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
    @Published var showTelegramSetupPanel = false
    @Published var telegramSetupToken = ""
    @Published var telegramSetupPairingCode = ""
    @Published var telegramSetupStatus = ""
    @Published var telegramSetupIsRunning = false
    @Published var showChannelCredentialPanel = false
    @Published var channelCredentialID = ""
    @Published var channelCredentialLabel = ""
    @Published var channelCredentialIcon = "bubble.left.and.bubble.right"
    @Published var channelCredentialAccount = "default"
    @Published var channelCredentialDisplayName = ""
    @Published var channelCredentialValues: [String: String] = [:]
    @Published var channelCredentialStatus = ""
    @Published var channelCredentialIsRunning = false
    @Published var agents: [AgentInfo] = []
    @Published var agentsStatus: String = "Not loaded"
    @Published var agentsIsLoading = false
    @Published var agentLogs: String = ""
    @Published var showAgentSetupPanel = false
    @Published var showAgentDeleteConfirmation = false
    @Published var agentDeleteCandidateID = ""
    @Published var agentDeleteCandidateName = ""
    @Published var agentDeleteIsRunning = false
    @Published var agentSetupEditingID = ""
    @Published var agentSetupID = ""
    @Published var agentSetupName = ""
    @Published var agentSetupEmoji = ""
    @Published var agentSetupGoal = ""
    @Published var agentSetupWorkspace = ""
    @Published var agentSetupModel = ""
    @Published var agentSetupMode: AgentModelMode = .cloud {
        didSet { reconcileAgentSetupModelForMode() }
    }
    @Published var agentSetupStatus = ""
    @Published var agentSetupIsRunning = false
    @Published var cronJobs: [CronJobInfo] = []
    @Published var cronJobsStatus: String = "Not loaded"
    @Published var cronJobsIsLoading = false
    @Published var cronJobLogs: String = ""
    @Published var showCronJobCreator = false
    @Published var cronCreateName = ""
    @Published var cronCreateAgentID = "main"
    @Published var cronCreateScheduleKind = "every" {
        didSet {
            if cronCreateScheduleKind == "at" && oldValue != "at" {
                cronCreateAtDate = Self.defaultAtDate()
                cronCreateScheduleValue = Self.cronAtDateString(cronCreateAtDate, timeZoneID: cronCreateTimeZoneID)
            }
        }
    }
    @Published var cronCreateScheduleValue = "30m"
    @Published var cronCreateAtDate = InstallerViewModel.defaultAtDate() {
        didSet {
            if cronCreateScheduleKind == "at" {
                cronCreateScheduleValue = Self.cronAtDateString(cronCreateAtDate, timeZoneID: cronCreateTimeZoneID)
            }
        }
    }
    @Published var cronCreateTimeZoneID = TimeZone.current.identifier {
        didSet {
            if cronCreateScheduleKind == "at" {
                cronCreateScheduleValue = Self.cronAtDateString(cronCreateAtDate, timeZoneID: cronCreateTimeZoneID)
            }
        }
    }
    @Published var cronCreateMessage = ""
    @Published var cronCreateDeliveryMode = "last"
    @Published var cronCreateDeliveryChannel = "telegram"
    @Published var cronCreateDeliveryAccount = ""
    @Published var cronCreateDeliveryTo = ""
    @Published var cronDeliveryDestinations: [CronDeliveryDestination] = []
    @Published var cronCreateIsRunning = false
    @Published var cronCreateError = ""
    @Published var cronDeleteCandidate: CronJobInfo? = nil
    @Published var cronDeleteConfirmText = ""
    @Published var cronDeleteIsRunning = false
    @Published var cronDeleteError = ""
    @Published var kanbanColumns: [KanbanColumn] = KanbanColumn.defaults {
        didSet { persistKanbanBoard() }
    }
    @Published var kanbanNewTitle = ""
    @Published var kanbanNewDetail = ""
    @Published var kanbanNewPriority = "Normal"
    @Published var kanbanNewAgentID = "main"
    @Published var kanbanNewSchedule = "1d"
    @Published var kanbanNewDeliveryChannel = "last"
    @Published var showKanbanTaskEditor = false
    @Published var kanbanEditingCardID = ""
    @Published var kanbanEditingColumnID = "backlog"
    @Published var kanbanEditorTitle = ""
    @Published var kanbanEditorDetail = ""
    @Published var kanbanEditorPriority = "Normal"
    @Published var kanbanEditorAgentID = "main"
    @Published var kanbanEditorCronEnabled = true
    @Published var kanbanEditorScheduleKind = "every" {
        didSet {
            if kanbanEditorScheduleKind == "at" && oldValue != "at" {
                kanbanEditorAtDate = Self.defaultAtDate()
                kanbanEditorScheduleValue = Self.cronAtDateString(kanbanEditorAtDate, timeZoneID: kanbanEditorTimeZoneID)
            }
        }
    }
    @Published var kanbanEditorScheduleValue = "1d"
    @Published var kanbanEditorAtDate = InstallerViewModel.defaultAtDate() {
        didSet {
            if kanbanEditorScheduleKind == "at" {
                kanbanEditorScheduleValue = Self.cronAtDateString(kanbanEditorAtDate, timeZoneID: kanbanEditorTimeZoneID)
            }
        }
    }
    @Published var kanbanEditorTimeZoneID = TimeZone.current.identifier {
        didSet {
            if kanbanEditorScheduleKind == "at" {
                kanbanEditorScheduleValue = Self.cronAtDateString(kanbanEditorAtDate, timeZoneID: kanbanEditorTimeZoneID)
            }
        }
    }
    @Published var kanbanEditorDeliveryMode = "last"
    @Published var kanbanEditorDeliveryChannel = "telegram"
    @Published var kanbanEditorDeliveryAccount = ""
    @Published var kanbanEditorDeliveryTo = ""
    @Published var kanbanEditorError = ""
    @Published var kanbanRunningCardIDs: Set<String> = []
    @Published var kanbanSchedulingCardIDs: Set<String> = []
    var kanbanAutomationSyncEnabled = true
    @Published var kanbanStatus = "Ready"
    @Published var healthLogs: String = ""
    @Published var healthStatus: String = "Unknown"
    @Published var usageLogs: String = ""
    @Published var estimatedMonthlyTokensM: Double = 2.0
    @Published var estimatedMonthlyCostUSD: Double = 0
    @Published var costAdvice: String = ""
    @Published var tokenMonitoringEnabled: Bool = true
    @Published var selectedHomeUsageWindow: UsageWindow = .today {
        didSet { UserDefaults.standard.set(selectedHomeUsageWindow.rawValue, forKey: Self.homeUsageWindowDefaultsKey) }
    }
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
    private static let homeUsageWindowDefaultsKey = "localclaw.home.usageWindow.v1"
    private static let kanbanDefaultsKey = "localclaw.kanban.board.v1"
    nonisolated static let simpleDeveloperEditTimeoutSeconds = 60

    init() {
        Self.ensureTelegramDefaultAccountToken()
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
        if let rawUsageWindow = UserDefaults.standard.string(forKey: Self.homeUsageWindowDefaultsKey),
           let usageWindow = UsageWindow(rawValue: rawUsageWindow) {
            selectedHomeUsageWindow = usageWindow
        }
        restoreChatSessions()
        restoreChatSavedNotes()
        restoreModelUsageRecords()
        restoreKanbanBoard()
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
        ChannelCatalogEntry(id: "line", label: "LINE", detailLabel: "LINE channel token", systemImage: "bubble.left.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "zalo", label: "Zalo", detailLabel: "Zalo app credentials", systemImage: "bubble.right.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "zalouser", label: "Zalo User", detailLabel: "Zalo user credentials", systemImage: "person.text.rectangle.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "nextcloud-talk", label: "Nextcloud Talk", detailLabel: "Nextcloud Talk bot config", systemImage: "cloud.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "twitch", label: "Twitch", detailLabel: "Twitch chat token", systemImage: "play.tv.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "nostr", label: "Nostr", detailLabel: "Nostr relay credentials", systemImage: "network", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "irc", label: "IRC", detailLabel: "Server, nick, and channel config", systemImage: "terminal.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "qqbot", label: "QQ Bot", detailLabel: "QQ bot credentials", systemImage: "q.circle.fill", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "clickclack", label: "ClickClack", detailLabel: "ClickClack token or endpoint", systemImage: "cursorarrow.click.2", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "synology-chat", label: "Synology Chat", detailLabel: "Synology Chat token or webhook", systemImage: "server.rack", origin: "OpenClaw channel"),
        ChannelCatalogEntry(id: "tlon", label: "Tlon", detailLabel: "Tlon token or endpoint", systemImage: "network.badge.shield.half.filled", origin: "OpenClaw channel")
    ]

    nonisolated static let openClawAddSupportedChannelIDs: Set<String> = [
        "telegram", "whatsapp", "discord", "irc", "googlechat", "slack", "signal", "imessage",
        "feishu", "nostr", "msteams", "mattermost", "nextcloud-talk", "matrix", "line", "zalo",
        "clickclack", "zalouser", "synology-chat", "tlon", "qqbot", "twitch"
    ]

    private static func channelSortRank(_ id: String) -> Int {
        defaultChannelCatalog.firstIndex { $0.id == id } ?? (defaultChannelCatalog.count + 1)
    }

    nonisolated private static func humanChannelLabel(_ id: String) -> String {
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

    nonisolated static func channelCredentialProfile(for channelID: String, label: String? = nil) -> ChannelCredentialProfile {
        let title = label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? label! : humanChannelLabel(channelID)

        func field(_ id: String, _ label: String, _ placeholder: String, _ cliOption: String, secure: Bool = true, required: Bool = true, help: String = "") -> ChannelCredentialField {
            ChannelCredentialField(id: id, label: label, placeholder: placeholder, cliOption: cliOption, secure: secure, required: required, help: help)
        }

        switch channelID {
        case "discord":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Discord setup",
                subtitle: "Paste the bot token from the Discord Developer Portal. The bot must be invited to the server with message permissions.",
                primaryButton: "Save Discord",
                fields: [
                    field("botToken", "Bot token", "Discord bot token", "--bot-token", help: "Developer Portal > Bot > Token")
                ],
                needsLoginAfterAdd: false
            )
        case "slack":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Slack setup",
                subtitle: "Use the Slack bot token. Add an app-level token only if your Slack app uses Socket Mode.",
                primaryButton: "Save Slack",
                fields: [
                    field("botToken", "Bot token", "xoxb-...", "--bot-token", help: "OAuth & Permissions > Bot User OAuth Token"),
                    field("appToken", "App token", "xapp-... (optional)", "--app-token", required: false, help: "Basic Information > App-Level Tokens")
                ],
                needsLoginAfterAdd: false
            )
        case "mattermost":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Mattermost setup",
                subtitle: "Use a Mattermost bot token and the base URL of your Mattermost server.",
                primaryButton: "Save Mattermost",
                fields: [
                    field("httpUrl", "Server URL", "https://chat.example.com", "--http-url", secure: false, help: "Mattermost base URL"),
                    field("botToken", "Bot token", "Mattermost bot token", "--bot-token", help: "System Console > Integrations > Bot Accounts")
                ],
                needsLoginAfterAdd: false
            )
        case "matrix":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Matrix setup",
                subtitle: "Use the homeserver URL and an access token for the Matrix account.",
                primaryButton: "Save Matrix",
                fields: [
                    field("baseUrl", "Homeserver URL", "https://matrix.example.com", "--base-url", secure: false),
                    field("token", "Access token", "Matrix access token", "--token")
                ],
                needsLoginAfterAdd: false
            )
        case "signal":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Signal setup",
                subtitle: "Connect LocalClaw to a Signal bridge or HTTP daemon.",
                primaryButton: "Save Signal",
                fields: [
                    field("signalNumber", "Signal number", "+15551234567", "--signal-number", secure: false),
                    field("httpUrl", "Bridge URL", "http://127.0.0.1:8080", "--http-url", secure: false)
                ],
                needsLoginAfterAdd: false
            )
        case "line":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "LINE setup",
                subtitle: "Paste the LINE channel access token and optional channel secret.",
                primaryButton: "Save LINE",
                fields: [
                    field("token", "Channel access token", "LINE channel access token", "--token"),
                    field("secret", "Channel secret", "LINE channel secret (optional)", "--secret", required: false)
                ],
                needsLoginAfterAdd: false
            )
        case "zalo", "zalouser":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "\(title) setup",
                subtitle: "Paste the Zalo token and optional app secret.",
                primaryButton: "Save \(title)",
                fields: [
                    field("token", "Access token", "\(title) access token", "--token"),
                    field("secret", "App secret", "\(title) app secret (optional)", "--secret", required: false)
                ],
                needsLoginAfterAdd: false
            )
        case "googlechat":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Google Chat setup",
                subtitle: "Paste the Google Chat credential payload or token and optional callback URL.",
                primaryButton: "Save Google Chat",
                fields: [
                    field("token", "Credential token/payload", "Google Chat token or credential payload", "--token"),
                    field("url", "Callback URL", "https://... (optional)", "--url", secure: false, required: false)
                ],
                needsLoginAfterAdd: false
            )
        case "msteams":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Microsoft Teams setup",
                subtitle: "Use your Teams bot/app credentials.",
                primaryButton: "Save Teams",
                fields: [
                    field("appToken", "App token", "Teams app token", "--app-token"),
                    field("secret", "Client secret", "Teams client secret", "--secret"),
                    field("url", "Callback URL", "https://... (optional)", "--url", secure: false, required: false)
                ],
                needsLoginAfterAdd: false
            )
        case "feishu", "wecom", "qqbot":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "\(title) setup",
                subtitle: "Use the app token and app secret from the platform developer console.",
                primaryButton: "Save \(title)",
                fields: [
                    field("appToken", "App token", "\(title) app token", "--app-token"),
                    field("secret", "App secret", "\(title) app secret", "--secret")
                ],
                needsLoginAfterAdd: false
            )
        case "nextcloud-talk":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Nextcloud Talk setup",
                subtitle: "Use your Nextcloud server URL and app token.",
                primaryButton: "Save Nextcloud Talk",
                fields: [
                    field("baseUrl", "Server URL", "https://cloud.example.com", "--base-url", secure: false),
                    field("token", "App token", "Nextcloud app token", "--token")
                ],
                needsLoginAfterAdd: false
            )
        case "twitch":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Twitch setup",
                subtitle: "Use a Twitch chat OAuth token. Set account name to the bot username.",
                primaryButton: "Save Twitch",
                fields: [
                    field("token", "OAuth token", "oauth:...", "--token")
                ],
                needsLoginAfterAdd: false
            )
        case "nostr":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "Nostr setup",
                subtitle: "Use a Nostr private key and optional relay URL.",
                primaryButton: "Save Nostr",
                fields: [
                    field("secret", "Private key", "nsec...", "--secret"),
                    field("url", "Relay URL", "wss://relay.example.com", "--url", secure: false, required: false)
                ],
                needsLoginAfterAdd: false
            )
        case "irc":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "IRC setup",
                subtitle: "Enter the IRC server URL. Use display name for the bot nick.",
                primaryButton: "Save IRC",
                fields: [
                    field("url", "Server URL", "irc://irc.libera.chat:6697/#channel", "--url", secure: false),
                    field("password", "Password", "server password (optional)", "--password", required: false)
                ],
                needsLoginAfterAdd: false
            )
        case "imessage":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "iMessage setup",
                subtitle: "Use macOS Messages. The default service is auto; add a DB path only for custom setups.",
                primaryButton: "Save iMessage",
                fields: [
                    field("service", "Service", "auto, imessage, or sms", "--service", secure: false, required: false),
                    field("dbPath", "Messages DB path", "~/Library/Messages/chat.db (optional)", "--db-path", secure: false, required: false)
                ],
                needsLoginAfterAdd: false
            )
        case "whatsapp":
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "WhatsApp setup",
                subtitle: "No token needed. LocalClaw prepares the channel, then opens the WhatsApp QR login flow.",
                primaryButton: "Start WhatsApp login",
                fields: [],
                needsLoginAfterAdd: true
            )
        default:
            return ChannelCredentialProfile(
                channelID: channelID,
                title: "\(title) setup",
                subtitle: "Enter the credentials required by this OpenClaw channel.",
                primaryButton: "Save \(title)",
                fields: [
                    field("token", "Token", "\(title) token", "--token"),
                    field("url", "URL", "https://... (optional)", "--url", secure: false, required: false)
                ],
                needsLoginAfterAdd: false
            )
        }
    }

    nonisolated static func configuredChannelSnapshots(from root: [String: Any]) -> [String: ChannelConfigSnapshot] {
        guard let channels = root["channels"] as? [String: Any] else { return [:] }

        return channels.reduce(into: [String: ChannelConfigSnapshot]()) { result, pair in
            guard let channelConfig = pair.value as? [String: Any] else { return }

            let enabled = channelConfig["enabled"] as? Bool ?? false
            let hasToken = !(channelConfig["token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasBotToken = !(channelConfig["botToken"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasTokenFile = !(channelConfig["tokenFile"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let accountsDict = channelConfig["accounts"] as? [String: Any] ?? [:]
            let configuredAccounts = accountsDict.compactMap { accountPair -> String? in
                guard let accountConfig = accountPair.value as? [String: Any] else { return nil }
                let accountEnabled = accountConfig["enabled"] as? Bool ?? true
                let accountHasToken = !(accountConfig["token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let accountHasBotToken = !(accountConfig["botToken"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let accountHasTokenFile = !(accountConfig["tokenFile"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let accountHasSession = !(accountConfig["session"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let accountHasAuthPath = !(accountConfig["authPath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return (accountEnabled || accountHasToken || accountHasBotToken || accountHasTokenFile || accountHasSession || accountHasAuthPath) ? accountPair.key : nil
            }
            .sorted()

            let configured = enabled || hasToken || hasBotToken || hasTokenFile || !configuredAccounts.isEmpty
            guard configured else { return }

            let accounts = configuredAccounts.isEmpty ? ["default"] : configuredAccounts
            result[pair.key] = ChannelConfigSnapshot(
                configured: true,
                accounts: accounts,
                tokenSource: hasTokenFile ? "tokenFile" : ((hasToken || hasBotToken) ? "config" : nil)
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

    nonisolated static func persistentTelegramTokenFilePath() -> String {
        NSHomeDirectory() + "/.openclaw/secrets/telegram-default-token"
    }

    nonisolated static func ensureTelegramDefaultAccountToken(configPath: String = NSHomeDirectory() + "/.openclaw/openclaw.json") {
        let configURL = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: configURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var channels = root["channels"] as? [String: Any],
              var telegram = channels["telegram"] as? [String: Any] else {
            return
        }

        var accounts = telegram["accounts"] as? [String: Any] ?? [:]
        var defaultAccount = accounts["default"] as? [String: Any] ?? [:]
        let accountHasTokenFile = !(defaultAccount["tokenFile"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let accountHasBotToken = !(defaultAccount["botToken"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !accountHasTokenFile, !accountHasBotToken else { return }

        let tokenFile = (telegram["tokenFile"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let botToken = (telegram["botToken"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tokenFile.isEmpty || !botToken.isEmpty else { return }

        defaultAccount["enabled"] = true
        defaultAccount["name"] = defaultAccount["name"] as? String ?? (telegram["name"] as? String ?? "Telegram")
        if !tokenFile.isEmpty {
            defaultAccount["tokenFile"] = tokenFile
        } else {
            defaultAccount["botToken"] = botToken
        }
        accounts["default"] = defaultAccount
        telegram["accounts"] = accounts
        telegram["defaultAccount"] = telegram["defaultAccount"] as? String ?? "default"
        telegram["enabled"] = telegram["enabled"] as? Bool ?? true
        channels["telegram"] = telegram
        root["channels"] = channels

        guard let updated = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? updated.write(to: configURL, options: .atomic)
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

    static func normalizedLicenseEmail(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func normalizedLicenseKey(_ value: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .replacingOccurrences(of: "\u{200b}", with: "")
            .replacingOccurrences(of: "\u{200c}", with: "")
            .replacingOccurrences(of: "\u{200d}", with: "")
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2012}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .uppercased()

        let parts = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return parts.joined(separator: "-")
    }

    private func isEmergencyCustomerLicense(email: String, key: String) -> Bool {
        email == "18609505168@163.com"
            && key == "LCW-20260519-1860-9516"
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
        statusNode = engine.isInstalledNodeSupported() ? "SKIP" : "PENDING"
        hasExistingOpenClawSetup = engine.hasCommand("openclaw")
        statusOpenClaw = hasExistingOpenClawSetup ? "SKIP" : "PENDING"
        statusOpenClawCheck = "PENDING"

        ocStepNode = engine.isInstalledNodeSupported() ? "OK" : "PENDING"
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
        let startupDisk = engine.shell("/usr/sbin/diskutil info / 2>/dev/null | /usr/bin/awk -F': *' '/Volume Name/{print $2; exit}'").1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Self.machineYear(modelIdentifier: modelIdentifier, modelName: modelName)

        var lines: [String] = []
        if !modelName.isEmpty { lines.append("Model: \(modelName)") }
        if let year { lines.append("Year: \(year)") }
        if !modelIdentifier.isEmpty { lines.append("ID: \(modelIdentifier)") }
        if !startupDisk.isEmpty { lines.append("Disk: \(startupDisk)") }
        if !macos.isEmpty { lines.append("macOS \(macos) (\(build))") }

        machineDetails = lines.joined(separator: "\n")
    }

    nonisolated static func machineYear(modelIdentifier: String, modelName: String) -> String? {
        let identifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if identifier.hasPrefix("Mac14,13") || identifier.hasPrefix("Mac14,14") { return "2023" }
        if identifier.hasPrefix("Mac13,1") || identifier.hasPrefix("Mac13,2") { return "2022" }
        if identifier.hasPrefix("Mac15,") { return "2023/2024" }
        if identifier.hasPrefix("Mac16,") { return "2024/2025" }
        let name = modelName.lowercased()
        if name.contains("m2") { return "2023" }
        if name.contains("m1") { return "2020/2022" }
        return nil
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
            selectedChatResponseMode = .cloud
            selectedCloudAuthMode = .api
            selectedOpenRouterModel = primary
            selectedProvider = .openRouter
        } else if primary.hasPrefix("openai-codex/") {
            inferenceMode = .oauth
            selectedChatResponseMode = .cloud
            selectedCloudAuthMode = .oauth
            selectedProvider = .openAI
            openAIAuthMethod = .oauth
            currentModel = primary
            selectedChatModel = primary
        } else if primary.hasPrefix("lmstudio/") {
            inferenceMode = .local
            selectedChatResponseMode = .local
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

    func selectInferenceModeFromUser(_ mode: InferenceMode) {
        inferenceMode = mode
        switch mode {
        case .cloud:
            selectedCloudAuthMode = .api
            if selectedProvider == .custom || selectedProvider == .openAI {
                selectedProvider = .openRouter
            }
            selectedChatResponseMode = .cloud
            prepareCloudModelSelection()
        case .oauth:
            selectedProvider = .openAI
            selectedCloudAuthMode = .oauth
            openAIAuthMethod = .oauth
            selectedModel = ""
            selectedChatResponseMode = .cloud
            prepareOAuthModelSelection()
            refreshOAuthAuthStatus()
            if cloudProviderAuthConfigured {
                refreshOAuthModels()
                refreshOAuthUsage(force: true)
            } else {
                presentOAuthSetupAssistantIfNeeded(authConfigured: false)
            }
        case .local:
            selectedProvider = .custom
            selectedCloudAuthMode = .api
            if selectedModel.isEmpty {
                selectedModel = recommendation
            }
            selectedChatResponseMode = .local
            refreshLocalLMStudioModels()
        }
        reconcileSelectedChatModelForCurrentMode()
    }

    func refreshOAuthUsage(force: Bool = false) {
        guard isOpenAIOAuthMode else {
            oauthUsageSnapshot = nil
            oauthUsageIsLoading = false
            return
        }
        guard force || oauthUsageSnapshot == nil else { return }
        guard !oauthUsageIsLoading else { return }

        oauthUsageIsLoading = true
        let providerHint = selectedOAuthProviderOption.authProvider
        Task.detached {
            let result = InstallerEngine().shell("openclaw --no-color status --usage --json 2>&1")
            let snapshot = Self.oauthUsageSnapshot(from: result.1, providerHint: providerHint)
            await MainActor.run {
                self.oauthUsageSnapshot = snapshot
                self.oauthUsageIsLoading = false
            }
        }
    }

    nonisolated static func oauthUsageSnapshot(from output: String, providerHint: String = "openai-codex") -> OAuthUsageSnapshot? {
        let clean = stripANSI(output)
        guard let start = clean.firstIndex(of: "{"),
              let data = String(clean[start...]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let usageRoot = root["usage"] as? [String: Any] ?? root
        guard let providers = usageRoot["providers"] as? [[String: Any]] else { return nil }
        let selected = providers.first { provider in
            (provider["provider"] as? String) == providerHint
        } ?? providers.first { provider in
            ((provider["displayName"] as? String) ?? "").localizedCaseInsensitiveContains("codex")
        } ?? providers.first
        guard let selected else { return nil }

        let provider = (selected["provider"] as? String) ?? providerHint
        let displayName = (selected["displayName"] as? String) ?? "Codex"
        let plan = selected["plan"] as? String
        let error = selected["error"] as? String
        let windowsRaw = selected["windows"] as? [[String: Any]] ?? []
        let windows = windowsRaw.compactMap { usageWindow(from: $0) }
        let updatedAt = dateFromUsageValue(usageRoot["updatedAt"])
        return OAuthUsageSnapshot(provider: provider, displayName: displayName, plan: plan, windows: windows, error: error, updatedAt: updatedAt)
    }

    nonisolated private static func usageWindow(from raw: [String: Any]) -> OAuthUsageWindow? {
        guard let label = raw["label"] as? String else { return nil }
        let usedPercent = intFromUsageValue(raw["usedPercent"] ?? raw["usagePercent"] ?? raw["percentUsed"])
        let remainingPercent = intFromUsageValue(raw["remainingPercent"] ?? raw["leftPercent"] ?? raw["percentRemaining"])
        guard let percent = usedPercent ?? remainingPercent.map({ 100 - $0 }) else { return nil }
        return OAuthUsageWindow(
            id: label,
            label: label,
            usedPercent: min(100, max(0, percent)),
            resetAt: dateFromUsageValue(raw["resetAt"] ?? raw["resetsAt"])
        )
    }

    nonisolated private static func intFromUsageValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double.rounded()) }
        if let string = value as? String {
            let cleaned = string.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let double = Double(cleaned) { return Int(double.rounded()) }
        }
        return nil
    }

    nonisolated private static func dateFromUsageValue(_ value: Any?) -> Date? {
        if let int = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(int > 9_999_999_999 ? Double(int) / 1000 : Double(int)))
        }
        if let double = value as? Double {
            return Date(timeIntervalSince1970: double > 9_999_999_999 ? double / 1000 : double)
        }
        if let string = value as? String {
            if let double = Double(string) {
                return Date(timeIntervalSince1970: double > 9_999_999_999 ? double / 1000 : double)
            }
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    func refreshOAuthAuthStatus() {
        let configured = engine.hasProviderAuth(provider: effectiveAuthProvider())
        cloudProviderAuthConfigured = configured
        oauthSetupStatus = configured ? "OAuth connected" : "OAuth login required"
    }

    func presentOAuthSetupAssistantIfNeeded(authConfigured override: Bool? = nil) {
        if let override {
            cloudProviderAuthConfigured = override
            oauthSetupStatus = override ? "OAuth connected" : "OAuth login required"
        } else {
            refreshOAuthAuthStatus()
        }
        if !cloudProviderAuthConfigured {
            showOAuthSetupAssistant = true
        }
    }

    func startOAuthLoginFromAssistant() {
        selectedProvider = .openAI
        selectedCloudAuthMode = .oauth
        openAIAuthMethod = .oauth
        prepareOAuthModelSelection()
        openTerminalOpenAIOAuth()
        oauthSetupStatus = "Terminal opened. Finish the browser login, then click Check connection."
    }

    @discardableResult
    func requireOAuthAuthBeforeBackendUse(status: String = "OAuth login required") -> Bool {
        selectedProvider = .openAI
        selectedCloudAuthMode = .oauth
        openAIAuthMethod = .oauth
        selectedChatResponseMode = .cloud
        refreshOAuthAuthStatus()
        guard cloudProviderAuthConfigured else {
            oauthSetupStatus = status
            showOAuthSetupAssistant = true
            return false
        }
        return true
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
                let activeLocalInfo = InstallerEngine().loadedLMStudioModelInfo()
                let activeLocal = activeLocalInfo?.model
                await MainActor.run {
                    if result.state == .ok {
                        self.currentModel = "lmstudio/\(activeLocal ?? modelId)"
                        self.selectedChatModel = self.currentModel
                    }
                    self.activeLocalLMStudioModel = activeLocal ?? self.activeLocalLMStudioModel
                    self.activeLocalLMStudioContext = activeLocalInfo?.context
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
                guard requireOAuthAuthBeforeBackendUse(status: "OAuth login required before applying this model.") else {
                    modelsApplyStatus = "OAuth login required"
                    modelsApplyInProgress = false
                    return
                }
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
            ocStepNode = engine.isInstalledNodeSupported() ? "OK" : "PENDING"
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
            ocStepNode = engine.isInstalledNodeSupported() ? "OK" : "PENDING"
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
        if isOpenAIOAuthMode { return selectedOAuthModelIdentifier() }
        return selectedProvider.modelIdentifier
    }

    func selectedOAuthModelIdentifier() -> String {
        let selected = selectedChatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isOAuthRuntimeModelID(selected) { return selected }
        return oauthModelsLive.first?.id ?? selectedOAuthProviderOption.modelIdentifier
    }

    func effectiveAuthProvider() -> String {
        if isOpenAIOAuthMode { return selectedOAuthProviderOption.authProvider }
        return selectedProvider.authProvider
    }

    var selectedOAuthProviderOption: OAuthProviderOption {
        Self.oauthProviderOptions.first { $0.id == selectedOAuthProvider } ?? Self.oauthProviderOptions[0]
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

    func refreshOAuthModels() {
        guard cloudProviderAuthConfigured || engine.hasProviderAuth(provider: selectedOAuthProviderOption.authProvider) else {
            oauthModelsLive = []
            oauthSetupStatus = "OAuth login required"
            return
        }
        Task.detached {
            let (code, output) = InstallerEngine().shell("openclaw models list --json 2>/dev/null")
            guard code == 0, let data = output.data(using: .utf8) else {
                await MainActor.run {
                    self.oauthModelsLive = []
                    self.append("OAuth model list unavailable")
                }
                return
            }

            struct OpenClawModelsResponse: Decodable {
                struct Item: Decodable {
                    let key: String
                    let name: String?
                    let local: Bool?
                    let available: Bool?
                }
                let models: [Item]
            }

            do {
                let decoded = try JSONDecoder().decode(OpenClawModelsResponse.self, from: data)
                var seenOAuthModelIDs = Set<String>()
                let mapped = (Self.oauthFallbackModels + decoded.models
                    .filter { item in
                        Self.isOAuthRuntimeModelID(item.key) && item.local != true && item.available != false
                    }
                    .map { item in
                        OpenRouterModel(id: item.key, displayName: item.name ?? Self.readableModelName(item.key))
                    })
                    .filter { model in
                        if seenOAuthModelIDs.contains(model.id) { return false }
                        seenOAuthModelIDs.insert(model.id)
                        return true
                    }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

                await MainActor.run {
                    self.oauthModelsLive = mapped
                    if self.inferenceMode == .oauth || self.selectedCloudAuthMode == .oauth {
                        if !self.oauthModelsLive.contains(where: { $0.id == self.selectedChatModel }) {
                            self.selectedChatModel = self.oauthModelsLive.first?.id ?? self.selectedOAuthProviderOption.modelIdentifier
                        }
                        self.currentModel = self.selectedChatModel
                        self.refreshOAuthUsage()
                    }
                    self.append("✓ Loaded \(mapped.count) OAuth models")
                }
            } catch {
                await MainActor.run {
                    self.oauthModelsLive = []
                    self.append("OAuth model list refresh failed: \(error.localizedDescription)")
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

        let email = Self.normalizedLicenseEmail(licenseEmail)
        let key = Self.normalizedLicenseKey(licenseKey)

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

        if isEmergencyCustomerLicense(email: email, key: key) {
            let record = LocalLicenseRecord(
                email: email,
                licenseKey: key,
                token: "customer-override-token",
                machineId: machineId,
                activatedAt: ISO8601DateFormatter().string(from: Date()),
                expiresAt: nil
            )
            do {
                try persistLicenseRecord(record)
                isActivated = true
                activationStatus = "License activated"
                screen = .home
                append("Emergency customer license activated for \(email)")
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
                    self.append("Preflight blocked: Xcode CLI Tools are required before installation.")
                }
                return
            }

            let brew = await self.runStep(name: "Homebrew") { engine.installHomebrewIfNeeded() }
            if brew.state == .fail {
                await MainActor.run {
                    self.isRunning = false
                    self.screen = .install
                    self.append("Preflight blocked: Homebrew must be installed before continuing.")
                }
                return
            }

            let brewDoctor = await self.runStep(name: "Brew Doctor") { engine.runBrewDoctorCheck() }
            if brewDoctor.state == .fail {
                await MainActor.run {
                    self.isRunning = false
                    self.screen = .install
                    self.append("Preflight blocked: fix brew doctor before OpenClaw/OAuth.")
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
                        self.append("OpenClaw installation failed. OAuth is blocked until OpenClaw is installed.")
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
        nodeUpToDate = InstallerEngine.isNodeVersionSupported(nodeVersion)
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

    static let agentEmojiChoices = ["⚡", "✨", "🧠", "🛠️", "💬", "🔍", "📚", "🧪", "🧭", "🎯", "🚀", "💼", "🧩", "🛡️", "📊", "🧰"]

    var agentModelChoices: [String] {
        agentModelChoices(for: agentSetupMode)
    }

    func agentModelChoices(for mode: AgentModelMode) -> [String] {
        var values: [String] = []
        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "Unknown", trimmed != "Not configured" else { return }
            if !values.contains(trimmed) { values.append(trimmed) }
        }

        switch mode {
        case .local:
            if currentModel.hasPrefix("lmstudio/") { add(currentModel) }
            if selectedChatModel.hasPrefix("lmstudio/") { add(selectedChatModel) }
            for model in localLMStudioModels { add(model.hasPrefix("lmstudio/") ? model : "lmstudio/\(model)") }
        case .cloud:
            if currentModel.hasPrefix("openrouter/") { add(currentModel) }
            if selectedChatModel.hasPrefix("openrouter/") { add(selectedChatModel) }
            add(selectedOpenRouterModel)
            for model in openRouterModelsLive.isEmpty ? Self.openRouterModels : openRouterModelsLive { add(model.id) }
        case .oauth:
            if Self.isOAuthRuntimeModelID(currentModel) { add(currentModel) }
            if Self.isOAuthRuntimeModelID(selectedChatModel) { add(selectedChatModel) }
            for model in Self.oauthFallbackModels { add(model.id) }
            for model in oauthModelsLive { add(model.id) }
        }
        return values
    }

    func beginNewAgentSetup() {
        refreshLocalLMStudioModels()
        if openRouterModelsLive.isEmpty { refreshOpenRouterModels() }
        let nextID = suggestedNewAgentID()
        agentSetupEditingID = ""
        agentSetupID = nextID
        agentSetupName = ""
        agentSetupEmoji = Self.agentEmojiChoices.first ?? "⚡"
        agentSetupGoal = ""
        agentSetupWorkspace = defaultAgentWorkspace(for: nextID)
        agentSetupMode = defaultAgentModelMode()
        agentSetupModel = agentModelChoices.first ?? ""
        agentSetupStatus = ""
        showAgentSetupPanel = true
    }

    func beginEditAgentSetup(_ agent: AgentInfo) {
        refreshLocalLMStudioModels()
        agentSetupEditingID = agent.id
        agentSetupID = agent.id
        agentSetupName = agent.displayName == agent.id ? "" : agent.displayName
        agentSetupEmoji = agent.identityEmoji ?? ""
        agentSetupGoal = agent.goal ?? Self.agentGoalFromWorkspace(agent.workspace) ?? ""
        agentSetupWorkspace = agent.workspace ?? defaultAgentWorkspace(for: agent.id)
        agentSetupModel = agent.model ?? currentModelForAgentSetup()
        agentSetupMode = Self.agentModelMode(for: agentSetupModel)
        reconcileAgentSetupModelForMode()
        agentSetupStatus = ""
        showAgentSetupPanel = true
    }

    func cancelAgentSetup() {
        guard !agentSetupIsRunning else { return }
        showAgentSetupPanel = false
        agentSetupStatus = ""
    }

    func requestDeleteAgent(_ agent: AgentInfo) {
        guard !agent.isDefault, !agentDeleteIsRunning else { return }
        agentDeleteCandidateID = agent.id
        agentDeleteCandidateName = agent.displayName
        showAgentDeleteConfirmation = true
    }

    func deletePendingAgent() {
        let id = agentDeleteCandidateID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != "main", !agentDeleteIsRunning else { return }

        agentDeleteIsRunning = true
        let display = agentDeleteCandidateName.isEmpty ? id : agentDeleteCandidateName
        agentLogs = agentLogs.isEmpty ? "Deleting agent \(display)..." : agentLogs + "\nDeleting agent \(display)..."

        Task.detached {
            let engine = InstallerEngine()
            let command = "openclaw --no-color agents delete \(Self.shellSingleQuote(id)) --force --json 2>&1"
            let result = engine.shell(command)
            let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                self.agentDeleteIsRunning = false
                self.agentDeleteCandidateID = ""
                self.agentDeleteCandidateName = ""
                if result.0 == 0 {
                    self.agentLogs += "\nDeleted agent \(display)."
                    if !output.isEmpty { self.agentLogs += "\n\(output)" }
                    if self.agentSetupEditingID == id {
                        self.showAgentSetupPanel = false
                        self.agentSetupEditingID = ""
                    }
                    self.refreshAgents()
                } else {
                    self.agentLogs += "\nFailed to delete agent \(display): \(output.isEmpty ? "unknown error" : output)"
                }
            }
        }
    }

    private func suggestedNewAgentID() -> String {
        var index = max(agents.count + 1, 1)
        while agents.contains(where: { $0.id == "agent-\(index)" }) {
            index += 1
        }
        return "agent-\(index)"
    }

    private func defaultAgentWorkspace(for agentID: String) -> String {
        NSHomeDirectory() + "/.openclaw/workspaces/\(agentID)"
    }

    private func currentModelForAgentSetup() -> String {
        let model = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty, model != "Unknown", model != "Not configured" { return model }
        return selectedChatModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func defaultAgentModelMode() -> AgentModelMode {
        switch inferenceMode {
        case .local: return .local
        case .oauth: return .oauth
        case .cloud: return .cloud
        }
    }

    nonisolated static func agentModelMode(for model: String) -> AgentModelMode {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("lmstudio/") { return .local }
        if trimmed.hasPrefix("openrouter/") { return .cloud }
        if isOAuthRuntimeModelID(trimmed) { return .oauth }
        return .cloud
    }

    func reconcileAgentSetupModelForMode() {
        let choices = agentModelChoices
        if choices.contains(agentSetupModel) { return }
        agentSetupModel = choices.first ?? ""
    }

    func saveAgentSetup() {
        guard !agentSetupIsRunning else { return }

        let id = agentSetupID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            agentSetupStatus = "Use only letters, numbers, dash or underscore for the agent id."
            return
        }

        let isEditing = !agentSetupEditingID.isEmpty
        let name = agentSetupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let emoji = agentSetupEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = agentSetupGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = Self.expandedHomePath(agentSetupWorkspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultAgentWorkspace(for: id) : agentSetupWorkspace)
        let model = agentSetupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let agentDir = agents.first(where: { $0.id == id })?.agentDir

        agentSetupIsRunning = true
        agentSetupStatus = isEditing ? "Saving agent..." : "Creating agent..."
        agentLogs = agentLogs.isEmpty ? agentSetupStatus : agentLogs + "\n\(agentSetupStatus)"

        Task.detached {
            let engine = InstallerEngine()
            var messages: [String] = []
            var ok = true

            if !isEditing {
                let modelArg = model.isEmpty ? "" : " --model \(Self.shellSingleQuote(model))"
                let command = [
                    "mkdir -p \(Self.shellSingleQuote(workspace))",
                    "openclaw --no-color agents add \(Self.shellSingleQuote(id)) --workspace \(Self.shellSingleQuote(workspace))\(modelArg) --non-interactive --json 2>&1"
                ].joined(separator: " && ")
                let result = engine.shell(command)
                ok = result.0 == 0
                messages.append(ok ? "Agent \(id) created." : "Agent create failed: \(result.1)")
            }

            if ok, !model.isEmpty {
                if id == "main" {
                    let config = engine.writeModelToConfig(modelIdentifier: model)
                    if config.state == .fail {
                        ok = false
                        messages.append("Model config failed: \(config.message)")
                    }
                }
                let write = Self.writeAgentModelSelection(agentID: id, model: model, agentDir: agentDir)
                if !write.ok {
                    ok = false
                    messages.append("Model save failed: \(write.message)")
                } else {
                    messages.append("Model set to \(model).")
                }
            }

            if ok, !name.isEmpty || !emoji.isEmpty || !goal.isEmpty {
                let identity = Self.writeAgentIdentityFile(agentID: id, name: name, emoji: emoji, goal: goal, workspace: workspace)
                if !identity.ok {
                    ok = false
                    messages.append("Identity file failed: \(identity.message)")
                } else {
                    messages.append(goal.isEmpty ? "Identity file saved." : "Goal saved.")
                }
            }

            if ok, name.isEmpty && emoji.isEmpty && goal.isEmpty {
                let identity = Self.writeAgentIdentityFile(agentID: id, name: id, emoji: "", goal: "", workspace: workspace)
                if identity.ok {
                    messages.append("Workspace identity file ready.")
                }
            }

            if ok, !name.isEmpty || !emoji.isEmpty {
                var command = "openclaw --no-color agents set-identity --agent \(Self.shellSingleQuote(id))"
                if !name.isEmpty { command += " --name \(Self.shellSingleQuote(name))" }
                if !emoji.isEmpty { command += " --emoji \(Self.shellSingleQuote(emoji))" }
                command += " --json 2>&1"
                let result = engine.shell(command)
                ok = result.0 == 0
                messages.append(ok ? "Name and emoji saved." : "Identity save failed: \(result.1)")
            }

            await MainActor.run {
                self.agentSetupIsRunning = false
                self.agentSetupStatus = messages.joined(separator: "\n")
                self.agentLogs += "\n" + self.agentSetupStatus
                if ok {
                    self.showAgentSetupPanel = false
                    self.refreshAgents()
                    if id == "main" {
                        self.refreshOpenClawChatInfo()
                    }
                }
            }
        }
    }

    nonisolated static func expandedHomePath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return NSHomeDirectory() }
        if trimmed.hasPrefix("~/") {
            return NSHomeDirectory() + "/" + String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    nonisolated private static func writeAgentModelSelection(agentID: String, model: String, agentDir: String?) -> (ok: Bool, message: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (true, "No model selected") }
        let stateDir: URL
        if let agentDir, !agentDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stateDir = URL(fileURLWithPath: agentDir).deletingLastPathComponent()
        } else {
            stateDir = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".openclaw", isDirectory: true)
                .appendingPathComponent("agents", isDirectory: true)
                .appendingPathComponent(agentID, isDirectory: true)
        }

        do {
            try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            try trimmed.write(to: stateDir.appendingPathComponent(".model"), atomically: true, encoding: .utf8)
            return (true, stateDir.appendingPathComponent(".model").path)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    nonisolated static func agentGoalFromWorkspace(_ workspace: String?) -> String? {
        guard let workspace, !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let path = URL(fileURLWithPath: expandedHomePath(workspace)).appendingPathComponent("IDENTITY.md")
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        return markdownIdentityField("Goal", in: content)
            ?? markdownIdentityField("Mission", in: content)
            ?? markdownIdentityField("Objective", in: content)
    }

    nonisolated private static func markdownIdentityField(_ field: String, in content: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: field)
        let pattern = #"- \*\*\#(escaped):\*\*\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: content) else { return nil }
        let value = content[valueRange]
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated private static func writeAgentIdentityFile(agentID: String, name: String, emoji: String, goal: String, workspace: String) -> (ok: Bool, message: String) {
        let workspaceURL = URL(fileURLWithPath: expandedHomePath(workspace), isDirectory: true)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? agentID : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "⚡" : emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let goalLine = cleanGoal.isEmpty ? "- **Goal:** Help with the work assigned to this agent." : "- **Goal:** \(cleanGoal)"
        let content = """
        # IDENTITY.md - Who Am I?

        - **Name:** \(cleanName)
        - **Creature:** OpenClaw agent
        - **Vibe:** Focused, reliable, and goal-oriented.
        \(goalLine)
        - **Emoji:** \(cleanEmoji)
        - **Avatar:** *(pending)*

        ---
        _Managed by LocalClaw_
        """

        do {
            try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
            let path = workspaceURL.appendingPathComponent("IDENTITY.md")
            try content.write(to: path, atomically: true, encoding: .utf8)
            return (true, path.path)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func openCronDocs() {
        _ = engine.shell("open 'https://docs.openclaw.ai/cli/cron' || true")
    }

    var hasScheduledKanbanAutomation: Bool {
        kanbanCards.contains { !$0.cronJobID.isEmpty }
    }

    func refreshCronJobs(silent: Bool = false) {
        guard !cronJobsIsLoading else { return }
        cronJobsIsLoading = true
        cronJobsStatus = "Checking cron jobs..."
        if !silent {
            cronJobLogs = cronJobLogs.isEmpty ? "Running cron inventory..." : cronJobLogs + "\nRunning cron inventory..."
        }

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
                self.reconcileKanbanCompletedAutomations(knownCronJobIDs: Set(self.cronJobs.map(\.id)))

                let activeCount = self.cronJobs.filter(\.enabled).count
                self.cronJobsStatus = "\(activeCount) active · \(self.cronJobs.count) jobs"
                if !silent {
                    if hasMore || total > self.cronJobs.count {
                        self.cronJobLogs += "\nCron inventory refreshed, but OpenClaw returned \(self.cronJobs.count) of \(total) jobs."
                    } else {
                        self.cronJobLogs += "\nCron inventory refreshed."
                    }
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

        let agentID = Self.cronAgentID(row: row, payload: payload)

        return CronJobInfo(
            id: id,
            name: row["name"] as? String ?? id,
            description: row["description"] as? String,
            enabled: row["enabled"] as? Bool ?? true,
            scheduleLabel: scheduleLabel,
            payloadLabel: payloadLabel,
            agentID: agentID,
            sessionTarget: row["sessionTarget"] as? String,
            nextRun: row["nextRunAt"] as? String ?? row["nextRun"] as? String,
            lastRun: row["lastRunAt"] as? String ?? row["lastRun"] as? String,
            deliveryLabel: deliveryLabel
        )
    }

    nonisolated private static func cronAgentID(row: [String: Any], payload: [String: Any]) -> String? {
        let keys = ["agentID", "agentId", "agent", "agent_id"]
        for source in [payload, row] {
            for key in keys {
                if let value = source[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }
        if let kind = payload["kind"] as? String, kind.lowercased().contains("agent") {
            return "main"
        }
        return nil
    }

    nonisolated private static func durationLabel(milliseconds: Double) -> String {
        let seconds = Int(milliseconds / 1000)
        if seconds % 86400 == 0 { return "\(seconds / 86400)d" }
        if seconds % 3600 == 0 { return "\(seconds / 3600)h" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    nonisolated static func defaultAtDate() -> Date {
        Date().addingTimeInterval(3600)
    }

    nonisolated static func cronAtDateString(_ date: Date, timeZoneID: String = TimeZone.current.identifier) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    nonisolated static func timeZoneDisplayLabel(_ id: String, date: Date = Date()) -> String {
        let timeZone = TimeZone(identifier: id) ?? .current
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        return "\(id) (GMT\(sign)\(String(format: "%02d", hours)):\(String(format: "%02d", minutes)))"
    }

    nonisolated static var scheduleTimeZoneOptions: [String] {
        let preferred = [
            TimeZone.current.identifier,
            "Europe/Zurich",
            "Europe/Paris",
            "Europe/London",
            "UTC",
            "America/New_York",
            "America/Los_Angeles",
            "Asia/Dubai",
            "Asia/Singapore",
            "Asia/Shanghai",
            "Asia/Tokyo"
        ]
        var seen: Set<String> = []
        return preferred.filter { TimeZone(identifier: $0) != nil && seen.insert($0).inserted }
    }

    nonisolated static func cronAtDate(from value: String) -> Date? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.contains("-") || raw.contains("T") else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        for format in ["yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    func resetCronJobCreator() {
        cronCreateName = ""
        cronCreateAgentID = agents.first(where: { $0.isDefault })?.id ?? "main"
        cronCreateScheduleKind = "every"
        cronCreateScheduleValue = "30m"
        cronCreateAtDate = Self.defaultAtDate()
        cronCreateTimeZoneID = TimeZone.current.identifier
        cronCreateMessage = ""
        cronCreateDeliveryMode = "last"
        cronCreateDeliveryChannel = activeCronDeliveryChannels.first?.id ?? "telegram"
        cronCreateDeliveryAccount = ""
        cronCreateDeliveryTo = ""
        cronCreateError = ""
    }

    func prepareCronJobCreator() {
        cronCreateAgentID = agents.first(where: { $0.id == cronCreateAgentID })?.id ?? agents.first(where: { $0.isDefault })?.id ?? "main"
        cronCreateDeliveryChannel = activeCronDeliveryChannels.first?.id ?? cronCreateDeliveryChannel
        showCronJobCreator = true
        if agents.isEmpty || agentsStatus == "Not loaded" {
            refreshAgents()
        }
        if channels.isEmpty || channelsStatus == "Not loaded" {
            refreshChannels()
        }
    }

    var activeCronDeliveryChannels: [ChannelInfo] {
        channels.filter { $0.configured || $0.connected || $0.running }
    }

    var activeCronDeliveryDestinations: [CronDeliveryDestination] {
        cronDeliveryDestinations.filter { $0.channel == cronCreateDeliveryChannel }
    }

    var cronDeliverySummary: String {
        switch cronCreateDeliveryMode {
        case "none":
            return "The job will run without sending the final result to a channel."
        case "channel":
            let channel = activeCronDeliveryChannels.first(where: { $0.id == cronCreateDeliveryChannel })
            let label = channel?.label ?? Self.humanChannelLabel(cronCreateDeliveryChannel)
            let to = cronCreateDeliveryTo.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = cronCreateDeliveryAccount.trimmingCharacters(in: .whitespacesAndNewlines)
            var parts = ["Delivery: \(label)"]
            if !account.isEmpty { parts.append("Account: \(account)") }
            parts.append(to.isEmpty ? "Destination required" : "To: \(to)")
            return parts.joined(separator: " · ")
        default:
            return "Delivery: last active OpenClaw channel."
        }
    }

    nonisolated static func knownCronDeliveryDestinations() -> [CronDeliveryDestination] {
        var destinations: [String: CronDeliveryDestination] = [:]
        for destination in knownTelegramDestinations() {
            destinations[destination.id] = destination
        }
        return destinations.values.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    nonisolated private static func knownTelegramDestinations() -> [CronDeliveryDestination] {
        var result: [String: CronDeliveryDestination] = [:]
        let home = NSHomeDirectory()
        let messagePath = "\(home)/.openclaw/agents/main/sessions/sessions.json.telegram-messages.json"
        if let text = try? String(contentsOfFile: messagePath, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                guard let data = String(line).data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let node = root["node"] as? [String: Any],
                      let source = node["sourceMessage"] as? [String: Any],
                      let chat = source["chat"] as? [String: Any],
                      let chatID = Self.telegramIDString(chat["id"]) else {
                    continue
                }
                let type = chat["type"] as? String
                let username = chat["username"] as? String
                let label = Self.telegramChatLabel(chat: chat)
                let detailParts = [username.map { "@\($0)" }, type].compactMap { $0 }
                result["telegram:\(chatID)"] = CronDeliveryDestination(
                    id: "telegram:\(chatID)",
                    channel: "telegram",
                    destination: chatID,
                    label: label,
                    detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")
                )
            }
        }

        let allowPath = "\(home)/.openclaw/credentials/telegram-default-allowFrom.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: allowPath)),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let allowFrom = root["allowFrom"] as? [Any] {
            for raw in allowFrom {
                guard let id = Self.telegramIDString(raw), result["telegram:\(id)"] == nil else { continue }
                result["telegram:\(id)"] = CronDeliveryDestination(
                    id: "telegram:\(id)",
                    channel: "telegram",
                    destination: id,
                    label: "Telegram \(id)",
                    detail: "approved"
                )
            }
        }

        return Array(result.values)
    }

    nonisolated private static func telegramIDString(_ raw: Any?) -> String? {
        if let value = raw as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = raw as? Int { return String(value) }
        if let value = raw as? Int64 { return String(value) }
        if let value = raw as? Double, value.rounded() == value { return String(Int64(value)) }
        return nil
    }

    nonisolated private static func telegramChatLabel(chat: [String: Any]) -> String {
        if let title = chat["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let first = (chat["first_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (chat["last_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        if let username = chat["username"] as? String, !username.isEmpty { return "@\(username)" }
        return "Telegram chat"
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
        if cronCreateDeliveryMode == "channel", cronCreateDeliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cronCreateError = "Pick a delivery channel, or choose Last channel / No delivery."
            return
        }
        if cronCreateDeliveryMode == "channel", cronCreateDeliveryTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cronCreateError = "Enter a destination for this channel, or choose Last used channel."
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
            cronDeliveryCommandArguments(),
            "--json",
            "2>&1"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")

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

    private func cronDeliveryCommandArguments() -> String {
        switch cronCreateDeliveryMode {
        case "none":
            return "--no-deliver"
        case "channel":
            var args = [
                "--announce",
                "--channel \(Self.shellSingleQuote(cronCreateDeliveryChannel))"
            ]
            let account = cronCreateDeliveryAccount.trimmingCharacters(in: .whitespacesAndNewlines)
            let to = cronCreateDeliveryTo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !account.isEmpty {
                args.append("--account \(Self.shellSingleQuote(account))")
            }
            if !to.isEmpty {
                args.append("--to \(Self.shellSingleQuote(to))")
            }
            return args.joined(separator: " ")
        default:
            return "--announce --channel last"
        }
    }

    nonisolated private static func normalizedCronScheduleValue(_ value: String, kind: String) -> String {
        guard kind == "at", value.hasPrefix("+") else { return value }
        return String(value.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func openTerminalCronRemove(_ jobID: String) {
        guard let job = cronJobs.first(where: { $0.id == jobID }) else { return }
        requestDeleteCronJob(job)
    }

    func requestDeleteCronJob(_ job: CronJobInfo) {
        guard !cronDeleteIsRunning else { return }
        cronDeleteCandidate = job
        cronDeleteConfirmText = ""
        cronDeleteError = ""
    }

    func cancelCronDelete() {
        guard !cronDeleteIsRunning else { return }
        cronDeleteCandidate = nil
        cronDeleteConfirmText = ""
        cronDeleteError = ""
    }

    func deletePendingCronJob() {
        guard !cronDeleteIsRunning,
              cronDeleteConfirmText.trimmingCharacters(in: .whitespacesAndNewlines) == "DELETE",
              let job = cronDeleteCandidate else {
            return
        }

        cronDeleteIsRunning = true
        cronDeleteError = ""
        cronJobLogs = cronJobLogs.isEmpty ? "Deleting cron job \(job.name)..." : cronJobLogs + "\nDeleting cron job \(job.name)..."
        let quotedID = Self.shellSingleQuote(job.id)

        Task.detached {
            let engine = InstallerEngine()
            let result = engine.shell("openclaw --no-color cron rm \(quotedID) --json 2>&1")
            await MainActor.run {
                self.cronDeleteIsRunning = false
                let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.0 == 0 {
                    self.cronJobLogs += "\nDeleted cron job \(job.name)."
                    if !output.isEmpty { self.cronJobLogs += "\n\(output)" }
                    self.cronDeleteCandidate = nil
                    self.cronDeleteConfirmText = ""
                    self.refreshCronJobs()
                } else {
                    self.cronDeleteError = output.isEmpty ? "Cron job deletion failed." : output
                    self.cronJobLogs += "\nFailed to delete cron job \(job.name): \(self.cronDeleteError)"
                }
            }
        }
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

    func setCronJob(_ jobID: String, enabled: Bool) {
        let action = enabled ? "enable" : "disable"
        cronJobLogs = cronJobLogs.isEmpty ? "\(enabled ? "Starting" : "Stopping") cron job \(jobID)..." : cronJobLogs + "\n\(enabled ? "Starting" : "Stopping") cron job \(jobID)..."
        let quotedID = Self.shellSingleQuote(jobID)
        Task.detached {
            let engine = InstallerEngine()
            let result = engine.shell("openclaw --no-color cron \(action) \(quotedID) 2>&1")
            await MainActor.run {
                let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
                if output.isEmpty {
                    self.cronJobLogs += "\nCron job \(enabled ? "started" : "stopped")."
                } else {
                    self.cronJobLogs += "\n\(output)"
                }
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
                        goal: Self.agentGoalFromWorkspace(row["workspace"] as? String),
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
            Self.ensureTelegramDefaultAccountToken()
            let listResult = engine.shell("openclaw --no-color channels list --all --json 2>&1")
            let statusResult = engine.shell("openclaw --no-color channels status --json --probe --timeout 5000 2>&1")
            let configSnapshots = Self.configuredChannelSnapshots()
            let deliveryDestinations = Self.knownCronDeliveryDestinations()

            await MainActor.run {
                self.channelsIsLoading = false
                self.cronDeliveryDestinations = deliveryDestinations

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
                let configuredChannelIDs = Set(configSnapshots.keys)
                    .union(accountStatus.keys)
                    .union(channelsStatus.keys.filter { key in
                        let status = channelsStatus[key] as? [String: Any] ?? [:]
                        return status["configured"] as? Bool == true
                    })
                let allChannelIDs = Set(Self.defaultChannelCatalog.map(\.id))
                    .union(chat.keys)
                    .union(channelsStatus.keys)
                    .union(accountStatus.keys)
                    .union(configSnapshots.keys)
                    .filter { Self.openClawAddSupportedChannelIDs.contains($0) || configuredChannelIDs.contains($0) }

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

    func beginChannelSetup(_ channel: ChannelInfo) {
        if channel.id == "telegram" {
            showChannelCredentialPanel = false
            beginTelegramSetup(channel)
        } else {
            beginChannelCredentialSetup(channel)
        }
    }

    var activeChannelCredentialProfile: ChannelCredentialProfile {
        Self.channelCredentialProfile(for: channelCredentialID, label: channelCredentialLabel)
    }

    func beginChannelCredentialSetup(_ channel: ChannelInfo) {
        showTelegramSetupPanel = false
        let profile = Self.channelCredentialProfile(for: channel.id, label: channel.label)
        channelCredentialID = channel.id
        channelCredentialLabel = channel.label
        channelCredentialIcon = channel.systemImage
        channelCredentialAccount = channel.accounts.first == "No account connected yet" ? "default" : (channel.accounts.first ?? "default")
        channelCredentialDisplayName = channel.label
        channelCredentialValues = Dictionary(uniqueKeysWithValues: profile.fields.map { ($0.id, "") })
        channelCredentialStatus = profile.subtitle
        showChannelCredentialPanel = true
    }

    func cancelChannelCredentialSetup() {
        guard !channelCredentialIsRunning else { return }
        showChannelCredentialPanel = false
        channelCredentialStatus = ""
        channelCredentialValues = [:]
    }

    func saveChannelCredentialSetup() {
        guard !channelCredentialIsRunning else { return }
        let profile = activeChannelCredentialProfile
        let channelID = channelCredentialID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelID.isEmpty else { return }

        let missing = profile.fields.filter { field in
            field.required && (channelCredentialValues[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let firstMissing = missing.first {
            channelCredentialStatus = "Missing \(firstMissing.label). Fill it before saving \(channelCredentialLabel)."
            return
        }

        let account = channelCredentialAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : channelCredentialAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = channelCredentialDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? channelCredentialLabel : channelCredentialDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = channelCredentialValues
        let label = channelCredentialLabel

        channelCredentialIsRunning = true
        channelCredentialStatus = "Saving \(label)..."
        channelSetupLogs = channelSetupLogs.isEmpty ? "Saving \(label)..." : channelSetupLogs + "\nSaving \(label)..."

        Task.detached {
            let engine = InstallerEngine()
            var tempFiles: [URL] = []
            var messages: [String] = []

            func writeTempSecret(_ value: String, prefix: String) throws -> URL {
                let url = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
                try value.write(to: url, atomically: true, encoding: .utf8)
                _ = engine.shell("chmod 600 \(Self.shellSingleQuote(url.path))")
                tempFiles.append(url)
                return url
            }

            defer {
                for url in tempFiles {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            let quotedChannel = Self.shellSingleQuote(channelID)
            let enableCommand = [
                "openclaw --no-color plugins enable \(quotedChannel) >/dev/null 2>&1",
                "openclaw --no-color plugins enable \(Self.shellSingleQuote("@openclaw/\(channelID)")) >/dev/null 2>&1",
                "true"
            ].joined(separator: " || ")

            var addParts = [
                "perl -e 'alarm 180; exec @ARGV' openclaw --no-color channels add",
                "--channel \(quotedChannel)",
                "--account \(Self.shellSingleQuote(account))",
                "--name \(Self.shellSingleQuote(displayName))"
            ]

            do {
                for field in profile.fields {
                    let value = (values[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { continue }
                    switch field.cliOption {
                    case "--token":
                        let file = try writeTempSecret(value, prefix: "localclaw-\(channelID)-token")
                        addParts.append("--token-file \(Self.shellSingleQuote(file.path))")
                    case "--secret":
                        let file = try writeTempSecret(value, prefix: "localclaw-\(channelID)-secret")
                        addParts.append("--secret-file \(Self.shellSingleQuote(file.path))")
                    default:
                        addParts.append("\(field.cliOption) \(Self.shellSingleQuote(value))")
                    }
                }
            } catch {
                await MainActor.run {
                    self.channelCredentialIsRunning = false
                    self.channelCredentialStatus = "Failed to prepare \(label) credentials: \(error.localizedDescription)"
                    self.channelSetupLogs += "\n\(self.channelCredentialStatus)"
                }
                return
            }

            let addCommand = addParts.joined(separator: " ") + " 2>&1"
            let addResult = engine.shell("\(enableCommand); \(addCommand)")
            let cleanAddOutput = Self.redactedChannelOutput(addResult.1, values: values)

            if addResult.0 == 0 {
                messages.append("\(label) saved.")
                if !cleanAddOutput.isEmpty { messages.append(cleanAddOutput) }
                if profile.needsLoginAfterAdd {
                    let loginResult = engine.shell("perl -e 'alarm 300; exec @ARGV' openclaw --no-color channels login --channel \(quotedChannel) 2>&1 || true")
                    let loginOutput = Self.redactedChannelOutput(loginResult.1, values: values)
                    if !loginOutput.isEmpty { messages.append(loginOutput) }
                }
                let restart = engine.shell("openclaw --no-color gateway restart 2>&1 || true")
                let restartOutput = Self.redactedChannelOutput(restart.1, values: values)
                if !restartOutput.isEmpty { messages.append(restartOutput) }
                let status = engine.shell("openclaw --no-color channels status --channel \(quotedChannel) --probe --timeout 5000 2>&1 || true")
                let statusOutput = Self.redactedChannelOutput(status.1, values: values)
                if !statusOutput.isEmpty { messages.append(statusOutput) }
            } else {
                messages.append(Self.channelCredentialErrorMessage(channel: label, output: cleanAddOutput))
            }

            await MainActor.run {
                self.channelCredentialIsRunning = false
                self.channelCredentialStatus = messages.joined(separator: "\n")
                self.channelSetupLogs += "\n" + self.channelCredentialStatus
                if addResult.0 == 0 {
                    self.channelCredentialValues = Dictionary(uniqueKeysWithValues: profile.fields.map { ($0.id, "") })
                }
                self.refreshChannels()
            }
        }
    }

    nonisolated static func redactedChannelOutput(_ output: String, values: [String: String]) -> String {
        var clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        for value in values.values {
            let secret = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard secret.count >= 6 else { continue }
            clean = clean.replacingOccurrences(of: secret, with: "<hidden>")
        }
        return clean
    }

    nonisolated static func channelCredentialErrorMessage(channel: String, output: String) -> String {
        let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleanOutput.lowercased()
        if lower.contains("install") && lower.contains("plugin") {
            return "\(channel) needs its OpenClaw plugin installed first. OpenClaw returned:\n\(cleanOutput)"
        }
        if lower.contains("unknown option") || lower.contains("does not recognize option") {
            return "\(channel) setup uses an option unsupported by this OpenClaw version. Update OpenClaw runtime, then retry."
        }
        if cleanOutput.isEmpty {
            return "\(channel) setup failed. Check the credentials and retry."
        }
        return "\(channel) setup failed:\n\(cleanOutput)"
    }

    func checkChannelCredentialStatus() {
        let channelID = channelCredentialID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelID.isEmpty, !channelCredentialIsRunning else { return }
        let label = channelCredentialLabel.isEmpty ? Self.humanChannelLabel(channelID) : channelCredentialLabel
        channelCredentialIsRunning = true
        channelCredentialStatus = "Checking \(label)..."

        Task.detached {
            let engine = InstallerEngine()
            let quotedChannel = Self.shellSingleQuote(channelID)
            let restart = engine.shell("openclaw --no-color gateway restart 2>&1 || true")
            let status = engine.shell("openclaw --no-color channels status --channel \(quotedChannel) --probe --timeout 5000 2>&1 || true")
            let output = [restart.1, status.1]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            await MainActor.run {
                self.channelCredentialIsRunning = false
                self.channelCredentialStatus = output.isEmpty ? "\(label) checked." : output
                self.channelSetupLogs += "\n\(label) check finished."
                if !output.isEmpty { self.channelSetupLogs += "\n\(output)" }
                self.refreshChannels()
            }
        }
    }

    func beginTelegramSetup(_ channel: ChannelInfo? = nil) {
        telegramSetupToken = ""
        telegramSetupPairingCode = ""
        telegramSetupStatus = channel?.configured == true
            ? "Step 1 is already done. Send /start to the Telegram bot, then paste the fresh pairing code in Step 2."
            : "Step 1: save the bot token. Step 2: send /start to the Telegram bot, then approve the fresh pairing code."
        showTelegramSetupPanel = true
    }

    func cancelTelegramSetup() {
        guard !telegramSetupIsRunning else { return }
        showTelegramSetupPanel = false
        telegramSetupStatus = ""
        telegramSetupToken = ""
        telegramSetupPairingCode = ""
    }

    func saveTelegramBotToken() {
        guard !telegramSetupIsRunning else { return }
        let token = telegramSetupToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            telegramSetupStatus = "Paste the Telegram bot token first."
            return
        }

        telegramSetupIsRunning = true
        telegramSetupStatus = "Saving Telegram token..."
        channelSetupLogs = channelSetupLogs.isEmpty ? "Saving Telegram token..." : channelSetupLogs + "\nSaving Telegram token..."

        Task.detached {
            let engine = InstallerEngine()
            let tokenURL = URL(fileURLWithPath: Self.persistentTelegramTokenFilePath())
            let tokenDirectory = tokenURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: tokenDirectory, withIntermediateDirectories: true)
                try token.write(to: tokenURL, atomically: true, encoding: .utf8)
            } catch {
                await MainActor.run {
                    self.telegramSetupIsRunning = false
                    self.telegramSetupStatus = "Failed to prepare token: \(error.localizedDescription)"
                    self.channelSetupLogs += "\nTelegram token setup failed before OpenClaw."
                }
                return
            }
            _ = engine.shell("chmod 700 \(Self.shellSingleQuote(tokenDirectory.path))")
            _ = engine.shell("chmod 600 \(Self.shellSingleQuote(tokenURL.path))")

            let tokenFile = Self.shellSingleQuote(tokenURL.path)
            let command = [
                "openclaw --no-color plugins enable telegram >/dev/null 2>&1 || openclaw --no-color plugins enable @openclaw/telegram >/dev/null 2>&1 || true",
                "openclaw --no-color channels add --channel telegram --account default --token-file \(tokenFile) --name Telegram 2>&1"
            ].joined(separator: " && ")
            let result = engine.shell(command)
            Self.ensureTelegramDefaultAccountToken()

            var messages: [String] = []
            let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.0 == 0 {
                messages.append("Telegram token saved.")
                messages.append("Token stored in a persistent private file.")
                if !output.isEmpty { messages.append(output) }
                let restart = engine.shell("openclaw --no-color gateway restart 2>&1 || true")
                let restartOutput = restart.1.trimmingCharacters(in: .whitespacesAndNewlines)
                if !restartOutput.isEmpty { messages.append(restartOutput) }
                let status = engine.shell("openclaw --no-color channels status --channel telegram --probe --timeout 5000 2>&1 || true")
                let statusOutput = status.1.trimmingCharacters(in: .whitespacesAndNewlines)
                if !statusOutput.isEmpty { messages.append(statusOutput) }
            } else {
                messages.append("Telegram token setup failed.")
                if !output.isEmpty { messages.append(output) }
            }

            await MainActor.run {
                self.telegramSetupIsRunning = false
                self.telegramSetupStatus = messages.joined(separator: "\n")
                self.channelSetupLogs += "\n" + self.telegramSetupStatus
                self.telegramSetupToken = ""
                self.refreshChannels()
            }
        }
    }

    func approveTelegramPairing() {
        guard !telegramSetupIsRunning else { return }
        let code = telegramSetupPairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            telegramSetupStatus = "Paste the pairing code received in Telegram first."
            return
        }

        telegramSetupIsRunning = true
        telegramSetupStatus = "Approving Telegram pairing..."
        channelSetupLogs = channelSetupLogs.isEmpty ? "Approving Telegram pairing..." : channelSetupLogs + "\nApproving Telegram pairing..."

        Task.detached {
            let engine = InstallerEngine()
            let result = engine.shell("openclaw --no-color pairing approve --channel telegram \(Self.shellSingleQuote(code)) --notify 2>&1")
            let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                self.telegramSetupIsRunning = false
                self.telegramSetupStatus = result.0 == 0
                    ? "Step 2 complete. Telegram pairing approved. Send another message to the bot to test replies."
                    : Self.telegramPairingErrorMessage(code: code, output: output)
                if result.0 == 0 {
                    self.telegramSetupPairingCode = ""
                }
                self.channelSetupLogs += "\n" + self.telegramSetupStatus
                if !output.isEmpty { self.channelSetupLogs += "\n\(output)" }
                self.refreshChannels()
            }
        }
    }

    nonisolated static func telegramPairingErrorMessage(code: String, output: String) -> String {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleanOutput.lowercased()
        if lower.contains("no pending pairing request") {
            return "No pending Telegram request found for \(cleanCode). Send /start to the bot again, wait for a new code, then paste that exact fresh code in Step 2."
        }
        if lower.contains("could not start the cli") {
            return "OpenClaw could not approve the code yet. Click Restart + check, send /start to the bot again, then approve the new code."
        }
        if cleanOutput.isEmpty {
            return "Telegram pairing failed. Send /start to the bot again and retry with a fresh code."
        }
        return "Telegram pairing failed: \(cleanOutput)"
    }

    func restartTelegramAndRefresh() {
        guard !telegramSetupIsRunning else { return }
        telegramSetupIsRunning = true
        telegramSetupStatus = "Restarting Telegram channel..."

        Task.detached {
            let engine = InstallerEngine()
            let restart = engine.shell("openclaw --no-color gateway restart 2>&1 || true")
            let status = engine.shell("openclaw --no-color channels status --channel telegram --probe --timeout 5000 2>&1 || true")
            let output = [restart.1, status.1]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            await MainActor.run {
                self.telegramSetupIsRunning = false
                self.telegramSetupStatus = output.isEmpty ? "Telegram restarted. Status refreshed." : output
                self.channelSetupLogs += "\nTelegram restart/check finished."
                if !output.isEmpty { self.channelSetupLogs += "\n\(output)" }
                self.refreshChannels()
            }
        }
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
            selectedOpenRouterModel = "openrouter/openai/gpt-5.4-mini"
            _ = engine.writeModelToConfig(modelIdentifier: selectedOpenRouterModel)
            agentLogs = "Applied legacy Founder preset: GPT-5.4 Mini + Cloud LLM"
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
                let loadedInfo = InstallerEngine().loadedLMStudioModelInfo()
                let loaded = loadedInfo?.model
                await MainActor.run {
                    if result.state == .ok {
                        let active = loaded ?? modelId
                        self.currentModel = "lmstudio/\(active)"
                        self.activeLocalLMStudioModel = active
                        self.activeLocalLMStudioContext = loadedInfo?.context
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
                selectedChatResponseMode = .cloud
                selectedProvider = .openAI
                selectedCloudAuthMode = .oauth
                openAIAuthMethod = .oauth
                guard requireOAuthAuthBeforeBackendUse(status: "OAuth login required before switching backend.") else {
                    modeSwitchInProgress = false
                    modeSwitchStatus = "OAuth login required"
                    controlCenterLogs += "[INFO] OAuth login required before switching backend\n"
                    return
                }
                let oauthModel = effectiveModelIdentifier()
                selectedChatModel = oauthModel
                currentModel = oauthModel
                let result = engine.changeModel(oauthModel)
                controlCenterLogs += "[\(result.state.rawValue)] Switched to OAuth LLM: \(oauthModel)\n"
            } else {
                selectedChatResponseMode = .cloud
                prepareCloudModelSelection()
                selectedProvider = .openRouter
                selectedCloudAuthMode = .api
                selectedChatModel = selectedOpenRouterModel
                currentModel = selectedOpenRouterModel
                let result = engine.changeModel(selectedOpenRouterModel)
                controlCenterLogs += "[\(result.state.rawValue)] Switched to Cloud LLM: \(selectedOpenRouterModel)\n"
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

    func restoreKanbanBoard() {
        guard let data = UserDefaults.standard.data(forKey: Self.kanbanDefaultsKey),
              let decoded = try? JSONDecoder().decode([KanbanColumn].self, from: data),
              !decoded.isEmpty else {
            kanbanColumns = KanbanColumn.defaults
            return
        }
        let decodedByID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        kanbanColumns = KanbanColumn.defaults.map { fallback in
            decodedByID[fallback.id] ?? fallback
        }
    }

    func persistKanbanBoard() {
        guard let data = try? JSONEncoder().encode(kanbanColumns) else { return }
        UserDefaults.standard.set(data, forKey: Self.kanbanDefaultsKey)
    }

    var kanbanCards: [KanbanCard] {
        kanbanColumns.flatMap(\.cards)
    }

    var kanbanActiveCardsCount: Int {
        kanbanColumns
            .filter { $0.id != "done" }
            .flatMap(\.cards)
            .count
    }

    var kanbanEditorCanSave: Bool {
        !kanbanEditorTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var kanbanEditorIsEditing: Bool {
        !kanbanEditingCardID.isEmpty
    }

    var activeKanbanDeliveryDestinations: [CronDeliveryDestination] {
        cronDeliveryDestinations.filter { $0.channel == kanbanEditorDeliveryChannel }
    }

    func beginCreateKanbanCard(columnID: String = "backlog") {
        kanbanEditingCardID = ""
        kanbanEditingColumnID = kanbanColumns.contains(where: { $0.id == columnID }) ? columnID : "backlog"
        kanbanEditorTitle = ""
        kanbanEditorDetail = ""
        kanbanEditorPriority = "Normal"
        kanbanEditorAgentID = agents.first(where: { $0.isDefault })?.id ?? "main"
        kanbanEditorCronEnabled = true
        kanbanEditorScheduleKind = "every"
        kanbanEditorScheduleValue = "1d"
        kanbanEditorAtDate = Self.defaultAtDate()
        kanbanEditorTimeZoneID = TimeZone.current.identifier
        kanbanEditorDeliveryMode = "last"
        kanbanEditorDeliveryChannel = activeCronDeliveryChannels.first?.id ?? "telegram"
        kanbanEditorDeliveryAccount = ""
        kanbanEditorDeliveryTo = ""
        kanbanEditorError = ""
        showKanbanTaskEditor = true
        if agents.isEmpty || agentsStatus == "Not loaded" {
            refreshAgents()
        }
        if channels.isEmpty || channelsStatus == "Not loaded" {
            refreshChannels()
        }
    }

    func beginEditKanbanCard(_ card: KanbanCard, columnID: String) {
        kanbanEditingCardID = card.id
        kanbanEditingColumnID = columnID
        kanbanEditorTitle = card.title
        kanbanEditorDetail = card.detail
        kanbanEditorPriority = card.priority
        kanbanEditorAgentID = card.agentID.isEmpty ? "main" : card.agentID
        kanbanEditorCronEnabled = card.cronEnabled
        kanbanEditorScheduleKind = card.scheduleKind.isEmpty ? "every" : card.scheduleKind
        kanbanEditorScheduleValue = card.reviewSchedule.isEmpty ? "1d" : card.reviewSchedule
        kanbanEditorTimeZoneID = card.scheduleTimeZoneID.isEmpty ? TimeZone.current.identifier : card.scheduleTimeZoneID
        kanbanEditorAtDate = Self.cronAtDate(from: kanbanEditorScheduleValue) ?? Self.defaultAtDate()
        if kanbanEditorScheduleKind == "at", Self.cronAtDate(from: kanbanEditorScheduleValue) == nil {
            kanbanEditorScheduleValue = Self.cronAtDateString(kanbanEditorAtDate, timeZoneID: kanbanEditorTimeZoneID)
        }
        kanbanEditorDeliveryMode = card.deliveryMode.isEmpty ? (card.deliveryChannel == "none" ? "none" : (card.deliveryChannel == "last" ? "last" : "channel")) : card.deliveryMode
        kanbanEditorDeliveryChannel = card.deliveryChannel == "last" || card.deliveryChannel == "none" ? (activeCronDeliveryChannels.first?.id ?? "telegram") : card.deliveryChannel
        kanbanEditorDeliveryAccount = card.deliveryAccount
        kanbanEditorDeliveryTo = card.deliveryTo
        kanbanEditorError = ""
        showKanbanTaskEditor = true
        if agents.isEmpty || agentsStatus == "Not loaded" {
            refreshAgents()
        }
        if channels.isEmpty || channelsStatus == "Not loaded" {
            refreshChannels()
        }
    }

    func cancelKanbanTaskEditor() {
        showKanbanTaskEditor = false
        kanbanEditingCardID = ""
        kanbanEditorError = ""
    }

    func saveKanbanTaskEditor() {
        let title = kanbanEditorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            kanbanEditorError = "Task title is required."
            return
        }
        let scheduleValue = kanbanEditorScheduleValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let deliveryChannel = kanbanEditorDeliveryMode == "channel" ? kanbanEditorDeliveryChannel : kanbanEditorDeliveryMode
        let now = Date()
        var savedCardID = ""

        if kanbanEditorIsEditing {
            guard let location = kanbanCardLocation(kanbanEditingCardID) else {
                kanbanEditorError = "This task could not be found anymore."
                return
            }
            kanbanColumns[location.columnIndex].cards[location.cardIndex].title = title
            kanbanColumns[location.columnIndex].cards[location.cardIndex].detail = kanbanEditorDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            kanbanColumns[location.columnIndex].cards[location.cardIndex].priority = kanbanEditorPriority
            kanbanColumns[location.columnIndex].cards[location.cardIndex].agentID = kanbanEditorAgentID
            kanbanColumns[location.columnIndex].cards[location.cardIndex].reviewSchedule = scheduleValue.isEmpty ? "1d" : scheduleValue
            kanbanColumns[location.columnIndex].cards[location.cardIndex].scheduleTimeZoneID = kanbanEditorTimeZoneID
            kanbanColumns[location.columnIndex].cards[location.cardIndex].scheduleKind = kanbanEditorScheduleKind
            kanbanColumns[location.columnIndex].cards[location.cardIndex].cronEnabled = kanbanEditorCronEnabled
            kanbanColumns[location.columnIndex].cards[location.cardIndex].deliveryMode = kanbanEditorDeliveryMode
            kanbanColumns[location.columnIndex].cards[location.cardIndex].deliveryChannel = deliveryChannel
            kanbanColumns[location.columnIndex].cards[location.cardIndex].deliveryAccount = kanbanEditorDeliveryAccount.trimmingCharacters(in: .whitespacesAndNewlines)
            kanbanColumns[location.columnIndex].cards[location.cardIndex].deliveryTo = kanbanEditorDeliveryTo.trimmingCharacters(in: .whitespacesAndNewlines)
            kanbanColumns[location.columnIndex].cards[location.cardIndex].updatedAt = now
            savedCardID = kanbanColumns[location.columnIndex].cards[location.cardIndex].id
            kanbanStatus = "Task updated."
        } else {
            let card = KanbanCard.fresh(
                title: title,
                detail: kanbanEditorDetail.trimmingCharacters(in: .whitespacesAndNewlines),
                priority: kanbanEditorPriority,
                agentID: kanbanEditorAgentID,
                reviewSchedule: scheduleValue.isEmpty ? "1d" : scheduleValue,
                scheduleTimeZoneID: kanbanEditorTimeZoneID,
                scheduleKind: kanbanEditorScheduleKind,
                cronEnabled: kanbanEditorCronEnabled,
                deliveryMode: kanbanEditorDeliveryMode,
                deliveryChannel: deliveryChannel,
                deliveryAccount: kanbanEditorDeliveryAccount.trimmingCharacters(in: .whitespacesAndNewlines),
                deliveryTo: kanbanEditorDeliveryTo.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let targetColumn = kanbanColumns.firstIndex(where: { $0.id == kanbanEditingColumnID }) ?? kanbanColumns.firstIndex(where: { $0.id == "backlog" })
            guard let index = targetColumn else { return }
            kanbanColumns[index].cards.insert(card, at: 0)
            savedCardID = card.id
            kanbanStatus = "Task added to \(kanbanColumns[index].title). It has not started yet."
        }

        showKanbanTaskEditor = false
        kanbanEditingCardID = ""
        kanbanEditorError = ""
        syncKanbanAutomation(cardID: savedCardID)
    }

    func addKanbanCard() {
        let title = kanbanNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            kanbanStatus = "Add a task title first."
            return
        }
        let detail = kanbanNewDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = KanbanCard.fresh(
            title: title,
            detail: detail,
            priority: kanbanNewPriority,
            agentID: kanbanNewAgentID,
            reviewSchedule: kanbanNewSchedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "1d" : kanbanNewSchedule.trimmingCharacters(in: .whitespacesAndNewlines),
            deliveryMode: kanbanNewDeliveryChannel == "none" ? "none" : (kanbanNewDeliveryChannel == "last" ? "last" : "channel"),
            deliveryChannel: kanbanNewDeliveryChannel
        )
        guard let index = kanbanColumns.firstIndex(where: { $0.id == "backlog" }) else { return }
        kanbanColumns[index].cards.insert(card, at: 0)
        kanbanNewTitle = ""
        kanbanNewDetail = ""
        kanbanStatus = "Task added to Backlog. It has not started yet."
    }

    func startKanbanCard(_ cardID: String) {
        guard let location = kanbanCardLocation(cardID),
              let targetColumnIndex = kanbanColumns.firstIndex(where: { $0.id == "doing" }) else { return }
        if location.columnIndex == targetColumnIndex {
            kanbanStatus = "Task is already in progress."
            return
        }
        var card = kanbanColumns[location.columnIndex].cards.remove(at: location.cardIndex)
        card.updatedAt = Date()
        kanbanColumns[targetColumnIndex].cards.insert(card, at: 0)
        kanbanStatus = "Task moved to In Progress. Work starts now."
    }

    func runKanbanCardNow(_ cardID: String) {
        guard let location = kanbanCardLocation(cardID) else { return }
        let card = kanbanColumns[location.columnIndex].cards[location.cardIndex]
        let message = [card.title, card.detail]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !message.isEmpty else {
            kanbanStatus = "Add task details before running this card."
            return
        }

        if !kanbanRunningCardIDs.contains(cardID) {
            startKanbanCard(cardID)
        }
        kanbanRunningCardIDs.insert(cardID)
        kanbanStatus = "Running \(card.title) with \(card.agentID.isEmpty ? "main" : card.agentID)..."

        let command = Self.kanbanRunCommand(
            agentID: card.agentID.isEmpty ? "main" : card.agentID,
            message: message,
            deliveryMode: card.deliveryMode,
            deliveryChannel: card.deliveryChannel,
            deliveryAccount: card.deliveryAccount,
            deliveryTo: card.deliveryTo
        )

        Task.detached {
            let engine = InstallerEngine()
            let result = engine.shell(command)
            let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                self.kanbanRunningCardIDs.remove(cardID)
                if result.0 == 0 {
                    self.moveKanbanCardToReviewIfPossible(cardID)
                    self.kanbanStatus = "Run finished. Review the result."
                } else {
                    self.kanbanStatus = output.isEmpty ? "Run failed." : "Run failed: \(output)"
                }
            }
        }
    }

    nonisolated static func kanbanRunCommand(
        agentID: String,
        message: String,
        deliveryMode: String,
        deliveryChannel: String,
        deliveryAccount: String,
        deliveryTo: String
    ) -> String {
        var args = [
            "openclaw --no-color agent",
            "--agent \(shellSingleQuote(agentID))",
            "--message \(shellSingleQuote(message))",
            "--timeout 600"
        ]

        if deliveryMode != "none" && deliveryChannel != "none" {
            args.append("--deliver")
            if deliveryMode == "last" || deliveryChannel == "last" {
                args.append("--reply-channel last")
            } else {
                args.append("--reply-channel \(shellSingleQuote(deliveryChannel))")
                let account = deliveryAccount.trimmingCharacters(in: .whitespacesAndNewlines)
                let to = deliveryTo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !account.isEmpty {
                    args.append("--reply-account \(shellSingleQuote(account))")
                }
                if !to.isEmpty {
                    args.append("--reply-to \(shellSingleQuote(to))")
                }
            }
        }

        args.append("2>&1")
        return args.joined(separator: " ")
    }

    private func moveKanbanCardToReviewIfPossible(_ cardID: String) {
        guard let location = kanbanCardLocation(cardID),
              let reviewIndex = kanbanColumns.firstIndex(where: { $0.id == "review" }),
              location.columnIndex != reviewIndex else { return }
        var card = kanbanColumns[location.columnIndex].cards.remove(at: location.cardIndex)
        card.updatedAt = Date()
        kanbanColumns[reviewIndex].cards.insert(card, at: 0)
    }

    func reconcileKanbanCompletedAutomations(knownCronJobIDs: Set<String>, now: Date = Date()) {
        guard let doneIndex = kanbanColumns.firstIndex(where: { $0.id == "done" }) else { return }
        var completedCards: [KanbanCard] = []

        for columnIndex in kanbanColumns.indices.reversed() {
            for cardIndex in kanbanColumns[columnIndex].cards.indices.reversed() {
                let card = kanbanColumns[columnIndex].cards[cardIndex]
                guard card.cronEnabled,
                      card.scheduleKind == "at",
                      !card.cronJobID.isEmpty,
                      !knownCronJobIDs.contains(card.cronJobID),
                      let runAt = Self.cronAtDate(from: card.reviewSchedule),
                      runAt <= now else {
                    continue
                }

                var completed = kanbanColumns[columnIndex].cards.remove(at: cardIndex)
                completed.cronJobID = ""
                completed.updatedAt = now
                completedCards.append(completed)
            }
        }

        guard !completedCards.isEmpty else { return }
        for card in completedCards.reversed() {
            kanbanColumns[doneIndex].cards.insert(card, at: 0)
        }
        kanbanStatus = completedCards.count == 1
            ? "\(completedCards[0].title) completed and moved to Done."
            : "\(completedCards.count) scheduled tasks completed and moved to Done."
    }

    func moveKanbanCard(_ cardID: String, direction: Int) {
        guard let location = kanbanCardLocation(cardID) else { return }
        let nextColumnIndex = location.columnIndex + direction
        guard kanbanColumns.indices.contains(nextColumnIndex) else { return }
        var card = kanbanColumns[location.columnIndex].cards.remove(at: location.cardIndex)
        card.updatedAt = Date()
        kanbanColumns[nextColumnIndex].cards.insert(card, at: 0)
        let targetID = kanbanColumns[nextColumnIndex].id
        if targetID == "doing" {
            kanbanStatus = "Moved to In Progress. Work starts now."
        } else if targetID == "done" {
            kanbanStatus = "Moved to Done. Task is complete."
        } else {
            kanbanStatus = "Moved to \(kanbanColumns[nextColumnIndex].title). It is not running."
        }
    }

    func deleteKanbanCard(_ cardID: String) {
        guard let location = kanbanCardLocation(cardID) else { return }
        let cronJobID = kanbanColumns[location.columnIndex].cards[location.cardIndex].cronJobID
        kanbanColumns[location.columnIndex].cards.remove(at: location.cardIndex)
        if !cronJobID.isEmpty {
            Task.detached {
                let engine = InstallerEngine()
                _ = engine.shell("openclaw --no-color cron rm \(Self.shellSingleQuote(cronJobID)) --json 2>&1")
            }
        }
        kanbanStatus = "Task removed."
    }

    func prepareCronFromKanbanCard(_ card: KanbanCard) {
        cronCreateName = card.title
        cronCreateAgentID = card.agentID.isEmpty ? "main" : card.agentID
        cronCreateScheduleKind = card.scheduleKind.isEmpty ? "every" : card.scheduleKind
        cronCreateScheduleValue = card.reviewSchedule.isEmpty ? "1d" : card.reviewSchedule
        cronCreateTimeZoneID = card.scheduleTimeZoneID.isEmpty ? TimeZone.current.identifier : card.scheduleTimeZoneID
        cronCreateAtDate = Self.cronAtDate(from: cronCreateScheduleValue) ?? Self.defaultAtDate()
        if cronCreateScheduleKind == "at", Self.cronAtDate(from: cronCreateScheduleValue) == nil {
            cronCreateScheduleValue = Self.cronAtDateString(cronCreateAtDate, timeZoneID: cronCreateTimeZoneID)
        }
        cronCreateMessage = [card.title, card.detail].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
        cronCreateDeliveryMode = card.cronEnabled ? (card.deliveryMode.isEmpty ? (card.deliveryChannel == "none" ? "none" : (card.deliveryChannel == "last" ? "last" : "channel")) : card.deliveryMode) : "none"
        if cronCreateDeliveryMode == "channel" {
            cronCreateDeliveryChannel = card.deliveryChannel
            cronCreateDeliveryAccount = card.deliveryAccount
            cronCreateDeliveryTo = card.deliveryTo
        } else {
            cronCreateDeliveryAccount = ""
            cronCreateDeliveryTo = ""
        }
        cronCreateError = ""
        showCronJobCreator = true
        kanbanStatus = "Cron form prepared. Click Create Job to schedule it."
    }

    func syncKanbanAutomation(cardID: String) {
        guard kanbanAutomationSyncEnabled else { return }
        guard let location = kanbanCardLocation(cardID) else { return }
        let card = kanbanColumns[location.columnIndex].cards[location.cardIndex]
        guard card.cronEnabled else {
            if !card.cronJobID.isEmpty {
                deleteKanbanAutomationJob(cardID: cardID, jobID: card.cronJobID)
            }
            return
        }
        guard !card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !card.reviewSchedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            kanbanStatus = "Automation needs a schedule."
            return
        }
        if card.deliveryMode == "channel", card.deliveryTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kanbanStatus = "Automation needs a destination for the selected channel."
            return
        }

        kanbanSchedulingCardIDs.insert(cardID)
        kanbanStatus = card.cronJobID.isEmpty ? "Scheduling automation..." : "Updating automation..."
        let command = Self.kanbanCronAddCommand(card: card)
        let previousJobID = card.cronJobID

        Task.detached {
            let engine = InstallerEngine()
            if !previousJobID.isEmpty {
                _ = engine.shell("openclaw --no-color cron rm \(Self.shellSingleQuote(previousJobID)) --json 2>&1")
            }
            let result = engine.shell(command)
            let output = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            let jobID = Self.extractCronJobID(from: output)
            await MainActor.run {
                self.kanbanSchedulingCardIDs.remove(cardID)
                if result.0 == 0, let jobID {
                    self.updateKanbanCard(cardID) { card in
                        card.cronJobID = jobID
                        card.updatedAt = Date()
                    }
                    self.kanbanStatus = "Automation scheduled. It will run at the configured time."
                    self.refreshCronJobs()
                } else if result.0 == 0 {
                    self.kanbanStatus = "Automation scheduled, but LocalClaw could not read the job id."
                    self.refreshCronJobs()
                } else {
                    self.kanbanStatus = output.isEmpty ? "Automation scheduling failed." : "Automation scheduling failed: \(output)"
                }
            }
        }
    }

    private func deleteKanbanAutomationJob(cardID: String, jobID: String) {
        kanbanSchedulingCardIDs.insert(cardID)
        Task.detached {
            let engine = InstallerEngine()
            _ = engine.shell("openclaw --no-color cron rm \(Self.shellSingleQuote(jobID)) --json 2>&1")
            await MainActor.run {
                self.kanbanSchedulingCardIDs.remove(cardID)
                self.updateKanbanCard(cardID) { card in
                    card.cronJobID = ""
                    card.updatedAt = Date()
                }
                self.kanbanStatus = "Automation disabled."
                self.refreshCronJobs()
            }
        }
    }

    nonisolated static func kanbanCronAddCommand(card: KanbanCard) -> String {
        let scheduleFlag: String
        switch card.scheduleKind {
        case "cron": scheduleFlag = "--cron"
        case "at": scheduleFlag = "--at"
        default: scheduleFlag = "--every"
        }
        let message = [card.title, card.detail]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let scheduleValue = normalizedCronScheduleValue(card.reviewSchedule, kind: card.scheduleKind)
        return [
            "openclaw --no-color cron add",
            "--name \(shellSingleQuote(card.title))",
            "--agent \(shellSingleQuote(card.agentID.isEmpty ? "main" : card.agentID))",
            "--message \(shellSingleQuote(message))",
            "--session isolated",
            "\(scheduleFlag) \(shellSingleQuote(scheduleValue))",
            card.scheduleKind == "cron" ? "--tz \(shellSingleQuote(card.scheduleTimeZoneID.isEmpty ? TimeZone.current.identifier : card.scheduleTimeZoneID))" : "",
            card.scheduleKind == "at" ? "--delete-after-run" : "",
            kanbanCronDeliveryArguments(card: card),
            "--json",
            "2>&1"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    nonisolated private static func kanbanCronDeliveryArguments(card: KanbanCard) -> String {
        switch card.deliveryMode {
        case "none":
            return "--no-deliver"
        case "channel":
            var args = [
                "--announce",
                "--channel \(shellSingleQuote(card.deliveryChannel))"
            ]
            let account = card.deliveryAccount.trimmingCharacters(in: .whitespacesAndNewlines)
            let to = card.deliveryTo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !account.isEmpty {
                args.append("--account \(shellSingleQuote(account))")
            }
            if !to.isEmpty {
                args.append("--to \(shellSingleQuote(to))")
            }
            return args.joined(separator: " ")
        default:
            return "--announce --channel last"
        }
    }

    nonisolated static func extractCronJobID(from output: String) -> String? {
        for candidate in jsonObjectCandidates(from: output) {
            if let id = extractCronJobIDFromJSONObject(candidate) {
                return id
            }
        }
        return nil
    }

    nonisolated private static func jsonObjectCandidates(from output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var candidates = [trimmed]
        candidates.append(contentsOf: output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("{") && $0.hasSuffix("}") })
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end {
            candidates.append(String(trimmed[start...end]))
        }
        return Array(Set(candidates))
    }

    nonisolated private static func extractCronJobIDFromJSONObject(_ json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["id", "jobID", "jobId"] {
                if let value = root[key] as? String, !value.isEmpty { return value }
            }
            if let job = root["job"] as? [String: Any] {
                for key in ["id", "jobID", "jobId"] {
                    if let value = job[key] as? String, !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    private func updateKanbanCard(_ cardID: String, mutate: (inout KanbanCard) -> Void) {
        guard let location = kanbanCardLocation(cardID) else { return }
        mutate(&kanbanColumns[location.columnIndex].cards[location.cardIndex])
    }

    private func kanbanCardLocation(_ cardID: String) -> (columnIndex: Int, cardIndex: Int)? {
        for columnIndex in kanbanColumns.indices {
            if let cardIndex = kanbanColumns[columnIndex].cards.firstIndex(where: { $0.id == cardID }) {
                return (columnIndex, cardIndex)
            }
        }
        return nil
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

    var selectedHomeUsageSummary: UsageSummary {
        Self.usageSummary(records: modelUsageRecords, window: selectedHomeUsageWindow)
    }

    nonisolated static func usageSummary(records: [ModelUsageRecord], window: UsageWindow, now: Date = Date(), calendar: Calendar = .current) -> UsageSummary {
        let startOfToday = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -(window.dayCount - 1), to: startOfToday) ?? startOfToday
        let filtered = records.filter { $0.createdAt >= startDate && $0.createdAt <= now }
        return UsageSummary(
            inputTokens: filtered.reduce(0) { $0 + $1.inputTokens },
            outputTokens: filtered.reduce(0) { $0 + $1.outputTokens },
            totalTokens: filtered.reduce(0) { $0 + $1.totalTokens },
            requestCount: filtered.count
        )
    }

    nonisolated static func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
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
        guard chatMemoryEnabled else { return [] }
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
        chatMemoryEnabled = false
        appendChatSystemMessageOnce("Chat memory cleared and paused.")
    }

    struct ChatContextUsage {
        let usedTokens: Int
        let maxTokens: Int

        var fraction: Double {
            guard maxTokens > 0 else { return 0 }
            return min(1, Double(usedTokens) / Double(maxTokens))
        }

        var percent: Int {
            Int((fraction * 100).rounded())
        }

        var label: String {
            "\(percent)% context used  \(InstallerViewModel.compactTokenCount(usedTokens)) / \(InstallerViewModel.compactTokenCount(maxTokens))"
        }
    }

    var chatContextUsage: ChatContextUsage {
        let contextText = chatContextTextForUsage()
        let used = Self.estimatedTokenCount(for: contextText)
        return ChatContextUsage(usedTokens: used, maxTokens: chatContextLimitTokens)
    }

    private var chatContextLimitTokens: Int {
        if inferenceMode == .local || selectedChatModel.hasPrefix("lmstudio/") || currentModel.hasPrefix("lmstudio/") {
            return max(activeLocalLMStudioContext ?? 32768, 16000)
        }
        return 400_000
    }

    private func chatContextTextForUsage() -> String {
        var parts: [String] = []
        let project = chatProjectContext(for: activeChatSessionID)
        if !project.isEmpty { parts.append(project) }
        if chatMemoryEnabled {
            parts.append(contentsOf: chatMemoryPreview)
        }
        parts.append(contentsOf: chatMessages.map { "\($0.role): \($0.text)" })
        let pending = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pending.isEmpty { parts.append("draft: \(pending)") }
        return parts.joined(separator: "\n")
    }

    nonisolated static func estimatedTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return max(1, Int(ceil(Double(trimmed.count) / 4.0)))
    }

    nonisolated static func compactTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 100_000 {
            return "\(tokens / 1000)k"
        }
        if tokens >= 1_000 {
            return String(format: "%.1fk", Double(tokens) / 1000)
        }
        return "\(tokens)"
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
        let selectedModelLooksCloud = selectedModelForRequest.hasPrefix("openrouter/") || Self.isOAuthRuntimeModelID(selectedModelForRequest)
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
            let engine = InstallerEngine()
            if shouldPrepareGateway {
                await MainActor.run {
                    if self.activeChatRequestID == requestID {
                        self.chatStatus = "Preparing OpenClaw..."
                    }
                }
                _ = engine.shell("openclaw gateway status >/dev/null 2>&1 || openclaw gateway start >/dev/null 2>&1 || true")
            }
            if !modelOverride.isEmpty {
                let allowResult = engine.ensureModelAllowedInConfig(modelIdentifier: modelOverride)
                if allowResult.state == .fail {
                    await MainActor.run {
                        let errorMessage = ChatMessage(role: "error", text: allowResult.message)
                        if useDeveloperSession { self.developerChatMessages.append(errorMessage) } else { self.chatMessages.append(errorMessage) }
                        self.chatStatus = "Error"
                        self.chatIsSending = false
                    }
                    return
                }
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

            let runtimeTurnID = (!useDeveloperSession || useFreshDeveloperContext || requestInferenceMode == .local)
                ? String(requestID.uuidString.prefix(8))
                : nil
            let runtimeSessionID = Self.runtimeSessionID(
                base: sessionID,
                modelID: modelOverride,
                useDeveloperSession: useDeveloperSession,
                freshTurnID: runtimeTurnID
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
        let showingOAuthModels = inferenceMode == .oauth || selectedCloudAuthMode == .oauth
        if !current.isEmpty && !current.lowercased().contains("not configured") {
            let currentID = Self.normalizedChatModelID(current, inferenceMode: inferenceMode, localModels: localLMStudioModels)
            let currentIsLocal = currentID.hasPrefix("lmstudio/") || localLMStudioModels.contains(currentID)
            let currentIsOAuth = Self.isOAuthRuntimeModelID(currentID)
            if showingOAuthModels, currentIsOAuth {
                models.append(OpenRouterModel(id: currentID, displayName: Self.readableModelName(currentID)))
            } else if !showingOAuthModels, currentIsLocal == showingLocalModels {
                models.append(OpenRouterModel(id: currentID, displayName: Self.readableModelName(currentID)))
            }
        }

        if showingOAuthModels {
            models.append(contentsOf: Self.oauthFallbackModels)
            models.append(contentsOf: oauthModelsLive)
        } else if showingLocalModels {
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
        } else if inferenceMode == .oauth || selectedCloudAuthMode == .oauth {
            prepareOAuthModelSelection()
        } else {
            prepareCloudModelSelection()
        }
    }

    func prepareOAuthModelSelection() {
        inferenceMode = .oauth
        selectedProvider = .openAI
        selectedCloudAuthMode = .oauth
        openAIAuthMethod = .oauth
        if oauthModelsLive.isEmpty {
            refreshOAuthModels()
        }
        if !Self.isOAuthRuntimeModelID(selectedChatModel) {
            selectedChatModel = Self.oauthFallbackModels.first?.id ?? selectedOAuthProviderOption.modelIdentifier
        }
        currentModel = selectedChatModel
    }

    func prepareCloudModelSelection() {
        inferenceMode = .cloud
        selectedProvider = .openRouter
        let cloudModels = openRouterModelsLive.isEmpty ? Self.openRouterModels : openRouterModelsLive
        if !cloudModels.contains(where: { $0.id == selectedOpenRouterModel }) {
            selectedOpenRouterModel = cloudModels.first?.id ?? "openrouter/openai/gpt-5.4-mini"
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
        } else if Self.isOAuthRuntimeModelID(model) {
            selectedChatResponseMode = .cloud
            inferenceMode = .oauth
            selectedProvider = .openAI
            selectedCloudAuthMode = .oauth
            openAIAuthMethod = .oauth
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
        if !localModel.isEmpty {
            selectedLocalLMStudioModel = localModel
            autoSetupLocalLMStudioModel(modelId: localModel, source: useDeveloperSession ? .developer : .chat)
            return
        }

        if Self.isOAuthRuntimeModelID(model) {
            guard requireOAuthAuthBeforeBackendUse(status: "OAuth login required before using this model.") else {
                chatStatus = "OAuth login required"
                let message = ChatMessage(role: "assistant", text: "Connect OAuth first, then select the OAuth model again.", modelName: "LocalClaw")
                if useDeveloperSession {
                    developerChatMessages.append(message)
                } else {
                    chatMessages.append(message)
                }
                return
            }
            let oauthModel = selectedOAuthModelIdentifier()
            selectedChatResponseMode = .cloud
            inferenceMode = .oauth
            selectedProvider = .openAI
            selectedCloudAuthMode = .oauth
            openAIAuthMethod = .oauth
            selectedChatModel = oauthModel
            currentModel = oauthModel
            chatGatewayPrepared = false
            resetMainAgentSessions()

            Task.detached {
                let engine = InstallerEngine()
                let result = engine.changeModel(oauthModel)
                await MainActor.run {
                    self.chatStatus = result.state == .ok ? "Ready" : "OAuth config error"
                    if result.state != .ok {
                        let message = ChatMessage(role: "error", text: result.message, modelName: "LocalClaw")
                        if useDeveloperSession {
                            self.developerChatMessages.append(message)
                        } else {
                            self.chatMessages.append(message)
                        }
                    }
                }
            }
            return
        }

        let cloudModel = Self.canonicalChatRuntimeModelID(Self.normalizedChatModelID(
            model,
            inferenceMode: .cloud,
            localModels: localLMStudioModels
        ))
        guard cloudModel.hasPrefix("openrouter/") else { return }

        selectedChatResponseMode = .cloud
        inferenceMode = .cloud
        selectedProvider = .openRouter
        selectedCloudAuthMode = .api
        selectedOpenRouterModel = cloudModel
        selectedChatModel = cloudModel
        currentModel = cloudModel
        chatGatewayPrepared = false
        resetMainAgentSessions()

        Task.detached {
            let engine = InstallerEngine()
            let result = engine.writeModelToConfig(modelIdentifier: cloudModel)
            _ = engine.ensureModelAllowedInConfig(modelIdentifier: cloudModel)
            await MainActor.run {
                if result.state == .ok {
                    self.chatStatus = "Ready"
                } else {
                    self.chatStatus = "Model config error"
                    let message = ChatMessage(role: "error", text: result.message, modelName: "LocalClaw")
                    if useDeveloperSession {
                        self.developerChatMessages.append(message)
                    } else {
                        self.chatMessages.append(message)
                    }
                }
            }
        }
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
            let loadedInfo = InstallerEngine().loadedLMStudioModelInfo()
            let loaded = loadedInfo?.model
            await MainActor.run {
                guard self.localLMStudioSetupRequestID == requestID else { return }
                self.localLMStudioSetupRequestID = nil
                self.localLMStudioSetupInProgress = false
                self.localLMStudioSetupStatus = result.message
                if result.state == .ok {
                    let active = loaded ?? modelId
                    self.currentModel = "lmstudio/\(active)"
                    self.activeLocalLMStudioModel = active
                    self.activeLocalLMStudioContext = loadedInfo?.context
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
        if trimmed.hasPrefix("openrouter/") || isOAuthRuntimeModelID(trimmed) { return "" }
        return trimmed
    }

    nonisolated static func isOAuthRuntimeModelID(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("openai-codex/")
            || trimmed.hasPrefix("openai/")
            || trimmed.hasPrefix("google-gemini-cli/")
            || trimmed.hasPrefix("github-copilot/")
    }

    nonisolated static func canonicalChatRuntimeModelID(_ id: String) -> String {
        repairedLegacyCloudModelID(id)
    }

    nonisolated static func repairedLegacyCloudModelID(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "openrouter/moonshotai/kimi-k2.5" || lower == "moonshot/kimi-k2.5" || lower == "moonshotai/kimi-k2.5" {
            return "openrouter/openai/gpt-5.4-mini"
        }
        return trimmed
    }

    nonisolated static func runtimeSessionID(base: String, modelID: String, useDeveloperSession: Bool, freshTurnID: String? = nil) -> String {
        if !useDeveloperSession {
            guard let freshTurnID, !freshTurnID.isEmpty else { return base }
            return "\(base)-turn-\(freshTurnID)"
        }
        let cleanModel = modelID
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
        }
        let suffix = String(String(cleanModel).split(separator: "-").joined(separator: "-").prefix(72))
        let modelScoped = suffix.isEmpty ? base : "\(base)-\(suffix)"
        guard let freshTurnID, !freshTurnID.isEmpty else { return modelScoped }
        return "\(modelScoped)-turn-\(freshTurnID)"
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
                return 600
            case .local:
                return 420
            case .cloud:
                return 420
            }
        }
        switch mode {
        case .fast:
            return 60
        case .deep:
            return 600
        case .local:
            return 420
        case .cloud:
            return 420
        }
    }

    nonisolated static func wallClockTimeoutSeconds(forAgentTimeout timeout: Int) -> Int {
        min(max(timeout + 120, 90), 900)
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
            (["yellow"], "yellow", ["#181107", "#fef3c7", "#fde68a", "#facc15", "#eab308", "#ca8a04", "#854d0e"]),
            (["violet", "purple"], "purple", ["#120a24", "#f5f3ff", "#ddd6fe", "#c084fc", "#a855f7", "#7c3aed", "#4c1d95"]),
            (["blue"], "blue", ["#07111f", "#eff6ff", "#bfdbfe", "#60a5fa", "#2563eb", "#1d4ed8", "#172554"]),
            (["green"], "green", ["#06140d", "#ecfdf5", "#bbf7d0", "#4ade80", "#16a34a", "#15803d", "#14532d"]),
            (["red"], "red", ["#1f0909", "#fef2f2", "#fecaca", "#f87171", "#ef4444", "#b91c1c", "#7f1d1d"]),
            (["orange"], "orange", ["#1c0f05", "#fff7ed", "#fed7aa", "#fb923c", "#f97316", "#c2410c", "#7c2d12"]),
            (["pink"], "pink", ["#1f0713", "#fdf2f8", "#fbcfe8", "#f472b6", "#ec4899", "#be185d", "#831843"]),
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

        let namedColors = ["purple", "violet", "yellow", "blue", "green", "red", "orange", "pink", "turquoise", "cyan"]
        for color in namedColors where color != palette.name {
            result = result.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: color))\\b", with: palette.name, options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    nonisolated static func isSimpleDeveloperEdit(_ text: String) -> Bool {
        let clean = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let editWords = ["change", "replace", "set", "update", "modify", "color", "theme", "css", "style", "title", "text", "button"]
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
            let suffix = "LocalClaw stopped this developer request after \(timeoutSeconds ?? 0)s because it exceeded the time budget. OpenClaw itself may still be running; check Gateway status before restarting."
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
            let suffix = "LocalClaw stopped this chat request after \(timeoutSeconds ?? 0)s because it exceeded the time budget. OpenClaw itself may still be running; check Gateway status before restarting."
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

    func pasteChatImageFromClipboard() {
        guard let image = Self.imageFromPasteboard(NSPasteboard.general) else {
            chatStatus = "No image in clipboard"
            return
        }

        do {
            chatImagePath = try Self.saveClipboardImage(image)
            chatStatus = "Image pasted"
        } catch {
            chatStatus = "Could not paste image: \(error.localizedDescription)"
        }
    }

    nonisolated static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            return image
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] where pasteboard.data(forType: type) != nil {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }

    nonisolated static func saveClipboardImage(_ image: NSImage) throws -> String {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LocalClawClipboardImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Clipboard image could not be converted to PNG"])
        }

        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".localclaw-installer", isDirectory: true)
            .appendingPathComponent("chat-images", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "pasted-image-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).png"
        let url = dir.appendingPathComponent(filename)
        try png.write(to: url, options: .atomic)
        return url.path
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
            let loadedInfo = engine.loadedLMStudioModelInfo()
            let loaded = loadedInfo?.model
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
                self.activeLocalLMStudioContext = loadedInfo?.context
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
        let loadedInfo = engine.loadedLMStudioModelInfo()
        let loaded = loadedInfo?.model
        localLMStudioModels = models
        activeLocalLMStudioModel = loaded ?? ""
        activeLocalLMStudioContext = loadedInfo?.context
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
        if localLMStudioRepairInProgress || localLMStudioSetupInProgress { return }
        if selectedLocalLMStudioModel.isEmpty {
            refreshLocalLMStudioModels()
        }
        let modelId = Self.localLMStudioModelID(from: selectedLocalLMStudioModel)
        guard !modelId.isEmpty else {
            localLMStudioSetupStatus = "No local model found in LM Studio"
            chatStatus = "Needs setup"
            return
        }

        let requestID = UUID()
        localLMStudioSetupRequestID = requestID
        localLMStudioRepairInProgress = true
        localLMStudioSetupInProgress = true
        selectedChatResponseMode = .local
        selectedLocalLMStudioModel = modelId
        localLMStudioSetupStatus = "Repairing LM Studio runtime..."
        let firstLine = "• Repairing LM Studio runtime for \(modelId)"
        localLMStudioSetupLog = localLMStudioSetupLog.isEmpty ? firstLine : localLMStudioSetupLog + "\n" + firstLine
        chatStatus = "Repairing LM Studio..."
        Task.detached {
            let engine = InstallerEngine()
            let repair = engine.repairLMStudioRuntime()
            guard repair.state == .ok else {
                await MainActor.run {
                    guard self.localLMStudioSetupRequestID == requestID else { return }
                    self.localLMStudioSetupRequestID = nil
                    self.localLMStudioRepairInProgress = false
                    self.localLMStudioSetupInProgress = false
                    self.localLMStudioSetupStatus = repair.message
                    self.chatStatus = "Error"
                    self.appendChatSystemMessageOnce("I couldn’t repair LM Studio automatically: \(repair.message)")
                    self.refreshLocalLMStudioModels()
                }
                return
            }

            await MainActor.run {
                guard self.localLMStudioSetupRequestID == requestID else { return }
                let line = "• \(repair.message)"
                self.localLMStudioSetupLog = self.localLMStudioSetupLog.isEmpty ? line : self.localLMStudioSetupLog + "\n" + line
                self.localLMStudioSetupStatus = "Repair finished. Loading \(modelId)..."
                self.chatStatus = "Setting up local model..."
            }

            let setup = engine.autoSetupLMStudioModel(modelId: modelId, contextLength: 32768) { message in
                DispatchQueue.main.async {
                    guard self.localLMStudioSetupRequestID == requestID else { return }
                    let line = "• \(message)"
                    self.localLMStudioSetupStatus = message
                    self.localLMStudioSetupLog = self.localLMStudioSetupLog.isEmpty ? line : self.localLMStudioSetupLog + "\n" + line
                }
            }
            let loadedInfo = engine.loadedLMStudioModelInfo()
            let loaded = loadedInfo?.model

            await MainActor.run {
                guard self.localLMStudioSetupRequestID == requestID else { return }
                self.localLMStudioSetupRequestID = nil
                self.localLMStudioRepairInProgress = false
                self.localLMStudioSetupInProgress = false
                self.localLMStudioSetupStatus = setup.message
                if setup.state == .ok {
                    let active = loaded ?? modelId
                    self.currentModel = "lmstudio/\(active)"
                    self.activeLocalLMStudioModel = active
                    self.activeLocalLMStudioContext = loadedInfo?.context
                    self.selectedLocalLMStudioModel = active
                    self.selectedChatResponseMode = .local
                    self.selectedChatModel = "lmstudio/\(active)"
                    self.chatGatewayPrepared = false
                    self.resetMainAgentSessions()
                    self.chatStatus = "Ready"
                    self.localLMStudioSetupStatus = "LM Studio repaired and ready with \(active)"
                    self.appendChatSystemMessageOnce("LM Studio repaired and local model ready: \(active).")
                } else {
                    self.chatStatus = "Needs setup"
                    self.appendChatSystemMessageOnce("LM Studio repair finished, but local setup failed: \(setup.message)")
                }
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
        if command -v node &>/dev/null && node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)' &>/dev/null; then
            echo "  ✓ Node $(node --version) ready"
        else
            echo "  → Installing/upgrading Node.js 22.19+..."
            brew upgrade node || brew install node
            if ! command -v node &>/dev/null || ! node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)' &>/dev/null; then
                echo "  ✗ Node 22.19+ is required for OpenClaw"
                exit 1
            fi
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
        export GATEWAY_TOKEN="\(gatewayToken)"
        export LOCALCLAW_MODEL_ID="\(effectiveModelIdentifier())"
        export OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
        node <<'NODE'
        const fs = require("fs");
        const path = process.env.OPENCLAW_CONFIG;
        let config = {};
        try {
          if (fs.existsSync(path)) config = JSON.parse(fs.readFileSync(path, "utf8"));
        } catch {}
        config.gateway = {
          ...(config.gateway || {}),
          mode: "local",
          port: 18789,
          bind: "loopback",
          auth: {
            ...((config.gateway && config.gateway.auth) || {}),
            mode: "token",
            token: process.env.GATEWAY_TOKEN || ""
          }
        };
        config.agents = config.agents || {};
        config.agents.defaults = config.agents.defaults || {};
        config.agents.defaults.model = {
          ...(config.agents.defaults.model || {}),
          primary: process.env.LOCALCLAW_MODEL_ID || ""
        };
        fs.writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
        NODE
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
            lines.append("    echo \"  → Installing or repairing LM Studio (this takes 5+ min)...\"")
            lines.append("    if brew list --cask lm-studio >/dev/null 2>&1; then")
            lines.append("        echo \"  → Homebrew knows lm-studio, but the app is missing. Reinstalling cleanly...\"")
            lines.append("        brew reinstall --cask lm-studio || brew uninstall --cask --force lm-studio || true")
            lines.append("    fi")
            lines.append("    if [ ! -d \"/Applications/LM Studio.app\" ]; then")
            lines.append("        brew install --cask lm-studio || brew reinstall --cask lm-studio")
            lines.append("    fi")
            lines.append("fi")
            lines.append("if [ -d \"/Applications/LM Studio.app\" ]; then")
            lines.append("    echo \"lmstudio:OK\" >> /tmp/localclaw_status")
            lines.append("else")
            lines.append("    echo \"  ⚠ LM Studio app still missing, but continuing if the lms CLI is available.\"")
            lines.append("    echo \"lmstudio:WARN\" >> /tmp/localclaw_status")
            lines.append("fi")
            lines.append("")
            lines.append("echo \"\"")
            lines.append("echo \"[3/7] Downloading AI Model...\"")
            lines.append("run_lms() {")
            lines.append("  if command -v lms >/dev/null 2>&1; then")
            lines.append("    lms \"$@\"")
            lines.append("  elif [ -x \"/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms\" ]; then")
            lines.append("    \"/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms\" \"$@\"")
            lines.append("  else")
            lines.append("    echo \"  ✕ LM Studio CLI not found. Open LM Studio once, then retry installation.\"")
            lines.append("    return 127")
            lines.append("  fi")
            lines.append("}")
            lines.append("LOCAL_MODEL_ID=\(shellSingleQuote(providerModelId))")
            lines.append("LOCAL_MODEL_NAME=\(shellSingleQuote(resolvedLocalModel))")
            lines.append("download_model_candidate() {")
            lines.append("  local query=\"$1\"")
            lines.append("  local provider_id=\"$2\"")
            lines.append("  local display_name=\"$3\"")
            lines.append("  [ -z \"$query\" ] && return 1")
            lines.append("  echo \"  → Checking LM Studio recommendation: $display_name ($query)\"")
            lines.append("  if run_lms get \"$query\" --gguf -y; then")
            lines.append("    LOCAL_MODEL_ID=\"$provider_id\"")
            lines.append("    LOCAL_MODEL_NAME=\"$display_name\"")
            lines.append("    return 0")
            lines.append("  fi")
            lines.append("  if [[ \"$query\" == *@* ]]; then")
            lines.append("    local base_query=\"${query%@*}\"")
            lines.append("    echo \"  → Exact quant unavailable. Asking LM Studio for best variant: $base_query\"")
            lines.append("    if run_lms get \"$base_query\" --gguf -y; then")
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
        lines.append("if command -v node &>/dev/null && node -e 'const [major, minor] = process.versions.node.split(\".\").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)' &>/dev/null; then")
        lines.append("    echo \"  ✓ Node $(node --version) ready\"")
        lines.append("    echo \"node:OK\" >> /tmp/localclaw_status")
        lines.append("else")
        lines.append("    echo \"  → Installing/upgrading Node.js 22.19+...\"")
        lines.append("    brew upgrade node || brew install node")
        lines.append("    if ! command -v node &>/dev/null || ! node -e 'const [major, minor] = process.versions.node.split(\".\").map(Number); process.exit(major > 22 || (major === 22 && minor >= 19) ? 0 : 1)' &>/dev/null; then")
        lines.append("        echo \"  ✗ Node 22.19+ is required for OpenClaw\"")
        lines.append("        echo \"node:FAIL\" >> /tmp/localclaw_status")
        lines.append("        exit 1")
        lines.append("    fi")
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
        lines.append("export GATEWAY_TOKEN")
        lines.append("echo \"$GATEWAY_TOKEN\" > /tmp/localclaw_token")
        if installLMStudio {
            lines.append("export LOCAL_MODEL_ID")
            lines.append("export LOCAL_MODEL_NAME")
            lines.append("LOCALCLAW_MODEL_ID=\"lmstudio/${LOCAL_MODEL_ID}\"")
            lines.append("export LOCALCLAW_MODEL_ID")
            lines.append("LOCALCLAW_LMSTUDIO=\"1\"")
            lines.append("export LOCALCLAW_LMSTUDIO")
        } else {
            lines.append("LOCALCLAW_MODEL_ID=\(shellSingleQuote(modelId))")
            lines.append("export LOCALCLAW_MODEL_ID")
            lines.append("LOCALCLAW_LMSTUDIO=\"0\"")
            lines.append("export LOCALCLAW_LMSTUDIO")
        }
        lines.append("OPENCLAW_CONFIG=\"$HOME/.openclaw/openclaw.json\"")
        lines.append("export OPENCLAW_CONFIG")
        lines.append("node <<'NODE'")
        lines.append("const fs = require(\"fs\");")
        lines.append("const path = process.env.OPENCLAW_CONFIG;")
        lines.append("let config = {};")
        lines.append("try {")
        lines.append("  if (fs.existsSync(path)) config = JSON.parse(fs.readFileSync(path, \"utf8\"));")
        lines.append("} catch {}")
        lines.append("config.gateway = {")
        lines.append("  ...(config.gateway || {}),")
        lines.append("  mode: \"local\",")
        lines.append("  port: 18789,")
        lines.append("  bind: \"loopback\",")
        lines.append("  auth: {")
        lines.append("    ...((config.gateway && config.gateway.auth) || {}),")
        lines.append("    mode: \"token\",")
        lines.append("    token: process.env.GATEWAY_TOKEN || \"\"")
        lines.append("  }")
        lines.append("};")
        lines.append("config.agents = config.agents || {};")
        lines.append("config.agents.defaults = config.agents.defaults || {};")
        lines.append("config.agents.defaults.model = {")
        lines.append("  ...(config.agents.defaults.model || {}),")
        lines.append("  primary: process.env.LOCALCLAW_MODEL_ID || \"\"")
        lines.append("};")
        lines.append("config.agents.defaults.sandbox = {")
        lines.append("  ...(config.agents.defaults.sandbox || {}),")
        lines.append("  mode: \"off\"")
        lines.append("};")
        lines.append("if (process.env.LOCALCLAW_LMSTUDIO === \"1\") {")
        lines.append("  config.models = config.models || {};")
        lines.append("  config.models.mode = config.models.mode || \"merge\";")
        lines.append("  config.models.providers = config.models.providers || {};")
        lines.append("  const lmstudio = config.models.providers.lmstudio || {};")
        lines.append("  lmstudio.baseUrl = \"http://127.0.0.1:1234/v1\";")
        lines.append("  lmstudio.apiKey = \"lmstudio\";")
        lines.append("  lmstudio.api = \"openai-completions\";")
        lines.append("  const localModel = { id: process.env.LOCAL_MODEL_ID || \"\", name: process.env.LOCAL_MODEL_NAME || process.env.LOCAL_MODEL_ID || \"Local model\", reasoning: false, input: [\"text\"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 32768, maxTokens: 4096 };")
        lines.append("  const models = Array.isArray(lmstudio.models) ? lmstudio.models.filter((model) => model.id !== localModel.id) : [];")
        lines.append("  if (localModel.id) models.unshift(localModel);")
        lines.append("  lmstudio.models = models;")
        lines.append("  config.models.providers.lmstudio = lmstudio;")
        lines.append("  config.tools = config.tools || {};")
        lines.append("  const deny = new Set(Array.isArray(config.tools.deny) ? config.tools.deny : []);")
        lines.append("  for (const item of [\"group:web\", \"browser\", \"web_search\", \"web_fetch\"]) deny.add(item);")
        lines.append("  config.tools.deny = Array.from(deny);")
        lines.append("}")
        lines.append("fs.writeFileSync(path, JSON.stringify(config, null, 2) + \"\\n\");")
        lines.append("NODE")
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

    struct UninstallSelectionItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let dangerous: Bool
    }

    private final class UninstallConfirmationDelegate: NSObject, NSTextFieldDelegate {
        private weak var input: NSTextField?
        private weak var confirmButton: NSButton?

        init(input: NSTextField, confirmButton: NSButton?) {
            self.input = input
            self.confirmButton = confirmButton
        }

        func controlTextDidChange(_ notification: Notification) {
            confirmButton?.isEnabled = input?.stringValue == "UNINSTALL"
        }
    }

    var selectedUninstallItems: [UninstallSelectionItem] {
        var items: [UninstallSelectionItem] = []
        if uninstallLMStudioSelected {
            items.append(UninstallSelectionItem(
                id: "lm-studio",
                title: "LM Studio app",
                detail: "LM Studio application and LM Studio runtime cache",
                dangerous: false
            ))
        }
        if uninstallModelsSelected {
            items.append(UninstallSelectionItem(
                id: "local-models",
                title: "Local LLM models",
                detail: "Downloaded model files in ~/.lmstudio/models and ~/.cache/lm-studio/models",
                dangerous: true
            ))
        }
        if uninstallOpenClawSelected {
            items.append(UninstallSelectionItem(
                id: "openclaw",
                title: "OpenClaw CLI and services",
                detail: "OpenClaw CLI, gateway service files, agents, and OpenClaw cache",
                dangerous: true
            ))
        }
        if uninstallNodeSelected {
            items.append(UninstallSelectionItem(
                id: "node",
                title: "Node.js and npm/npx",
                detail: "Node.js binaries, npm/npx/corepack links, ~/.npm, ~/.nvm, and ~/.node-gyp",
                dangerous: false
            ))
        }
        if uninstallHomebrewSelected {
            items.append(UninstallSelectionItem(
                id: "homebrew",
                title: "Homebrew",
                detail: "Homebrew itself using the official Homebrew uninstall script",
                dangerous: true
            ))
        }
        if uninstallConfigsSelected {
            items.append(UninstallSelectionItem(
                id: "configs",
                title: "Configs and cache",
                detail: "~/.openclaw, ~/.openclaw-gateway, ~/.cache/openclaw, ~/.cache/lm-studio, and OpenClaw/nvm shell entries",
                dangerous: true
            ))
        }
        return items
    }

    var uninstallSelectedCount: Int {
        selectedUninstallItems.count
    }

    var hasUninstallSelection: Bool {
        uninstallSelectedCount > 0
    }

    var uninstallPrimaryButtonTitle: String {
        if isUninstalling { return "Working..." }
        if uninstallSelectedCount == 0 { return "Select items to uninstall" }
        return "Uninstall \(uninstallSelectedCount) selected item\(uninstallSelectedCount == 1 ? "" : "s")"
    }

    func prepareUninstallCenter() {
        resetUninstallSelection()
        refreshUninstallInventory()
    }

    func resetUninstallSelection() {
        uninstallLMStudioSelected = false
        uninstallModelsSelected = false
        uninstallOpenClawSelected = false
        uninstallNodeSelected = false
        uninstallHomebrewSelected = false
        uninstallConfigsSelected = false
    }

    func confirmAndRunSelectedUninstall() {
        if isUninstalling || !hasUninstallSelection { return }
        let items = selectedUninstallItems
        guard confirmSelectedUninstall(items: items) else { return }
        runSelectedUninstall()
    }

    private func confirmSelectedUninstall(items: [UninstallSelectionItem]) -> Bool {
        let count = items.count
        let itemList = items.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Confirm uninstall"
        alert.informativeText = """
        LocalClaw will remove exactly these selected items:

        \(itemList)

        Type UNINSTALL to enable the final button.
        """
        alert.addButton(withTitle: "Uninstall \(count) selected item\(count == 1 ? "" : "s")")
        alert.addButton(withTitle: "Cancel")

        let confirmButton = alert.buttons.first
        confirmButton?.isEnabled = false

        let label = NSTextField(wrappingLabelWithString: "Required confirmation:")
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let input = NSTextField(string: "")
        input.placeholderString = "UNINSTALL"

        let stack = NSStackView(views: [label, input])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 360),
            input.widthAnchor.constraint(equalToConstant: 360)
        ])

        let delegate = UninstallConfirmationDelegate(input: input, confirmButton: confirmButton)
        input.delegate = delegate

        alert.accessoryView = stack
        return alert.runModal() == .alertFirstButtonReturn
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
            ("OpenClaw CLI and services", uninstallOpenClawSelected, [
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
                self.resetUninstallSelection()
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
        case .kanban: return 0
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
    @State private var pasteEventMonitor: Any?
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
                            case .kanban: kanbanCenter
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenModelsCenter"))) { _ in
            vm.screen = .models
        }
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in
            if vm.screen == .kanban, vm.hasScheduledKanbanAutomation, !vm.cronJobsIsLoading {
                vm.refreshCronJobs(silent: true)
            }
        }
        .frame(minWidth: 1100, idealWidth: 1440, maxWidth: .infinity,
               minHeight: 760, idealHeight: 920, maxHeight: .infinity)
        .preferredColorScheme(appearance == "light" ? .light : .dark)
        .onAppear {
            vm.bootstrap()
            installClipboardImagePasteShortcutIfNeeded()
        }
        .onDisappear {
            if let pasteEventMonitor {
                NSEvent.removeMonitor(pasteEventMonitor)
                self.pasteEventMonitor = nil
            }
        }
        .sheet(isPresented: $vm.showCronJobCreator) {
            cronJobCreatorSheet
        }
        .sheet(isPresented: $vm.showKanbanTaskEditor) {
            kanbanTaskEditorSheet
        }
        .sheet(item: $vm.cronDeleteCandidate) { job in
            cronJobDeleteSheet(job)
        }
        .sheet(isPresented: $vm.showOAuthSetupAssistant) {
            oauthSetupAssistantSheet
        }
        .alert("Homebrew Required", isPresented: $vm.showHomebrewPrompt) {
            Button("Install Homebrew", role: .none) { vm.installHomebrewWithUserConsent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Homebrew is needed to install LM Studio, Node.js and OpenClaw. Click 'Install Homebrew' and enter your Mac password when prompted.")
        }
        .alert("Delete this agent?", isPresented: $vm.showAgentDeleteConfirmation) {
            Button("Delete Agent", role: .destructive) { vm.deletePendingAgent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deleting \(vm.agentDeleteCandidateName.isEmpty ? vm.agentDeleteCandidateID : vm.agentDeleteCandidateName) also removes its OpenClaw state/workspace and any routes that depend on it. This cannot be undone.")
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
                .onChange(of: vm.inferenceMode) { newValue in
                    vm.selectInferenceModeFromUser(newValue)
                    if newValue == .oauth && !vm.cloudProviderAuthConfigured {
                        return
                    }
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

    private var oauthSetupAssistantSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: vm.cloudProviderAuthConfigured ? "checkmark.seal.fill" : "person.badge.key.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(vm.cloudProviderAuthConfigured ? Color(NSColor.systemGreen) : UI.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.cloudProviderAuthConfigured ? "OAuth LLM is connected" : "Connect OAuth LLM")
                        .font(AppFont.heading(24))
                        .foregroundStyle(UI.text)
                    Text(vm.cloudProviderAuthConfigured ? "LocalClaw found an OAuth profile in OpenClaw." : "Use your ChatGPT/Codex account without pasting an API key.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                oauthSheetStep(number: 1, title: "Start login", detail: "LocalClaw opens Terminal and runs the OpenClaw OAuth login command.")
                oauthSheetStep(number: 2, title: "Approve in browser", detail: "Finish the ChatGPT/Codex login flow in the browser window.")
                oauthSheetStep(number: 3, title: "Check connection", detail: "Come back here and verify that OpenClaw saved the OAuth profile.")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.lineSoft, lineWidth: 1))

            HStack(spacing: 8) {
                Text(vm.oauthSetupStatus)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(vm.cloudProviderAuthConfigured ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
                Spacer()
                Text(vm.selectedOAuthModelIdentifier())
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    vm.showOAuthSetupAssistant = false
                }
                .buttonStyle(CTAButton(primary: false))

                Spacer()

                Button("Check connection") {
                    vm.refreshOAuthAuthStatus()
                    if vm.cloudProviderAuthConfigured {
                        vm.showOAuthSetupAssistant = false
                        vm.refreshOAuthModels()
                        vm.applyInferenceModeSwitch()
                    }
                }
                .buttonStyle(CTAButton(primary: false))

                Button(vm.cloudProviderAuthConfigured ? "Done" : "Start OAuth Login") {
                    if vm.cloudProviderAuthConfigured {
                        vm.showOAuthSetupAssistant = false
                    } else {
                        vm.startOAuthLoginFromAssistant()
                    }
                }
                .buttonStyle(CTAButton(primary: true))
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(UI.bg)
    }

    private func oauthSheetStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.text)
                .frame(width: 22, height: 22)
                .background(Circle().fill(UI.accent.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                Text(detail)
                    .font(AppFont.body(11))
                    .foregroundStyle(UI.muted)
            }
        }
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
            sidebarButton("Kanban", icon: "rectangle.3.group", isActive: vm.screen == .kanban, isBeta: true) { vm.screen = .kanban }
            sidebarButton("Help", icon: "cross.case", isActive: vm.screen == .healthCenter) { vm.screen = .healthCenter }
            sidebarButton("Uninstall", icon: "trash", isActive: vm.screen == .uninstallCenter) { vm.screen = .uninstallCenter }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("OPENCLAW VERSION")
                        .font(AppFont.heading(10))
                        .kerning(1.0)
                        .foregroundStyle(UI.muted)
                    Spacer()
                    Circle()
                        .fill(vm.openclawInstalledVersion == "Not installed" ? Color(NSColor.systemRed) : Color(NSColor.systemGreen))
                        .frame(width: 11, height: 11)
                }
                Text(openClawSidebarVersionLabel)
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))

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

    private var openClawSidebarVersionLabel: String {
        let version = vm.openclawInstalledVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.isEmpty || version == "Checking..." { return "Checking..." }
        if version == "Not installed" { return "Not installed" }
        return version.hasPrefix("v") ? version : "v\(version)"
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
                        Text("Live dashboard for your OpenClaw setup: health, token usage, channels, active model, and recent events.")
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
                    dashboardUsageKpiCard()
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

    private func dashboardUsageKpiCard() -> some View {
        let summary = vm.selectedHomeUsageSummary
        let inputLabel = InstallerViewModel.formatTokenCount(summary.inputTokens)
        let outputLabel = InstallerViewModel.formatTokenCount(summary.outputTokens)
        let requestLabel = summary.requestCount == 1 ? "1 request" : "\(summary.requestCount) requests"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(UI.accent)
                Spacer()
                Picker("", selection: $vm.selectedHomeUsageWindow) {
                    ForEach(InstallerViewModel.UsageWindow.allCases) { window in
                        Text(window.rawValue).tag(window)
                    }
                }
                .labelsHidden()
                .frame(width: 96)
            }
            Text(InstallerViewModel.formatTokenCount(summary.totalTokens))
                .font(AppFont.bodySemi(19))
                .foregroundStyle(UI.text)
                .lineLimit(1)
            Text("Tokens used")
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.muted)
            Text(summary.totalTokens == 0 ? "No recorded usage yet" : "\(requestLabel) · in \(inputLabel) / out \(outputLabel)")
                .font(AppFont.body(11))
                .foregroundStyle(UI.muted)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .topLeading)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.accent.opacity(0.22), lineWidth: 1))
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
                oauthUsagePill
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
        .onAppear { vm.refreshOAuthUsage() }
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
                    .disabled(vm.localLMStudioSetupInProgress || vm.localLMStudioRepairInProgress || vm.selectedLocalLMStudioModel.isEmpty)

                    Button("SCAN") { vm.refreshLocalLMStudioModels() }
                        .buttonStyle(CompactChatButton(primary: false))
                        .disabled(vm.localLMStudioSetupInProgress || vm.localLMStudioRepairInProgress)

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
                    oauthUsagePill
                    chatModelPicker(width: 260)
                    Spacer()
                    Label(vm.chatStatus, systemImage: vm.chatStatus == "Ready" ? "checkmark.circle.fill" : "circle.fill")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(vm.chatStatus == "Ready" ? Color(NSColor.systemGreen) : UI.accent)
                }
            }

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

                ZStack(alignment: .bottom) {
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
                            .padding(.bottom, 54)
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

                    chatContextUsageBar
                        .padding(.bottom, 10)
                        .allowsHitTesting(false)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .onAppear {
            vm.refreshOpenClawChatInfo()
            vm.refreshOAuthUsage()
        }
    }

    func scrollChatToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
            }
        }
    }

    var chatContextUsageBar: some View {
        let usage = vm.chatContextUsage
        let tint = usage.fraction > 0.85 ? Color(NSColor.systemRed) : (usage.fraction > 0.65 ? Color(NSColor.systemOrange) : UI.accent)

        return HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(UI.lineSoft)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, proxy.size.width * usage.fraction))
                }
            }
            .frame(width: 92, height: 6)

            Text(usage.label)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(UI.cardSoft))
        .overlay(Capsule().stroke(UI.lineSoft, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .center)
        .help("Approximate context used by this chat")
    }

    var chatMemoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Label("Memory", systemImage: "memorychip")
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.text)
                    .lineLimit(1)
                Spacer()
                Button {
                    vm.chatMemoryEnabled.toggle()
                } label: {
                    Image(systemName: vm.chatMemoryEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(vm.chatMemoryEnabled ? UI.accent : UI.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(vm.chatIsSending)
                .help(vm.chatMemoryEnabled ? "Pause memory" : "Enable memory")

                Button(action: { vm.forgetChatMemory() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(UI.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(vm.chatIsSending || (!vm.chatMemoryEnabled && vm.chatSavedNotes.isEmpty))
                .help("Forget chat memory")
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
                chatComposerIcon("clipboard", help: "Paste image from clipboard") { vm.pasteChatImageFromClipboard() }
                chatComposerIcon("globe", help: "Web context", disabled: true)
                chatComposerIcon("apps.iphone", help: "Apps", disabled: true)

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
        .onPasteCommand(of: [.image]) { _ in
            vm.pasteChatImageFromClipboard()
        }
    }

    private func installClipboardImagePasteShortcutIfNeeded() {
        guard pasteEventMonitor == nil else { return }
        pasteEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isCommandV = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                && event.charactersIgnoringModifiers?.lowercased() == "v"
            guard isCommandV,
                  vm.screen == .chat,
                  InstallerViewModel.imageFromPasteboard(NSPasteboard.general) != nil else {
                return event
            }

            vm.pasteChatImageFromClipboard()
            return nil
        }
    }

    func chatModelPicker(width: CGFloat) -> some View {
        Picker("", selection: $vm.selectedChatModel) {
            ForEach(vm.availableChatModels) { model in
                Text(model.displayName).tag(model.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: width)
        .disabled(vm.chatIsSending)
        .onAppear { vm.ensureSelectedChatModel() }
        .onChange(of: vm.selectedChatModel) { _ in
            vm.handleChatModelSelectionChanged(useDeveloperSession: false)
        }
        .help("Choose the model for OpenClaw Chat")
    }

    func chatComposerIcon(_ systemName: String, help: String, disabled: Bool = false, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(UI.muted)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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

    @ViewBuilder
    var oauthUsagePill: some View {
        if vm.isOpenAIOAuthMode {
            let snapshot = vm.oauthUsageSnapshot
            let percent = snapshot?.primaryUsedPercent
            let label = vm.oauthUsageIsLoading ? "Usage..." : (snapshot?.buttonLabel ?? "Usage")
            let tint = percent.map { $0 >= 90 ? Color(NSColor.systemRed) : ($0 >= 75 ? Color(NSColor.systemOrange) : UI.accent) } ?? UI.muted

            Button(action: { vm.refreshOAuthUsage(force: true) }) {
                HStack(spacing: 8) {
                    if vm.oauthUsageIsLoading {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(label)
                        .font(AppFont.bodySemi(11))
                        .lineLimit(1)
                }
                .foregroundStyle(percent == nil ? UI.muted : UI.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(UI.cardSoft))
                .overlay(Capsule().stroke(tint.opacity(percent == nil ? 0.45 : 0.9), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(vm.oauthUsageIsLoading)
            .help(snapshot?.tooltipLabel ?? "Refresh OAuth usage")
        }
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
                        vm.selectInferenceModeFromUser(newValue)
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
                    vm.selectInferenceModeFromUser(.cloud)
                }
                installPathCard(
                    title: "OAuth LLM",
                    detail: "OpenAI ChatGPT/Codex login, no API key paste.",
                    icon: "person.badge.key",
                    selected: vm.inferenceMode == .oauth
                ) {
                    vm.selectInferenceModeFromUser(.oauth)
                }
                installPathCard(
                    title: "Local LLM",
                    detail: "LM Studio local models, more private.",
                    icon: "lock.desktopcomputer",
                    selected: vm.inferenceMode == .local
                ) {
                    vm.selectInferenceModeFromUser(.local)
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
        case "Node": return vm.nodeUpToDate
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
                oauthSetupAssistant
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

    private var oauthSetupAssistant: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.key.fill")
                    .foregroundStyle(UI.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.cloudProviderAuthConfigured ? "OAuth connected" : "OAuth setup assistant")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.text)
                    Text(vm.cloudProviderAuthConfigured ? "Your OpenClaw OAuth profile is ready." : "Choose the account provider to connect.")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text(vm.cloudProviderAuthConfigured ? "Ready" : "Needs login")
                    .font(AppFont.bodySemi(10))
                    .foregroundStyle(vm.cloudProviderAuthConfigured ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill((vm.cloudProviderAuthConfigured ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange)).opacity(0.12)))
            }

            ForEach(InstallerViewModel.oauthProviderOptions) { provider in
                Button {
                    vm.selectedOAuthProvider = provider.id
                    vm.prepareOAuthModelSelection()
                    if !vm.cloudProviderAuthConfigured {
                        vm.showOAuthSetupAssistant = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: vm.selectedOAuthProvider == provider.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(provider.available ? UI.accent : UI.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(AppFont.bodySemi(12))
                                .foregroundStyle(UI.text)
                            Text(provider.detail)
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.muted)
                        }
                        Spacer()
                        Text(provider.available ? "Connect" : "Not supported")
                            .font(AppFont.bodySemi(10))
                            .foregroundStyle(provider.available ? UI.accent : UI.muted)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(vm.selectedOAuthProvider == provider.id ? UI.accent.opacity(0.10) : UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(vm.selectedOAuthProvider == provider.id ? UI.accent.opacity(0.45) : UI.lineSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!provider.available)
            }

            Text("For now, OpenClaw exposes OAuth through ChatGPT/Codex. Other providers stay in API key mode until their OAuth login is supported by OpenClaw.")
                .font(AppFont.body(10))
                .foregroundStyle(UI.muted)
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
                    vm.showOAuthSetupAssistant = true
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
                statusRow("LM Studio", vm.selectedModel.isEmpty ? "SKIP" : vm.statusLMStudio)
                statusRow("Model", vm.selectedModel.isEmpty ? "SKIP" : vm.statusModel)
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
                versionRow("Node", vm.nodeVersion, "22.19+ required for OpenClaw", isUpToDate: vm.nodeUpToDate)
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
                Button("New Agent") { vm.beginNewAgentSetup() }
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

            if vm.showAgentSetupPanel {
                agentSetupPanel
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
                vm.beginEditAgentSetup(agent)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(CTAButton(primary: false))

            Button {
                vm.requestDeleteAgent(agent)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(CTAButton(primary: false))
            .foregroundStyle(agent.isDefault ? UI.muted.opacity(0.35) : Color(NSColor.systemRed))
            .disabled(agent.isDefault || vm.agentDeleteIsRunning)
            .help(agent.isDefault ? "The main agent cannot be deleted." : "Delete this agent and its OpenClaw state/workspace.")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(agent.statusTint.opacity(0.35), lineWidth: 1))
    }

    var agentSetupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(vm.agentSetupEditingID.isEmpty ? "New agent" : "Edit agent", systemImage: vm.agentSetupEditingID.isEmpty ? "person.badge.plus" : "slider.horizontal.3")
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                Spacer()
                if vm.agentSetupIsRunning {
                    ProgressView()
                        .scaleEffect(0.75)
                }
                Button("Cancel") { vm.cancelAgentSetup() }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(vm.agentSetupIsRunning)
            }

            LazyVGrid(columns: [GridItem(.flexible(minimum: 180)), GridItem(.flexible(minimum: 220))], spacing: 10) {
                agentSetupTextField("Agent ID", text: $vm.agentSetupID, placeholder: "support", disabled: !vm.agentSetupEditingID.isEmpty)
                agentSetupTextField("Display name", text: $vm.agentSetupName, placeholder: "Support agent")
                agentSetupTextField("Workspace", text: $vm.agentSetupWorkspace, placeholder: "~/.openclaw/workspaces/support")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Emoji")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
                    ForEach(InstallerViewModel.agentEmojiChoices, id: \.self) { emoji in
                        Button {
                            vm.agentSetupEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 18))
                                .frame(width: 34, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8).fill(vm.agentSetupEmoji == emoji ? UI.accent.opacity(0.22) : UI.card))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(vm.agentSetupEmoji == emoji ? UI.accent : UI.lineSoft, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Goal")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
                TextField("What should this agent do? Example: Handle local coding tasks using only LM Studio.", text: $vm.agentSetupGoal, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.text)
                    .lineLimit(2...4)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Mode")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
                Picker("", selection: $vm.agentSetupMode) {
                    ForEach(InstallerViewModel.AgentModelMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .tint(UI.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
                HStack(spacing: 8) {
                    Picker("", selection: $vm.agentSetupModel) {
                        Text("OpenClaw default").tag("")
                        ForEach(vm.agentModelChoices, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)

                    TextField("custom model id, ex: lmstudio/google/gemma-4-e2b", text: $vm.agentSetupModel)
                        .textFieldStyle(.plain)
                        .font(AppFont.body(12))
                        .foregroundStyle(UI.text)
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                }
            }

            HStack(spacing: 10) {
                Button(vm.agentSetupIsRunning ? "Saving..." : (vm.agentSetupEditingID.isEmpty ? "Create Agent" : "Save Agent")) {
                    vm.saveAgentSetup()
                }
                .buttonStyle(CTAButton(primary: true))
                .disabled(vm.agentSetupIsRunning)

                Text(vm.agentSetupStatus.isEmpty ? "Create and configure OpenClaw agents without leaving LocalClaw." : vm.agentSetupStatus)
                    .font(AppFont.body(11))
                    .foregroundStyle(vm.agentSetupStatus.lowercased().contains("failed") ? Color(NSColor.systemRed) : UI.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.accent.opacity(0.24), lineWidth: 1))
    }

    private func agentSetupTextField(_ title: String, text: Binding<String>, placeholder: String, disabled: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(AppFont.body(12))
                .foregroundStyle(disabled ? UI.muted : UI.text)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                .disabled(disabled)
        }
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
            if vm.agentsStatus == "Not loaded" || vm.agents.isEmpty {
                vm.refreshAgents()
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

    private func cronAgent(for job: InstallerViewModel.CronJobInfo) -> InstallerViewModel.AgentInfo? {
        guard let agentID = job.agentID, !agentID.isEmpty else { return nil }
        return vm.agents.first { $0.id == agentID }
    }

    private func cronAgentName(for job: InstallerViewModel.CronJobInfo) -> String {
        if let agent = cronAgent(for: job) {
            return agent.displayName
        }
        return job.agentID ?? "No agent"
    }

    private func cronRuntimeLabel(for job: InstallerViewModel.CronJobInfo) -> String {
        if let agent = cronAgent(for: job) {
            return agent.runtimeLabel
        }
        if job.agentID != nil {
            return vm.agentsIsLoading ? "Checking runtime..." : "Runtime unknown"
        }
        return "No agent"
    }

    private func cronRuntimeTint(for job: InstallerViewModel.CronJobInfo) -> Color {
        if let agent = cronAgent(for: job) {
            return agent.runtimeTint
        }
        return job.agentID == nil ? UI.muted : Color(NSColor.systemOrange)
    }

    private func cronModelLabel(for job: InstallerViewModel.CronJobInfo) -> String? {
        guard let agent = cronAgent(for: job),
              let model = agent.model,
              !model.isEmpty else { return nil }
        return model
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
                        HStack(spacing: 8) {
                            cronBadge("Agent: \(selectedAgent.displayName)", color: UI.muted, icon: "person.crop.circle")
                            cronBadge(selectedAgent.runtimeLabel, color: selectedAgent.runtimeTint, icon: selectedAgent.runtimeLabel == "Local LLM" ? "desktopcomputer" : "cloud.fill")
                        }
                        if let model = selectedAgent.model, !model.isEmpty {
                            Text(model)
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
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

                        if vm.cronCreateScheduleKind == "at" {
                            DatePicker("", selection: $vm.cronCreateAtDate, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                        } else {
                            TextField(schedulePrompt, text: $vm.cronCreateScheduleValue)
                                .textFieldStyle(.plain)
                                .font(AppFont.body(13))
                                .foregroundStyle(UI.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                        }
                    }

                    if vm.cronCreateScheduleKind == "at" {
                        Picker("Location", selection: $vm.cronCreateTimeZoneID) {
                            ForEach(InstallerViewModel.scheduleTimeZoneOptions, id: \.self) { zone in
                                Text(InstallerViewModel.timeZoneDisplayLabel(zone, date: vm.cronCreateAtDate)).tag(zone)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(AppFont.body(12))
                        Text("Runs once at \(vm.cronCreateScheduleValue) in \(InstallerViewModel.timeZoneDisplayLabel(vm.cronCreateTimeZoneID, date: vm.cronCreateAtDate))")
                            .font(AppFont.body(11))
                            .foregroundStyle(UI.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if vm.cronCreateScheduleKind != "at" {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                            ForEach(schedulePresets(for: vm.cronCreateScheduleKind), id: \.label) { preset in
                                Button(preset.label) {
                                    vm.cronCreateScheduleKind = preset.kind
                                    vm.cronCreateScheduleValue = preset.value
                                }
                                .buttonStyle(PresetPillButton(selected: vm.cronCreateScheduleKind == preset.kind && vm.cronCreateScheduleValue == preset.value))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Destination")
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(UI.muted)
                        Spacer()
                        Button("Refresh channels") { vm.refreshChannels() }
                            .buttonStyle(.plain)
                            .font(AppFont.bodySemi(11))
                            .foregroundStyle(UI.accent)
                            .disabled(vm.channelsIsLoading)
                    }

                    Picker("", selection: $vm.cronCreateDeliveryMode) {
                        Text("Last used channel").tag("last")
                        Text("Choose channel").tag("channel")
                        Text("No delivery").tag("none")
                    }
                    .pickerStyle(.segmented)

                    Text(vm.cronDeliverySummary)
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if vm.cronCreateDeliveryMode == "channel" {
                        HStack(spacing: 8) {
                            Picker("", selection: $vm.cronCreateDeliveryChannel) {
                                if vm.activeCronDeliveryChannels.isEmpty {
                                    Text("No configured channel").tag("")
                                } else {
                                    ForEach(vm.activeCronDeliveryChannels) { channel in
                                        Text("\(channel.label) · \(channel.connectionLabel)").tag(channel.id)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))

                            TextField("Account ID optional", text: $vm.cronCreateDeliveryAccount)
                                .textFieldStyle(.plain)
                                .font(AppFont.body(13))
                                .foregroundStyle(UI.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                                .frame(width: 170)
                        }

                        TextField("Destination required: Telegram chatId, Discord channel/user, phone number...", text: $vm.cronCreateDeliveryTo)
                            .textFieldStyle(.plain)
                            .font(AppFont.body(13))
                            .foregroundStyle(UI.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))

                        if !vm.activeCronDeliveryDestinations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Known destinations")
                                    .font(AppFont.bodySemi(11))
                                    .foregroundStyle(UI.muted)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                                    ForEach(vm.activeCronDeliveryDestinations) { destination in
                                        Button(destination.displayLabel) {
                                            vm.cronCreateDeliveryTo = destination.destination
                                        }
                                        .buttonStyle(PresetPillButton(selected: vm.cronCreateDeliveryTo == destination.destination))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    }
                                }
                            }
                        }

                        if vm.activeCronDeliveryChannels.isEmpty {
                            Text("No configured channel found yet. Connect Telegram, Discord, Slack or another channel first, then refresh.")
                                .font(AppFont.body(11))
                                .foregroundStyle(Color(NSColor.systemOrange))
                                .fixedSize(horizontal: false, vertical: true)
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

    private func cronJobDeleteSheet(_ job: InstallerViewModel.CronJobInfo) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Delete cron job", systemImage: "trash")
                        .font(AppFont.heading(24))
                        .foregroundStyle(UI.text)
                    Text("This removes the scheduled job from OpenClaw. The agent and channels stay installed.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Button("Cancel") { vm.cancelCronDelete() }
                    .buttonStyle(SheetActionButton(primary: false))
                    .disabled(vm.cronDeleteIsRunning)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(job.name)
                    .font(AppFont.bodySemi(18))
                    .foregroundStyle(UI.text)
                Text(job.id)
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(job.detailSummary)
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.systemRed).opacity(0.45), lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text("Type DELETE to confirm")
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.muted)
                TextField("DELETE", text: $vm.cronDeleteConfirmText)
                    .textFieldStyle(.plain)
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
            }

            if !vm.cronDeleteError.isEmpty {
                Text(vm.cronDeleteError)
                    .font(AppFont.body(12))
                    .foregroundStyle(Color(NSColor.systemRed))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.systemRed).opacity(0.10)))
            }

            HStack {
                Spacer()
                Button(vm.cronDeleteIsRunning ? "Deleting..." : "Delete cron job") {
                    vm.deletePendingCronJob()
                }
                .buttonStyle(SheetActionButton(primary: true))
                .disabled(vm.cronDeleteIsRunning || vm.cronDeleteConfirmText.trimmingCharacters(in: .whitespacesAndNewlines) != "DELETE")
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(UI.bg)
    }

    private var schedulePrompt: String {
        switch vm.cronCreateScheduleKind {
        case "cron": return "0 9 * * *"
        case "at": return "15m, 1h, or 2026-05-17T12:00:00+02:00"
        default: return "30m, 2h, 1d"
        }
    }

    private var kanbanSchedulePrompt: String {
        switch vm.kanbanEditorScheduleKind {
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

    private func schedulePresets(for kind: String) -> [(label: String, kind: String, value: String)] {
        switch kind {
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
                        if job.agentID != nil {
                            cronBadge("Agent: \(cronAgentName(for: job))", color: UI.muted, icon: "person.crop.circle")
                            cronBadge(cronRuntimeLabel(for: job), color: cronRuntimeTint(for: job), icon: cronRuntimeLabel(for: job) == "Local LLM" ? "desktopcomputer" : "cloud.fill")
                        }
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
                    if let model = cronModelLabel(for: job) {
                        Text(model)
                            .font(AppFont.body(11))
                            .foregroundStyle(UI.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if job.agentID != nil && !vm.agentsIsLoading {
                        Text("Agent runtime not found. Refresh Agents to verify the model before relying on this job.")
                            .font(AppFont.body(11))
                            .foregroundStyle(Color(NSColor.systemOrange))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Button("Run") { vm.runCronJobNow(job.id) }
                    .buttonStyle(CTAButton(primary: false))
                Button(job.enabled ? "Stop" : "Start") {
                    vm.setCronJob(job.id, enabled: !job.enabled)
                }
                .buttonStyle(CTAButton(primary: false))
                Button("Delete") { vm.requestDeleteCronJob(job) }
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

    var kanbanCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("KANBAN")
                            .font(AppFont.heading(28))
                            .foregroundStyle(UI.text)
                        Text("BETA")
                            .font(AppFont.bodySemi(10))
                            .foregroundStyle(UI.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 999).fill(UI.accent.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 999).stroke(UI.accent.opacity(0.35), lineWidth: 1))
                    }
                    Text("Plan work in classic Kanban stages. A card does not run until you start it or create a Cron Job.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text(vm.kanbanStatus)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
                Button("Refresh Agents") { vm.refreshAgents() }
                    .buttonStyle(CTAButton(primary: false))
                    .disabled(vm.agentsIsLoading)
                Button("New Task") { vm.beginCreateKanbanCard() }
                    .buttonStyle(CTAButton(primary: true))
            }

            HStack(spacing: 10) {
                kanbanMetricCard("Tasks", value: "\(vm.kanbanCards.count)", icon: "rectangle.stack.fill", tint: UI.accent)
                kanbanMetricCard("In progress", value: "\(vm.kanbanColumns.first { $0.id == "doing" }?.cards.count ?? 0)", icon: "bolt.fill", tint: Color(NSColor.systemOrange))
                kanbanMetricCard("Agents", value: "\(max(vm.agents.count, 1))", icon: "person.2.fill", tint: Color(NSColor.systemBlue))
                kanbanMetricCard("Schedulable", value: "\(vm.kanbanCards.filter { $0.cronEnabled }.count)", icon: "calendar.badge.clock", tint: Color(NSColor.systemGreen))
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(vm.kanbanColumns) { column in
                    kanbanColumn(column)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(UI.lineSoft, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear {
            if vm.agentsStatus == "Not loaded" || vm.agents.isEmpty {
                vm.refreshAgents()
            }
            if vm.hasScheduledKanbanAutomation {
                vm.refreshCronJobs(silent: true)
            }
        }
    }

    private func kanbanColumn(_ column: InstallerViewModel.KanbanColumn) -> some View {
        let tint = kanbanColor(column.colorName)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: column.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(column.title)
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                Spacer()
                Text("\(column.cards.count)")
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.card))
            }
            Text(kanbanColumnDescription(column.id))
                .font(AppFont.body(10))
                .foregroundStyle(UI.muted)
                .lineLimit(2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if column.cards.isEmpty {
                        Button {
                            vm.beginCreateKanbanCard(columnID: column.id)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Add task")
                                    .font(AppFont.bodySemi(12))
                            }
                            .foregroundStyle(UI.muted)
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(RoundedRectangle(cornerRadius: 10).fill(UI.card.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(column.cards) { card in
                            kanbanCard(card, columnID: column.id)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.28), lineWidth: 1))
    }

    private func kanbanCard(_ card: InstallerViewModel.KanbanCard, columnID: String) -> some View {
        let priorityTint = kanbanPriorityColor(card.priority)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title)
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.text)
                        .lineLimit(2)
                    if !card.detail.isEmpty {
                        Text(card.detail)
                            .font(AppFont.body(11))
                            .foregroundStyle(UI.muted)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 6)
                Button { vm.beginEditKanbanCard(card, columnID: columnID) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(UI.muted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Edit task")
                Button { vm.deleteKanbanCard(card.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(UI.muted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Remove task")
            }

            HStack(spacing: 6) {
                kanbanMiniBadge(kanbanCardStateLabel(columnID), icon: kanbanCardStateIcon(columnID), tint: kanbanColumnTint(columnID))
                kanbanMiniBadge(card.priority, icon: "flag.fill", tint: priorityTint)
                kanbanMiniBadge(agentName(for: card.agentID), icon: "person.crop.circle", tint: UI.muted)
            }
            HStack(spacing: 6) {
                kanbanMiniBadge(card.cronEnabled ? kanbanScheduleLabel(for: card) : "No cron", icon: "clock", tint: Color(NSColor.systemBlue))
                kanbanMiniBadge(kanbanDeliveryLabel(for: card), icon: "paperplane.fill", tint: Color(NSColor.systemGreen))
            }
            if card.cronEnabled {
                HStack(spacing: 6) {
                    kanbanMiniBadge(card.cronJobID.isEmpty ? "Not scheduled" : "Scheduled", icon: card.cronJobID.isEmpty ? "calendar.badge.exclamationmark" : "calendar.badge.checkmark", tint: card.cronJobID.isEmpty ? Color(NSColor.systemOrange) : Color(NSColor.systemGreen))
                    if vm.kanbanSchedulingCardIDs.contains(card.id) {
                        kanbanMiniBadge("Scheduling", icon: "hourglass", tint: Color(NSColor.systemBlue))
                    }
                }
            }

            HStack(spacing: 6) {
                kanbanIconAction("chevron.left", help: "Move left", disabled: columnID == vm.kanbanColumns.first?.id) {
                    vm.moveKanbanCard(card.id, direction: -1)
                }
                Button { vm.runKanbanCardNow(card.id) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: vm.kanbanRunningCardIDs.contains(card.id) ? "hourglass" : "paperplane.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(vm.kanbanRunningCardIDs.contains(card.id) ? "Running" : "Run now")
                            .font(AppFont.bodySemi(12))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(CompactGhostButton())
                .disabled(vm.kanbanRunningCardIDs.contains(card.id))
                .help("Run this task with the selected agent now")
                if columnID != "doing" && columnID != "done" {
                    kanbanIconAction("play.fill", help: "Move to In Progress") {
                        vm.startKanbanCard(card.id)
                    }
                }
                kanbanIconAction("calendar.badge.plus", help: card.cronEnabled ? "Schedule as Cron Job" : "Automation is disabled", disabled: !card.cronEnabled) {
                    vm.syncKanbanAutomation(cardID: card.id)
                }
                kanbanIconAction("chevron.right", help: "Move right", disabled: columnID == vm.kanbanColumns.last?.id) {
                    vm.moveKanbanCard(card.id, direction: 1)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(priorityTint.opacity(0.24), lineWidth: 1))
    }

    private var kanbanTaskEditorSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(vm.kanbanEditorIsEditing ? "Edit Kanban Task" : "New Kanban Task")
                        .font(AppFont.heading(24))
                        .foregroundStyle(UI.text)
                    Text("Creating a card only plans the work. Automation creates a real Cron Job when you save.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Button("Cancel") { vm.cancelKanbanTaskEditor() }
                    .buttonStyle(SheetActionButton(primary: false))
            }

            VStack(alignment: .leading, spacing: 12) {
                kanbanFormField("Task", text: $vm.kanbanEditorTitle, prompt: "Review support tickets")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Details")
                        .font(AppFont.bodySemi(12))
                        .foregroundStyle(UI.muted)
                    TextEditor(text: $vm.kanbanEditorDetail)
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 100)
                        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Priority")
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(UI.muted)
                        Picker("", selection: $vm.kanbanEditorPriority) {
                            ForEach(["Low", "Normal", "High", "Urgent"], id: \.self) { value in
                                Text(value).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Agent")
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(UI.muted)
                        Picker("", selection: $vm.kanbanEditorAgentID) {
                            if vm.agents.isEmpty {
                                Text("Main assistant").tag("main")
                            } else {
                                ForEach(vm.agents) { agent in
                                    Text(agent.isDefault ? "\(agent.displayName) · main" : agent.displayName).tag(agent.id)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Automation setup", isOn: $vm.kanbanEditorCronEnabled)
                        .toggleStyle(.switch)
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(UI.text)

                    if vm.kanbanEditorCronEnabled {
                        Text("Saving this task creates or updates a real Cron Job. It runs at the configured time, no matter where the card is on the board.")
                            .font(AppFont.body(11))
                            .foregroundStyle(UI.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Picker("", selection: $vm.kanbanEditorScheduleKind) {
                                Text("Every").tag("every")
                                Text("Cron").tag("cron")
                                Text("At").tag("at")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 230)

                            if vm.kanbanEditorScheduleKind == "at" {
                                DatePicker("", selection: $vm.kanbanEditorAtDate, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                            } else {
                                TextField(kanbanSchedulePrompt, text: $vm.kanbanEditorScheduleValue)
                                    .textFieldStyle(.plain)
                                    .font(AppFont.body(13))
                                    .foregroundStyle(UI.text)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                            }
                        }

                        if vm.kanbanEditorScheduleKind == "at" {
                            Picker("Location", selection: $vm.kanbanEditorTimeZoneID) {
                                ForEach(InstallerViewModel.scheduleTimeZoneOptions, id: \.self) { zone in
                                    Text(InstallerViewModel.timeZoneDisplayLabel(zone, date: vm.kanbanEditorAtDate)).tag(zone)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(AppFont.body(12))
                            Text("Runs once at \(vm.kanbanEditorScheduleValue) in \(InstallerViewModel.timeZoneDisplayLabel(vm.kanbanEditorTimeZoneID, date: vm.kanbanEditorAtDate))")
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if vm.kanbanEditorScheduleKind != "at" {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                                ForEach(schedulePresets(for: vm.kanbanEditorScheduleKind), id: \.label) { preset in
                                    Button(preset.label) {
                                        vm.kanbanEditorScheduleKind = preset.kind
                                        vm.kanbanEditorScheduleValue = preset.value
                                    }
                                    .buttonStyle(PresetPillButton(selected: vm.kanbanEditorScheduleKind == preset.kind && vm.kanbanEditorScheduleValue == preset.value))
                                }
                            }
                        }

                        HStack {
                            Text("Destination")
                                .font(AppFont.bodySemi(12))
                                .foregroundStyle(UI.muted)
                            Spacer()
                            Button("Refresh channels") { vm.refreshChannels() }
                                .buttonStyle(.plain)
                                .font(AppFont.bodySemi(11))
                                .foregroundStyle(UI.accent)
                                .disabled(vm.channelsIsLoading)
                        }

                        Picker("", selection: $vm.kanbanEditorDeliveryMode) {
                            Text("Last used channel").tag("last")
                            Text("Choose channel").tag("channel")
                            Text("No delivery").tag("none")
                        }
                        .pickerStyle(.segmented)

                        if vm.kanbanEditorDeliveryMode == "channel" {
                            HStack(spacing: 8) {
                                Picker("", selection: $vm.kanbanEditorDeliveryChannel) {
                                    if vm.activeCronDeliveryChannels.isEmpty {
                                        Text("No configured channel").tag("")
                                    } else {
                                        ForEach(vm.activeCronDeliveryChannels) { channel in
                                            Text("\(channel.label) · \(channel.connectionLabel)").tag(channel.id)
                                        }
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))

                                TextField("Account ID optional", text: $vm.kanbanEditorDeliveryAccount)
                                    .textFieldStyle(.plain)
                                    .font(AppFont.body(13))
                                    .foregroundStyle(UI.text)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                                    .frame(width: 170)
                            }

                            TextField("Destination optional until Cron creation", text: $vm.kanbanEditorDeliveryTo)
                                .textFieldStyle(.plain)
                                .font(AppFont.body(13))
                                .foregroundStyle(UI.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 8).fill(UI.cardSoft))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))

                            if !vm.activeKanbanDeliveryDestinations.isEmpty {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                                    ForEach(vm.activeKanbanDeliveryDestinations) { destination in
                                        Button(destination.displayLabel) {
                                            vm.kanbanEditorDeliveryTo = destination.destination
                                        }
                                        .buttonStyle(PresetPillButton(selected: vm.kanbanEditorDeliveryTo == destination.destination))
                                        .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(UI.lineSoft, lineWidth: 1))

                if !vm.kanbanEditorError.isEmpty {
                    Text(vm.kanbanEditorError)
                        .font(AppFont.body(12))
                        .foregroundStyle(Color(NSColor.systemRed))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.systemRed).opacity(0.10)))
                }
            }

            HStack {
                Text(vm.kanbanEditorIsEditing ? "Changes update the selected card immediately." : "The card stays editable after it is added.")
                    .font(AppFont.body(12))
                    .foregroundStyle(UI.muted)
                Spacer()
                Button(vm.kanbanEditorIsEditing ? "Save Task" : "Add Task") {
                    vm.saveKanbanTaskEditor()
                }
                .buttonStyle(SheetActionButton(primary: true))
                .disabled(!vm.kanbanEditorCanSave)
            }
        }
        .padding(22)
        .frame(width: 720)
        .background(UI.bg)
    }

    private func kanbanMetricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
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

    private func kanbanFormField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppFont.bodySemi(10))
                .foregroundStyle(UI.muted)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(AppFont.body(12))
                .foregroundStyle(UI.text)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
        }
    }

    private func kanbanMiniBadge(_ label: String, icon: String, tint: Color) -> some View {
        Label(label.isEmpty ? "None" : label, systemImage: icon)
            .font(AppFont.bodySemi(9))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
    }

    private func kanbanIconAction(_ icon: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(disabled ? UI.muted.opacity(0.45) : UI.text)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(UI.cardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(UI.lineSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private func agentName(for agentID: String) -> String {
        if agentID == "main" || agentID.isEmpty { return "Claw" }
        return vm.agents.first { $0.id == agentID }?.displayName ?? agentID
    }

    private func kanbanColumnDescription(_ columnID: String) -> String {
        switch columnID {
        case "backlog": return "Ideas and tasks. Not started."
        case "ready": return "Prioritized and waiting."
        case "doing": return "Work has started."
        case "review": return "Waiting for validation."
        case "done": return "Finished work."
        default: return "Kanban stage."
        }
    }

    private func kanbanCardStateLabel(_ columnID: String) -> String {
        switch columnID {
        case "backlog": return "Not started"
        case "ready": return "Ready"
        case "doing": return "Started"
        case "review": return "Review"
        case "done": return "Done"
        default: return "Task"
        }
    }

    private func kanbanCardStateIcon(_ columnID: String) -> String {
        switch columnID {
        case "backlog": return "tray.full"
        case "ready": return "checklist"
        case "doing": return "play.fill"
        case "review": return "eye.fill"
        case "done": return "checkmark.seal.fill"
        default: return "rectangle.stack.fill"
        }
    }

    private func kanbanColumnTint(_ columnID: String) -> Color {
        let colorName = vm.kanbanColumns.first { $0.id == columnID }?.colorName ?? "gray"
        return kanbanColor(colorName)
    }

    private func kanbanScheduleLabel(for card: InstallerViewModel.KanbanCard) -> String {
        guard card.scheduleKind == "at" else { return card.reviewSchedule }
        let zone = card.scheduleTimeZoneID.isEmpty ? TimeZone.current.identifier : card.scheduleTimeZoneID
        let shortZone = zone.split(separator: "/").last.map(String.init) ?? zone
        return "\(card.reviewSchedule) · \(shortZone)"
    }

    private func kanbanDeliveryLabel(for card: InstallerViewModel.KanbanCard) -> String {
        if !card.cronEnabled || card.deliveryMode == "none" || card.deliveryChannel == "none" {
            return "No delivery"
        }
        if card.deliveryMode == "last" || card.deliveryChannel == "last" {
            return "Last channel"
        }
        let channel = vm.channels.first { $0.id == card.deliveryChannel }
        let label = channel?.label ?? card.deliveryChannel
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
        if !card.deliveryTo.isEmpty {
            return "\(label) · set"
        }
        return label
    }

    private func kanbanColor(_ name: String) -> Color {
        switch name {
        case "blue": return Color(NSColor.systemBlue)
        case "green": return Color(NSColor.systemGreen)
        case "red": return UI.accent
        case "purple": return Color(NSColor.systemPurple)
        default: return UI.muted
        }
    }

    private func kanbanPriorityColor(_ priority: String) -> Color {
        switch priority {
        case "Urgent": return Color(NSColor.systemRed)
        case "High": return Color(NSColor.systemOrange)
        case "Low": return UI.muted
        default: return UI.accent
        }
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
                            faqRow(question: "How can I confirm Local LLM mode is really active?", answer: "In top bar, mode should display LOCAL LLM. In Models, apply Local LLM mode and run a quick test message.")
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
                    vm.selectInferenceModeFromUser(newValue)
                }

                if vm.inferenceMode == .oauth {
                    HStack(spacing: 8) {
                        Picker("OAuth model", selection: $vm.selectedChatModel) {
                            ForEach(vm.availableChatModels.filter { InstallerViewModel.isOAuthRuntimeModelID($0.id) }) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            vm.refreshOAuthAuthStatus()
                            if vm.cloudProviderAuthConfigured {
                                vm.refreshOAuthModels()
                            } else {
                                vm.oauthSetupStatus = "OAuth login required"
                            }
                        }
                        .onChange(of: vm.selectedChatModel) { _ in
                            vm.handleChatModelSelectionChanged(useDeveloperSession: false)
                        }

                        Button("Refresh") {
                            if vm.requireOAuthAuthBeforeBackendUse(status: "OAuth login required before refreshing OAuth models.") {
                                vm.refreshOAuthModels()
                            }
                        }
                            .buttonStyle(CTAButton(primary: false))
                    }
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
                modelConfigRow(title: "OAuth model", subtitle: vm.selectedOAuthModelIdentifier(), icon: "person.badge.key", status: vm.cloudProviderAuthConfigured ? "Ready" : "Needs login")
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
                    count: vm.inferenceMode == .oauth ? vm.availableChatModels.filter { InstallerViewModel.isOAuthRuntimeModelID($0.id) }.count : (vm.openRouterModelsLive.isEmpty ? InstallerViewModel.openRouterModels.count : vm.openRouterModelsLive.count),
                    emptyText: vm.inferenceMode == .oauth ? "No OAuth model loaded yet." : "No cloud catalog loaded.",
                    rows: vm.inferenceMode == .oauth ? vm.availableChatModels.filter { InstallerViewModel.isOAuthRuntimeModelID($0.id) }.map(\.id) : Array((vm.openRouterModelsLive.isEmpty ? InstallerViewModel.openRouterModels.map(\.displayName) : vm.openRouterModelsLive.map(\.displayName)).prefix(8)),
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

            if vm.showTelegramSetupPanel {
                telegramSetupPanel
            }

            if vm.showChannelCredentialPanel {
                channelCredentialSetupPanel
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

    private var telegramSetupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Telegram setup", systemImage: "paperplane.fill")
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                Spacer()
                if vm.telegramSetupIsRunning {
                    ProgressView()
                        .scaleEffect(0.75)
                }
                Button("Cancel") { vm.cancelTelegramSetup() }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(vm.telegramSetupIsRunning)
            }

            LazyVGrid(columns: [GridItem(.flexible(minimum: 260)), GridItem(.flexible(minimum: 220))], spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("1")
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(UI.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save bot token")
                                .font(AppFont.bodySemi(13))
                                .foregroundStyle(UI.text)
                            Text("Paste the @BotFather token once. LocalClaw restarts the gateway after saving it.")
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.muted)
                                .lineLimit(2)
                        }
                    }
                    SecureField("Paste token from @BotFather", text: $vm.telegramSetupToken)
                        .textFieldStyle(.plain)
                        .font(AppFont.body(12))
                        .foregroundStyle(UI.text)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                    Button("1 Save token + restart") { vm.saveTelegramBotToken() }
                        .buttonStyle(CTAButton(primary: true))
                        .disabled(vm.telegramSetupIsRunning)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("2")
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(UI.text)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(UI.card))
                            .overlay(Circle().stroke(UI.lineSoft, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Approve Telegram user")
                                .font(AppFont.bodySemi(13))
                                .foregroundStyle(UI.text)
                            Text("After Step 1, send /start to the bot, then paste the fresh pairing code here.")
                                .font(AppFont.body(11))
                                .foregroundStyle(UI.muted)
                                .lineLimit(2)
                        }
                    }
                    TextField("Code received after /start", text: $vm.telegramSetupPairingCode)
                        .textFieldStyle(.plain)
                        .font(AppFont.body(12))
                        .foregroundStyle(UI.text)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                    HStack(spacing: 8) {
                        Button("2 Approve pairing code") { vm.approveTelegramPairing() }
                            .buttonStyle(CTAButton(primary: true))
                            .disabled(vm.telegramSetupIsRunning)
                        Button("Check") { vm.restartTelegramAndRefresh() }
                            .buttonStyle(CTAButton(primary: false))
                            .disabled(vm.telegramSetupIsRunning)
                    }
                }
            }

            Text(vm.telegramSetupStatus.isEmpty ? "Telegram stays in OpenClaw config during LocalClaw updates." : vm.telegramSetupStatus)
                .font(AppFont.body(11))
                .foregroundStyle(vm.telegramSetupStatus.lowercased().contains("failed") ? Color(NSColor.systemRed) : UI.muted)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.accent.opacity(0.24), lineWidth: 1))
    }

    private var channelCredentialSetupPanel: some View {
        let profile = vm.activeChannelCredentialProfile
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(profile.title, systemImage: vm.channelCredentialIcon)
                    .font(AppFont.bodySemi(14))
                    .foregroundStyle(UI.text)
                Spacer()
                if vm.channelCredentialIsRunning {
                    ProgressView()
                        .scaleEffect(0.75)
                }
                Button("Cancel") { vm.cancelChannelCredentialSetup() }
                    .buttonStyle(CompactChatButton(primary: false))
                    .disabled(vm.channelCredentialIsRunning)
            }

            Text(profile.subtitle)
                .font(AppFont.body(12))
                .foregroundStyle(UI.muted)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible(minimum: 220)), GridItem(.flexible(minimum: 220))], spacing: 10) {
                channelSetupPlainField("Account ID", text: $vm.channelCredentialAccount, placeholder: "default")
                channelSetupPlainField("Display name", text: $vm.channelCredentialDisplayName, placeholder: vm.channelCredentialLabel)
                ForEach(profile.fields) { field in
                    channelSetupCredentialField(field)
                }
            }

            HStack(spacing: 10) {
                Button(profile.primaryButton) { vm.saveChannelCredentialSetup() }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(vm.channelCredentialIsRunning)
                Button("Check") { vm.checkChannelCredentialStatus() }
                    .buttonStyle(CTAButton(primary: false))
                    .disabled(vm.channelCredentialIsRunning)

                Spacer(minLength: 0)
            }

            Text(vm.channelCredentialStatus.isEmpty ? "Credentials are stored in OpenClaw config and preserved during LocalClaw updates." : vm.channelCredentialStatus)
                .font(AppFont.body(11))
                .foregroundStyle(vm.channelCredentialStatus.lowercased().contains("failed") || vm.channelCredentialStatus.lowercased().contains("missing") ? Color(NSColor.systemRed) : UI.muted)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.cardSoft))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UI.accent.opacity(0.24), lineWidth: 1))
    }

    private func channelSetupCredentialField(_ field: InstallerViewModel.ChannelCredentialField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(field.label)
                    .font(AppFont.bodySemi(11))
                    .foregroundStyle(UI.muted)
                if field.required {
                    Text("required")
                        .font(AppFont.bodySemi(9))
                        .foregroundStyle(UI.accent)
                }
                Spacer(minLength: 0)
            }
            Group {
                if field.secure {
                    SecureField(field.placeholder, text: channelCredentialBinding(field.id))
                } else {
                    TextField(field.placeholder, text: channelCredentialBinding(field.id))
                }
            }
            .textFieldStyle(.plain)
            .font(AppFont.body(12))
            .foregroundStyle(UI.text)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
            if !field.help.isEmpty {
                Text(field.help)
                    .font(AppFont.body(10))
                    .foregroundStyle(UI.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func channelSetupPlainField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.bodySemi(11))
                .foregroundStyle(UI.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(AppFont.body(12))
                .foregroundStyle(UI.text)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
        }
    }

    private func channelCredentialBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { vm.channelCredentialValues[key] ?? "" },
            set: { vm.channelCredentialValues[key] = $0 }
        )
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
                    vm.beginChannelSetup(channel)
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
            Text("Send /start to the bot, then approve the pairing code in LocalClaw.")
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
                vm.beginChannelSetup(channel)
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
                        Text("Only select what you really want to remove. This can delete your OpenClaw setup, local models, and configuration.")
                            .font(AppFont.bodySemi(12))
                            .foregroundStyle(Color(NSColor.systemOrange))
                            .fixedSize(horizontal: false, vertical: true)
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
                        uninstallRow(
                            "LM Studio app",
                            isOn: $vm.uninstallLMStudioSelected,
                            installed: vm.hasLMStudioInstalled,
                            removalText: "LM Studio application and LM Studio runtime cache"
                        )
                        uninstallRow(
                            "Local LLM models",
                            isOn: $vm.uninstallModelsSelected,
                            installed: vm.hasLocalModelsInstalled,
                            removalText: "Downloaded model files in ~/.lmstudio/models and ~/.cache/lm-studio/models",
                            dangerous: true
                        )
                        uninstallRow(
                            "OpenClaw CLI and services",
                            isOn: $vm.uninstallOpenClawSelected,
                            installed: vm.hasOpenClawInstalled,
                            removalText: "OpenClaw CLI, gateway service files, agents, and OpenClaw cache",
                            dangerous: true
                        )
                        uninstallRow(
                            "Node.js and npm/npx",
                            isOn: $vm.uninstallNodeSelected,
                            installed: vm.hasNodeInstalled,
                            removalText: "Node.js binaries, npm/npx/corepack links, ~/.npm, ~/.nvm, and ~/.node-gyp"
                        )
                        uninstallRow(
                            "Homebrew",
                            isOn: $vm.uninstallHomebrewSelected,
                            installed: vm.hasHomebrewInstalled,
                            removalText: "Homebrew itself using the official Homebrew uninstall script",
                            dangerous: true
                        )
                        uninstallRow(
                            "Configs and cache",
                            isOn: $vm.uninstallConfigsSelected,
                            installed: vm.hasConfigCacheInstalled,
                            removalText: "~/.openclaw, ~/.openclaw-gateway, ~/.cache/openclaw, ~/.cache/lm-studio, and OpenClaw/nvm shell entries",
                            dangerous: true
                        )
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

                        Text("Selected removal")
                            .font(AppFont.bodySemi(13))
                            .foregroundStyle(UI.text)
                        if vm.hasUninstallSelection {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(vm.selectedUninstallItems) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.title)
                                                .font(AppFont.bodySemi(12))
                                                .foregroundStyle(item.dangerous ? Color(NSColor.systemRed) : UI.text)
                                            if item.dangerous {
                                                Text("Dangerous")
                                                    .font(AppFont.bodySemi(9))
                                                    .foregroundStyle(Color(NSColor.systemRed))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(RoundedRectangle(cornerRadius: 999).fill(Color(NSColor.systemRed).opacity(0.12)))
                                            }
                                        }
                                        Text(item.detail)
                                            .font(AppFont.body(11))
                                            .foregroundStyle(UI.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(UI.card))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(UI.lineSoft, lineWidth: 1))
                        } else {
                            Text("Nothing selected.")
                                .font(AppFont.body(12))
                                .foregroundStyle(UI.muted)
                        }

                        Divider().overlay(UI.lineSoft)

                        Text("Actions")
                            .font(AppFont.bodySemi(13))
                            .foregroundStyle(UI.text)
                        Button(vm.uninstallPrimaryButtonTitle) {
                            vm.confirmAndRunSelectedUninstall()
                        }
                        .buttonStyle(CTAButton(primary: true))
                        .disabled(vm.isUninstalling || !vm.hasUninstallSelection)

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
        .onAppear { vm.prepareUninstallCenter() }
    }

    func uninstallRow(_ title: String, isOn: Binding<Bool>, installed: Bool, removalText: String, dangerous: Bool = false) -> some View {
        let isSelected = isOn.wrappedValue
        let dangerColor = Color(NSColor.systemRed)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(AppFont.bodySemi(13))
                        .foregroundStyle(dangerous ? dangerColor : UI.text)
                        .lineLimit(1)
                    if dangerous {
                        Text("Dangerous")
                            .font(AppFont.bodySemi(9))
                            .foregroundStyle(dangerColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 999).fill(dangerColor.opacity(0.12)))
                    }
                }
                Text(installed ? "Installed" : "Not installed")
                    .font(AppFont.body(11))
                    .foregroundStyle(installed ? Color(NSColor.systemGreen) : UI.muted)
                if isSelected {
                    Text("Removes: \(removalText)")
                        .font(AppFont.body(11))
                        .foregroundStyle(dangerous ? dangerColor : UI.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .background(RoundedRectangle(cornerRadius: 8).fill(dangerous ? dangerColor.opacity(isSelected ? 0.14 : 0.06) : UI.card))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(dangerous ? dangerColor.opacity(isSelected ? 0.70 : 0.35) : UI.lineSoft, lineWidth: 1))
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
            case "Node", "Node.js": return vm.nodeVersion != "Not installed" && vm.nodeVersion != "Checking..."
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

    // MARK: - New Command Center (Part 3 - Advanced)
    
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
