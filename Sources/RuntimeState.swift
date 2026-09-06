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
        case .attention: return issues.count == 1 ? "Ready with one recommendation" : "Ready with \(issues.count) recommendations"
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
        let openAIUsesOAuth = model.hasPrefix("openai/") && OpenClawCompatibility.openAIUsesOAuth(
            in: engine.readOpenClawConfig() ?? [:], oauthAvailable: engine.hasOAuthAuth(provider: "openai")
        )
        let route = Self.route(for: model, openAIUsesOAuth: openAIUsesOAuth)
        let openClawVersion = engine.installedVersion(for: "openclaw")
        let openClawInstalled = openClawVersion != "Not installed"
        let lmStudioInstalled = engine.hasLMStudioApp()
        let loadedLocalModel = engine.loadedLMStudioModelInfo()?.model
        let downloadedLocalModels = route == .local ? engine.listLMStudioLLMModelIds() : []
        let authProvider = Self.authProvider(for: model)
        let authReady = route == .local || (authProvider.map(engine.hasProviderAuth(provider:)) ?? false)
        return Self.resolve(
            gatewayReady: gateway.isRunning, gatewayDetail: gateway.message,
            openClawInstalled: openClawInstalled, openClawVersion: openClawVersion,
            model: model, route: route, authReady: authReady,
            lmStudioInstalled: lmStudioInstalled, loadedLocalModel: loadedLocalModel,
            downloadedLocalModels: downloadedLocalModels, connectedChannels: connectedChannels
        )
    }

    static func resolve(
        gatewayReady: Bool, gatewayDetail: String, openClawInstalled: Bool, openClawVersion: String,
        model: String, route: RuntimeRoute, authReady: Bool, lmStudioInstalled: Bool,
        loadedLocalModel: String?, downloadedLocalModels: [String], connectedChannels: Int
    ) -> RuntimeSnapshot {
        let modelConfigured = route != .unavailable
        let localModelReady = route != .local || Self.localModel(model, matchesAnyOf: downloadedLocalModels)
        let selectedLocalModelLoaded = loadedLocalModel.map { Self.localModel(model, matchesAnyOf: [$0]) } ?? false
        let authLabel: String = {
            switch route {
            case .local:
                return localModelReady ? "Model available" : "Model not available"
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
        if openClawInstalled && !gatewayReady {
            issues.append(RuntimeIssue(id: "gateway", title: "Gateway is offline", detail: gatewayDetail, severity: .blocking))
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
            issues.append(RuntimeIssue(id: "local-model", title: "Local model is not available", detail: "Download the configured model or choose an installed model before the next local request.", severity: .blocking))
        } else if route == .local && !selectedLocalModelLoaded {
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
            gatewayReady: gatewayReady,
            gatewayDetail: gatewayDetail,
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

    static func route(for model: String, openAIUsesOAuth: Bool = false) -> RuntimeRoute {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("openai/"), openAIUsesOAuth { return .oauth }
        if normalized.hasPrefix("lmstudio/") { return .local }
        if normalized.hasPrefix("openai-codex/") || normalized.hasPrefix("google-gemini-cli/") { return .oauth }
        if normalized.hasPrefix("openrouter/") || normalized.hasPrefix("openai/") || normalized.hasPrefix("anthropic/") || normalized.hasPrefix("google/") || normalized.hasPrefix("x-ai/") { return .cloud }
        if normalized.isEmpty || ["not configured", "unknown", "profile selection required", "agent selection required"].contains(normalized) { return .unavailable }
        return .custom
    }

    static func authProvider(for model: String) -> String? {
        guard route(for: model) != .unavailable else { return nil }
        let prefix = model.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", maxSplits: 1).first.map(String.init)?.lowercased()
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
        let normalized = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let configured = normalized.hasPrefix("lmstudio/") ? String(normalized.dropFirst("lmstudio/".count)) : normalized
        guard !configured.isEmpty else { return false }
        return downloadedModels.contains { downloaded in
            let candidate = downloaded.lowercased()
            return candidate == configured || candidate.hasSuffix("/\(configured)") || configured.hasSuffix("/\(candidate)")
        }
    }
}
