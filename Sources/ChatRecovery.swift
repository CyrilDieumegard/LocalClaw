import Foundation

enum ChatRecoveryKind: String, Codable, Sendable {
    case runtimeFiles
    case gateway
    case authentication
    case localModel
    case session
    case timeout
    case unknown
}

struct ChatRecoveryPlan: Equatable, Sendable {
    let kind: ChatRecoveryKind
    let title: String
    let explanation: String
    let primaryActionLabel: String
    let systemImage: String

    static func classify(error raw: String) -> ChatRecoveryPlan {
        let clean = raw
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .lowercased()

        if clean.contains("err_module_not_found") ||
            (clean.contains("cannot find module") && clean.contains("openclaw/dist")) {
            return ChatRecoveryPlan(
                kind: .runtimeFiles,
                title: "OpenClaw needs a runtime refresh",
                explanation: "The Gateway is still using files from an older OpenClaw build. LocalClaw can refresh the service, verify the runtime, and retry without deleting your configuration, projects, channels, or models.",
                primaryActionLabel: "Repair & Retry",
                systemImage: "wrench.and.screwdriver.fill"
            )
        }

        if clean.contains("embeddedattemptsessiontakeovererror") ||
            clean.contains("session file changed") ||
            clean.contains("session takeover") ||
            clean.contains("prompt lock") {
            return ChatRecoveryPlan(
                kind: .session,
                title: "The chat session changed",
                explanation: "Another OpenClaw process updated this session while the request was running. LocalClaw can retry in a fresh runtime session while keeping the visible project context.",
                primaryActionLabel: "Fresh Session & Retry",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
        }

        if clean.contains("unauthorized") ||
            clean.contains("invalid api key") ||
            clean.contains("authentication failed") ||
            clean.contains("oauth token") ||
            clean.contains("token expired") ||
            clean.contains("status 401") ||
            clean.contains("status 403") {
            return ChatRecoveryPlan(
                kind: .authentication,
                title: "Authentication needs attention",
                explanation: "The selected model cannot authenticate. Open Models to reconnect the OAuth account or API key. Your message remains available in this chat.",
                primaryActionLabel: "Open Models",
                systemImage: "person.badge.key.fill"
            )
        }

        if clean.contains("lm studio") ||
            clean.contains("lmstudio") ||
            clean.contains("model not found") ||
            clean.contains("model is not loaded") ||
            clean.contains("context window too small") {
            return ChatRecoveryPlan(
                kind: .localModel,
                title: "The local model needs attention",
                explanation: "Open Models to load, repair, or replace the local model. LocalClaw will keep the failed message ready for another attempt.",
                primaryActionLabel: "Open Models",
                systemImage: "desktopcomputer.trianglebadge.exclamationmark"
            )
        }

        if clean.contains("timed out") ||
            clean.contains("timeout") ||
            clean.contains("deadline exceeded") ||
            clean.contains("code=124") {
            return ChatRecoveryPlan(
                kind: .timeout,
                title: "The request took too long",
                explanation: "OpenClaw did not finish before the safety limit. Retry the request, or choose a faster model if this continues.",
                primaryActionLabel: "Retry Request",
                systemImage: "clock.badge.exclamationmark.fill"
            )
        }

        if clean.contains("gatewayclientrequesterror") ||
            clean.contains("gateway closed") ||
            clean.contains("gateway offline") ||
            clean.contains("rpc failed") ||
            clean.contains("econnrefused") ||
            clean.contains("connection refused") ||
            clean.contains("1006 abnormal closure") ||
            clean.contains("websocket") {
            return ChatRecoveryPlan(
                kind: .gateway,
                title: "Gateway stopped responding",
                explanation: "LocalClaw can reinstall the user service, restart the Gateway, verify RPC health, and then resend your message.",
                primaryActionLabel: "Restart & Retry",
                systemImage: "arrow.clockwise.circle.fill"
            )
        }

        return ChatRecoveryPlan(
            kind: .unknown,
            title: "OpenClaw returned an unexpected error",
            explanation: "LocalClaw can refresh the Gateway and run a health check before retrying. If the error remains, Help will retain a redacted diagnostic for support.",
            primaryActionLabel: "Recover & Retry",
            systemImage: "cross.case.fill"
        )
    }
}
