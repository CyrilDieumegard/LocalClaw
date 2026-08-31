import Foundation

enum OpenClawUpdateResult {
    // Doctor can print valid JSON examples before the CLI's final result. Never
    // interpret examples, nested steps, or plugin outcomes as the update envelope.
    static func envelope(in output: String) -> [String: Any]? {
        objects(in: output).last {
            $0["status"] is String && $0["root"] is String && $0["mode"] is String &&
            ($0["steps"] is [Any] || ($0["mode"] as? String == "finalize" &&
                $0["restart"] as? Bool == false && $0["phaseTimings"] is [Any] && $0["postUpdate"] is [String: Any]))
        }
    }

    static func objects(in output: String) -> [[String: Any]] {
        let bytes = Array(output.utf8)
        var objects: [[String: Any]] = []
        var start = 0
        while start < bytes.count {
            guard bytes[start] == 0x7B || bytes[start] == 0x5B else { start += 1; continue }
            var stack: [UInt8] = []
            var quoted = false
            var escaped = false
            var end: Int?
            for index in start..<bytes.count {
                let byte = bytes[index]
                if quoted {
                    if escaped { escaped = false }
                    else if byte == 0x5C { escaped = true }
                    else if byte == 0x22 { quoted = false }
                } else if byte == 0x22 { quoted = true }
                else if byte == 0x7B { stack.append(0x7D) }
                else if byte == 0x5B { stack.append(0x5D) }
                else if byte == 0x7D || byte == 0x5D {
                    guard stack.last == byte else { break }
                    stack.removeLast()
                    if stack.isEmpty { end = index; break }
                }
            }
            if let end, let value = try? JSONSerialization.jsonObject(with: Data(bytes[start...end])) {
                if let object = value as? [String: Any] { objects.append(object) }
                start = end + 1
            } else { start += 1 }
        }
        return objects
    }

    static func needsPluginApproval(_ text: String) -> Bool {
        let current = OpenClawRecoveryDiagnostic.currentFailure(in: text).lowercased()
        return current.contains("plugin_capability_consent_required") ||
            current.contains("requires capability consent") || current.contains("plugin approval required")
    }

    static func pluginFailure(in result: [String: Any]) -> String? {
        guard let plugins = (result["postUpdate"] as? [String: Any])?["plugins"] as? [String: Any],
              let status = plugins["status"] as? String, ["error", "warning"].contains(status) else { return nil }
        let data = (try? JSONSerialization.data(withJSONObject: plugins, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let details = String(decoding: data, as: UTF8.self)
        if needsPluginApproval(details) {
            return "Plugin approval required. The OpenClaw core is installed; new plugin permissions were not accepted. Review Plugin Permissions, then Finish Repair. The core will not be reinstalled.\n\(details)"
        }
        return "The OpenClaw core is installed, but plugin repair needs attention. Repair will resume without reinstalling the core.\n\(details)"
    }
}

struct OpenClawUpdateCheckpoint: Codable {
    let package: String
    let node: String
    let state: String
    let config: String
    let target: String
    let archive: String
    let archiveSize: UInt64
    let archiveModified: Date

    static func location(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/LocalClaw/runtime-backups/pending-update.json")
    }

    static func save(home: URL, runtime: OpenClawRuntimeInstallation, target: String, archive: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        guard let size = attributes[.size] as? NSNumber, size.uint64Value > 0,
              let modified = attributes[.modificationDate] as? Date else {
            throw MaintenanceError("The verified recovery backup is no longer available.")
        }
        let checkpoint = Self(package: runtime.package.path, node: runtime.node.resolvingSymlinksInPath().path, state: runtime.state.path,
                              config: runtime.config.path, target: target, archive: archive.path,
                              archiveSize: size.uint64Value, archiveModified: modified)
        let file = location(home: home)
        try JSONEncoder().encode(checkpoint).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func load(home: URL, runtime: OpenClawRuntimeInstallation) -> Self? {
        guard let data = try? Data(contentsOf: location(home: home)),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.package == runtime.package.path, value.node == runtime.node.resolvingSymlinksInPath().path,
              value.state == runtime.state.path, value.config == runtime.config.path,
              value.target == runtime.version,
              URL(fileURLWithPath: value.archive).deletingLastPathComponent().resolvingSymlinksInPath() ==
                location(home: home).deletingLastPathComponent().resolvingSymlinksInPath(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: value.archive),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.uint64Value == value.archiveSize,
              attributes[.modificationDate] as? Date == value.archiveModified else { return nil }
        return value
    }
}
