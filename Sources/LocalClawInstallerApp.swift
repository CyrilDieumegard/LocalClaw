import SwiftUI
import Foundation
import AppKit

@MainActor
final class InstallerViewModel: ObservableObject {
    enum Screen { case license, home, options, install, ready, updates, controlCenter, commandCenter, uninstallCenter, channelSetup, templates, healthCenter, usageCenter }
    enum InstallMode: String {
        case llmOnly = "Install Local LLM only"
        case openClawOnly = "Install OpenClaw only"
        case updateOnly = "Update existing setup"
        case fullInstall = "Full Install"
    }

    enum InferenceMode: String, CaseIterable, Identifiable {
        case cloud = "Cloud"
        case local = "Local LLM"

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
        OpenRouterModel(id: "openrouter/moonshotai/kimi-k2.5", displayName: "⭐ Kimi K2.5"),
        OpenRouterModel(id: "openrouter/anthropic/claude-3.5-sonnet", displayName: "⭐ Claude 3.5 Sonnet"),
        OpenRouterModel(id: "openrouter/openai/gpt-4o", displayName: "⭐ GPT-4o"),
        OpenRouterModel(id: "openrouter/openai/gpt-4o-mini", displayName: "⭐ GPT-4o Mini"),
        
        // Claude family
        OpenRouterModel(id: "openrouter/anthropic/claude-3.5-haiku", displayName: "Claude 3.5 Haiku"),
        OpenRouterModel(id: "openrouter/anthropic/claude-3-opus", displayName: "Claude 3 Opus"),
        OpenRouterModel(id: "openrouter/anthropic/claude-3-sonnet", displayName: "Claude 3 Sonnet"),
        OpenRouterModel(id: "openrouter/anthropic/claude-3-haiku", displayName: "Claude 3 Haiku"),
        
        // GPT family
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

    @Published var licenseEmail: String = ""
    @Published var licenseKey: String = ""
    @Published var activationStatus: String = "License required"
    @Published var isActivated: Bool = false
    @Published var isActivating: Bool = false

    @Published var chip: String = ""
    @Published var ram: String = ""
    @Published var recommendation: String = ""

    @Published var selectedModel: String = ""
    @Published var inferenceMode: InferenceMode = .cloud
    @Published var installLMStudio = true
    @Published var installOpenClaw = true

    @Published var selectedProvider: AIProvider = .openRouter
    @Published var openAIAuthMethod: AIProvider.OpenAIAuthMethod = .apiKey
    @Published var selectedOpenRouterModel: String = "openrouter/moonshotai/kimi-k2.5"
    @Published var openRouterKeyVerified: Bool = false
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
    @Published var installerCurrentVersion = "1.0.0"
    @Published var installerLatestVersion = "Checking..."
    @Published var installerUpdateStatus = "Checking..."
    @Published var installerDownloadURL = ""
    @Published var brewUpToDate = false
    @Published var nodeUpToDate = false
    @Published var lmStudioUpToDate = false

    @Published var logs: String = ""
    @Published var downloadProgress: Double = 0
    @Published var currentDownloadFile: String = ""
    @Published var isRunning = false

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
    @Published var channelSetupLogs: String = ""
    @Published var templateLogs: String = ""
    @Published var healthLogs: String = ""
    @Published var healthStatus: String = "Unknown"
    @Published var usageLogs: String = ""
    @Published var estimatedMonthlyTokensM: Double = 2.0
    @Published var estimatedMonthlyCostUSD: Double = 0
    @Published var costAdvice: String = ""
    @Published var modeSwitchInProgress: Bool = false
    @Published var modeSwitchStatus: String = ""

    // Installation status tracking (using existing status variables)
    var statusNodeJS: String {
        get { statusNode }
        set { statusNode = newValue }
    }
    var statusConfig: String = "PENDING"
    var statusService: String = "PENDING"

    let modelOptions = [
        "Qwen 3.5 35B-A3B Q4_K_M",
        "Qwen 3.5 27B Q4_K_M",
        "Qwen 3.5 9B Q4_K_M",
        "Qwen 3.5 4B Q4_K_M",
        "Qwen 3.5 2B Q4_K_M",
        "Qwen 3.5 0.8B Q4_K_M",
        "Qwen 3 14B Q4_K_M",
        "Qwen 3 8B Q4_K_M",
        "Nemotron 3 Nano 4B Q4_K_M",
        "DeepSeek R1 14B Q4_K_M",
        "Llama 3.3 8B Q4_K_M"
    ]

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
    }

    private var licenseEndpoint: String {
        ProcessInfo.processInfo.environment["LOCALCLAW_LICENSE_ENDPOINT"] ?? "https://localclaw.io/api/license/activate"
    }

    var isMockLicenseEndpoint: Bool {
        licenseEndpoint.contains("127.0.0.1") || licenseEndpoint.contains("localhost")
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

    var progress: Double {
        let states = [statusHomebrew, statusLMStudio, statusNode, statusOpenClaw, statusOpenClawCheck, statusModel]
        let done = states.filter { $0 == "OK" || $0 == "SKIP" }.count
        return Double(done) / 6.0
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
        refreshVersions()

        // Auto-detect existing token from config
        loadTokenFromConfig()

        // Load OpenRouter model from config if exists
        loadOpenRouterModelFromConfig()
        refreshUninstallInventory()

        if isActivated && !engine.hasCommand("brew") {
            showHomebrewPrompt = true
        }
        screen = isActivated ? .home : .license
    }

    private func loadOpenRouterModelFromConfig() {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agents = json["agents"] as? [String: Any],
              let defaults = agents["defaults"] as? [String: Any],
              let model = defaults["model"] as? [String: Any],
              let primary = model["primary"] as? String else {
            return
        }

        if primary.hasPrefix("openrouter/") {
            inferenceMode = .cloud
            selectedOpenRouterModel = primary
            selectedProvider = .openRouter
        } else if primary.hasPrefix("lmstudio/") {
            inferenceMode = .local
            let localId = primary.replacingOccurrences(of: "lmstudio/", with: "")
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

    func killHeavyProcess(_ pid: Int) {
        let result = engine.killProcess(pid: pid)
        controlCenterLogs += "[\(result.state.rawValue)] \(result.message)\n"
        refreshControlCenter()
    }

    func emergencyCleanupAction() {
        let result = engine.emergencyCleanup()
        controlCenterLogs += "[\(result.state.rawValue)] \(result.message)\n"
        refreshControlCenter()
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
        if inferenceMode == .cloud && providerNeedsApiKey() && requiredProviderKey().isEmpty {
            errors.append("Add API key for \(selectedProvider.rawValue)")
        }

        if inferenceMode == .local && selectedModel.isEmpty {
            errors.append("Select a local model")
        }
        
        // OpenRouter specific validation
        if inferenceMode == .cloud && selectedProvider == .openRouter {
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

    var isOpenAIOAuthMode: Bool {
        selectedProvider == .openAI && openAIAuthMethod == .oauth
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

    func useTestLicense() {
        licenseEmail = "cyril@test.local"
        licenseKey = "LCW-20991231-0001-BASE"
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

        if key.hasPrefix("LCW-") && !isValidOfflineKey(key) {
            activationStatus = "License expired or invalid format"
            return
        }

        if isValidOfflineKey(key) {
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
        let payload = LicenseActivationPayload(email: email, licenseKey: key, machineId: machineId, appVersion: "1.0.0")

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

        if isValidOfflineKey(record.licenseKey) || (record.expiresAt != nil) {
            isActivated = true
            activationStatus = "Activated on this Mac"
        } else {
            isActivated = false
            activationStatus = "License expired, renew required"
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
            await self.runStep(name: "Homebrew") { engine.installHomebrewIfNeeded() }
            if installLMStudio {
                await self.runStep(name: "LM Studio") { engine.installLMStudioIfNeeded() }
            } else {
                await MainActor.run { self.statusLMStudio = "SKIP" }
            }

            if installMode == .llmOnly {
                await self.runModelStep(engine: engine, query: modelQuery)
            } else {
                await MainActor.run { self.statusModel = "SKIP" }
            }

            await self.runStep(name: "Node") { engine.installNodeIfNeeded() }
            if installOpenClaw {
                await self.runStep(name: "OpenClaw") { engine.installOpenClawIfNeeded() }
                // Bug 5: Write gateway config before verify
                await self.runStep(name: "Config") { engine.writeOpenClawConfig(gatewayToken: token) }
                // Bug 6: Write model config
                await self.runStep(name: "Model Config") { engine.writeModelToConfig(modelIdentifier: modelId) }
                // Install gateway service and create agent
                await self.runStep(name: "Gateway Service") { engine.installGatewayService() }
                await self.runStep(name: "Default Agent") { engine.createDefaultAgent() }
                await self.runStep(name: "Start Gateway") { engine.startGateway() }
                await self.runStep(name: "OpenClaw Check") { engine.verifyOpenClawSetup() }
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

    func updateLocalClaw() {
        let defaultRepoDir = NSHomeDirectory() + "/LocalClaw"
        let repoDir = ProcessInfo.processInfo.environment["LOCALCLAW_REPO_DIR"] ?? defaultRepoDir
        let repoURL = ProcessInfo.processInfo.environment["LOCALCLAW_GITHUB_REPO"] ?? "https://github.com/CyrilDieumegard/LocalClaw.git"

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

        LOCAL_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
        REMOTE_SHA=$(git rev-parse origin/main 2>/dev/null || echo "")

        if [ -n "$LOCAL_SHA" ] && [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
          echo "Already up to date."
        else
          echo "Updating to latest main..."
          git pull --ff-only origin main || exit 1
        fi

        echo ""
        echo "Rebuilding..."
        swift build || exit 1

        echo ""
        echo "Done."
        echo "Run LocalClaw with:"
        echo "cd $REPO_DIR && swift run"
        echo ""
        read -r "REPLY?Press Enter to close..."
        """

        let scriptPath = "/tmp/localclaw_update.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            _ = engine.shell("chmod +x \(scriptPath)")
            _ = engine.shell("osascript -e 'tell application \"Terminal\" to do script \"\(scriptPath)\"'")
            append("Opened Terminal for LocalClaw update")
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
            await self.runStep(name: "Homebrew") { engine.updateHomebrew() }
            await self.runStep(name: "LM Studio") { engine.upgradeLMStudioIfInstalled() }
            await self.runStep(name: "Node") { engine.upgradeNodeIfInstalled() }
            await self.runStep(name: "OpenClaw") { engine.updateOpenClawIfInstalled() }
            await MainActor.run {
                self.isRunning = false
                self.refreshVersions()
                self.append("Update finished")
            }
        }
    }

    func openLMStudio() { _ = engine.shell("open -a 'LM Studio' || true") }
    func openOpenClaw() { _ = engine.shell("openclaw || true") }

    func openChannelDocs() {
        _ = engine.shell("open 'https://docs.openclaw.ai/channels' || true")
    }

    func openTerminalChannelLogin(_ channel: String) {
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
            echo "Running: $OPENCLAW_BIN channels login --channel \(channel)"
            echo ""
            "$OPENCLAW_BIN" channels login --channel \(channel)
            echo ""
            echo "If login is done, test with:"
            echo "$OPENCLAW_BIN message send --channel \(channel) --message \"LocalClaw test\""
            echo ""
        fi

        read -r "REPLY?Press Enter to close..."
        """

        let path = "/tmp/localclaw_channel_\(channel).sh"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        _ = engine.shell("chmod +x \(path)")
        _ = engine.shell("open -a Terminal \(path)")

        channelSetupLogs = channelSetupLogs.isEmpty ? "Started \(channel) login in Terminal" : channelSetupLogs + "\nStarted \(channel) login in Terminal"
    }

    func applyAgentTemplate(_ template: String) {
        switch template {
        case "founder":
            inferenceMode = .cloud
            selectedProvider = .openRouter
            selectedOpenRouterModel = "openrouter/moonshotai/kimi-k2.5"
            _ = engine.writeModelToConfig(modelIdentifier: selectedOpenRouterModel)
            templateLogs = "Applied Founder mode: Kimi K2.5 + cloud"
        case "support":
            inferenceMode = .cloud
            selectedProvider = .openRouter
            selectedOpenRouterModel = "openrouter/google/gemini-2.5-flash-preview"
            _ = engine.writeModelToConfig(modelIdentifier: selectedOpenRouterModel)
            templateLogs = "Applied Support mode: Gemini 2.5 Flash + cloud"
        case "growth":
            inferenceMode = .cloud
            selectedProvider = .openRouter
            selectedOpenRouterModel = "openrouter/openai/gpt-4o-mini"
            _ = engine.writeModelToConfig(modelIdentifier: selectedOpenRouterModel)
            templateLogs = "Applied Growth mode: GPT-4o Mini + cloud"
        case "dev":
            inferenceMode = .local
            selectedModel = !recommendation.isEmpty ? recommendation : (modelOptions.first ?? "")
            if let localId = localProviderModelIds[selectedModel] {
                _ = engine.writeModelToConfig(modelIdentifier: "lmstudio/\(localId)")
            }
            templateLogs = "Applied Dev mode: local \(selectedModel)"
        default:
            templateLogs = "Unknown template"
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
            selectedProvider = .custom
            ensureLMStudioAuthProfileForMainAgent()

            var localId = detectLiveLMStudioModelId()
            if localId.hasPrefix("lmstudio/") {
                localId = String(localId.dropFirst("lmstudio/".count))
            }
            if localId.contains("/") {
                localId = String(localId.split(separator: "/").last ?? Substring(localId))
            }

            if localId.isEmpty {
                if selectedModel.isEmpty {
                    selectedModel = !recommendation.isEmpty ? recommendation : (modelOptions.first ?? "")
                }
                localId = localProviderModelIds[selectedModel] ?? ""
            }

            if !localId.isEmpty {
                writePrimaryAndSecondaryModel(primary: "lmstudio/\(localId)", secondary: nil)
                controlCenterLogs += "[OK] Switched to Local: lmstudio/\(localId)\n"
            } else {
                controlCenterLogs += "[FAIL] Local switch failed: no model found in LM Studio\n"
            }
        } else {
            selectedProvider = .openRouter
            if selectedOpenRouterModel.isEmpty {
                selectedOpenRouterModel = "openrouter/moonshotai/kimi-k2.5"
            }
            writePrimaryAndSecondaryModel(primary: selectedOpenRouterModel, secondary: nil)
            controlCenterLogs += "[OK] Switched to Cloud: \(selectedOpenRouterModel)\n"
        }

        resetMainAgentSessions()
        _ = engine.shell("openclaw gateway restart --preserve-token 2>/dev/null || openclaw gateway restart 2>/dev/null || true")
        controlCenterLogs += "[OK] Gateway restarted after mode switch\n"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.refreshControlCenter()
            self.modeSwitchInProgress = false
            self.modeSwitchStatus = self.inferenceMode == .local ? "Switched to Local" : "Switched to Cloud"
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
        let installLMStudio = (inferenceMode == .local)
        let resolvedLocalModel = selectedModel.isEmpty ? recommendation : selectedModel
        let modelQuery = modelQueries[resolvedLocalModel] ?? ""
        let localModelSlug = modelQuery.split(separator: "@").first.map(String.init) ?? "openai"
        let providerModelId = localProviderModelIds[resolvedLocalModel] ?? localModelSlug
        let modelId = installLMStudio ? "lmstudio/\(providerModelId)" : (selectedProvider == .openRouter ? selectedOpenRouterModel : effectiveModelIdentifier())
        let authProvider = effectiveAuthProvider()
        let apiKey = installLMStudio ? "" : requiredProviderKey()
        
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
            lines.append("echo \"  → Downloading \(modelQuery)...\"")
            lines.append("LMS_CMD='lms'")
            lines.append("if ! command -v lms &>/dev/null; then")
            lines.append("  if [ -x \"/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms\" ]; then")
            lines.append("    LMS_CMD=\"/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms\"")
            lines.append("  fi")
            lines.append("fi")
            lines.append("$LMS_CMD get \(modelQuery) --gguf -y || echo \"  ! Model download failed, continue setup\"")
            lines.append("echo \"model:OK\" >> /tmp/localclaw_status")
        } else {
            lines.append("")
            lines.append("echo \"\"")
            lines.append("echo \"[2/7] Skipping LM Studio (cloud only)\"")
            lines.append("echo \"lmstudio:SKIP\" >> /tmp/localclaw_status")
            lines.append("")
            lines.append("echo \"\"")
            lines.append("echo \"[3/7] Skipping local model (cloud only)\"")
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
        lines.append("        \"primary\": \"\(modelId)\"")
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
            lines.append("          { \"id\": \"\(providerModelId)\", \"name\": \"\(resolvedLocalModel)\", \"reasoning\": false, \"input\": [\"text\"], \"cost\": { \"input\": 0, \"output\": 0, \"cacheRead\": 0, \"cacheWrite\": 0 }, \"contextWindow\": 32768, \"maxTokens\": 4096 }")
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

    private func runStep(name: String, action: @escaping () -> StepResult) async {
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
    static let bg = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let bg2 = Color(red: 0.94, green: 0.94, blue: 0.93)
    static let card = Color(red: 0.97, green: 0.97, blue: 0.96)
    static let cardSoft = Color(red: 0.98, green: 0.98, blue: 0.97)
    static let accent = Color(red: 1.00, green: 0.30, blue: 0.24)
    static let accent2 = Color(red: 1.00, green: 0.42, blue: 0.24)
    static let text = Color(red: 0.12, green: 0.17, blue: 0.28)
    static let muted = Color(red: 0.37, green: 0.45, blue: 0.57)
}

enum AppFont {
    static func heading(_ size: CGFloat) -> Font { .custom("SpaceGrotesk-Bold", size: size) }
    static func body(_ size: CGFloat) -> Font { .custom("Inter-Regular", size: size) }
    static func bodySemi(_ size: CGFloat) -> Font { .custom("Inter-SemiBold", size: size) }
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
    let action: () -> Void

    private var iconColor: Color {
        selected ? UI.accent : Color.black.opacity(0.72)
    }

    private var cardFill: AnyShapeStyle {
        selected
            ? AnyShapeStyle(LinearGradient(colors: [UI.accent.opacity(0.18), UI.accent2.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(LinearGradient(colors: [UI.card, UI.cardSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var cardStroke: Color {
        selected ? UI.accent.opacity(0.45) : Color.black.opacity(0.08)
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

                Text(label)
                    .font(AppFont.bodySemi(18))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .frame(width: 180)
            }
            .frame(width: 190)
        }
        .buttonStyle(.plain)
    }
}

struct ProgressSteps: View {
    let screen: InstallerViewModel.Screen

    private var idx: Int {
        switch screen {
        case .license: return 0
        case .home: return 0
        case .options: return 1
        case .install: return 2
        case .ready: return 3
        case .updates: return 3
        case .controlCenter: return 0
        case .commandCenter: return 0
        case .uninstallCenter: return 0
        case .channelSetup: return 0
        case .templates: return 0
        case .healthCenter: return 0
        case .usageCenter: return 0
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
            .fill(Color.black.opacity(0.12))
            .frame(height: 3)
    }

    private func step(_ label: String, _ number: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(idx + 1 >= number ? UI.accent : Color.black.opacity(0.10))
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
    @StateObject private var vm = InstallerViewModel()

    var body: some View {
        ZStack {
            LinearGradient(colors: [UI.bg, UI.bg2], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            if vm.screen == .license {
                VStack(spacing: 16) {
                    topBar
                    license
                }
                .frame(maxWidth: 1120)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            } else {
                HStack(spacing: 16) {
                    sidebar
                        .frame(width: 240)

                    VStack(spacing: 14) {
                        topBar

                        Group {
                            switch vm.screen {
                            case .license: license
                            case .home: home
                            case .options: options
                            case .install: install
                            case .ready: ready
                            case .updates: updates
                            case .controlCenter: controlCenter
                            case .commandCenter: commandCenter
                            case .uninstallCenter: uninstallCenter
                            case .channelSetup: channelSetup
                            case .templates: templates
                            case .healthCenter: healthCenter
                            case .usageCenter: usageCenter
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: 1260, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReturnToHome"))) { _ in
            vm.screen = .home
        }
        .frame(minWidth: 980, idealWidth: 1220, maxWidth: 1500,
               minHeight: 700, idealHeight: 820, maxHeight: 1100)
        .onAppear { vm.bootstrap() }
        .alert("Homebrew Required", isPresented: $vm.showHomebrewPrompt) {
            Button("Install Homebrew", role: .none) { vm.installHomebrewWithUserConsent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Homebrew is needed to install LM Studio, Node.js and OpenClaw. Click 'Install Homebrew' and enter your Mac password when prompted.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            BrandLogoView(size: 20)
            Text("LocalClaw")
                .font(AppFont.bodySemi(18))
                .foregroundStyle(UI.text)

            Text(vm.inferenceMode == .local ? "LOCAL" : "CLOUD")
                .font(AppFont.bodySemi(10))
                .foregroundStyle(vm.inferenceMode == .local ? Color(NSColor.systemGreen) : UI.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Picker("", selection: $vm.inferenceMode) {
                    Text("Cloud").tag(InstallerViewModel.InferenceMode.cloud)
                    Text("Local").tag(InstallerViewModel.InferenceMode.local)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
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
            sidebarButton("Command Center", icon: "slider.horizontal.3", isActive: vm.screen == .commandCenter) { vm.screen = .commandCenter }
            sidebarButton("Channels", icon: "bubble.left.and.bubble.right", isActive: vm.screen == .channelSetup) { vm.screen = .channelSetup }
            sidebarButton("Templates", icon: "square.grid.2x2", isActive: vm.screen == .templates) { vm.screen = .templates }
            sidebarButton("Health", icon: "cross.case", isActive: vm.screen == .healthCenter) { vm.screen = .healthCenter }
            sidebarButton("Usage & Cost", icon: "dollarsign.circle", isActive: vm.screen == .usageCenter) { vm.screen = .usageCenter }
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
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private func sidebarButton(_ title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .font(AppFont.bodySemi(13))
                Spacer()
            }
            .foregroundStyle(isActive ? .white : UI.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(isActive ? UI.accent : UI.cardSoft))
        }
        .buttonStyle(.plain)
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
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
    }

    var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("LocalClaw")
                        .font(AppFont.heading(40))
                        .foregroundStyle(UI.text)
                    Text("Install, update or control your OpenClaw setup.")
                        .font(AppFont.body(16))
                        .foregroundStyle(UI.muted)

                    HStack(spacing: 10) {
                        Button("Use Local LLM") {
                            vm.inferenceMode = .local
                            if vm.selectedModel.isEmpty { vm.selectedModel = vm.recommendation }
                            vm.screen = .options
                        }
                        .buttonStyle(CTAButton(primary: vm.inferenceMode == .local))

                        Button("Use Cloud") {
                            vm.inferenceMode = .cloud
                            vm.selectedModel = ""
                            vm.screen = .options
                        }
                        .buttonStyle(CTAButton(primary: vm.inferenceMode == .cloud))
                    }
                }
                .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 220), spacing: 18, alignment: .top)], spacing: 20) {
                    HomeTile(label: "Install", icon: "plus.circle", selected: false) {
                        vm.chooseMode(.fullInstall)
                    }
                    HomeTile(label: "Update Center", icon: "arrow.clockwise", selected: false) {
                        vm.screen = .updates
                    }
                    HomeTile(label: "Control Center", icon: "slider.horizontal.3", selected: false) {
                        vm.screen = .commandCenter
                    }
                    HomeTile(label: "Channels", icon: "bubble.left.and.bubble.right", selected: false) {
                        vm.screen = .channelSetup
                    }
                    HomeTile(label: "Templates", icon: "square.grid.2x2", selected: false) {
                        vm.screen = .templates
                    }
                    HomeTile(label: "Health", icon: "cross.case", selected: false) {
                        vm.screen = .healthCenter
                    }
                    HomeTile(label: "Usage & Cost", icon: "dollarsign.circle", selected: false) {
                        vm.screen = .usageCenter
                    }
                    HomeTile(label: "Uninstall Center", icon: "trash", selected: false) {
                        vm.screen = .uninstallCenter
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
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
                    .onChange(of: vm.inferenceMode) { newValue in
                        if newValue == .local {
                            if vm.selectedModel.isEmpty {
                                vm.selectedModel = vm.recommendation
                            }
                            vm.selectedProvider = .custom
                        } else {
                            vm.selectedModel = ""
                            if vm.selectedProvider == .custom {
                                vm.selectedProvider = .openRouter
                            }
                        }
                    }

                    Text(vm.inferenceMode == .local ? "Run fully local with LM Studio" : "Use cloud models via provider API")
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

                if vm.inferenceMode == .cloud {
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

                    Button(vm.isRunning ? "Installing in Terminal..." : "Install Everything") {
                        vm.openTerminalAndInstallFull()
                    }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(vm.isRunning)
                }
            }
            .padding(22)
            .frame(maxWidth: 600, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
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

            Picker("Provider", selection: $vm.selectedProvider) {
                ForEach(InstallerViewModel.AIProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.menu)

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

    @ViewBuilder
    private var openRouterModelPicker: some View {
        if vm.selectedProvider == .openRouter && vm.openRouterKeyVerified {
            Picker("Model", selection: $vm.selectedOpenRouterModel) {
                ForEach(InstallerViewModel.openRouterModels, id: \.self) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        if vm.selectedProvider == .openAI {
            VStack(alignment: .leading, spacing: 8) {
                Picker("OpenAI auth", selection: $vm.openAIAuthMethod) {
                    ForEach(InstallerViewModel.AIProvider.OpenAIAuthMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if vm.openAIAuthMethod == .apiKey {
                    SecureField("OpenAI API Key", text: $vm.openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text("OAuth uses your ChatGPT/Codex account (no API key needed).")
                        .font(AppFont.body(11))
                        .foregroundStyle(UI.muted)

                    Button("Sign in with OpenAI (OAuth)") {
                        vm.openTerminalOpenAIOAuth()
                    }
                    .buttonStyle(CTAButton(primary: false))
                }
            }
        } else if vm.providerNeedsApiKey() {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("API Key", text: bindingForProviderKey())
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 3: Installing")
                .font(AppFont.heading(30)).foregroundStyle(UI.text)
            ProgressView(value: vm.progress).tint(UI.accent)
            statusRow("Homebrew", vm.statusHomebrew)
            statusRow("LM Studio", vm.statusLMStudio)
            statusRow("Model", vm.statusModel)
            statusRow("Node", vm.statusNode)
            statusRow("OpenClaw", vm.statusOpenClaw)
            statusRow("OpenClaw Check", vm.statusOpenClawCheck)
            ScrollView {
                Text(vm.logs).font(.system(size: 12, design: .monospaced)).foregroundStyle(UI.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(height: 180)

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
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
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
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.07), lineWidth: 1))

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
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.07), lineWidth: 1))

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
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.07), lineWidth: 1))

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
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
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

            VStack(spacing: 8) {
                versionRow("OpenClaw", vm.openclawInstalledVersion, vm.openclawLatestVersion, isUpToDate: vm.openclawUpdateStatus == "Up to date")
                versionRow("Homebrew", vm.brewVersion, "latest via brew update", isUpToDate: vm.brewUpToDate)
                versionRow("Node", vm.nodeVersion, "latest via brew upgrade", isUpToDate: vm.nodeUpToDate)
                versionRow("LM Studio", vm.lmStudioVersion, "latest via brew cask", isUpToDate: vm.lmStudioUpToDate)
                versionRow("LocalClaw", vm.installerCurrentVersion, vm.installerLatestVersion, isUpToDate: vm.installerUpdateStatus == "Up to date")
            }

            HStack(spacing: 10) {
                Button(vm.isRunning ? "UPDATING..." : "UPDATE ALL") { vm.updateAll() }
                    .buttonStyle(CTAButton(primary: true))
                    .disabled(vm.isRunning)
                Button("CHECK") { vm.refreshVersions() }.buttonStyle(CTAButton(primary: false))
                Button("UPDATE LOCALCLAW") { vm.updateLocalClaw() }
                    .buttonStyle(CTAButton(primary: false))
                Button("BACK") { vm.screen = .home }.buttonStyle(CTAButton(primary: false))
            }

            Divider().overlay(Color.black.opacity(0.08))

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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
    }

    var templates: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AGENT TEMPLATES")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("One-click presets by use-case.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button("Founder mode") { vm.applyAgentTemplate("founder") }
                    .buttonStyle(CTAButton(primary: true))
                Button("Support mode") { vm.applyAgentTemplate("support") }
                    .buttonStyle(CTAButton(primary: false))
                Button("Growth mode") { vm.applyAgentTemplate("growth") }
                    .buttonStyle(CTAButton(primary: false))
                Button("Dev mode") { vm.applyAgentTemplate("dev") }
                    .buttonStyle(CTAButton(primary: false))
            }

            Text("Applied template log")
                .font(AppFont.bodySemi(14))
                .foregroundStyle(UI.muted)

            ScrollView {
                Text(vm.templateLogs.isEmpty ? "No template applied yet." : vm.templateLogs)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(UI.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
    }

    var healthCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HEALTH & RECOVERY")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Diagnose, repair, and backup your setup.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Text(vm.healthStatus)
                    .font(AppFont.bodySemi(12))
                    .foregroundStyle(vm.healthStatus == "Healthy" ? .green : (vm.healthStatus == "Critical" ? .red : .orange))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(UI.cardSoft))
            }

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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
    }

    var usageCenter: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("USAGE & COST")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Estimate token costs and optimize model spend.")
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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))

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
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
        .onAppear { vm.refreshUsageCostEstimate() }
    }

    var channelSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CHANNEL SETUP")
                        .font(AppFont.heading(28))
                        .foregroundStyle(UI.text)
                    Text("Connect messaging channels in one click.")
                        .font(AppFont.body(13))
                        .foregroundStyle(UI.muted)
                }
                Spacer()
                Button("Open docs") { vm.openChannelDocs() }
                    .buttonStyle(CTAButton(primary: false))
            }

            HStack(spacing: 10) {
                Button("Connect Telegram") { vm.openTerminalChannelLogin("telegram") }
                    .buttonStyle(CTAButton(primary: true))
                Button("Connect WhatsApp") { vm.openTerminalChannelLogin("whatsapp") }
                    .buttonStyle(CTAButton(primary: false))
                Button("Connect Discord") { vm.openTerminalChannelLogin("discord") }
                    .buttonStyle(CTAButton(primary: false))
            }

            Text("Live log")
                .font(AppFont.bodySemi(14))
                .foregroundStyle(UI.muted)

            ScrollView {
                Text(vm.channelSetupLogs.isEmpty ? "No channel setup started yet." : vm.channelSetupLogs)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(UI.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
            .background(RoundedRectangle(cornerRadius: 10).fill(UI.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
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
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.07), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Safety")
                            .font(AppFont.bodySemi(13))
                            .foregroundStyle(UI.text)
                        Text("Open apps may respawn background processes. Close LM Studio and browsers first for a cleaner uninstall.")
                            .font(AppFont.body(12))
                            .foregroundStyle(UI.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider().overlay(Color.black.opacity(0.08))

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
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.07), lineWidth: 1))
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08), lineWidth: 1))
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
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.05), lineWidth: 1))
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
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.06), lineWidth: 1))
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
                            // Recommended
                            Text("⭐ Kimi K2.5").tag("openrouter/moonshotai/kimi-k2.5")
                            Text("⭐ Claude 3.5 Sonnet").tag("openrouter/anthropic/claude-3.5-sonnet")
                            Text("⭐ GPT-4o").tag("openrouter/openai/gpt-4o")
                            Text("⭐ GPT-4o Mini").tag("openrouter/openai/gpt-4o-mini")
                            
                            Divider()
                            
                            // All others
                            Text("Claude 3.5 Haiku").tag("openrouter/anthropic/claude-3.5-haiku")
                            Text("Claude 3 Opus").tag("openrouter/anthropic/claude-3-opus")
                            Text("Claude 3 Sonnet").tag("openrouter/anthropic/claude-3-sonnet")
                            Text("Claude 3 Haiku").tag("openrouter/anthropic/claude-3-haiku")
                            Text("GPT-4 Turbo").tag("openrouter/openai/gpt-4-turbo")
                            Text("GPT-4").tag("openrouter/openai/gpt-4")
                            Text("GPT-3.5 Turbo").tag("openrouter/openai/gpt-3.5-turbo")
                            Text("Gemini 2.5 Flash").tag("openrouter/google/gemini-2.5-flash-preview")
                            Text("Gemini 2.0 Flash").tag("openrouter/google/gemini-2.0-flash-exp")
                            Text("Gemini 1.5 Pro").tag("openrouter/google/gemini-1.5-pro")
                            Text("Llama 3.3 70B").tag("openrouter/meta-llama/llama-3.3-70b-instruct")
                            Text("Llama 3.2 90B Vision").tag("openrouter/meta-llama/llama-3.2-90b-vision-instruct")
                            Text("Llama 3.1 405B").tag("openrouter/meta-llama/llama-3.1-405b-instruct")
                            Text("Llama 3.1 70B").tag("openrouter/meta-llama/llama-3.1-70b-instruct")
                            Text("Llama 3.1 8B").tag("openrouter/meta-llama/llama-3.1-8b-instruct")
                            Text("DeepSeek Chat").tag("openrouter/deepseek/deepseek-chat")
                            Text("DeepSeek Coder").tag("openrouter/deepseek/deepseek-coder")
                            Text("Mistral Large").tag("openrouter/mistralai/mistral-large")
                            Text("Mistral Medium").tag("openrouter/mistralai/mistral-medium")
                            Text("Mistral Small").tag("openrouter/mistralai/mistral-small")
                            Text("Qwen 3.5 35B-A3B").tag("openrouter/qwen/qwen3.5-35b-a3b")
                            Text("Qwen 3.5 27B").tag("openrouter/qwen/qwen3.5-27b")
                            Text("Qwen 3.5 122B-A10B").tag("openrouter/qwen/qwen3.5-122b-a10b")
                            Text("Qwen 3.5 9B").tag("openrouter/qwen/qwen3.5-9b")
                            Text("Qwen 3.5 4B").tag("openrouter/qwen/qwen3.5-4b")
                            Text("Qwen 3.5 2B").tag("openrouter/qwen/qwen3.5-2b")
                            Text("Qwen 3.5 0.8B").tag("openrouter/qwen/qwen3.5-0.8b")
                            Text("Qwen 2.5 72B").tag("openrouter/qwen/qwen-2.5-72b-instruct")
                            Text("Qwen 2.5 32B").tag("openrouter/qwen/qwen-2.5-32b-instruct")
                            Text("Grok 2").tag("openrouter/x-ai/grok-2")
                            Text("Grok 2 Mini").tag("openrouter/x-ai/grok-2-mini")
                            Text("Command R+").tag("openrouter/cohere/command-r-plus")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 280)

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
            ContentView().preferredColorScheme(.light)
        }
    }
}
