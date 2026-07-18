import Foundation
import Testing
@testable import localclaw_mac_installer

struct StabilityServicesTests {
    @Test func runtimeRouteClassifiesSupportedBackends() {
        #expect(RuntimeSnapshotResolver.route(for: "openrouter/openai/gpt-5.4-mini") == .cloud)
        #expect(RuntimeSnapshotResolver.route(for: "openai-codex/gpt-5.4") == .oauth)
        #expect(RuntimeSnapshotResolver.route(for: "google-gemini-cli/gemini-2.5-pro") == .oauth)
        #expect(RuntimeSnapshotResolver.route(for: "lmstudio/google/gemma-4-e2b") == .local)
        #expect(RuntimeSnapshotResolver.route(for: "") == .unavailable)
    }

    @Test func runtimeAuthProviderMatchesModelPrefix() {
        #expect(RuntimeSnapshotResolver.authProvider(for: "openrouter/openai/gpt-5.4-mini") == "openrouter")
        #expect(RuntimeSnapshotResolver.authProvider(for: "openai-codex/gpt-5.4") == "openai-codex")
        #expect(RuntimeSnapshotResolver.authProvider(for: "google-gemini-cli/gemini-2.5-pro") == "google")
        #expect(RuntimeSnapshotResolver.authProvider(for: "lmstudio/google/gemma-4-e2b") == nil)
    }

    @Test @MainActor func catalogValidationAcceptsSupportedSchema() throws {
        let data = """
        {
          "schemaVersion": 1,
          "catalogVersion": 3,
          "generatedAt": "2026-07-18T12:00:00Z",
          "source": "test",
          "models": [{
            "name": "Test Model",
            "query": "test-model@q4_k_m",
            "providerId": "test/model",
            "family": "test",
            "summary": "Test candidate",
            "fileSizeGB": 2.5,
            "maxContextK": 128,
            "qualityScore": 4,
            "codingScore": 4,
            "reasoningScore": 4,
            "speedScore": 4,
            "toolUseScore": 4,
            "multimodal": false,
            "badges": []
          }]
        }
        """.data(using: .utf8)!

        let document = try LocalModelCatalogService().decodeAndValidate(data)

        #expect(document.catalogVersion == 3)
        #expect(document.models.first?.providerId == "test/model")
    }

    @Test @MainActor func catalogValidationRejectsDuplicateModels() {
        let candidate = """
        {
          "name": "Duplicate",
          "query": "duplicate@q4_k_m",
          "providerId": "test/duplicate",
          "family": "test",
          "summary": "Duplicate candidate",
          "fileSizeGB": 2,
          "maxContextK": 128,
          "qualityScore": 4,
          "codingScore": 4,
          "reasoningScore": 4,
          "speedScore": 4,
          "toolUseScore": 4,
          "multimodal": false,
          "badges": []
        }
        """
        let data = """
        {
          "schemaVersion": 1,
          "catalogVersion": 1,
          "generatedAt": "2026-07-18T12:00:00Z",
          "source": "test",
          "models": [\(candidate), \(candidate)]
        }
        """.data(using: .utf8)!

        #expect(throws: LocalModelCatalogService.CatalogError.self) {
            try LocalModelCatalogService().decodeAndValidate(data)
        }
    }

    @Test func recoveryPointRestoresOpenClawConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("localclaw-recovery-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent(".openclaw/openclaw.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"agents":{"defaults":{"model":{"primary":"lmstudio/test"}}}}"#.write(to: config, atomically: true, encoding: .utf8)
        let service = RecoveryService(homeDirectory: root.path)

        let point = try service.createSnapshot(reason: "Test")
        try #"{"changed":true}"#.write(to: config, atomically: true, encoding: .utf8)
        try service.restore(point)
        let restored = try String(contentsOf: config, encoding: .utf8)

        #expect(point.files.contains("openclaw.json"))
        #expect(restored.contains("lmstudio/test"))
    }

    @Test func automationReceiptTracksDurationAndOutcome() throws {
        let started = Date(timeIntervalSince1970: 100)
        let receipt = AutomationReceipt(
            source: .cron,
            sourceID: "daily-check",
            title: "Daily check",
            startedAt: started,
            finishedAt: started.addingTimeInterval(4.2),
            status: .succeeded,
            agentID: "main",
            modelID: "openai-codex/gpt-5.4",
            destination: "Telegram",
            summary: "Delivered"
        )

        let data = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(AutomationReceipt.self, from: data)

        #expect(decoded.status == .succeeded)
        #expect(decoded.durationLabel == "4.2s")
        #expect(decoded.destination == "Telegram")
    }

    @Test func chatRecoveryClassifiesCommonOpenClawFailures() {
        let missingModule = "GatewayClientRequestError: Cannot find module '/opt/homebrew/lib/node_modules/openclaw/dist/exec-defaults-old.js'; code=ERR_MODULE_NOT_FOUND"
        #expect(ChatRecoveryPlan.classify(error: missingModule).kind == .runtimeFiles)
        #expect(ChatRecoveryPlan.classify(error: "Gateway closed with 1006 abnormal closure").kind == .gateway)
        #expect(ChatRecoveryPlan.classify(error: "EmbeddedAttemptSessionTakeoverError: session file changed while prompt lock was released").kind == .session)
        #expect(ChatRecoveryPlan.classify(error: "Invalid API key, status 401").kind == .authentication)
        #expect(ChatRecoveryPlan.classify(error: "GatewayClientRequestError: Invalid API key, status 401").kind == .authentication)
        #expect(ChatRecoveryPlan.classify(error: "LM Studio model is not loaded").kind == .localModel)
        #expect(ChatRecoveryPlan.classify(error: "Request timed out after 540 seconds").kind == .timeout)
        #expect(ChatRecoveryPlan.classify(error: "Unexpected internal failure").kind == .unknown)
    }
}
