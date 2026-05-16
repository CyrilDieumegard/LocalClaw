import Foundation

enum SecretRedactor {
    private static let sensitiveKeys: Set<String> = [
        "api_key",
        "apikey",
        "apiKey",
        "authorization",
        "key",
        "password",
        "secret",
        "token"
    ]

    static func redactConfigText(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return redactPlainText(raw)
        }

        let redacted = redactJSONValue(json)
        guard JSONSerialization.isValidJSONObject(redacted),
              let output = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: output, encoding: .utf8) else {
            return redactPlainText(raw)
        }

        return text
    }

    private static func redactJSONValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var copy: [String: Any] = [:]
            for (key, nested) in dict {
                copy[key] = isSensitiveKey(key) ? "<redacted>" : redactJSONValue(nested)
            }
            return copy
        }

        if let array = value as? [Any] {
            return array.map { redactJSONValue($0) }
        }

        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if sensitiveKeys.contains(normalized) { return true }

        let lower = normalized.lowercased()
        return lower.contains("token")
            || lower.contains("secret")
            || lower.contains("password")
            || lower.contains("apikey")
            || lower.contains("api_key")
            || lower == "key"
    }

    private static func redactPlainText(_ raw: String) -> String {
        let patterns = [
            #"(?i)([A-Z0-9_]*(?:API[_-]?KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*\s*=\s*)[^\s]+"#,
            #"(?i)(\"(?:api[_-]?key|apikey|token|secret|password|key)\"\s*:\s*\")[^\"]*(\")"#
        ]

        return patterns.reduce(raw) { text, pattern in
            text.replacingOccurrences(
                of: pattern,
                with: "$1<redacted>$2",
                options: .regularExpression
            )
        }
    }
}
