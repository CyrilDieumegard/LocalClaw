import Foundation

struct LocalModelCatalogDocument: Codable, Sendable {
    let schemaVersion: Int
    let catalogVersion: Int
    let generatedAt: Date
    let source: String
    let models: [InstallerViewModel.LocalModelCandidate]
}

final class LocalModelCatalogService: @unchecked Sendable {
    enum CatalogError: LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case unsupportedSchema
        case invalidCatalog

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "The model catalog endpoint is not trusted."
            case .invalidResponse: return "The model catalog could not be downloaded."
            case .unsupportedSchema: return "The model catalog format is newer than this LocalClaw version."
            case .invalidCatalog: return "The model catalog did not pass validation."
            }
        }
    }

    private let endpoint: URL
    private let cacheURL: URL

    init(
        endpoint: URL = URL(string: "https://localclaw.io/downloads/local-model-catalog-v1.json")!,
        fileManager: FileManager = .default
    ) {
        self.endpoint = endpoint
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        self.cacheURL = support.appendingPathComponent("LocalClaw/local-model-catalog-v1.json")
    }

    func fetch() async throws -> LocalModelCatalogDocument {
        guard endpoint.scheme == "https", endpoint.host == "localclaw.io" else { throw CatalogError.invalidEndpoint }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count < 512_000 else {
            throw CatalogError.invalidResponse
        }
        let document = try decodeAndValidate(data)
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
        return document
    }

    func cached() -> LocalModelCatalogDocument? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? decodeAndValidate(data)
    }

    func decodeAndValidate(_ data: Data) throws -> LocalModelCatalogDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(LocalModelCatalogDocument.self, from: data)
        guard document.schemaVersion == 1 else { throw CatalogError.unsupportedSchema }
        guard (1...100).contains(document.models.count) else { throw CatalogError.invalidCatalog }
        var names = Set<String>()
        for model in document.models {
            guard !model.name.isEmpty,
                  !model.query.isEmpty,
                  !model.providerId.isEmpty,
                  model.fileSizeGB > 0,
                  model.maxContextK > 0,
                  (0...5).contains(model.qualityScore),
                  (0...5).contains(model.codingScore),
                  (0...5).contains(model.reasoningScore),
                  (0...5).contains(model.speedScore),
                  (0...5).contains(model.toolUseScore),
                  names.insert(model.name).inserted else {
                throw CatalogError.invalidCatalog
            }
        }
        return document
    }
}
