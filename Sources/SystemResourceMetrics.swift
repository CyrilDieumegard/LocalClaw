import Foundation

/// Pure parsers shared by Home and both resource panels.
enum SystemResourceMetrics {
    static let memoryExplanation = "Whole Mac memory used, excluding reclaimable file cache. Available memory includes that cache."
    static let processExplanation = "Process groups show resident RAM (RSS), which differs from Activity Monitor’s Memory column. Groups may overlap; Node includes OpenClaw when hosted by Node."

    static func memory(fromVMStat raw: String, totalBytes: UInt64) -> (usedGB: Double, availableGB: Double) {
        let lines = raw.components(separatedBy: .newlines)
        guard let header = lines.first,
              let pageSize = header.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap(Double.init).first, pageSize > 0 else { return (0, 0) }
        var counts: [String: Double] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let value = Double(parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))),
                  value >= 0 else { continue }
            counts[String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))] = value
        }
        guard totalBytes > 0,
              let purgeable = counts["Pages purgeable"],
              let fileBacked = counts["File-backed pages"],
              let free = counts["Pages free"] else { return (0, 0) }

        // Subtract reclaimable memory from physical RAM, preserving kernel/reserved
        // allocations absent from the anonymous + wired + compressor page counts.
        // Speculative pages are already included in File-backed pages; do not add
        // them twice. Compressed memory stays used, without counting its logical size.
        let availableBytes = min(Double(totalBytes), (free + fileBacked + purgeable) * pageSize)
        let scale = 1_073_741_824.0
        return ((Double(totalBytes) - availableBytes) / scale, availableBytes / scale)
    }

    struct ProcessMemory: Equatable {
        var lmStudioMB = 0
        var openclawMB = 0
        var nodeMB = 0
    }

    static func processMemory(fromPS raw: String, arguments: String = "") -> ProcessMemory {
        struct Row {
            let pid: Int
            let parent: Int
            let rss: Int
            let command: String
        }
        let rows = raw.split(separator: "\n").compactMap { line -> Row? in
            let parts = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 4, let pid = Int(parts[0]), pid > 0,
                  let parent = Int(parts[1]), let rss = Int(parts[2]), rss >= 0 else { return nil }
            return Row(pid: pid, parent: parent, rss: rss, command: String(parts[3]))
        }
        let argumentsByPID = Dictionary(arguments.split(separator: "\n").compactMap { line -> (Int, String)? in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
            return (pid, String(parts[1]))
        }, uniquingKeysWith: { first, _ in first })
        var lmStudio = Set<Int>()
        var openclaw = Set<Int>()
        var node = Set<Int>()
        for row in rows {
            let command = row.command
            let words = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let executable = words.first.map { ($0 as NSString).lastPathComponent.lowercased() } ?? ""
            let isNode = executable == "node" || executable == "nodejs"
            let isOpenClawTitle = executable == "openclaw" || executable == "openclaw-gateway"
            // Recognize Node's entry script, not an incidental mention in a shell,
            // grep command, or a later user-supplied argument.
            let script = argumentsByPID[row.pid]?.split(whereSeparator: { $0.isWhitespace }).dropFirst().first.map(String.init) ?? ""
            let scriptName = (script as NSString).lastPathComponent.lowercased()
            let isOpenClawScript = isNode && (scriptName == "openclaw" || scriptName == "openclaw.mjs"
                || script.hasSuffix("/openclaw/dist/index.js") || script.hasSuffix("/openclaw/dist/entry.js"))
            if isNode || isOpenClawTitle { node.insert(row.pid) }
            if isOpenClawTitle || isOpenClawScript { openclaw.insert(row.pid) }
            if command.hasPrefix("/"), command.contains("/LM Studio.app/Contents/") {
                lmStudio.insert(row.pid)
            } else if command == "LM Studio" || command.hasPrefix("LM Studio Helper") {
                lmStudio.insert(row.pid)
            }
        }
        // Include helpers, even when their executable has an unrelated name.
        func descendants(of roots: Set<Int>) -> Set<Int> {
            var result = roots
            var previousCount: Int
            repeat {
                previousCount = result.count
                for row in rows where result.contains(row.parent) { result.insert(row.pid) }
            } while result.count != previousCount
            return result
        }
        lmStudio = descendants(of: lmStudio)
        openclaw = descendants(of: openclaw)
        func megabytes(_ pids: Set<Int>) -> Int {
            // Deduplicate PIDs and round only after summing the group's KiB.
            var seen = Set<Int>()
            return rows.reduce(0) { sum, row in
                sum + (pids.contains(row.pid) && seen.insert(row.pid).inserted ? row.rss : 0)
            } / 1024
        }
        return ProcessMemory(lmStudioMB: megabytes(lmStudio), openclawMB: megabytes(openclaw), nodeMB: megabytes(node))
    }
}
