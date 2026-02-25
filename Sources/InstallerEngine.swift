import Foundation

enum InstallState: String {
    case pending = "PENDING"
    case ok = "OK"
    case skip = "SKIP"
    case fail = "FAIL"
}

struct HardwareProfile {
    let chip: String
    let memoryGB: Int
    let isAppleSilicon: Bool
}

struct Recommendation {
    let tier: String
    let model: String
    let quant: String
    let rationale: String
}

struct StepResult {
    let state: InstallState
    let message: String
}

struct VersionInfo {
    let installed: String
    let latest: String
    let updateAvailable: Bool
}

struct LicenseActivationPayload: Codable {
    let email: String
    let licenseKey: String
    let machineId: String
    let appVersion: String
}

struct LicenseActivationResponse: Codable {
    let ok: Bool
    let token: String?
    let message: String?
    let expiresAt: String?
}

final class InstallerEngine: @unchecked Sendable {
    private func lmsCommandPath() -> String {
        if hasCommand("lms") { return "lms" }
        let bundled = "/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms"
        if FileManager.default.fileExists(atPath: bundled) { return "'\(bundled)'" }
        return "lms"
    }

    func shell(_ command: String) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return (1, "Failed command: \(command)\n\(error.localizedDescription)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func detectHardware() -> HardwareProfile {
        let (_, chipRaw) = shell("sysctl -n machdep.cpu.brand_string 2>/dev/null || true")
        let chip = chipRaw.isEmpty ? "Apple Silicon" : chipRaw

        let (_, memRaw) = shell("sysctl -n hw.memsize")
        let memBytes = Int64(memRaw) ?? 0
        let memGB = max(1, Int((Double(memBytes) / 1024 / 1024 / 1024).rounded()))

        let c = chip.lowercased()
        let isAppleSilicon = c.contains("apple") || c.contains("m1") || c.contains("m2") || c.contains("m3") || c.contains("m4")

        return HardwareProfile(chip: chip, memoryGB: memGB, isAppleSilicon: isAppleSilicon)
    }

    func recommend(for profile: HardwareProfile) -> Recommendation {
        switch profile.memoryGB {
        case ..<16:
            return Recommendation(tier: "Starter", model: "Qwen 3 8B", quant: "Q4_K_M", rationale: "Fast and stable on 8-16 GB")
        case 16..<32:
            return Recommendation(tier: "Balanced", model: "Qwen 3 14B", quant: "Q4_K_M", rationale: "Best quality and speed on 16-24 GB")
        default:
            return Recommendation(tier: "Power", model: "Qwen 3 32B", quant: "Q4_K_M", rationale: "Higher quality on 32 GB+")
        }
    }

    func hasCommand(_ name: String) -> Bool {
        let (code, out) = shell("command -v \(name)")
        return code == 0 && !out.isEmpty
    }

    func hasLMStudioApp() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/LM Studio.app")
    }

    func installHomebrewIfNeeded() -> StepResult {
        if hasCommand("brew") {
            return StepResult(state: .skip, message: "Homebrew already installed")
        }
        // Try regular install first
        let (code, _) = shell("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
        if code == 0 {
            configureBrewPath()
            return StepResult(state: .ok, message: "Homebrew installed")
        }
        // If regular install fails (non-admin, non-interactive), try with admin privileges via osascript
        return installHomebrewWithAdmin()
    }

    private func installHomebrewWithAdmin() -> StepResult {
        let script = """
        do shell script "/bin/bash -c \\\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\\"" with administrator privileges
        """
        let (code, out) = shell("osascript -e '\(script)'")
        if code == 0 {
            configureBrewPath()
            return StepResult(state: .ok, message: "Homebrew installed (admin)")
        }
        return StepResult(state: .fail, message: "Homebrew install failed (admin required).\n\(out)")
    }

    private func configureBrewPath() {
        // Ensure brew is on PATH for Apple Silicon Macs
        let armBrewPath = "/opt/homebrew/bin"
        let intelBrewPath = "/usr/local/bin"
        if FileManager.default.fileExists(atPath: "\(armBrewPath)/brew") {
            _ = shell("echo 'eval \"$(\(armBrewPath)/brew shellenv)\"' >> ~/.zprofile && eval \"$(\(armBrewPath)/brew shellenv)\"")
        } else if FileManager.default.fileExists(atPath: "\(intelBrewPath)/brew") {
            _ = shell("echo 'eval \"$(\(intelBrewPath)/brew shellenv)\"' >> ~/.zprofile && eval \"$(\(intelBrewPath)/brew shellenv)\"")
        }
    }

    func installLMStudioIfNeeded() -> StepResult {
        if hasLMStudioApp() {
            return StepResult(state: .skip, message: "LM Studio already installed")
        }
        let (code, out) = shell("brew install --cask lm-studio")
        return code == 0
            ? StepResult(state: .ok, message: "LM Studio installed")
            : StepResult(state: .fail, message: out)
    }

    func installNodeIfNeeded() -> StepResult {
        if hasCommand("node") {
            return StepResult(state: .skip, message: "Node already installed")
        }
        let (code, out) = shell("brew install node")
        return code == 0
            ? StepResult(state: .ok, message: "Node installed")
            : StepResult(state: .fail, message: out)
    }

    func installOpenClawIfNeeded() -> StepResult {
        if hasCommand("openclaw") {
            return StepResult(state: .skip, message: "openclaw command already present")
        }
        let (code, out) = shell("npm i -g openclaw@latest")
        return code == 0
            ? StepResult(state: .ok, message: "Installed with: npm i -g openclaw@latest")
            : StepResult(state: .fail, message: out)
    }

    /// Write gateway.mode=local and gateway auth token to openclaw.json (Bug 5)
    func writeOpenClawConfig(gatewayToken: String) -> StepResult {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        let configDir = NSHomeDirectory() + "/.openclaw"

        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        var config: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
        }

        // Set gateway.mode = "local" and auth
        var gateway = config["gateway"] as? [String: Any] ?? [:]
        gateway["mode"] = "local"
        gateway["port"] = 18789
        gateway["bind"] = "loopback"
        if !gatewayToken.isEmpty {
            var auth: [String: Any] = gateway["auth"] as? [String: Any] ?? [:]
            auth["mode"] = "token"
            auth["token"] = gatewayToken
            gateway["auth"] = auth
        }
        config["gateway"] = gateway

        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            return StepResult(state: .ok, message: "Config written: gateway.mode=local")
        } catch {
            return StepResult(state: .fail, message: "Failed to write config: \(error.localizedDescription)")
        }
    }

    /// Write the selected AI model to openclaw.json (Bug 6)
    func writeModelToConfig(modelIdentifier: String) -> StepResult {
        if modelIdentifier.isEmpty {
            return StepResult(state: .skip, message: "No model to configure")
        }

        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"

        var config: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
        }

        // Set agents.defaults.model.primary
        var agents = config["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]
        var model = defaults["model"] as? [String: Any] ?? [:]
        model["primary"] = modelIdentifier
        defaults["model"] = model
        agents["defaults"] = defaults
        config["agents"] = agents

        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            return StepResult(state: .ok, message: "Model configured: \(modelIdentifier)")
        } catch {
            return StepResult(state: .fail, message: "Failed to write model config: \(error.localizedDescription)")
        }
    }

    /// Write API key to OpenClaw config + agent auth store
    func writeApiKeyToConfig(provider: String, apiKey: String) -> StepResult {
        if apiKey.isEmpty { return StepResult(state: .skip, message: "No API key provided") }

        let fm = FileManager.default
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        let authStorePath = NSHomeDirectory() + "/.openclaw/agents/main/agent/auth-profiles.json"

        // 1) Write ~/.openclaw/openclaw.json (legacy/global path)
        var config: [String: Any] = [:]
        if let data = fm.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
        }

        var auth = config["auth"] as? [String: Any] ?? [:]
        var profiles = auth["profiles"] as? [String: Any] ?? [:]

        let profileKey = "\(provider):default"
        let profile: [String: Any] = [
            "type": "api_key",
            "provider": provider,
            "key": apiKey
        ]
        profiles[profileKey] = profile
        auth["profiles"] = profiles
        config["auth"] = auth

        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        } catch {
            return StepResult(state: .fail, message: "Failed to write openclaw.json API key: \(error.localizedDescription)")
        }

        // 2) Write ~/.openclaw/agents/main/agent/auth-profiles.json (actual runtime store)
        do {
            let authStoreDir = (authStorePath as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: authStoreDir, withIntermediateDirectories: true)

            var authStore: [String: Any] = [:]
            if let data = fm.contents(atPath: authStorePath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                authStore = json
            }

            var storedProfiles = authStore["profiles"] as? [String: Any] ?? [:]
            storedProfiles[profileKey] = profile
            authStore["version"] = (authStore["version"] as? Int) ?? 1
            authStore["profiles"] = storedProfiles

            let data = try JSONSerialization.data(withJSONObject: authStore, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: authStorePath), options: .atomic)
        } catch {
            return StepResult(state: .fail, message: "Failed to write auth-profiles.json: \(error.localizedDescription)")
        }

        // 3) Also write key into ~/.openclaw/.env
        let envPath = NSHomeDirectory() + "/.openclaw/.env"
        var envLines: [String] = []
        if let existing = try? String(contentsOfFile: envPath, encoding: .utf8) {
            envLines = existing.components(separatedBy: "\n")
        }

        let envKeyMap: [String: String] = [
            "openrouter": "OPENROUTER_API_KEY",
            "openai": "OPENAI_API_KEY",
            "anthropic": "ANTHROPIC_API_KEY",
            "google": "GEMINI_API_KEY",
            "xai": "XAI_API_KEY"
        ]

        if let envKey = envKeyMap[provider] {
            envLines = envLines.filter { !$0.hasPrefix("\(envKey)=") }
            envLines.append("\(envKey)=\(apiKey)")
            try? envLines.joined(separator: "\n").write(toFile: envPath, atomically: true, encoding: .utf8)
        }

        return StepResult(state: .ok, message: "API key saved for \(provider) (openclaw.json + auth store + .env)")
    }

    /// Install gateway service (LaunchAgent)
    func installGatewayService() -> StepResult {
        let (code, out) = shell("openclaw gateway install")
        return code == 0
            ? StepResult(state: .ok, message: "Gateway service installed")
            : StepResult(state: .fail, message: out)
    }

    /// Start gateway service
    func startGateway() -> StepResult {
        let (code, out) = shell("openclaw gateway start")
        return code == 0
            ? StepResult(state: .ok, message: "Gateway started")
            : StepResult(state: .fail, message: out)
    }

    /// Create default agent
    func createDefaultAgent() -> StepResult {
        let (code, out) = shell("openclaw agent init main --default")
        return code == 0
            ? StepResult(state: .ok, message: "Agent 'main' created")
            : StepResult(state: .fail, message: out)
    }

    /// Run doctor repair
    func runDoctorRepair() -> StepResult {
        let (code, out) = shell("openclaw doctor --repair --yes --no-color 2>&1")
        return code == 0
            ? StepResult(state: .ok, message: "Doctor repair completed")
            : StepResult(state: .fail, message: out)
    }

    /// Restart gateway
    func restartGateway() -> StepResult {
        let (code, out) = shell("openclaw gateway restart 2>&1")
        return code == 0
            ? StepResult(state: .ok, message: "Gateway restarted")
            : StepResult(state: .fail, message: out)
    }

    /// Change model
    func changeModel(_ modelId: String) -> StepResult {
        // Write model to config directly
        let result = writeModelToConfig(modelIdentifier: modelId)
        
        // Also update the agents/main/.session file if it exists
        let workspacePath = NSHomeDirectory() + "/.openclaw/agents/main"
        let modelFilePath = workspacePath + "/.model"
        
        do {
            try FileManager.default.createDirectory(atPath: workspacePath, withIntermediateDirectories: true)
            try modelId.write(toFile: modelFilePath, atomically: true, encoding: .utf8)
        } catch {
            // Non-critical, just log
        }
        
        // Just restart gateway, don't regenerate token
        _ = shell("openclaw gateway restart --preserve-token 2>&1 || openclaw gateway restart 2>&1 || true")
        
        return StepResult(state: result.state, message: "Model set to \(modelId). Gateway restarted to apply changes.")
    }

    /// Get gateway status
    func getGatewayStatus() -> (isRunning: Bool, message: String) {
        let (code, out) = shell("openclaw gateway status --no-color 2>&1 | head -5")
        return (code == 0, out)
    }

    /// Get current model
    func getCurrentModel() -> String {
        let (_, out) = shell("openclaw agent current 2>&1 || echo 'Unknown'")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Open the OpenClaw dashboard in the default browser
    func openDashboard() -> StepResult {
        // Start gateway if not running
        _ = shell("openclaw gateway start 2>/dev/null || true")
        // Give it a moment
        _ = shell("sleep 2")
        
        // Read token from config
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        var token = ""
        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let t = auth["token"] as? String {
            token = t
        }
        
        // Open dashboard with token if available
        let url = token.isEmpty ? "http://localhost:18789" : "http://localhost:18789?token=\(token)"
        let (code, _) = shell("open '\(url)'")
        return code == 0
            ? StepResult(state: .ok, message: token.isEmpty ? "Dashboard opened" : "Dashboard opened with token")
            : StepResult(state: .fail, message: "Could not open dashboard")
    }

    func verifyOpenClawSetup() -> StepResult {
        let (vCode, vOut) = shell("openclaw --version")
        if vCode != 0 {
            return StepResult(state: .fail, message: "OpenClaw CLI check failed")
        }

        let (sCode, _) = shell("openclaw status --no-color")
        if sCode != 0 {
            return StepResult(state: .fail, message: "Gateway status check failed")
        }

        let version = vOut.components(separatedBy: "\n").first ?? vOut
        return StepResult(state: .ok, message: "OpenClaw ready (\(version))")
    }

    func repairOpenClawSetupQuiet() -> StepResult {
        let (code, _) = shell("openclaw doctor --non-interactive --repair --yes --no-color")
        return code == 0
            ? StepResult(state: .ok, message: "Configuration repair completed")
            : StepResult(state: .fail, message: "Configuration repair failed")
    }

    func runOpenClawInAppSetup() -> [StepResult] {
        var results: [StepResult] = []

        let (vCode, vOut) = shell("openclaw --version")
        if vCode == 0 {
            results.append(StepResult(state: .ok, message: "CLI detected: \(vOut.components(separatedBy: "\n").first ?? vOut)"))
        } else {
            results.append(StepResult(state: .fail, message: "OpenClaw CLI not available"))
            return results
        }

        let (dCode, dOut) = shell("openclaw doctor --non-interactive --repair --yes --no-color")
        results.append(StepResult(state: dCode == 0 ? .ok : .fail, message: dOut.isEmpty ? "Doctor completed" : dOut))

        let (gCode, gOut) = shell("openclaw gateway status --no-color")
        results.append(StepResult(state: gCode == 0 ? .ok : .fail, message: gOut.isEmpty ? "Gateway checked" : gOut))

        return results
    }

    func hasModelInstalled(_ query: String) -> Bool {
        let base = query.split(separator: "@").first.map(String.init) ?? query
        let lms = lmsCommandPath()
        let (code, out) = shell("\(lms) ls")
        return code == 0 && out.lowercased().contains(base.lowercased())
    }

    func installModelIfNeeded(_ query: String) -> StepResult {
        if query.isEmpty {
            return StepResult(state: .skip, message: "Model query missing")
        }
        if hasModelInstalled(query) {
            return StepResult(state: .skip, message: "Model already installed")
        }
        let lms = lmsCommandPath()
        let (code, out) = shell("\(lms) get \(query) --gguf -y")
        return code == 0
            ? StepResult(state: .ok, message: "Model installed in LM Studio")
            : StepResult(state: .fail, message: out)
    }

    func installModelStreaming(_ query: String, onLine: @escaping @Sendable (String) -> Void) -> StepResult {
        if query.isEmpty {
            return StepResult(state: .skip, message: "Model query missing")
        }
        if hasModelInstalled(query) {
            return StepResult(state: .skip, message: "Model already installed")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\(lmsCommandPath()) get \(query) --gguf -y"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = ""
        var fullOutput = ""

        do {
            try process.run()
        } catch {
            return StepResult(state: .fail, message: "Failed to start model install: \(error.localizedDescription)")
        }

        let handle = pipe.fileHandleForReading
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { continue }
            fullOutput += chunk
            buffer += chunk
            let parts = buffer.components(separatedBy: "\n")
            for line in parts.dropLast() {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { onLine(clean) }
            }
            buffer = parts.last ?? ""
        }

        process.waitUntilExit()

        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { onLine(tail) }

        if process.terminationStatus == 0 {
            return StepResult(state: .ok, message: "Model installed in LM Studio")
        }
        return StepResult(state: .fail, message: fullOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func installedVersion(for command: String) -> String {
        let (code, out) = shell("\(command) --version")
        if code != 0 || out.isEmpty { return "Not installed" }
        return out.components(separatedBy: "\n").first ?? out
    }

    func machineIdentifier() -> String {
        let (code, out) = shell("ioreg -rd1 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}'")
        if code == 0 {
            let clean = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return clean }
        }
        return Host.current().localizedName ?? UUID().uuidString
    }

    func installedLMStudioVersion() -> String {
        let app = "/Applications/LM Studio.app"
        if !FileManager.default.fileExists(atPath: app) { return "Not installed" }
        let (code, out) = shell("/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/LM Studio.app/Contents/Info.plist' 2>/dev/null")
        return (code == 0 && !out.isEmpty) ? out : "Installed"
    }

    func latestOpenClawVersion() -> String {
        let (code, out) = shell("npm view openclaw version 2>/dev/null")
        return (code == 0 && !out.isEmpty) ? out : "Unknown"
    }

    func openClawVersionInfo() -> VersionInfo {
        let installedRaw = installedVersion(for: "openclaw")
        let installed = installedRaw.replacingOccurrences(of: "OpenClaw ", with: "")
        let latest = latestOpenClawVersion()
        if installed == "Not installed" || latest == "Unknown" {
            return VersionInfo(installed: installed, latest: latest, updateAvailable: false)
        }
        return VersionInfo(installed: installed, latest: latest, updateAvailable: installed != latest)
    }

    func updateHomebrew() -> StepResult {
        let (code, out) = shell("brew update")
        return code == 0 ? StepResult(state: .ok, message: "Homebrew updated") : StepResult(state: .fail, message: out)
    }

    func upgradeLMStudioIfInstalled() -> StepResult {
        if !hasLMStudioApp() {
            return StepResult(state: .skip, message: "LM Studio not installed")
        }

        // If LM Studio was installed manually (not via Homebrew cask),
        // do not report a false failure in Update Center.
        let (listedCode, listedOut) = shell("brew list --cask lm-studio 2>/dev/null || true")
        if listedCode != 0 || listedOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return StepResult(state: .skip, message: "LM Studio installed manually (not managed by Homebrew cask)")
        }

        let (code, out) = shell("brew upgrade --cask lm-studio")
        return code == 0
            ? StepResult(state: .ok, message: "LM Studio upgraded or already up to date")
            : StepResult(state: .fail, message: out)
    }

    func upgradeNodeIfInstalled() -> StepResult {
        if !hasCommand("node") {
            return StepResult(state: .skip, message: "Node not installed")
        }
        let (code, out) = shell("brew upgrade node")
        return code == 0 ? StepResult(state: .ok, message: "Node upgraded or already up to date") : StepResult(state: .fail, message: out)
    }

    func updateOpenClawIfInstalled() -> StepResult {
        if !hasCommand("openclaw") {
            return StepResult(state: .skip, message: "OpenClaw not installed")
        }
        let (code, out) = shell("npm i -g openclaw@latest")
        return code == 0 ? StepResult(state: .ok, message: "OpenClaw updated") : StepResult(state: .fail, message: out)
    }
}
