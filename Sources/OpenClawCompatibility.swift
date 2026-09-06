import Foundation

enum OpenClawCompatibility {
    static func usesUnifiedOpenAIRoutes(version: String) -> Bool {
        (InstallerEngine.compareVersion(version, "2026.8.1") ?? -1) >= 0
    }

    static func modelID(_ raw: String, version: String) -> String {
        let model = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard usesUnifiedOpenAIRoutes(version: version) else { return model }
        for prefix in ["openai-codex/", "codex/"] where model.lowercased().hasPrefix(prefix) {
            return "openai/" + model.dropFirst(prefix.count)
        }
        return model
    }

    // Preserve the configured owner across legacy-roster migrations. LocalClaw's
    // historical main fallback applies only when no owner has been selected.
    static func chatAgentID(in config: [String: Any]) -> String? {
        let agents = config["agents"] as? [String: Any] ?? [:]
        let identifiers: [String]
        let defaults: [String]
        if let entries = agents["entries"] as? [String: Any] {
            identifiers = Array(entries.keys)
            defaults = entries.compactMap { id, entry in
                (entry as? [String: Any])?["default"] as? Bool == true ? id : nil
            }
        } else if let list = agents["list"] as? [[String: Any]] {
            identifiers = list.compactMap { $0["id"] as? String }
            defaults = list.filter { $0["default"] as? Bool == true }.compactMap { $0["id"] as? String }
        } else {
            identifiers = agents["ownership"] as? String == "explicit" ? [] : ["main"]
            defaults = []
        }
        func validOwner(_ owner: String) -> String? {
            guard identifiers.contains(owner),
                  owner.range(of: #"^[a-z0-9][a-z0-9_-]*$"#, options: .regularExpression) != nil else { return nil }
            return owner
        }
        let systemAgent = (agents["defaults"] as? [String: Any])?["systemAgent"] as? [String: Any]
        if let rawOwner = systemAgent?["agentId"] {
            guard let owner = rawOwner as? String else { return nil }
            return validOwner(owner.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if agents["ownership"] as? String != "explicit", !defaults.isEmpty {
            guard defaults.count == 1 else { return nil }
            return validOwner(defaults[0])
        }
        if identifiers.contains("main") { return "main" }
        guard identifiers.count == 1, let only = identifiers.first else { return nil }
        return validOwner(only)
    }

    static func openAIUsesOAuth(in config: [String: Any], oauthAvailable: Bool) -> Bool {
        let providers = (config["models"] as? [String: Any])?["providers"] as? [String: Any] ?? [:]
        if (providers["openai"] as? [String: Any])?["auth"] as? String == "api-key" { return false }
        let auth = config["auth"] as? [String: Any] ?? [:]
        let profiles = auth["profiles"] as? [String: Any] ?? [:]
        let order = (auth["order"] as? [String: Any])?["openai"] as? [String] ?? []
        for id in order {
            guard let profile = profiles[id] as? [String: Any],
                  let mode = (profile["mode"] ?? profile["type"]) as? String else { continue }
            return mode == "oauth"
        }
        return oauthAvailable
    }

    static func summarizedAuthProviders(in auth: [String: Any]) -> Set<String> {
        Set((auth["providersWithOAuth"] as? [String] ?? []).compactMap { label in
            let normalized = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.range(of: #"^[a-z0-9_-]+(?: \([0-9]+\))?$"#, options: .regularExpression) != nil else { return nil }
            return normalized.components(separatedBy: " ")[0]
        })
    }

    static func oauthProviders(inModelStatus status: [String: Any]) -> Set<String> {
        guard let auth = status["auth"] as? [String: Any] else { return [] }
        return Set((auth["providers"] as? [[String: Any]] ?? []).compactMap { provider in
            let profiles = provider["profiles"] as? [String: Any] ?? [:]
            guard (profiles["oauth"] as? Int ?? 0) > 0 else { return nil }
            return (provider["provider"] as? String)?.lowercased()
        })
    }
}
