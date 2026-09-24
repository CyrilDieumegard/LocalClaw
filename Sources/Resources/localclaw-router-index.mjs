import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

const DECISION_MODEL = "onnx/gliner2.5-small-v1";
const RUBRIC_VERSION = "localclaw-route-v2";
const ROUTER_AGENT = "localclaw-router";

function validText(value, maximum) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= maximum;
}

export default definePluginEntry({
  id: "localclaw-router",
  name: "LocalClaw Local Router",
  description: "Classifies LocalClaw beta chat requests with a local ONNX decision model.",
  register(api) {
    api.registerGatewayMethod(
      "localclaw.router.classify",
      async ({ params, respond, signal }) => {
        if (!validText(params.prompt, 1_600) ||
            (params.prior !== undefined && !validText(params.prior, 400))) {
          respond(true, { status: "unavailable", reason: "invalid-input" });
          return;
        }

        // Fail before evaluation if the configured role could send a decision
        // to a hosted provider. The beta promises local classification only.
        if (api.config?.agents?.entries?.[ROUTER_AGENT]?.decisionModel !== DECISION_MODEL) {
          respond(true, { status: "unavailable", reason: "local-model-not-selected" });
          return;
        }

        try {
          const outcome = await api.runtime.decisions.evaluate(
            {
              state: params.prior
                ? `Previous request: ${params.prior.trim()}\nCurrent request: ${params.prompt.trim()}`
                : params.prompt.trim(),
              questions: {
                route: {
                  type: "choice",
                  instructions: "Classify the difficulty and subject of this chat request.",
                  criteria: {
                    economical: "A single-step simple task: translate, correct spelling, rewrite a short text, summarize a passage, or answer a direct factual question.",
                    reasoning: "A complex or multi-step task: compare options with tradeoffs, make a strategic plan, calculate or solve mathematics, analyze risks, synthesize evidence, or reason carefully.",
                    coding: "A software task: write, debug, review or explain Python, JavaScript, SwiftUI, SQL, APIs, commands, tests or software architecture.",
                  },
                },
              },
            },
            {
              agentId: ROUTER_AGENT,
              purpose: "localclaw.chat.routing",
              rubricVersion: RUBRIC_VERSION,
              timeoutMs: 25_000,
              signal: signal ?? AbortSignal.timeout(25_000),
            },
          );

          if (outcome.status !== "ok") {
            respond(true, { status: "unavailable", reason: outcome.reason });
            return;
          }
          if (outcome.provenance.providerId !== "onnx" ||
              outcome.result.answers.route?.type !== "choice") {
            respond(true, { status: "unavailable", reason: "unexpected-provider-result" });
            return;
          }

          const answer = outcome.result.answers.route;
          respond(true, {
            status: "ok",
            route: answer.choice,
            probabilities: answer.probabilities,
            routerModel: outcome.result.model,
            providerId: outcome.provenance.providerId,
            rubricVersion: RUBRIC_VERSION,
          });
        } catch {
          // Avoid echoing provider errors or prompt material to RPC callers.
          respond(true, { status: "unavailable", reason: "local-evaluation-failed" });
        }
      },
      { scope: "operator.write" },
    );
  },
});
