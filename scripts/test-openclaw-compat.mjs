import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const packageRoot = resolve(process.argv[2] ?? "/opt/homebrew/lib/node_modules/openclaw");
const root = mkdtempSync(join(tmpdir(), "localclaw-compat-smoke-"));
const state = join(root, ".openclaw");
mkdirSync(state, { recursive: true });
const environment = {
  PATH: process.env.PATH,
  HOME: root,
  OPENCLAW_HOME: root,
  OPENCLAW_STATE_DIR: state,
  OPENCLAW_CONFIG_PATH: join(state, "openclaw.json"),
  OPENCLAW_DIST_DIR: join(packageRoot, "dist"),
  NO_COLOR: "1",
};
const cli = join(packageRoot, "openclaw.mjs");
const script = fileURLToPath(new URL("../Sources/Resources/goal-controller.mjs", import.meta.url));

function run(args, input, timeout = 60_000) {
  const result = spawnSync(process.execPath, args, {
    env: environment, input, encoding: "utf8", timeout, killSignal: "SIGKILL", maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.status, 0, `${args.join(" ")}\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}

try {
  const version = run([cli, "--version"]).trim();
  console.log(version);
  const modern = version.includes("2026.8.");
  writeFileSync(environment.OPENCLAW_CONFIG_PATH, JSON.stringify({
    gateway: { mode: "local", port: 19879, bind: "loopback" },
    agents: {
      ...(modern ? { entries: { main: {}, writer: {} }, ownership: "explicit" } : { list: [{ id: "main", default: true }, { id: "writer" }] }),
      defaults: { workspace: join(root, "workspace"), model: { primary: "lmstudio/fixture" } },
    },
  }));
  for (const args of [["agent"], ["models", "list"], ["models", "status"],
    ["gateway", "status"], ["cron", "add"], ["channels", "add"],
    ["channels", "status"], ["agents", "add"], ["plugins", "registry"],
    ["sessions", "compact"]]) {
    run([cli, ...args, "--help"]);
    console.log(`PASS CLI ${args.join(" ")}`);
  }
  run([cli, "config", "validate"]);
  console.log("PASS configuration schema");
  const listed = JSON.parse(run([cli, "models", "list", "--agent", "writer", "--json"]));
  assert.ok(Array.isArray(listed.models));
  JSON.parse(run([cli, "plugins", "registry", "--refresh", "--json"]));
  console.log("PASS scoped model discovery and plugin registry refresh");
  const actions = ["status", "start", "status", "pause", "resume", "edit", "complete", "clear", "status"];
  const requests = actions.map((action, index) => ({
    id: String(index), action, sessionKey: "agent:writer:explicit:localclaw-compat-goal",
    objective: action === "edit" ? "Updated compatibility fixture" : "Compatibility fixture",
    tokenBudget: 5000,
  }));
  const output = run([script], requests.map((value) => JSON.stringify(value)).join("\n") + "\n");
  const envelopes = output.split("\n").flatMap((line) => {
    try { return [JSON.parse(line)]; } catch { return []; }
  });
  assert.equal(envelopes.find((value) => value.type === "ready")?.ok, true, output);
  const responses = envelopes.filter((value) => value.type === "response");
  assert.equal(responses.length, actions.length, output);
  assert.ok(responses.every((value) => value.ok), output);
  assert.equal(responses[0].goal, null);
  assert.equal(responses[1].goal.tokenBudget, 5000);
  assert.equal(responses[3].goal.status, "paused");
  assert.equal(responses[4].goal.status, "active");
  assert.equal(responses[5].goal.objective, "Updated compatibility fixture");
  assert.equal(responses[6].goal.status, "complete");
  assert.equal(responses[8].goal, null);
  console.log("PASS named-agent Goal lifecycle (start/status/pause/resume/edit/complete/clear)");
  const archive = join(root, "state-backup.tar.gz");
  run([cli, "backup", "create", "--no-include-workspace", "--verify", "--output", archive, "--json"]);
  assert.ok(statSync(archive).size > 0);
  console.log("PASS verified pre-update state backup (without copying project workspaces)");
  if (modern) {
    run([cli, "models", "auth", "paste-api-key", "--agent", "writer", "--provider", "lmstudio"], "fixture-not-a-real-secret\n");
    const status = JSON.parse(run([cli, "models", "status", "--agent", "writer", "--json"]));
    assert.ok(status.auth.providers.some((provider) => provider.provider === "lmstudio" && provider.profiles.apiKey > 0));
    assert.ok(status.auth.storePath.endsWith(".sqlite"));
    console.log("PASS API key import via stdin into SQLite credential store");
    const sessionID = run(["--input-type=module", "-e", `
      const store = await import(${JSON.stringify(pathToFileURL(join(packageRoot, "dist/plugin-sdk/session-store-runtime.js")).href)});
      const transcript = await import(${JSON.stringify(pathToFileURL(join(packageRoot, "dist/plugin-sdk/session-transcript-runtime.js")).href)});
      const scope = { agentId: "writer", sessionKey: "agent:writer:explicit:localclaw-compat-goal", storePath: store.resolveStorePath(undefined, {agentId: "writer"}) };
      const entry = store.getSessionEntry(scope);
      scope.sessionId = entry.sessionId;
      await transcript.appendSessionTranscriptMessageByIdentity({...scope, message: {
        role: "assistant", content: [{type: "toolCall", id: "fixture-write", name: "write", arguments: {path: "index.html", content: "PRIVATE_BODY"}}], timestamp: Date.now()
      }});
      await transcript.appendSessionTranscriptMessageByIdentity({...scope, message: {
        role: "toolResult", toolCallId: "fixture-write", content: [{type: "text", text: "PRIVATE_RESULT"}], isError: false, timestamp: Date.now()
      }});
      console.log(entry.sessionId);
    `]).trim();
    const activityScript = fileURLToPath(new URL("../Sources/Resources/developer-activity.mjs", import.meta.url));
    const activity = spawnSync(process.execPath, [activityScript, "writer", sessionID], {
      env: environment, encoding: "utf8", timeout: 5000, maxBuffer: 1024 * 1024,
    });
    assert.match(activity.stdout, /fixture-write/, activity.stderr);
    assert.match(activity.stdout, /toolResult/, activity.stderr);
    assert.ok(!activity.stdout.includes("PRIVATE_"));
    assert.equal(activity.stdout.trim().split("\n").length, 2, "Activity should not replay unchanged events");
    console.log("PASS SQLite Developer activity, incremental reads, private payloads excluded");
    writeFileSync(environment.OPENCLAW_CONFIG_PATH, JSON.stringify({
      gateway: { mode: "remote", remote: {url: "ws://127.0.0.1:19879"} },
      agents: {
        list: [{id: "main", default: true}, {id: "writer", workspace: join(root, "writer-workspace")}],
        defaults: { workspace: join(root, "workspace"), model: {primary: "openai-codex/gpt-5.5"}, models: {"openai-codex/gpt-5.5": {alias: "My chosen model"}} },
      },
      auth: {profiles: {"openai-codex:fixture": {provider: "openai-codex", mode: "oauth"}}, order: {"openai-codex": ["openai-codex:fixture"]}},
    }));
    // OPENCLAW_HOME makes the new runtime explicitly refuse host service management.
    // Remote mode additionally skips local Gateway repair in this migration fixture.
    run([cli, "doctor", "--fix", "--yes", "--non-interactive"], undefined, 300_000);
    run([cli, "config", "validate"]);
    const migrated = JSON.parse(readFileSync(environment.OPENCLAW_CONFIG_PATH, "utf8"));
    assert.ok(migrated.agents.entries.main && migrated.agents.entries.writer);
    assert.equal(migrated.agents.list, undefined);
    assert.equal(migrated.agents.defaults.model.primary, "openai/gpt-5.5");
    assert.equal(migrated.agents.defaults.models["openai/gpt-5.5"].alias, "My chosen model");
    assert.equal(migrated.agents.defaults.models["openai/gpt-5.5"].agentRuntime.id, "codex");
    assert.equal(migrated.auth.profiles["openai:fixture"].provider, "openai");
    assert.deepEqual(migrated.auth.order.openai, ["openai:fixture"]);
    console.log("PASS legacy doctor migration: roster, selected model, runtime intent, auth metadata and auth order preserved");
  }
  console.log("All compatibility smoke tests passed; no customer state or provider calls used.");
} finally {
  rmSync(root, { recursive: true, force: true });
}
