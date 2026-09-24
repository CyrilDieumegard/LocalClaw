import XCTest
@testable import localclaw_mac_installer

final class RoutedChatPolicyTests: XCTestCase {
    private let mapping = RoutedModelMapping(
        economical: "openrouter/example/cheap",
        reasoning: "openai/example-strong",
        coding: "openai/example-code"
    )

    private var available: Set<String> {
        Set(mapping.modelIDs)
    }

    func testClearRoutineTaskSelectsEconomicalModel() throws {
        let decision = RoutedDecision(
            status: "ok", route: .economical,
            probabilities: ["economical": 0.84, "reasoning": 0.10, "coding": 0.06],
            routerModel: "gliner2.5-small-v1", providerId: "onnx",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        let selected = try RoutedChatPolicy.select(
            decision: decision, mapping: mapping,
            availableModelIDs: available, prompt: "Traduis cette phrase en anglais.", excerpted: false
        )
        XCTAssertEqual(selected.modelID, mapping.economical)
        XCTAssertFalse(selected.wasAmbiguous)
    }

    func testCloseLocalScoresChooseVisibleAnalysisFallback() throws {
        let decision = RoutedDecision(
            status: "ok", route: .economical,
            probabilities: ["economical": 0.37, "reasoning": 0.35, "coding": 0.28],
            routerModel: "gliner2.5-small-v1", providerId: "onnx",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        let selected = try RoutedChatPolicy.select(
            decision: decision, mapping: mapping,
            availableModelIDs: available, prompt: "Please summarize this short paragraph.", excerpted: false
        )
        XCTAssertEqual(selected.modelID, mapping.reasoning)
        XCTAssertEqual(selected.task, .unclear)
        XCTAssertTrue(selected.wasAmbiguous)
    }

    func testShortTranslationUsesEconomicalModelDespitePreviousContextBias() throws {
        let decision = RoutedDecision(
            status: "ok", route: .coding,
            probabilities: ["economical": 0.47, "reasoning": 0.02, "coding": 0.51],
            routerModel: "gliner2.5-small-v1", providerId: "onnx",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        let selected = try RoutedChatPolicy.select(
            decision: decision, mapping: mapping, availableModelIDs: available,
            prompt: "Traduis en français : Hello.", excerpted: false
        )
        XCTAssertEqual(selected.routerTask, .coding)
        XCTAssertEqual(selected.task, .economical)
        XCTAssertEqual(selected.modelID, mapping.economical)
        XCTAssertFalse(selected.wasAmbiguous)
    }

    func testBriefPresenceQuestionUsesEconomicalModelDespiteShortContextFallback() throws {
        let decision = RoutedDecision(
            status: "ok", route: .economical,
            probabilities: ["economical": 0.80, "reasoning": 0.07, "coding": 0.13],
            routerModel: "gliner2.5-small-v1", providerId: "onnx",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        for prompt in ["tu est la?", "Tu es là ?", "Are you there?"] {
            let selected = try RoutedChatPolicy.select(
                decision: decision, mapping: mapping,
                availableModelIDs: available, prompt: prompt, excerpted: false
            )
            XCTAssertEqual(selected.task, .economical, prompt)
            XCTAssertEqual(selected.modelID, mapping.economical, prompt)
        }
    }

    func testBriefClarificationUsesEconomicalModelButAnalysisStaysStrong() throws {
        let decision = RoutedDecision(
            status: "ok", route: .reasoning,
            probabilities: ["economical": 0.38, "reasoning": 0.46, "coding": 0.16],
            routerModel: "gliner2.5-small-v1", providerId: "onnx",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        let clarification = try RoutedChatPolicy.select(
            decision: decision, mapping: mapping,
            availableModelIDs: available, prompt: "heuu astra ?!?", excerpted: false
        )
        XCTAssertEqual(clarification.modelID, mapping.economical)
        let analysis = try RoutedChatPolicy.select(
            decision: decision, mapping: mapping,
            availableModelIDs: available, prompt: "Analyse les risques", excerpted: false
        )
        XCTAssertEqual(analysis.modelID, mapping.reasoning)
    }

    func testHostedDecisionResultAndUnavailableModelFailClosed() {
        let decision = RoutedDecision(
            status: "ok", route: .coding,
            probabilities: ["economical": 0.03, "reasoning": 0.07, "coding": 0.90],
            routerModel: "other", providerId: "hosted",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        XCTAssertThrowsError(try RoutedChatPolicy.select(
            decision: decision, mapping: mapping,
            availableModelIDs: available, prompt: "Write Python code", excerpted: false
        ))
        let local = RoutedDecision(
            status: "ok", route: .coding, probabilities: decision.probabilities,
            routerModel: "gliner2.5-small-v1", providerId: "onnx",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        XCTAssertThrowsError(try RoutedChatPolicy.select(
            decision: local, mapping: mapping,
            availableModelIDs: Set([mapping.economical, mapping.reasoning]), prompt: "Write Python code", excerpted: false
        ))
    }

    func testComplexPromptCannotUseCheapModelDespiteHighClassifierScore() throws {
        let decision = RoutedDecision(
            status: "ok", route: .economical,
            probabilities: ["economical": 0.94, "reasoning": 0.04, "coding": 0.02],
            routerModel: "gliner2.5-small-v1", providerId: "onnx",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        let result = try RoutedChatPolicy.select(
            decision: decision, mapping: mapping, availableModelIDs: available,
            prompt: "Construis un plan stratégique sur trois ans et analyse les risques.", excerpted: false
        )
        XCTAssertEqual(result.routerTask, .economical)
        XCTAssertEqual(result.task, .reasoning)
        XCTAssertEqual(result.modelID, mapping.reasoning)
    }

    func testCodePromptUsesCodeSlotDespiteClassifierMistake() throws {
        let decision = RoutedDecision(
            status: "ok", route: .reasoning,
            probabilities: ["economical": 0.05, "reasoning": 0.80, "coding": 0.15],
            routerModel: "gliner2.5-small-v1", providerId: "onnx",
            rubricVersion: "localclaw-route-v2", reason: nil
        )
        let result = try RoutedChatPolicy.select(
            decision: decision, mapping: mapping, availableModelIDs: available,
            prompt: "Explique cette requête SQL et propose un index.", excerpted: false
        )
        XCTAssertEqual(result.task, .coding)
        XCTAssertEqual(result.modelID, mapping.coding)
    }

    func testLongPromptExcerptKeepsBothEnds() {
        let input = "BEGIN" + String(repeating: "x", count: 2_000) + "END"
        let excerpt = RoutedChatPolicy.excerpt(input)
        XCTAssertTrue(excerpt.excerpted)
        XCTAssertTrue(excerpt.text.hasPrefix("BEGIN"))
        XCTAssertTrue(excerpt.text.hasSuffix("END"))
        XCTAssertLessThan(excerpt.text.count, input.count)
        XCTAssertLessThanOrEqual(excerpt.text.utf8.count, RoutedChatPolicy.currentPromptByteLimit)
    }

    func testMultilingualRoutingStateFitsConservativeLocalBudget() {
        let current = RoutedChatPolicy.excerpt(String(repeating: "Analyse ce code Swift et les risques 你好😀", count: 80))
        let prior = RoutedChatPolicy.priorContext(String(repeating: "Previous request בעברית😀", count: 30))
        XCTAssertTrue(current.excerpted)
        XCTAssertNotNil(prior)
        XCTAssertLessThanOrEqual(current.text.utf8.count, RoutedChatPolicy.currentPromptByteLimit)
        XCTAssertLessThanOrEqual(prior!.utf8.count, RoutedChatPolicy.priorPromptByteLimit)
        let state = "Previous request: \(prior!)\nCurrent request: \(current.text)"
        XCTAssertLessThanOrEqual(state.utf8.count, 320)
    }

    func testRouterBridgeResourcesAreBundled() {
        let testBundle = Bundle(for: Self.self)
        for name in ["localclaw-router-index.mjs", "localclaw-router-plugin.json", "localclaw-router-package.json"] {
            let candidates = GoalControllerResourceLocator.candidateURLs(
                bundleURL: testBundle.bundleURL,
                resourceURL: testBundle.resourceURL,
                executableURL: testBundle.executableURL,
                scriptName: name
            )
            XCTAssertTrue(candidates.contains { FileManager.default.fileExists(atPath: $0.path) },
                          "Missing bundled resource: \(name)")
        }
    }

    func testCloudModelPickerExcludesLocalAndDelegatedRoutes() {
        XCTAssertTrue(RoutedChatService.supportsChatModel("openrouter/deepseek/deepseek-v4-flash"))
        XCTAssertTrue(RoutedChatService.supportsChatModel("openai-codex/gpt-5.4"))
        XCTAssertFalse(RoutedChatService.supportsChatModel("lmstudio/google/gemma-4-e2b"))
        XCTAssertFalse(RoutedChatService.supportsChatModel("ollama/llama3:latest"))
        XCTAssertFalse(RoutedChatService.supportsChatModel("openrouter/auto"))
    }

    func testMissingRouterMethodShowsSetupInsteadOfRawGatewayError() {
        XCTAssertTrue(RoutedChatService.isMissingRouterMethod("Error: unknown method: localclaw.router.classify"))
        XCTAssertTrue(RoutedChatService.isMissingRouterMethod("{\"error\":\"Unknown Method: localclaw.router.classify\"}"))
        XCTAssertFalse(RoutedChatService.isMissingRouterMethod("unknown method: unrelated.method"))
        XCTAssertFalse(RoutedChatService.isMissingRouterMethod("gateway connection refused"))
        XCTAssertEqual(RoutedChatError.routerSetupRequired.errorDescription,
                       "Set up local router to download the decision model and enable routing on this Mac.")
    }

    func testReloadRetriesOnlyExplicitNoReplacementRetainedWork() {
        let temporary = "Plugin onnx still has active retained work; retry after the work finishes. Gateway generation 8: replacement not applied."
        XCTAssertTrue(RoutedChatService.canRetryPluginReload(temporary))
        XCTAssertFalse(RoutedChatService.canRetryPluginReload("Plugin operation failed during prepare: replacement not applied."))
        XCTAssertFalse(RoutedChatService.canRetryPluginReload("Plugin onnx still has active retained work; replacement may have applied."))
    }

    func testInterruptedTurnRecoversOnlyMatchingCompletedGatewayReply() {
        let key = "agent:main:explicit:localclaw-routed-00000000-0000-0000-0000-000000000001"
        let created = Date(timeIntervalSince1970: 1_790_244_777.521)
        let response: [String: Any] = [
            "sessionInfo": ["key": key, "status": "done", "hasActiveRun": false, "lastRunId": "run-1"],
            "messages": [
                ["role": "user", "timestamp": 1_790_244_779_638 as NSNumber],
                ["role": "assistant", "timestamp": 1_790_244_780_331 as NSNumber,
                 "provider": "openrouter", "model": "openai/gpt-5.3-codex",
                 "__openclaw": ["runId": "run-1"],
                 "content": [["type": "text", "text": "A completed reply"]],
                 "usage": ["input": 10, "output": 4]]
            ]
        ]
        switch RoutedChatService.recovery(from: response, sessionKey: key, createdAt: created,
                                          expectedModelID: "openrouter/openai/gpt-5.3-codex") {
        case .recovered(let reply):
            XCTAssertEqual(reply.text, "A completed reply")
            XCTAssertEqual(reply.actualModelID, "openrouter/openai/gpt-5.3-codex")
            XCTAssertEqual(reply.outputTokens, 4)
        default: XCTFail("The exact finished turn should be recovered")
        }
        XCTAssertTrue({
            if case .unmatched = RoutedChatService.recovery(from: response, sessionKey: key,
                                                             createdAt: created,
                                                             expectedModelID: "openai/gpt-6-sol") { return true }
            return false
        }())
        var running = response
        running["sessionInfo"] = ["key": key, "status": "running", "hasActiveRun": true]
        XCTAssertTrue({
            if case .running = RoutedChatService.recovery(from: running, sessionKey: key,
                                                           createdAt: created,
                                                           expectedModelID: "openrouter/openai/gpt-5.3-codex") { return true }
            return false
        }())
    }
}
