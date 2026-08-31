import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

assert.ok(process.argv[2], 'Pass the unpacked OpenClaw 2026.8.1 package directory.');
const pkg = fs.realpathSync(process.argv[2]);
assert.equal(JSON.parse(fs.readFileSync(path.join(pkg, 'package.json'))).version, '2026.8.1');
const helper = fileURLToPath(new URL('../Sources/Resources/exec-approvals-migration.mjs', import.meta.url));
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'localclaw-exec-migration-'));
const policy = {
  version: 1,
  defaults: { security: 'deny', ask: 'always', askFallback: 'deny', autoAllowSkills: false },
  agents: { main: { allowlist: [{ id: 'fixture-only', pattern: '/usr/bin/true' }] } },
};
let passed = 0;

function fixture(name, contents = JSON.stringify(policy)) {
  const home = path.join(root, name);
  const state = path.join(home, '.openclaw');
  fs.mkdirSync(state, { recursive: true, mode: 0o700 });
  const source = path.join(state, 'exec-approvals.json');
  fs.writeFileSync(source, contents, { mode: 0o600 });
  const backup = path.join(home, 'original-approvals.backup');
  fs.copyFileSync(source, backup);
  fs.writeFileSync(path.join(state, 'openclaw.json'), JSON.stringify({
    gateway: { mode: 'remote', remote: { url: 'ws://127.0.0.1:65530', token: 'isolated-test-token' } },
    meta: { lastTouchedVersion: '2026.7.1-2', lastTouchedAt: '2026-08-01T00:00:00.000Z' },
    agents: { defaults: { heartbeat: { skipWhenBusy: true } } },
    memory: { backend: 'builtin' },
  }));
  // No host credentials, real service label, package installs or provider calls.
  const env = { HOME: home, OPENCLAW_HOME: home, TMPDIR: home,
    PATH: `${path.dirname(process.execPath)}:/usr/bin:/bin:/usr/sbin:/sbin`,
    OPENCLAW_STATE_DIR: state, OPENCLAW_CONFIG_PATH: path.join(state, 'openclaw.json'),
    OPENCLAW_SERVICE_REPAIR_POLICY: 'external', OPENCLAW_LAUNCHD_LABEL: 'io.localclaw.exec-migration-fixture',
    OPENCLAW_GATEWAY_PORT: '65530', OPENCLAW_NO_RESPAWN: '1', NO_COLOR: '1' };
  const run = (argv, extra = {}) => spawnSync(process.execPath, argv, {
    env: { ...env, ...extra }, cwd: home, encoding: 'utf8', timeout: 90000, maxBuffer: 4 * 1024 * 1024,
  });
  const migrate = () => run([helper, pkg, state]);
  return { home, state, source, backup, contents, run, migrate };
}

function checkPolicy(f) {
  const db = new DatabaseSync(path.join(f.state, 'state/openclaw.sqlite'), { readOnly: true });
  try {
    const stored = JSON.parse(db.prepare('SELECT raw_json FROM exec_approvals_config').get().raw_json);
    assert.deepEqual(stored.defaults, policy.defaults);
    assert.deepEqual(stored.agents, policy.agents);
    assert.equal(db.prepare('PRAGMA integrity_check').get().integrity_check, 'ok');
    assert.equal(fs.readFileSync(f.backup, 'utf8'), f.contents);
  } finally { db.close(); }
}

function success(result) {
  assert.equal(result.status, 0, `${result.error?.message ?? ''}\n${result.stdout}\n${result.stderr}`);
}

try {
  const valid = fixture('valid');
  const broken = valid.run([path.join(pkg, 'openclaw.mjs'), 'doctor', '--fix', '--non-interactive'], { OPENCLAW_UPDATE_IN_PROGRESS: '1' });
  assert.notEqual(broken.status, 0);
  assert.match(broken.stderr + broken.stdout, /Legacy exec approvals exist/);
  assert.equal(fs.readFileSync(valid.source, 'utf8'), valid.contents);
  success(valid.migrate());
  assert.equal(fs.existsSync(valid.source), false);
  checkPolicy(valid);
  success(valid.run([path.join(pkg, 'openclaw.mjs'), 'doctor', '--fix', '--yes', '--non-interactive']));
  checkPolicy(valid);
  success(valid.run([path.join(pkg, 'openclaw.mjs'), 'config', 'validate', '--json']));
  console.log('PASS real Doctor failure reproduced; official migration, Doctor and config validation succeed; deny/ask policy and backup preserved.');
  passed++;

  success(valid.migrate());
  checkPolicy(valid);
  console.log('PASS repeated migration is idempotent.');
  passed++;

  const claim = fixture('interrupted');
  fs.renameSync(claim.source, claim.source + '.doctor-importing');
  success(claim.migrate());
  checkPolicy(claim);
  assert.equal(fs.existsSync(claim.source + '.doctor-importing'), false);
  console.log('PASS interrupted official import resumes.');
  passed++;

  for (const [name, contents] of [['invalid-json', '{invalid'], ['invalid-policy', JSON.stringify({ version: 1, defaults: { security: 'invalid' } })]]) {
    const f = fixture(name, contents);
    assert.notEqual(f.migrate().status, 0);
    assert.equal(fs.readFileSync(f.source, 'utf8'), contents);
    assert.equal(fs.readFileSync(f.backup, 'utf8'), contents);
    console.log(`PASS ${name} is preserved and blocks activation.`);
    passed++;
  }

  const conflicting = JSON.stringify({ ...policy, defaults: { ...policy.defaults, security: 'full' } });
  fs.writeFileSync(valid.source, conflicting);
  assert.notEqual(valid.migrate().status, 0);
  checkPolicy(valid);
  assert.equal(fs.readFileSync(valid.source, 'utf8'), conflicting);
  console.log('PASS conflicting legacy policy never overwrites restrictive canonical permissions.');
  passed++;

  const linked = fixture('linked');
  fs.unlinkSync(linked.source);
  fs.symlinkSync(linked.backup, linked.source);
  assert.notEqual(linked.migrate().status, 0);
  assert.equal(fs.readFileSync(linked.backup, 'utf8'), linked.contents);
  assert.ok(fs.lstatSync(linked.source).isSymbolicLink());
  console.log('PASS symlinked legacy file is refused and its target is untouched.');
  passed++;

  const newer = fixture('newer-database');
  fs.mkdirSync(path.join(newer.state, 'state'));
  const database = path.join(newer.state, 'state/openclaw.sqlite');
  const db = new DatabaseSync(database);
  db.exec("PRAGMA user_version=999; CREATE TABLE retained(value TEXT); INSERT INTO retained VALUES ('keep')");
  db.close();
  const originalDB = fs.readFileSync(database);
  assert.notEqual(newer.migrate().status, 0);
  assert.deepEqual(fs.readFileSync(database), originalDB);
  assert.equal(fs.readFileSync(newer.source, 'utf8'), newer.contents);
  console.log('PASS newer schema is not downgraded or deleted.');
  passed++;
  console.log(`${passed} real OpenClaw migration checks passed. No live services or user data changed.`);
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
