import Foundation

enum RuntimeRoute: String, Codable, Sendable {
    case cloud = "Cloud LLM"
    case oauth = "OAuth LLM"
    case local = "Local LLM"
    case custom = "Custom LLM"
    case unavailable = "Not configured"
}

enum RuntimeHealth: String, Codable, Sendable {
    case checking = "Checking"
    case ready = "Ready"
    case attention = "Needs attention"
    case blocked = "Blocked"
}

struct RuntimeIssue: Identifiable, Codable, Equatable, Sendable {
    enum Severity: String, Codable, Sendable {
        case warning
        case blocking
    }

    let id: String
    let title: String
    let detail: String
    let severity: Severity
}

struct RuntimeSnapshot: Codable, Equatable, Sendable {
    let capturedAt: Date
    let health: RuntimeHealth
    let gatewayReady: Bool
    let gatewayDetail: String
    let openClawInstalled: Bool
    let openClawVersion: String
    let route: RuntimeRoute
    let modelID: String
    let modelReady: Bool
    let authReady: Bool
    let authLabel: String
    let lmStudioInstalled: Bool
    let loadedLocalModel: String?
    let connectedChannels: Int
    let issues: [RuntimeIssue]

    static let checking = RuntimeSnapshot(
        capturedAt: .distantPast,
        health: .checking,
        gatewayReady: false,
        gatewayDetail: "Checking OpenClaw Gateway...",
        openClawInstalled: false,
        openClawVersion: "Checking...",
        route: .unavailable,
        modelID: "Checking...",
        modelReady: false,
        authReady: false,
        authLabel: "Checking...",
        lmStudioInstalled: false,
        loadedLocalModel: nil,
        connectedChannels: 0,
        issues: []
    )

    var isUsable: Bool {
        health == .ready || health == .attention
    }

    var statusTitle: String {
        switch health {
        case .checking: return "Checking your setup"
        case .ready: return "Ready to use"
        case .attention: return "Ready with one recommendation"
        case .blocked: return "Action required"
        }
    }

    var routeLine: String {
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelLabel = model.isEmpty ? "No model" : model
        let gateway = gatewayReady ? "Gateway online" : "Gateway offline"
        return "Next request: \(modelLabel) · \(route.rawValue) · \(authLabel) · \(gateway)"
    }

    var freshnessLabel: String {
        guard capturedAt != .distantPast else { return "Not checked yet" }
        let seconds = max(0, Int(Date().timeIntervalSince(capturedAt)))
        if seconds < 5 { return "Checked now" }
        if seconds < 60 { return "Checked \(seconds)s ago" }
        return "Checked \(max(1, seconds / 60))m ago"
    }
}

final class RuntimeSnapshotResolver: @unchecked Sendable {
    private let engine: InstallerEngine

    init(engine: InstallerEngine = InstallerEngine()) {
        self.engine = engine
    }

    func capture(connectedChannels: Int) -> RuntimeSnapshot {
        let gateway = engine.getGatewayStatus()
        let model = engine.getCurrentModel().trimmingCharacters(in: .whitespacesAndNewlines)
        let route = Self.route(for: model)
        let openClawVersion = commandOutput("openclaw --version 2>&1 | head -1")
        let openClawInstalled = !openClawVersion.isEmpty && !openClawVersion.lowercased().contains("command not found")
        let lmStudioInstalled = engine.hasLMStudioApp()
        let loadedLocalModel = engine.loadedLMStudioModelInfo()?.model
        let downloadedLocalModels = route == .local ? engine.listLMStudioLLMModelIds() : []
        let modelConfigured = !model.isEmpty && model != "Not configured" && model != "Unknown"
        let localModelReady = route != .local || Self.localModel(model, matchesAnyOf: downloadedLocalModels)
        let authProvider = Self.authProvider(for: model)
        let authReady = route == .local || (authProvider.map(engine.hasProviderAuth(provider:)) ?? false)
        let authLabel: String = {
            switch route {
            case .local:
                return localModelReady ? "Model available" : "Model not loaded"
            case .cloud, .oauth:
                return authReady ? "Authentication ready" : "Authentication missing"
            case .custom:
                return authReady ? "Authentication ready" : "Check authentication"
            case .unavailable:
                return "No model selected"
            }
        }()

        var issues: [RuntimeIssue] = []
        if !openClawInstalled {
            issues.append(RuntimeIssue(id: "openclaw", title: "OpenClaw is not installed", detail: "Install or update the OpenClaw runtime before using LocalClaw.", severity: .blocking))
        }
        if openClawInstalled && !gateway.isRunning {
            issues.append(RuntimeIssue(id: "gateway", title: "Gateway is offline", detail: gateway.message, severity: .blocking))
        }
        if !modelConfigured {
            issues.append(RuntimeIssue(id: "model", title: "No active model", detail: "Choose a model before sending a request.", severity: .blocking))
        }
        if modelConfigured && (route == .cloud || route == .oauth) && !authReady {
            issues.append(RuntimeIssue(id: "auth", title: "Authentication is missing", detail: "Connect the account or API key required by \(model).", severity: .blocking))
        }
        if route == .local && !lmStudioInstalled {
            issues.append(RuntimeIssue(id: "lmstudio", title: "LM Studio is not installed", detail: "Local models require LM Studio.", severity: .blocking))
        } else if route == .local && !localModelReady {
            issues.append(RuntimeIssue(id: "local-model", title: "Local model is not ready", detail: "Load or download the configured model before the next local request.", severity: .warning))
        } else if route == .local && loadedLocalModel == nil {
            issues.append(RuntimeIssue(id: "local-load", title: "Local model is not loaded", detail: "LocalClaw can load it on demand, but the first request may take longer.", severity: .warning))
        }

        let health: RuntimeHealth
        if issues.contains(where: { $0.severity == .blocking }) {
            health = .blocked
        } else if issues.isEmpty {
            health = .ready
        } else {
            health = .attention
        }

        return RuntimeSnapshot(
            capturedAt: Date(),
            health: health,
            gatewayReady: gateway.isRunning,
            gatewayDetail: gateway.message,
            openClawInstalled: openClawInstalled,
            openClawVersion: openClawInstalled ? openClawVersion : "Not installed",
            route: route,
            modelID: modelConfigured ? model : "Not configured",
            modelReady: modelConfigured && localModelReady,
            authReady: authReady,
            authLabel: authLabel,
            lmStudioInstalled: lmStudioInstalled,
            loadedLocalModel: loadedLocalModel,
            connectedChannels: connectedChannels,
            issues: issues
        )
    }

    private func commandOutput(_ command: String) -> String {
        engine.shell(command).1.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func route(for model: String) -> RuntimeRoute {
        let normalized = model.lowercased()
        if normalized.hasPrefix("lmstudio/") { return .local }
        if normalized.hasPrefix("openai-codex/") || normalized.hasPrefix("google-gemini-cli/") { return .oauth }
        if normalized.hasPrefix("openrouter/") || normalized.hasPrefix("openai/") || normalized.hasPrefix("anthropic/") || normalized.hasPrefix("google/") || normalized.hasPrefix("x-ai/") { return .cloud }
        if normalized.isEmpty || normalized == "not configured" || normalized == "unknown" { return .unavailable }
        return .custom
    }

    static func authProvider(for model: String) -> String? {
        let prefix = model.split(separator: "/", maxSplits: 1).first.map(String.init)?.lowercased()
        switch prefix {
        case "openrouter": return "openrouter"
        case "openai-codex": return "openai-codex"
        case "openai": return "openai"
        case "anthropic": return "anthropic"
        case "google", "google-gemini-cli": return "google"
        case "x-ai": return "xai"
        case "lmstudio", .none: return nil
        default: return prefix
        }
    }

    private static func localModel(_ configuredModel: String, matchesAnyOf downloadedModels: [String]) -> Bool {
        let configured = configuredModel
            .replacingOccurrences(of: "lmstudio/", with: "")
            .lowercased()
        guard !configured.isEmpty else { return false }
        return downloadedModels.contains { downloaded in
            let candidate = downloaded.lowercased()
            return candidate == configured || candidate.hasSuffix("/\(configured)") || configured.hasSuffix("/\(candidate)")
        }
    }
}
