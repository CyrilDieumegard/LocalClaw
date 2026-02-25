import SwiftUI
import Foundation
import Combine

// MARK: - Terminal View Component (Partie 1)

/// Un terminal natif intégré avec output temps réel et input
@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var output: String = ""
    @Published var inputText: String = ""
    @Published var isRunning: Bool = false
    @Published var currentCommand: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private var currentProcess: Process?
    
    /// Append text to terminal output
    func append(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(text)\n"
        output += line
    }
    
    /// Clear terminal output
    func clear() {
        output = ""
    }
    
    /// Execute a command and stream output
    func execute(_ command: String, streaming: Bool = true) {
        guard !isRunning else {
            append("⚠️  Une commande est déjà en cours...")
            return
        }
        
        isRunning = true
        currentCommand = command
        append("$ \(command)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        currentProcess = process
        
        if streaming {
            // Stream output in real-time
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                DispatchQueue.main.async {
                    self?.output += text
                }
            }
        }
        
        do {
            try process.run()
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.currentProcess = nil
                    pipe.fileHandleForReading.readabilityHandler = nil
                    
                    let exitCode = process.terminationStatus
                    if exitCode == 0 {
                        self?.append("✅ Commande terminée (exit 0)")
                    } else {
                        self?.append("❌ Commande échouée (exit \(exitCode))")
                    }
                }
            }
        } catch {
            append("❌ Erreur: \(error.localizedDescription)")
            isRunning = false
            currentProcess = nil
        }
    }
    
    /// Execute interactive OpenClaw command with streaming
    func executeOpenClaw(_ args: String) {
        execute("openclaw \(args)", streaming: true)
    }
    
    /// Cancel current running command
    func cancel() {
        guard let process = currentProcess, isRunning else { return }
        process.terminate()
        append("⚠️  Commande interrompue par l'utilisateur")
        isRunning = false
        currentProcess = nil
    }
    
    /// Execute user input from text field
    func executeInput() {
        let cmd = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        inputText = ""
        execute(cmd)
    }
    
    /// Get gateway status and display it
    func checkGatewayStatus() {
        execute("openclaw gateway status --no-color 2>&1")
    }
    
    /// Start gateway with output visible
    func startGateway() {
        execute("openclaw gateway start 2>&1")
    }
    
    /// Stop gateway
    func stopGateway() {
        execute("openclaw gateway stop 2>&1")
    }
    
    /// Restart gateway
    func restartGateway() {
        execute("openclaw gateway restart 2>&1")
    }
    
    /// Run doctor
    func runDoctor() {
        execute("openclaw doctor --repair --yes --no-color 2>&1")
    }
    
    /// Show config
    func showConfig() {
        execute("cat ~/.openclaw/openclaw.json 2>&1 || echo 'Config not found'")
    }
    
    /// Show OpenClaw version
    func showVersion() {
        execute("openclaw --version")
    }
    
    /// Show logs (if available)
    func showLogs() {
        execute("cat ~/.openclaw/logs/openclaw.log 2>&1 | tail -100 || echo 'No logs available'")
    }
}

struct TerminalView: View {
    @StateObject private var viewModel = TerminalViewModel()
    @State private var autoScroll = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            terminalToolbar
            
            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.output)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(UI.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("terminal-bottom")
                }
                .scrollIndicators(.hidden)
                .background(UI.card)
                .onChange(of: viewModel.output) { _ in
                    if autoScroll {
                        withAnimation {
                            proxy.scrollTo("terminal-bottom", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input area
            terminalInput
        }
        .background(UI.card)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var terminalToolbar: some View {
        HStack(spacing: 12) {
            // Quick actions
            Group {
                ToolbarButton("Status", icon: "checkmark.circle", action: { viewModel.checkGatewayStatus() })
                ToolbarButton("Start", icon: "play.fill", action: { viewModel.startGateway() })
                ToolbarButton("Stop", icon: "stop.fill", action: { viewModel.stopGateway() })
                ToolbarButton("Restart", icon: "arrow.clockwise", action: { viewModel.restartGateway() })
                ToolbarButton("Doctor", icon: "stethoscope", action: { viewModel.runDoctor() })
                ToolbarButton("Config", icon: "doc.text", action: { viewModel.showConfig() })
                ToolbarButton("Logs", icon: "doc.text.magnifyingglass", action: { viewModel.showLogs() })
            }

            Spacer()

            // Controls
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            Button(action: { viewModel.clear() }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Effacer")

            if viewModel.isRunning {
                Button(action: { viewModel.cancel() }) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Annuler la commande")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(UI.cardSoft)
    }
    
    private var terminalInput: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(UI.accent)
            
            TextField("Entrez une commande...", text: $viewModel.inputText)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.executeInput() }
            
            Button(action: { viewModel.executeInput() }) {
                Image(systemName: "return")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.inputText.isEmpty || viewModel.isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(UI.cardSoft)
        .overlay(
            Rectangle()
                .fill(UI.accent.opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }
}

struct ToolbarButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    
    init(_ label: String, icon: String, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 48, height: 36)
        }
        .buttonStyle(ToolbarButtonStyle())
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.accentColor : Color.gray.opacity(0.2))
            )
    }
}

// Preview - désactivé pour la compilation
// #Preview {
//     TerminalView()
//         .frame(width: 600, height: 400)
// }
