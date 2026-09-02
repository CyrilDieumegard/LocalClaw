import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

assert.ok(process.argv[2], 'Pass the unpacked OpenClaw package directory.');
const pkg = fs.realpathSync(process.argv[2]);
const original = fs.readFileSync(path.join(pkg, 'package.json'));
const version = JSON.parse(original).version;
assert.match(version, /^\d{4}\.\d+\.\d+$/);
const parts = version.split('.').map(Number);
assert.ok(parts[0] > 2026 || (parts[0] === 2026 && (parts[1] > 8 || (parts[1] === 8 && parts[2] >= 1))),
  `Post-update fixture must be OpenClaw >= 2026.8.1, got ${version}`);
const root = fs.mkdtempSync('/private/tmp/localclaw-post-update-');
const state = path.join(root, '.openclaw');
const label = 'io.localclaw.post-update-fixture';
const quote = value => JSON.stringify(value);
const hash = createHash('sha256').update(path.join(state, 'state/openclaw.sqlite')).digest('hex').slice(0, 8);
const locks = `/private/tmp/openclaw-state-locks-${process.getuid()}`;

try {
  fs.mkdirSync(state);
  fs.writeFileSync(path.join(state, 'openclaw.json'), JSON.stringify({
    gateway: { mode: 'remote', remote: { url: 'ws://127.0.0.1:65530', token: 'fixture-only' } },
    plugins: { enabled: false },
  }));
  const env = {
    HOME: root, OPENCLAW_HOME: root, TMPDIR: root, SQLITE_TMPDIR: root,
    XDG_CACHE_HOME: path.join(root, '.cache'),
    PATH: `${path.dirname(process.execPath)}:/usr/bin:/bin:/usr/sbin:/sbin`,
    OPENCLAW_STATE_DIR: state, OPENCLAW_CONFIG_PATH: path.join(state, 'openclaw.json'),
    OPENCLAW_SERVICE_REPAIR_POLICY: 'external', OPENCLAW_LAUNCHD_LABEL: label,
    OPENCLAW_NO_RESPAWN: '1', NO_COLOR: '1',
  };
  // Native 8.1 keeps cross-process coordinator locks in /tmp, not TMPDIR.
  // Permit only the hash for this disposable database, never another state's lock.
  const allowedLock = `^${locks}/[a-z-]+[.]${hash}[.]lock[.]sqlite(-wal|-shm|-journal)?$`;
  const policy = `(version 1)(allow default)(deny network*)(deny file-read* (subpath ${quote(os.homedir())}))(deny file-write* (require-not (require-any (subpath ${quote(root)}) (literal ${quote(locks)}) (regex ${quote(allowedLock)}))))`;
  for (let attempt = 1; attempt <= 2; attempt++) {
    const result = spawnSync('/usr/bin/sandbox-exec', ['-p', policy, process.execPath,
      path.join(pkg, 'openclaw.mjs'), 'update', 'repair', '--yes', '--json', '--timeout', '30'],
    { env, cwd: root, encoding: 'utf8', timeout: 90000, maxBuffer: 8 * 1024 * 1024 });
    assert.equal(result.status, 0, `${result.error?.message ?? ''}\n${result.stdout}\n${result.stderr}`);
    const output = JSON.parse(result.stdout);
    assert.equal(output.mode, 'finalize');
    assert.equal(output.status, 'ok');
    assert.equal(output.root, pkg);
    assert.equal(output.restart, false);
    assert.equal(output.postUpdate.doctor.status, 'ok');
    assert.equal(output.postUpdate.plugins.status, 'ok');
    assert.ok(output.phaseTimings.some(phase => phase.phase === 'doctor' && phase.outcome === 'completed'));
    assert.equal(fs.existsSync(path.join(root, 'Library/LaunchAgents/ai.openclaw.gateway.plist')), false);
    assert.deepEqual(fs.readFileSync(path.join(pkg, 'package.json')), original);
    console.log(`PASS native OpenClaw ${version} update repair ${attempt}: finalization JSON, Doctor, plugins, no core replacement or service restart.`);
  }
  console.log('Network and host home access denied. Isolated state only; no providers or customer services used.');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
  for (const family of ['state-lifecycle', 'gateway-lifecycle']) {
    for (const suffix of ['', '-wal', '-shm', '-journal']) {
      fs.rmSync(path.join(locks, `${family}.${hash}.lock.sqlite${suffix}`), { force: true });
    }
  }
}
