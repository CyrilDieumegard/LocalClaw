import SwiftUI
import Foundation
import Combine

// MARK: - Async Command Runner (Non-isolated)

final class AsyncCommandRunner: @unchecked Sendable {
    private var process: Process?
    
    func run(_ command: String, onOutput: @escaping @Sendable (String) -> Void, onComplete: @escaping @Sendable (Int32) -> Void) {
        let process = Process()
        self.process = process
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Lire la sortie en temps réel sans bloquer
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            
            let lines = text.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                onOutput(line)
            }
        }
        
        process.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            self?.process = nil
            onComplete(proc.terminationStatus)
        }
        
        do {
            try process.run()
        } catch {
            onOutput("Error: \(error.localizedDescription)")
            onComplete(-1)
        }
    }
    
    func cancel() {
        process?.terminate()
    }
}

// MARK: - Advanced Command Center (Partie 3)

/// ViewModel for real-time Gateway monitoring
@MainActor
final class CommandCenterViewModel: ObservableObject {
    @Published var gatewayStatus: GatewayStatus = .unknown
    @Published var gatewayLogs: [LogEntry] = []
    @Published var isMonitoring: Bool = false
    @Published var autoScroll: Bool = true
    @Published var selectedModel: String = "kimi"
    @Published var systemInfo: SystemInfo = SystemInfo()
    
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let engine = InstallerEngine()
    
    enum GatewayStatus: String {
        case online = "Online"
        case offline = "Offline"
        case error = "Error"
        case unknown = "Unknown"
        case checking = "Checking..."
        
        var color: Color {
            switch self {
            case .online: return Color(NSColor.systemGreen)
            case .offline: return Color(NSColor.systemRed)
            case .error: return Color(NSColor.systemOrange)
            case .unknown: return Color(NSColor.secondaryLabelColor)
            case .checking: return Color(NSColor.controlAccentColor)
            }
        }
        
        var icon: String {
            switch self {
            case .online: return "checkmark.circle.fill"
            case .offline: return "xmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .unknown: return "questionmark.circle.fill"
            case .checking: return "arrow.triangle.2.circlepath"
            }
        }
    }
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let message: String
        
        enum LogLevel: String {
            case info = "INFO"
            case warning = "WARN"
            case error = "ERROR"
            case success = "OK"
            case command = "CMD"
            
            var color: Color {
                switch self {
                case .info: return Color(NSColor.controlAccentColor)
                case .warning: return Color(NSColor.systemOrange)
                case .error: return Color(NSColor.systemRed)
                case .success: return Color(NSColor.systemGreen)
                case .command: return Color(NSColor.secondaryLabelColor)
                }
            }
        }
    }
    
    struct SystemInfo {
        var openclawVersion: String = "Checking..."
        var nodeVersion: String = "Checking..."
        var gatewayPort: String = "18789"
        var configPath: String = "~/.openclaw/openclaw.json"
        var logPath: String = "~/.openclaw/logs/"
    }
    
    func startMonitoring() {
        isMonitoring = true
        addLog(.info, "Monitoring started")
        
        // Check immédiat
        checkGatewayStatus()
        refreshSystemInfo()
        
        // Timer toutes les 5 secondes
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                self.checkGatewayStatus()
            }
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        addLog(.info, "Monitoring stopped")
    }
    
    func checkGatewayStatus() {
        gatewayStatus = .checking
        
        // Test 1: Vérifier si le port répond (méthode fiable)
        let (_, portCheck) = engine.shell("curl -s -o /dev/null -w '%{http_code}' http://localhost:18789/api/health 2>/dev/null || echo '000'")
        let portResponds = portCheck.trimmingCharacters(in: .whitespacesAndNewlines) == "200"
        
        // Test 2: Vérifier via CLI
        let (_, output) = engine.shell("openclaw gateway status --no-color 2>&1")
        let cliSaysRunning = output.contains("running") || output.contains("Online")
        
        if portResponds || cliSaysRunning {
            gatewayStatus = .online
        } else if output.contains("not running") || output.contains("Offline") {
            gatewayStatus = .offline
        } else {
            gatewayStatus = .error
        }
    }
    
    func refreshSystemInfo() {
        let (_, ocVersion) = engine.shell("openclaw --version 2>&1 | head -1")
        let (_, nodeVer) = engine.shell("node --version 2>&1")
        
        systemInfo.openclawVersion = ocVersion.isEmpty ? "Not installed" : ocVersion
        systemInfo.nodeVersion = nodeVer.isEmpty ? "Not installed" : nodeVer
    }
    
    func addLog(_ level: LogEntry.LogLevel, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        gatewayLogs.append(entry)
        
        // Garder seulement les 500 dernières entrées
        if gatewayLogs.count > 500 {
            gatewayLogs.removeFirst(gatewayLogs.count - 500)
        }
    }
    
    func clearLogs() {
        gatewayLogs.removeAll()
    }
    
    // MARK: - Async Command Execution
    
    private let commandRunner = AsyncCommandRunner()
    
    func executeCommandAsync(_ command: String, onOutput: @escaping @Sendable (String) -> Void, onComplete: @escaping @Sendable (Int32) -> Void) {
        commandRunner.run(command, onOutput: onOutput, onComplete: onComplete)
    }
    
    // MARK: - Quick Actions
    
    func startGateway() {
        addLog(.command, "Starting gateway...")
        executeCommandAsync("openclaw gateway start 2>&1", onOutput: { line in
            DispatchQueue.main.async {
                if line.contains("error") || line.contains("Error") {
                    self.addLog(.error, line)
                } else {
                    self.addLog(.info, line)
                }
            }
        }, onComplete: { code in
            DispatchQueue.main.async {
                // Sync token after start
                self.syncTokenFromConfig()
                
                // Wait 3 seconds then verify status
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.checkGatewayStatus()
                    if self.gatewayStatus == .online {
                        self.addLog(.success, "Gateway started successfully")
                    } else if code == 0 {
                        self.addLog(.warning, "Gateway start returned OK but service not responding.")
                        self.addLog(.info, "Trying to install service...")
                        self.installGatewayService()
                    } else {
                        self.addLog(.error, "Gateway start failed (exit \(code))")
                    }
                }
            }
        })
    }
    
    func stopGateway() {
        addLog(.command, "Stopping gateway...")
        executeCommandAsync("openclaw gateway stop", onOutput: { line in
            DispatchQueue.main.async {
                self.addLog(.info, line)
            }
        }, onComplete: { code in
            DispatchQueue.main.async {
                if code == 0 {
                    self.addLog(.success, "Gateway stopped")
                } else {
                    self.addLog(.warning, "Gateway stop returned \(code)")
                }
                self.checkGatewayStatus()
            }
        })
    }
    
    func restartGateway() {
        addLog(.command, "Restarting gateway...")
        
        // Étape 1: Stop
        executeCommandAsync("openclaw gateway stop", onOutput: { line in
            DispatchQueue.main.async {
                self.addLog(.info, "[stop] \(line)")
            }
        }, onComplete: { _ in
            DispatchQueue.main.async {
                self.addLog(.info, "Waiting 2 seconds...")
            }
            
            // Attendre 2 secondes puis start
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.executeCommandAsync("openclaw gateway start", onOutput: { line in
                    DispatchQueue.main.async {
                        if line.contains("error") || line.contains("Error") {
                            self.addLog(.error, "[start] \(line)")
                        } else {
                            self.addLog(.info, "[start] \(line)")
                        }
                    }
                }, onComplete: { code in
                    DispatchQueue.main.async {
                        // Sync token after restart
                        self.syncTokenFromConfig()
                        
                        // Wait 2 seconds then verify
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.checkGatewayStatus()
                            if self.gatewayStatus == .online {
                                self.addLog(.success, "Gateway restarted successfully")
                            } else if code == 0 {
                                self.addLog(.warning, "Gateway restart returned OK but service not responding. Run: openclaw gateway install")
                            } else {
                                self.addLog(.error, "Gateway restart failed (exit \(code))")
                            }
                        }
                    }
                })
            }
        })
    }
    
    func runDoctor() {
        addLog(.command, "Running doctor...")
        executeCommandAsync("openclaw doctor --repair --yes --no-color", onOutput: { line in
            DispatchQueue.main.async {
                if line.contains("✓") || line.contains("OK") || line.contains("fixed") {
                    self.addLog(.success, line)
                } else if line.contains("✗") || line.contains("FAIL") || line.contains("error") || line.contains("Error") {
                    self.addLog(.error, line)
                } else if line.contains("⚠") || line.contains("WARN") || line.contains("warning") {
                    self.addLog(.warning, line)
                } else {
                    self.addLog(.info, line)
                }
            }
        }, onComplete: { code in
            DispatchQueue.main.async {
                if code == 0 {
                    self.addLog(.success, "Doctor completed successfully")
                } else {
                    self.addLog(.warning, "Doctor completed with exit code \(code)")
                }
            }
        })
    }
    
    // All OpenRouter models available
    let availableModels: [(key: String, name: String, id: String)] = [
        ("kimi", "Kimi K2.5", "openrouter/moonshotai/kimi-k2.5"),
        ("claude-sonnet", "Claude 3.5 Sonnet", "openrouter/anthropic/claude-3.5-sonnet"),
        ("claude-haiku", "Claude 3.5 Haiku", "openrouter/anthropic/claude-3.5-haiku"),
        ("gpt4o", "GPT-4o", "openrouter/openai/gpt-4o"),
        ("gpt4o-mini", "GPT-4o Mini", "openrouter/openai/gpt-4o-mini"),
        ("gemini", "Gemini 2.5 Flash", "openrouter/google/gemini-2.5-flash-preview"),
        ("llama", "Llama 3.3 70B", "openrouter/meta-llama/llama-3.3-70b-instruct"),
        ("deepseek", "DeepSeek Chat", "openrouter/deepseek/deepseek-chat"),
        ("mistral", "Mistral Large", "openrouter/mistralai/mistral-large"),
        ("qwen", "Qwen 2.5 72B", "openrouter/qwen/qwen-2.5-72b-instruct"),
        ("grok", "Grok 2", "openrouter/x-ai/grok-2"),
        ("command-r", "Command R+", "openrouter/cohere/command-r-plus")
    ]
    
    private func setPrimaryModel(_ modelId: String, mode: String) {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"

        guard let data = FileManager.default.contents(atPath: configPath),
              var json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) else {
            addLog(.error, "Cannot read ~/.openclaw/openclaw.json")
            return
        }

        var agents = json["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]
        var model = defaults["model"] as? [String: Any] ?? [:]
        model["primary"] = modelId
        defaults["model"] = model

        // Apply runtime profile depending on Local vs Cloud switch
        var sandbox = defaults["sandbox"] as? [String: Any] ?? [:]
        sandbox["mode"] = "off"
        defaults["sandbox"] = sandbox

        var tools = json["tools"] as? [String: Any] ?? [:]
        var deny = Set((tools["deny"] as? [String]) ?? [])

        if mode == "local" {
            deny.insert("group:web")
            deny.insert("browser")
            deny.insert("web_search")
            deny.insert("web_fetch")
        } else {
            deny.remove("group:web")
            deny.remove("browser")
            deny.remove("web_search")
            deny.remove("web_fetch")
        }

        tools["deny"] = Array(deny).sorted()
        json["tools"] = tools

        agents["defaults"] = defaults
        json["agents"] = agents

        do {
            let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            addLog(.success, "Mode switched to \(mode) + model \(modelId)")
            addLog(.info, "Restarting Gateway to apply changes...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.restartGateway()
            }
        } catch {
            addLog(.error, "Failed writing config: \(error.localizedDescription)")
        }
    }

    private func detectInstalledLocalModel() -> String {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [String: Any],
              let providers = models["providers"] as? [String: Any],
              let lmstudio = providers["lmstudio"] as? [String: Any],
              let list = lmstudio["models"] as? [[String: Any]],
              let first = list.first,
              let id = first["id"] as? String,
              !id.isEmpty else {
            return "openai"
        }
        return id
    }

    func switchToLocalLLM() {
        let localId = detectInstalledLocalModel()
        addLog(.command, "Switching to local mode (lmstudio/\(localId))...")
        setPrimaryModel("lmstudio/\(localId)", mode: "local")
    }

    func switchToCloudLLM() {
        guard let model = availableModels.first(where: { $0.key == selectedModel }) else { return }
        addLog(.command, "Switching to cloud mode (\(model.name))...")
        setPrimaryModel(model.id, mode: "cloud")
    }

    func changeModel() {
        switchToCloudLLM()
    }
    
    func openDashboard() {
        addLog(.command, "Opening dashboard...")
        // Read current token and open with tokenized URL
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        var token = ""
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let t = auth["token"] as? String {
            token = t
        }
        
        if !token.isEmpty {
            let url = "http://localhost:18789?token=\(token)"
            _ = engine.shell("open '\(url)' 2>&1 || open http://localhost:18789 2>&1 || true")
            addLog(.success, "Dashboard opened with token")
        } else {
            _ = engine.shell("open http://localhost:18789 2>&1 || true")
            addLog(.success, "Dashboard opened (no token found)")
        }
    }
    
    func installGatewayService() {
        addLog(.command, "Installing gateway service...")
        executeCommandAsync("openclaw gateway install", onOutput: { line in
            DispatchQueue.main.async {
                self.addLog(.info, line)
            }
        }, onComplete: { code in
            DispatchQueue.main.async {
                // Sync token after install (it might have changed)
                self.syncTokenFromConfig()
                
                if code == 0 {
                    self.addLog(.success, "Gateway service installed. Now you can Start Gateway.")
                } else {
                    self.addLog(.error, "Install failed (exit \(code))")
                }
            }
        })
    }
    
    private func syncTokenFromConfig() {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = json["gateway"] as? [String: Any],
              let auth = gateway["auth"] as? [String: Any],
              let token = auth["token"] as? String else {
            return
        }
        if !token.isEmpty {
            addLog(.info, "Token: \(token.prefix(16))...")
        }
    }
    
    func viewConfig() {
        addLog(.command, "Reading config...")
        executeCommandAsync("cat ~/.openclaw/openclaw.json", onOutput: { line in
            DispatchQueue.main.async {
                self.addLog(.info, line)
            }
        }, onComplete: { code in
            DispatchQueue.main.async {
                if code != 0 {
                    self.addLog(.error, "Config not found")
                }
            }
        })
    }
    
    func fixAuth() {
        addLog(.command, "Fixing authentication (reinstalling gateway)...")
        // Stop, uninstall, install, start
        executeCommandAsync("openclaw gateway stop 2>&1; openclaw gateway uninstall 2>&1; sleep 1; openclaw gateway install 2>&1", onOutput: { line in
            DispatchQueue.main.async {
                self.addLog(.info, line)
            }
        }, onComplete: { code in
            DispatchQueue.main.async {
                // Sync token after reinstall
                self.syncTokenFromConfig()
                
                if code == 0 {
                    self.addLog(.success, "Gateway reinstalled. Starting...")
                    // Now start
                    self.executeCommandAsync("openclaw gateway start", onOutput: { line in
                        DispatchQueue.main.async { self.addLog(.info, line) }
                    }, onComplete: { startCode in
                        DispatchQueue.main.async {
                            // Sync token again after start
                            self.syncTokenFromConfig()
                            
                            if startCode == 0 {
                                self.addLog(.success, "Gateway restarted. Dashboard should work now.")
                            } else {
                                self.addLog(.error, "Gateway start failed (exit \(startCode))")
                            }
                            self.checkGatewayStatus()
                        }
                    })
                } else {
                    self.addLog(.error, "Reinstall failed (exit \(code))")
                }
            }
        })
    }
    
    func copyLogsToClipboard() {
        let logText = gatewayLogs.map { "[\(formatTime($0.timestamp))] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
        addLog(.success, "Logs copied to clipboard")
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    func openWorkspace() {
        addLog(.command, "Opening workspace...")
        _ = engine.shell("open ~/.openclaw 2>&1 || true")
        addLog(.success, "Workspace opened in Finder")
    }
    
    func updateOpenClaw() {
        addLog(.command, "Updating OpenClaw...")
        executeCommandAsync("npm i -g openclaw@latest", onOutput: { line in
            DispatchQueue.main.async {
                self.addLog(.info, line)
            }
        }, onComplete: { code in
            DispatchQueue.main.async {
                if code == 0 {
                    self.addLog(.success, "OpenClaw updated")
                    self.refreshSystemInfo()
                } else {
                    self.addLog(.error, "Update failed")
                }
            }
        })
    }
}

// MARK: - Advanced Command Center View

struct AdvancedCommandCenterView: View {
    @StateObject private var viewModel = CommandCenterViewModel()
    @State private var leftPanelWidth: CGFloat = 320
    @State private var showSettings = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Panel: Controls & Status
            leftPanel
                .frame(width: leftPanelWidth)
                .background(UI.card)
            
            // Resizer
            resizer
            
            // Right Panel: Terminal & Logs
            rightPanel
                .background(UI.card)
        }
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
    
    // MARK: - Left Panel
    
    private var leftPanel: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Status Card
                statusSection

                // Quick Actions
                actionsSection

                // Local/Cloud switch + model
                modelSection

                // System Info
                systemInfoSection

                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(UI.accent)
                Text("Command Center")
                    .font(AppFont.heading(20))
                    .foregroundStyle(UI.text)
                Spacer()
                Button(action: { NotificationCenter.default.post(name: Notification.Name("ReturnToHome"), object: nil) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(AppFont.bodySemi(12))
                    }
                    .foregroundStyle(UI.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(UI.card)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Text("Control and real-time monitoring")
                .font(AppFont.body(12))
                .foregroundStyle(UI.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STATUS")
                .font(AppFont.heading(10))
                .kerning(0.6)
                .foregroundStyle(UI.accent)
            
            HStack(spacing: 12) {
                // Gateway Status
                StatusCard(
                    title: "Gateway",
                    value: viewModel.gatewayStatus.rawValue,
                    icon: viewModel.gatewayStatus.icon,
                    color: viewModel.gatewayStatus.color
                )
                
                // Monitoring Indicator
                StatusCard(
                    title: "Monitor",
                    value: viewModel.isMonitoring ? "Active" : "Stopped",
                    icon: viewModel.isMonitoring ? "waveform" : "waveform.slash",
                    color: viewModel.isMonitoring ? .green : .gray
                )
            }
            
            // Last Check
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(UI.muted)
                Text("Last check: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))")
                    .font(.caption)
                    .foregroundStyle(UI.muted)
                Spacer()
            }
        }
        .padding(12)
        .background(UI.cardSoft)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK ACTIONS")
                .font(AppFont.heading(10))
                .kerning(0.6)
                .foregroundStyle(UI.accent)
            
            VStack(spacing: 8) {
                ActionButton(
                    title: "Start Gateway",
                    icon: "play.fill",
                    color: .green,
                    action: { viewModel.startGateway() }
                )
                
                ActionButton(
                    title: "Stop Gateway",
                    icon: "stop.fill",
                    color: .red,
                    action: { viewModel.stopGateway() }
                )
                
                ActionButton(
                    title: "Install Gateway Service",
                    icon: "arrow.down.circle.fill",
                    color: .purple,
                    action: { viewModel.installGatewayService() }
                )
                
                ActionButton(
                    title: "Restart Gateway",
                    icon: "arrow.clockwise",
                    color: .orange,
                    action: { viewModel.restartGateway() }
                )
                
                ActionButton(
                    title: "Run Doctor",
                    icon: "stethoscope",
                    color: .blue,
                    action: { viewModel.runDoctor() }
                )
                
                ActionButton(
                    title: "Fix Auth",
                    icon: "key.fill",
                    color: .red,
                    action: { viewModel.fixAuth() }
                )
                
                ActionButton(
                    title: "Open Dashboard",
                    icon: "globe",
                    color: .purple,
                    action: { viewModel.openDashboard() }
                )
                
                ActionButton(
                    title: "View Config",
                    icon: "doc.text",
                    color: .gray,
                    action: { viewModel.viewConfig() }
                )
                
                ActionButton(
                    title: "Open Workspace",
                    icon: "folder",
                    color: .gray,
                    action: { viewModel.openWorkspace() }
                )
                
                ActionButton(
                    title: "Update OpenClaw",
                    icon: "arrow.down.circle",
                    color: .blue,
                    action: { viewModel.updateOpenClaw() }
                )
            }
        }
        .padding(12)
        .background(UI.cardSoft)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }
    
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI MODEL")
                .font(AppFont.heading(10))
                .kerning(0.6)
                .foregroundStyle(UI.accent)

            HStack(spacing: 8) {
                Button(action: { viewModel.switchToLocalLLM() }) {
                    Label("Local LLM", systemImage: "internaldrive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButton(primary: false))

                Button(action: { viewModel.switchToCloudLLM() }) {
                    Label("Cloud", systemImage: "cloud.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CTAButton(primary: true))
            }

            Picker("Cloud model", selection: $viewModel.selectedModel) {
                ForEach(viewModel.availableModels, id: \.key) { model in
                    Text(model.name).tag(model.key)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(12)
        .background(UI.cardSoft)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }
    
    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SYSTEM")
                .font(AppFont.heading(10))
                .kerning(0.6)
                .foregroundStyle(UI.accent)
            
            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "OpenClaw", value: viewModel.systemInfo.openclawVersion)
                InfoRow(label: "Node.js", value: viewModel.systemInfo.nodeVersion)
                InfoRow(label: "Port", value: viewModel.systemInfo.gatewayPort)
            }
        }
        .padding(12)
        .background(UI.cardSoft)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .cornerRadius(10)
    }
    
    // MARK: - Resizer
    
    private var resizer: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 4)
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 2)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newWidth = leftPanelWidth + value.translation.width
                        leftPanelWidth = max(280, min(450, newWidth))
                    }
            )
            .cursor(.resizeLeftRight)
    }
    
    // MARK: - Right Panel
    
    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Logs Toolbar
            HStack {
                Text("LOGS")
                    .font(AppFont.heading(10))
                    .kerning(0.6)
                    .foregroundStyle(UI.muted)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { viewModel.copyLogsToClipboard() }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Copy")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(UI.muted)
                    
                    Button(action: { viewModel.clearLogs() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Clear")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(UI.muted)
                    
                    Toggle("Auto-scroll", isOn: $viewModel.autoScroll)
                        .toggleStyle(.checkbox)
                    
                    Toggle("Monitoring", isOn: Binding(
                        get: { viewModel.isMonitoring },
                        set: { newValue in
                            if newValue {
                                viewModel.startMonitoring()
                            } else {
                                viewModel.stopMonitoring()
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(UI.cardSoft)
            
            // Logs List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.gatewayLogs) { entry in
                            LogRow(entry: entry)
                        }
                        .id("logs-bottom")
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
                .background(UI.card)
                .onChange(of: viewModel.gatewayLogs.count) { _ in
                    if viewModel.autoScroll {
                        withAnimation {
                            proxy.scrollTo("logs-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(UI.muted)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.white.opacity(0.5))
        .cornerRadius(8)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.text)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(UI.cardSoft)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(UI.muted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(UI.text)
                .lineLimit(1)
        }
    }
}

struct LogRow: View {
    let entry: CommandCenterViewModel.LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatTime(entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(UI.muted)
                .frame(width: 60, alignment: .leading)
            
            Text("[\(entry.level.rawValue)]")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.level.color)
                .frame(width: 50, alignment: .leading)
            
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(UI.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// Helper extension pour le curseur
extension View {
    func cursor(_ type: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                type.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
