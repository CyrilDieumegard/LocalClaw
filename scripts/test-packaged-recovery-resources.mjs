import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

assert.ok(process.argv[2], 'Pass the built or downloaded LocalClaw.app directory.');
const source = fs.realpathSync(process.argv[2]);
assert.equal(path.extname(source), '.app');
const root = fs.realpathSync(fs.mkdtempSync('/private/tmp/localclaw-packaged-resources-'));
const bundle = 'localclaw-mac-installer_localclaw-mac-installer.bundle';
const script = 'exec-approvals-migration.mjs';
const hostHome = fs.realpathSync(os.homedir());
const profile = `(version 1)
  (allow default)
  (deny network*)
  (deny file-read* (subpath (param "HOST_HOME")))
  (deny file-write* (require-not (subpath (param "FIXTURE"))))`;
let passed = 0;

try {
  for (const damage of ['none', 'missing-bundle', 'missing-script', 'empty', 'directory', 'external-symlink']) {
    const home = path.join(root, damage);
    const app = path.join(home, 'Applications', 'LocalClaw.app');
    fs.mkdirSync(home, { recursive: true });
    const copy = spawnSync('/usr/bin/ditto', ['--noextattr', '--noacl', source, app], { encoding: 'utf8' });
    assert.equal(copy.status, 0, copy.stderr);
    const resource = path.join(app, 'Contents', 'Resources', bundle, script);
    // An adjacent development-style resource must not hide a damaged customer app.
    const decoy = path.join(home, 'Applications', bundle, script);
    fs.mkdirSync(path.dirname(decoy), { recursive: true });
    fs.writeFileSync(decoy, 'throw new Error("external resource must never execute");');
    if (damage === 'missing-bundle') fs.rmSync(path.dirname(resource), { recursive: true });
    if (damage === 'missing-script') fs.unlinkSync(resource);
    if (damage === 'empty') fs.writeFileSync(resource, '');
    if (damage === 'directory' || damage === 'external-symlink') {
      fs.unlinkSync(resource);
      if (damage === 'directory') fs.mkdirSync(resource);
      else fs.symlinkSync(decoy, resource);
    }
    if (damage !== 'none') {
      const clean = spawnSync('/usr/bin/xattr', ['-cr', app], { encoding: 'utf8' });
      assert.equal(clean.status, 0, clean.stderr);
      const sign = spawnSync('/usr/bin/codesign', ['--force', '--sign', '-', app], { encoding: 'utf8' });
      assert.equal(sign.status, 0, sign.stderr);
    }
    const result = spawnSync('/usr/bin/sandbox-exec', [
      '-D', `HOST_HOME=${hostHome}`, '-D', `FIXTURE=${root}`, '-p', profile,
      path.join(app, 'Contents', 'MacOS', 'LocalClaw'), '--check-recovery-resources',
    ], {
      cwd: home, env: { HOME: home, CFFIXED_USER_HOME: home, TMPDIR: home, PATH: '/usr/bin:/bin' },
      encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024,
    });
    assert.equal(result.error, undefined, result.error?.message);
    assert.equal(result.signal, null, `${damage}: unexpected crash ${result.signal}\n${result.stderr}`);
    assert.equal(result.status, damage === 'none' ? 0 : 1, `${damage}: ${result.stdout}\n${result.stderr}`);
    const report = JSON.parse(result.stdout);
    assert.equal(report.ok, damage === 'none');
    if (damage === 'none') {
      assert.equal(report.resource, resource);
      assert.match(report.version, /^\d+\.\d+\.\d+$/);
    } else {
      assert.match(report.error, /LocalClaw repair resource/);
      assert.match(report.error, /No recovery backup or OpenClaw update was started/);
    }
    assert.ok(!fs.existsSync(path.join(home, '.openclaw')));
    console.log(`PASS ${damage}: isolated packaged app, exit ${result.status}, no crash`);
    passed++;
  }
  console.log(`${passed} packaged resource checks passed with host-home reads and network access denied.`);
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
