import Foundation

enum OpenClawStateInspection: Equatable {
    struct Owner: Equatable {
        let pid: Int
        let command: String
        let descriptor: String
        let type: String
        let path: String

        var summary: String { "\(command) (PID \(pid)), FD \(descriptor): \(path)" }
    }

    case clear
    case busy([Owner])
    case failed(String)

    static func command(state: String) -> String {
        // Do not let the inspection's own working directory appear as an owner.
        "cd / && LC_ALL=C /usr/sbin/lsof -nP +w -F0pcftn +D \(OpenClawRuntimeInstallation.quote(state)) 2>&1"
    }

    static func parse(code: Int32, output: String) -> Self {
        if code == 1 && output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .clear }
        let diagnostic = String(output.replacingOccurrences(of: "\0", with: "\n").prefix(4_000))
        // macOS lsof can return 1 with valid records for directory-only matches.
        guard code == 0 || code == 1 else {
            return .failed("File inspection failed (exit \(code)).\n\(diagnostic)")
        }
        guard output.trimmingCharacters(in: .newlines).hasSuffix("\0") else {
            return .failed("File inspection returned an unexpected response.\n\(diagnostic)")
        }

        var pid: Int?
        var command: String?
        var descriptor: String?
        var type: String?
        var path: String?
        var records: [Owner] = []
        var malformed = false

        func finishFile() {
            guard let descriptor else { return }
            guard let pid, let command, !command.isEmpty, let type, !type.isEmpty,
                  let path, !path.isEmpty else {
                malformed = true
                return
            }
            records.append(Owner(pid: pid, command: command, descriptor: descriptor, type: type, path: path))
        }

        // NUL-delimited fields preserve spaces and newlines inside file names.
        for raw in output.split(separator: "\0", omittingEmptySubsequences: false) {
            let field = raw.drop(while: { $0 == "\n" })
            if field.isEmpty { continue }
            let value = String(field.dropFirst())
            switch field.first {
            case "p":
                if pid != nil && descriptor == nil { malformed = true }
                finishFile()
                pid = Int(value)
                if (pid ?? 0) <= 0 { malformed = true }
                command = nil
                descriptor = nil
                type = nil
                path = nil
            case "c":
                if pid == nil || command != nil || descriptor != nil { malformed = true }
                command = value
            case "f":
                finishFile()
                if pid == nil || command == nil || value.isEmpty { malformed = true }
                descriptor = value
                type = nil
                path = nil
            case "t":
                if descriptor == nil || type != nil { malformed = true }
                type = value
            case "n":
                if descriptor == nil || path != nil { malformed = true }
                path = value
            default:
                malformed = true
            }
        }
        finishFile()
        guard !malformed, descriptor != nil, !records.isEmpty else {
            return .failed("File inspection was incomplete or contained warnings.\n\(diagnostic)")
        }
        // A cwd/root reference does not hold a SQLite database or WAL open.
        // All actual file handles remain blockers, including read-only handles.
        let blockers = records.filter { !(($0.descriptor == "cwd" || $0.descriptor == "rtd") && $0.type == "DIR") }
        return blockers.isEmpty ? .clear : .busy(blockers)
    }
}
