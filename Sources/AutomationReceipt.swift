import Foundation

struct AutomationReceipt: Identifiable, Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case cron = "Cron Job"
        case kanban = "Kanban"
    }

    enum Status: String, Codable, Sendable {
        case running = "Running"
        case succeeded = "Succeeded"
        case failed = "Failed"
        case unknown = "Unknown"
    }

    let id: UUID
    let source: Source
    let sourceID: String
    let title: String
    let startedAt: Date
    var finishedAt: Date?
    var status: Status
    let agentID: String?
    let modelID: String?
    let destination: String?
    var summary: String?
    var error: String?

    init(
        id: UUID = UUID(),
        source: Source,
        sourceID: String,
        title: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: Status = .running,
        agentID: String?,
        modelID: String?,
        destination: String?,
        summary: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.source = source
        self.sourceID = sourceID
        self.title = title
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.agentID = agentID
        self.modelID = modelID
        self.destination = destination
        self.summary = summary
        self.error = error
    }

    var durationLabel: String? {
        guard let finishedAt else { return nil }
        let seconds = max(0, finishedAt.timeIntervalSince(startedAt))
        return seconds < 60 ? String(format: "%.1fs", seconds) : "\(Int(seconds / 60))m \(Int(seconds) % 60)s"
    }
}

enum AutomationReceiptStore {
    private static let defaultsKey = "localclaw.automation.receipts.v1"

    static func load(defaults: UserDefaults = .standard) -> [AutomationReceipt] {
        guard let data = defaults.data(forKey: defaultsKey),
              let receipts = try? decoder.decode([AutomationReceipt].self, from: data) else { return [] }
        // A previous app process can no longer observe the run it started.
        // OpenClaw may still finish it: neither success nor failure is proven.
        return receipts.map { receipt in
            guard receipt.status == .running else { return receipt }
            var recovered = receipt
            recovered.status = .unknown
            recovered.finishedAt = nil
            recovered.summary = "LocalClaw restarted before completion was confirmed. Check OpenClaw history before retrying."
            return recovered
        }.sorted { $0.startedAt > $1.startedAt }
    }

    static func save(_ receipts: [AutomationReceipt], defaults: UserDefaults = .standard) {
        let recent = Array(receipts.sorted { $0.startedAt > $1.startedAt }.prefix(100))
        guard let data = try? encoder.encode(recent) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
