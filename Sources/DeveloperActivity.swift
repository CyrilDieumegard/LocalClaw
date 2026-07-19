import Foundation

struct DeveloperActivityEvent: Identifiable, Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case running
        case succeeded
        case failed
    }

    let id: String
    let title: String
    let detail: String
    let startedAt: Date
    var state: State
}

enum DeveloperActivityParser {
    static func applying(
        jsonLine: String,
        to currentEvents: [DeveloperActivityEvent],
        projectPath: String
    ) -> [DeveloperActivityEvent] {
        guard let data = jsonLine.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "message",
              let message = root["message"] as? [String: Any],
              let role = message["role"] as? String else {
            return currentEvents
        }

        var events = currentEvents
        if role == "assistant", let content = message["content"] as? [[String: Any]] {
            for item in content where item["type"] as? String == "toolCall" {
                guard let id = item["id"] as? String,
                      let name = item["name"] as? String,
                      !events.contains(where: { $0.id == id }) else { continue }
                let arguments = item["arguments"] as? [String: Any] ?? [:]
                let summary = toolSummary(name: name, arguments: arguments, projectPath: projectPath)
                events.append(
                    DeveloperActivityEvent(
                        id: id,
                        title: summary.title,
                        detail: summary.detail,
                        startedAt: messageDate(message) ?? Date(),
                        state: .running
                    )
                )
            }
        } else if role == "toolResult", let toolCallID = message["toolCallId"] as? String,
                  let index = events.firstIndex(where: { $0.id == toolCallID }) {
            events[index].state = (message["isError"] as? Bool) == true ? .failed : .succeeded
        }

        return Array(events.suffix(12))
    }

    static func toolSummary(
        name: String,
        arguments: [String: Any],
        projectPath: String
    ) -> (title: String, detail: String) {
        let normalized = name.lowercased()
        let path = (arguments["path"] as? String)
            ?? (arguments["file_path"] as? String)
            ?? (arguments["filePath"] as? String)
            ?? ""
        let displayPath = safeDisplayPath(path, projectPath: projectPath)
        let fileLabel = displayPath.isEmpty ? "project files" : displayPath

        switch normalized {
        case "read":
            return ("Reading \(fileLabel)", "Inspecting existing code")
        case "edit", "apply_patch", "write":
            return ("Editing \(fileLabel)", "Applying code changes")
        case "exec", "shell":
            return commandSummary(arguments["command"] as? String ?? "")
        case "process":
            return ("Waiting for a project command", "Build or test still running")
        case "image":
            return ("Inspecting generated visuals", "Checking the visual result")
        case "browser", "browser_automation":
            return ("Testing the preview", "Interacting with the app")
        case "memory_search", "memory_get":
            return ("Checking project context", "Looking up relevant workspace notes")
        case "sessions_list", "sessions_history", "sessions_send", "sessions_spawn":
            return ("Checking agent sessions", "Coordinating the coding task")
        default:
            return ("Using \(humanizedToolName(name))", "OpenClaw tool activity")
        }
    }

    private static func commandSummary(_ command: String) -> (title: String, detail: String) {
        let clean = command.lowercased()
        if clean.contains("npm install") || clean.contains("npm i ") {
            return ("Installing project dependencies", "Running the package manager")
        }
        if clean.contains("npm run build") || clean.contains("swift build") || clean.contains("xcodebuild") {
            return ("Building the project", "Verifying that the code compiles")
        }
        if clean.contains("npm test") || clean.contains("npm run test") || clean.contains("swift test") || clean.contains("pytest") || clean.contains("vitest") {
            return ("Running project tests", "Checking behavior after changes")
        }
        if clean.contains("playwright") || clean.contains("screenshot") || clean.contains("curl http://localhost") || clean.contains("curl http://127.0.0.1") {
            return ("Testing the preview", "Checking the running app")
        }
        if clean.contains("git status") || clean.contains("git diff") || clean.contains("git log") {
            return ("Checking source control", "Reviewing changed files")
        }
        return ("Running a project command", "Shell command in the workspace")
    }

    private static func safeDisplayPath(_ path: String, projectPath: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let project = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let candidate = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        if candidate.hasPrefix(project + "/") {
            return String(candidate.dropFirst(project.count + 1))
        }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private static func humanizedToolName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private static func messageDate(_ message: [String: Any]) -> Date? {
        guard let raw = message["timestamp"] else { return nil }
        if let milliseconds = raw as? Double {
            return Date(timeIntervalSince1970: milliseconds > 10_000_000_000 ? milliseconds / 1_000 : milliseconds)
        }
        if let string = raw as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }
}
