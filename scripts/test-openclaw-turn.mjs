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
const legacyConfig = process.argv.includes("--legacy-config");
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
async function runCLI(arguments_, environment, timeout = 60000) {
  const process_ = spawn(process.execPath, [join(packageRoot, "openclaw.mjs"), ...arguments_], {
    env: environment, stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  process_.stdout.on("data", (data) => { output += data; });
  process_.stderr.on("data", (data) => { output += data; });
  const timer = setTimeout(() => process_.kill("SIGKILL"), timeout);
  try {
    const [code] = await once(process_, "close");
    return { code, output };
  } finally { clearTimeout(timer); }
}
try {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const portProbe = createServer();
  portProbe.listen(0, "127.0.0.1"); await once(portProbe, "listening");
  const gatewayPort = portProbe.address().port;
  await new Promise((done) => portProbe.close(done));
  const environment = {
    PATH: process.env.PATH, HOME: root, OPENCLAW_HOME: root, OPENCLAW_STATE_DIR: state,
    OPENCLAW_CONFIG_PATH: join(state, "openclaw.json"), NO_COLOR: "1", OPENCLAW_NO_AUTO_UPDATE: "1",
    OPENCLAW_SUPERVISOR_MODE: "external", OPENCLAW_SERVICE_REPAIR_POLICY: "external",
    OPENCLAW_LAUNCHD_LABEL: "io.localclaw.isolated-config-test",
  };
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
  const configPath = join(state, "openclaw.json");
  if (legacyConfig) {
    config.meta = { lastTouchedAt: "2026-08-01T00:00:00.000Z", lastTouchedVersion: "2026.7.1-2" };
    config.agents.defaults.heartbeat = { skipWhenBusy: true };
    config.memory = { backend: "builtin" };
  }
  writeFileSync(configPath, JSON.stringify(config));
  if (legacyConfig) {
    const original = readFileSync(configPath);
    const before = await runCLI(["config", "validate", "--json"], environment);
    assert.notEqual(before.code, 0, "Legacy configuration must fail strict validation before repair");
    assert.match(before.output, /"valid":\s*false/, before.output);
    assert.equal(requests, 0, "Configuration checks must not call the model");
    const backup = join(root, "original-config.backup.json");
    writeFileSync(backup, original, { mode: 0o600 });
    writeFileSync(join(workspace, "existing-project.txt"), "Keep existing project work\n");
    // Both native service gates are external. Doctor can mutate only the isolated
    // HOME/state fixture, never install, restart or clean up the host LaunchAgent.
    const doctor = await runCLI(["doctor", "--fix", "--yes", "--non-interactive", "--no-workspace-suggestions"], environment, 180000);
    assert.equal(doctor.code, 0, doctor.output);
    const after = await runCLI(["config", "validate", "--json"], environment);
    assert.equal(after.code, 0, after.output);
    assert.match(after.output, /"valid":\s*true/, after.output);
    const repaired = JSON.parse(readFileSync(configPath, "utf8"));
    assert.equal(repaired.meta?.lastTouchedAt, undefined);
    assert.equal(repaired.agents.defaults.heartbeat?.skipWhenBusy, undefined);
    assert.equal(repaired.memory?.backend, undefined);
    assert.equal(repaired.agents.defaults.model.primary, "lmstudio/fixture");
    assert.equal(repaired.models.providers.lmstudio.apiKey, "fixture-only");
    assert.deepEqual(repaired.tools.allow, config.tools.allow);
    assert.deepEqual(readFileSync(backup), original);
    assert.equal(readFileSync(join(workspace, "existing-project.txt"), "utf8"), "Keep existing project work\n");
    assert.equal(requests, 0, "Doctor must not send a model request");
    console.log("PASS real configuration migration: rejected meta/agents.defaults/memory -> fresh Doctor -> valid configuration; backup, credentials, tool policy and project preserved; native service mutations disabled.");
  }
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
