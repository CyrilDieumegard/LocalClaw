import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

assert.ok(process.argv[2], 'Pass a packaged LocalClaw.app. Optional: a real diagnostic file.');
const root = fs.mkdtempSync('/private/tmp/localclaw-packaged-update-');
const app = path.join(root, 'Applications/LocalClaw.app');
const q = JSON.stringify;
try {
  const copy = spawnSync('/usr/bin/ditto', ['--noextattr', '--noacl', fs.realpathSync(process.argv[2]), app], { encoding: 'utf8' });
  assert.equal(copy.status, 0, copy.stderr);
  const warning = {
    status: 'ok', mode: 'npm', root: '/fixture/openclaw', steps: [{ name: 'doctor', exitCode: 0 }],
    postUpdate: { plugins: { status: 'warning', npm: { outcomes: [
      { pluginId: 'codex', status: 'error', code: 'PLUGIN_CAPABILITY_CONSENT_REQUIRED' },
    ] } } },
  };
  const fixtures = [
    ['doctor-example', `Doctor: '["telegram:123456789"]'\n${JSON.stringify(warning)}`, 0, 'ok', true],
    ['finalization', JSON.stringify({ status: 'ok', mode: 'finalize', root: '/fixture/openclaw',
      restart: false, phaseTimings: [], postUpdate: { plugins: { status: 'ok' } } }), 0, 'ok', false],
    ['failed-update', JSON.stringify({ status: 'error', mode: 'npm', root: '/fixture/openclaw', steps: [] }), 0, 'error', false],
    ['unrecognized', '["telegram:123456789"]\n{"status":"ok"}', 1, undefined, undefined],
  ];
  if (process.argv[3]) fixtures.push(['customer-diagnostic', fs.readFileSync(process.argv[3], 'utf8'), 0, 'ok', true]);
  for (const [name, text, exitCode, updateStatus, needsApproval] of fixtures) {
    const file = path.join(root, `${name}.txt`);
    fs.writeFileSync(file, text, { mode: 0o600 });
    const policy = `(version 1)(allow default)(deny network*)(deny file-read* (subpath ${q(os.homedir())}))(deny file-write* (require-not (subpath ${q(root)})))`;
    const result = spawnSync('/usr/bin/sandbox-exec', ['-p', policy,
      path.join(app, 'Contents/MacOS/LocalClaw'), '--check-update-output', file],
    { cwd: root, env: { HOME: root, CFFIXED_USER_HOME: root, TMPDIR: root, PATH: '/usr/bin:/bin' },
      encoding: 'utf8', timeout: 15000 });
    assert.equal(result.status, exitCode, `${name}: ${result.stderr}\n${result.stdout}`);
    const output = JSON.parse(result.stdout);
    assert.equal(output.gatewayVerified, false, 'Parsing a log is not a live Gateway health check');
    if (exitCode === 0) {
      assert.equal(output.updateStatus, updateStatus);
      assert.equal(output.needsPluginApproval, needsApproval);
    } else assert.equal(output.ok, false);
    assert.equal(fs.existsSync(path.join(root, '.openclaw')), false);
    console.log(`PASS ${name}: packaged parser, no service or user-data access.`);
  }
} finally { fs.rmSync(root, { recursive: true, force: true }); }
