import assert from "node:assert/strict";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

// An actual OpenClaw tool turn against a deterministic localhost model, without
// cloud credentials, LM Studio, launchd, or any existing customer configuration.
const packageRoot = resolve(process.argv[2]);
const viaGateway = process.argv.includes("--gateway");
const root = mkdtempSync(join(tmpdir(), "localclaw-turn-"));
const state = join(root, ".openclaw");
const workspace = join(root, "workspace");
mkdirSync(state); mkdirSync(workspace);
let requests = 0;
const server = createServer(async (request, response) => {
  let data = "";
  for await (const part of request) data += part;
  if (!request.url.endsWith("/chat/completions")) { response.writeHead(404).end(); return; }
  const body = JSON.parse(data);
  requests++;
  const completed = body.messages.some((message) => message.role === "tool");
  assert.ok(completed || body.tools.some((tool) => tool.function.name === "write"), "Write tool must be available");
  const message = completed
    ? { role: "assistant", content: "Compatibility turn completed; fixture.txt was written." }
    : { role: "assistant", content: null, tool_calls: [{ id: "call_fixture", type: "function", function: {
      name: "write", arguments: JSON.stringify({ path: join(workspace, "fixture.txt"), content: "LocalClaw compatibility OK\n" }),
    } }] };
  const base = { id: "chatcmpl-fixture", object: "chat.completion", created: 1, model: "fixture" };
  const finish = completed ? "stop" : "tool_calls";
  if (body.stream) {
    response.writeHead(200, { "Content-Type": "text/event-stream" });
    const delta = { ...message };
    if (delta.tool_calls) delta.tool_calls = delta.tool_calls.map((tool, index) => ({ index, ...tool }));
    response.write(`data: ${JSON.stringify({ ...base, object: "chat.completion.chunk", choices: [{ index: 0, delta, finish_reason: null }] })}\n\n`);
    response.write(`data: ${JSON.stringify({ ...base, object: "chat.completion.chunk", choices: [{ index: 0, delta: {}, finish_reason: finish }], usage: {prompt_tokens: 12, completion_tokens: 8, total_tokens: 20} })}\n\n`);
    response.end("data: [DONE]\n\n");
  } else {
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(JSON.stringify({ ...base, choices: [{ index: 0, message, finish_reason: finish }], usage: {prompt_tokens: 12, completion_tokens: 8, total_tokens: 20} }));
  }
});
let child;
let gateway;
try {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const portProbe = createServer();
  portProbe.listen(0, "127.0.0.1"); await once(portProbe, "listening");
  const gatewayPort = portProbe.address().port;
  await new Promise((done) => portProbe.close(done));
  const environment = { PATH: process.env.PATH, HOME: root, OPENCLAW_HOME: root, OPENCLAW_STATE_DIR: state, OPENCLAW_CONFIG_PATH: join(state, "openclaw.json"), NO_COLOR: "1" };
  const config = {
    gateway: { mode: "local", bind: "loopback", port: gatewayPort, auth: {mode: "token", token: "localclaw-isolated-test-only"} },
    agents: { entries: { writer: {} }, ownership: "explicit", defaults: {
      workspace, model: { primary: "lmstudio/fixture" },
      models: { "lmstudio/fixture": { agentRuntime: { id: "openclaw" } } },
    } },
    models: { providers: { lmstudio: {
      baseUrl: `http://127.0.0.1:${server.address().port}/v1`, apiKey: "fixture-only",
      api: "openai-completions", models: [{ id: "fixture", name: "Fixture", contextWindow: 32768, maxTokens: 4096, reasoning: false, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0} }],
    } } },
    tools: { allow: ["read", "write"] },
  };
  writeFileSync(join(state, "openclaw.json"), JSON.stringify(config));
  writeFileSync(join(root, "prompt.txt"), "Create fixture.txt containing LocalClaw compatibility OK using the write tool, then confirm completion.");
  let gatewayLog = "";
  if (viaGateway) {
    gateway = spawn(process.execPath, [join(packageRoot, "openclaw.mjs"), "gateway", "run"], {env: environment, stdio: ["ignore", "pipe", "pipe"]});
    gateway.stdout.on("data", (data) => { gatewayLog += data; });
    gateway.stderr.on("data", (data) => { gatewayLog += data; });
    let healthy = false;
    for (let i = 0; i < 60; i++) {
      try { healthy = (await fetch(`http://127.0.0.1:${gatewayPort}/healthz`, {signal: AbortSignal.timeout(1000)})).ok; } catch {}
      if (healthy) break;
      if (gateway.exitCode !== null) break;
      await new Promise((done) => setTimeout(done, 500));
    }
    assert.ok(healthy, gatewayLog);
  }
  child = spawn(process.execPath, [join(packageRoot, "openclaw.mjs"), "agent", ...(viaGateway ? [] : ["--local"]), "--agent", "writer", "--session-id", "localclaw-fixture-turn", "--model", "lmstudio/fixture", "--message-file", join(root, "prompt.txt"), "--thinking", "off", "--timeout", "60", "--json"], {
    env: environment,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  child.stdout.on("data", (data) => { output += data; });
  child.stderr.on("data", (data) => { output += data; });
  const timer = setTimeout(() => child.kill("SIGKILL"), 90000);
  const [code] = await once(child, "close");
  clearTimeout(timer);
  assert.equal(code, 0, output);
  assert.match(output, /Compatibility turn completed/, output);
  assert.equal(readFileSync(join(workspace, "fixture.txt"), "utf8"), "LocalClaw compatibility OK\n");
  assert.equal(requests, 2, "One tool call, one confirmation; no retry loop");
  if (viaGateway) assert.ok(!output.includes("falling back") && !output.includes("Gateway agent failed"), output);
  console.log(`PASS real OpenClaw ${viaGateway ? "Gateway" : "embedded"} turn: explicit agent + message file + model override + streamed write tool + on-disk artifact + final reply (2 model requests)`);
} finally {
  if (child && child.exitCode === null) child.kill("SIGKILL");
  if (gateway && gateway.exitCode === null) {
    const closed = once(gateway, "close");
    gateway.kill("SIGTERM");
    const timeout = setTimeout(() => gateway.kill("SIGKILL"), 5000);
    await closed; clearTimeout(timeout);
  }
  server.closeAllConnections(); server.close();
  rmSync(root, { recursive: true, force: true });
}
