// OpenClaw 2026.8.1 calls the approvals store before its Doctor import runs.
// Invoke that release's own transactional migration first, never rewrite its DB here.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

try {
  const [packageArgument, stateArgument] = process.argv.slice(2);
  if (!packageArgument || !stateArgument) throw new Error('Package and state paths are required.');
  const packageRoot = fs.realpathSync(packageArgument);
  const stateDir = fs.realpathSync(stateArgument);
  if (fs.realpathSync(process.env.OPENCLAW_STATE_DIR) !== stateDir) {
    throw new Error('The migration state directory does not match the Gateway.');
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(packageRoot, 'package.json'), 'utf8'));
  if (manifest.name !== 'openclaw' || manifest.version !== '2026.8.1') {
    throw new Error('This migration adapter only supports the verified OpenClaw 2026.8.1 release.');
  }
  const dist = fs.realpathSync(path.join(packageRoot, 'dist'));
  if (path.dirname(dist) !== packageRoot) throw new Error('Unexpected OpenClaw module location.');
  const candidates = fs.readdirSync(dist).filter(name => /^state-migrations\.exec-approvals-[\w-]+\.js$/.test(name));
  if (candidates.length !== 1) throw new Error('Cannot identify the official approvals migration unambiguously.');
  const modulePath = path.join(dist, candidates[0]);
  if (fs.realpathSync(modulePath) !== modulePath) throw new Error('The migration module must not be a symlink.');
  const module = await import(pathToFileURL(modulePath).href);
  const exportedFunction = name => {
    const matches = Object.values(module).filter(value => typeof value === 'function' && value.name === name);
    if (matches.length !== 1) throw new Error(`The official migration contract changed: ${name}.`);
    return matches[0];
  };
  const detect = exportedFunction('detectLegacyExecApprovals');
  const migrate = exportedFunction('migrateLegacyExecApprovals');
  const detection = { stateDir, doctorOnlyStateMigrations: true };
  const result = await migrate({ stateDir, env: process.env, detected: detect(detection) });
  if (!Array.isArray(result.warnings) || !Array.isArray(result.changes)) {
    throw new Error('OpenClaw returned an unrecognized migration result.');
  }
  if (result.warnings.length || detect(detection).hasLegacy) {
    throw new Error(`Approvals migration did not finish. Existing authorization policy was not reset. ${result.warnings.join('\n')}`);
  }
  console.log(JSON.stringify({ ok: true, version: manifest.version, stateDir, changes: result.changes }));
} catch (error) {
  console.error(JSON.stringify({ ok: false, error: error.message }));
  process.exitCode = 1;
}
