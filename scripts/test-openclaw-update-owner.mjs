import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

const updater = resolve(process.argv[2]);
const target = JSON.parse(readFileSync(join(updater, "package.json"), "utf8")).version;
const home = mkdtempSync("/private/tmp/localclaw-update-owner-");
const prefix = join(home, ".local");
const pkg = join(prefix, "lib/node_modules/openclaw");
const state = join(home, ".openclaw");
const label = "io.localclaw.update-ownership-fixture";
const escapeXML = (value) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

try {
  for (const directory of [join(pkg, "dist"), join(state, "state"), join(home, "Library/LaunchAgents")]) {
    mkdirSync(directory, { recursive: true });
  }
  writeFileSync(join(pkg, "package.json"), JSON.stringify({ name: "openclaw", version: "2026.7.1-2", bin: { openclaw: "openclaw.mjs" } }));
  writeFileSync(join(pkg, "openclaw.mjs"), "");
  writeFileSync(join(pkg, "dist/index.js"), "");
  writeFileSync(join(state, "openclaw.json"), JSON.stringify({ gateway: { mode: "local", bind: "loopback" } }));
  const db = new DatabaseSync(join(state, "state/openclaw.sqlite"));
  db.exec("PRAGMA user_version=15");
  db.close();

  const args = [process.execPath, join(pkg, "dist/index.js"), "gateway", "--port", "19877"];
  const plist = `<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>${label}</string><key>ProgramArguments</key><array>${args.map((value) => `<string>${escapeXML(value)}</string>`).join("")}</array></dict></plist>`;
  writeFileSync(join(home, "Library/LaunchAgents", `${label}.plist`), plist);

  // Read-only planning with a distinct, never-loaded service label. No host credentials inherited.
  const env = {
    HOME: home, PATH: process.env.PATH, OPENCLAW_STATE_DIR: state,
    OPENCLAW_CONFIG_PATH: join(state, "openclaw.json"), OPENCLAW_LAUNCHD_LABEL: label,
    OPENCLAW_NO_AUTO_UPDATE: "1", NPM_CONFIG_PREFIX: prefix, npm_config_prefix: prefix, NO_COLOR: "1",
  };
  const preload = fileURLToPath(new URL("./templates/update-owner-test-preload.mjs", import.meta.url));
  const result = spawnSync(process.execPath, ["--import", preload, join(updater, "openclaw.mjs"), "update", "--tag", target, "--dry-run", "--json", "--timeout", "30"], {
    env, encoding: "utf8", timeout: 90_000, maxBuffer: 2 * 1024 * 1024,
  });
  assert.equal(result.status, 0, `${result.error?.message ?? ""}\n${result.stdout}\n${result.stderr}`);
  const plan = JSON.parse(result.stdout);
  assert.equal(plan.dryRun, true);
  assert.equal(plan.root, pkg, "A staged updater must target the Gateway package, not itself or ambient npm");
  assert.equal(plan.currentVersion, "2026.7.1-2");
  assert.equal(plan.targetVersion, target);
  assert.equal(JSON.parse(readFileSync(join(pkg, "package.json"), "utf8")).version, "2026.7.1-2");
  console.log(`PASS real OpenClaw ${target} updater targets the isolated Gateway's .local installation with schema 15.`);
  console.log("Dry-run with a test-only OS account fixture: no packages replaced, no LaunchAgents loaded and no provider calls.");
} finally {
  rmSync(home, { recursive: true, force: true });
}
