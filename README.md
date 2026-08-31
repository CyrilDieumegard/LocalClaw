# LocalClaw for macOS

![LocalClaw](https://localclaw.io/images/twitter-card.png)

Native SwiftUI control plane for installing, operating, and automating OpenClaw on Apple Silicon Macs.

<p align="center">
  <img src="https://localclaw.io/images/crab-logo.png" alt="LocalClaw Logo" width="180" />
</p>

## What this repo contains

This repository ships **source code only**.
No DMG or prebuilt binaries are committed here.

## Product surfaces

- Guided first install and in-app updates
- Cloud, OAuth, and LM Studio local runtimes
- Hardware-aware local model advisor with a validated, cached catalog
- OpenClaw Chat with project memory and image attachments
- Developer workspaces, Git/GitHub actions, and local preview
- Channels, agents, cron jobs, and Kanban automation
- Canonical runtime health shared by Home, Models, Help, and Control Center
- Automatic restore points before repairs and updates
- Redacted customer support reports and automation execution receipts

## Quick start

```bash
swift run
```

## Run tests

```bash
swift test
```

## OpenClaw compatibility

LocalClaw 1.0.199 targets OpenClaw 2026.8.1 and retains the 2026.7.1 runtime path.
Update LocalClaw first, then use Updates to upgrade OpenClaw. Before replacing
the runtime, LocalClaw creates and verifies a state backup under
`~/Library/Application Support/LocalClaw/runtime-backups/`. The normal portable
backup excludes project workspaces. If the old runtime cannot read an already
migrated database, LocalClaw stops the identified Gateway, checks for other open
state files, and archives the entire state directory instead (including nested
workspaces, so allow extra disk space). It never deletes or downgrades SQLite.
The offline inventory excludes actual Unix sockets, not files merely named
`.sock`. It preserves file contents, POSIX modes, symbolic links and empty
directories, but does not pack extended attributes, ACLs or AppleDouble metadata.
Source metadata is not changed. A conservative free-space check accounts for
uncompressed input, archive overhead and 2 GiB of update reserve before packing.
The archive is written privately to a temporary file and promoted only after
successful verification. Failed attempts remove only their own incomplete
archives; older backups and source data remain untouched.

Maintenance checks free space before runtime discovery/registry requests, then
checks the offline archive estimate before stopping the Gateway. ENOSPC and
quota failures route to Storage Recovery instead of another generic repair.
The sheet measures free space, the default npm download cache and recovery
backups. With explicit confirmation it can clear only `~/.npm/_cacache`, after
checking ownership, rejecting linked cache roots and checking for open files.
It preserves npm credentials, installed packages, local models, projects and
all existing backups. The cache is disposable download data
([npm cache documentation](https://docs.npmjs.com/cli/v11/commands/npm-cache/)).
Custom cache locations are not automatically cleaned. Additional disk space
may still need to be freed manually; clearing a cache cannot guarantee enough
room for the full archive and update. Retry Repair never resends a chat request.

Updates target the npm package and Node used by the LaunchAgent, including the
new generated environment-wrapper format. An incompatible old CLI is replaced
through a staged, newer updater after backup; the staged updater must first
confirm it targets the original service installation. OpenClaw manages plugin
convergence and restart, and LocalClaw requires a valid configuration, the expected
Gateway version and healthy RPC before reporting success. Quick Repair and Doctor
use the same recovery for schema mismatches and rejected configuration.
Unknown agent-delivery outcomes are not replayed.
Custom/unidentified service layouts or unsafe backups stop with diagnostics.

OpenClaw 2026.8.1 can fail inside Doctor because its generated-approvals repair
accesses the approvals store before importing `exec-approvals.json`. After a
verified offline backup, LocalClaw invokes that release's own transactional
`migrateLegacyExecApprovals` importer before the managed update. Its native
ownership lock, validation, import receipt and read-back checks remain active.
LocalClaw does not write authorization rows itself or relax permissions.
Malformed/conflicting sources remain blocked and preserved. The compatibility
adapter is restricted to 2026.8.1 and refuses an unknown module/export contract.
An already-installed target release does not need another staged updater.
The normal update still owns Doctor, plugin convergence and Gateway activation;
successful import alone is never reported as a healthy Gateway.

Run the real-package regression in isolated temporary homes (no host credentials,
live services, package installation or model calls):

```bash
node scripts/test-openclaw-exec-migration.mjs /path/to/openclaw-2026.8.1-package
```

Chat and Developer now launch the CLI with the service's Node, package, config,
state directory, and port rather than whichever OpenClaw appears first on PATH.
Every request checks Gateway RPC first. A stopped service must pass two health
checks after startup; a start command alone does not count as recovery.
The in-chat Repair Gateway action restores connectivity without resending a
possibly running task. If startup fails, it includes the service diagnostics
and redacted startup errors instead of silently opening Help or retrying.

If an old CLI refuses configuration sections such as `meta`, `agents.defaults`
or `memory`, recovery resolves the release independently of that broken CLI,
backs up state, then uses the newer native updater and its configuration
migrations. LocalClaw does not manually strip configuration keys. It refuses a
release older than the installed runtime or a newer recorded config version.
Historical startup logs cannot override the current failure or trigger a model
retry. Repair failures retain their redacted cause instead of a generic message.

Offline recovery uses structured file-inspection results. A process whose only
reference is a working/root directory no longer blocks the backup. Actual file
handles, including read-only SQLite/WAL handles, remain protected. Blocking
diagnostics identify the process, PID and file; inspection errors are reported
separately rather than claiming another client owns the database. No process is
killed automatically, and a failed inspection still prevents backup and update.

The offline-backup tests perform a native macOS archive/restore with a real Unix
socket, SQLite database, WAL/SHM files, project files, links and extended
attributes. They also cover insufficient space, write/verification failures and
preservation of previous archives. Run them with
`swift test --filter OpenClawOfflineBackupTests`.

This release handles canonical `openai/*` routes, keyed agent ownership, SQLite
credential imports, Goals, and incremental Developer activity. Existing explicit
model policies and selected model suffixes are preserved; authentication alone
does not replace the default model.

Run isolated compatibility checks against an installed npm package:

```bash
node scripts/test-openclaw-compat.mjs /path/to/node_modules/openclaw
node scripts/test-openclaw-turn.mjs /path/to/node_modules/openclaw
node scripts/test-openclaw-turn.mjs /path/to/node_modules/openclaw --gateway
node scripts/test-openclaw-turn.mjs /path/to/node_modules/openclaw --gateway --legacy-config
node scripts/test-openclaw-update-owner.mjs /path/to/new/node_modules/openclaw
node scripts/test-openclaw-update-owner.mjs /path/to/new/node_modules/openclaw --legacy-config
```

The first check supports 2026.7.1 and 2026.8.1. The turn checks target 2026.8.1,
use a deterministic localhost model and temporary HOME, and create a real file
through OpenClaw's write tool. They do not use customer accounts or paid models.
The migration check may resolve official plugins from the network. These checks
do not replace manual validation of provider logins, external channels, or billing.
The update-owner check is a dry-run of the real updater with a test-only OS
account fixture. It checks install targeting, not a live customer migration.
The legacy-config turn check runs the real Doctor with both native service
mutation gates disabled, validates the migrated config, then starts only a
temporary Gateway and verifies a tool turn. It preserves and checks the fixture's
backup, model selection, credentials, tool policy, and existing project file.

## Build a local DMG

```bash
bash scripts/build-dmg.sh
```

Build artifacts are generated in `dist/` and ignored by git.

## Signing, notarization, and publishing

Local development builds stay ad-hoc signed by default:

```bash
bash scripts/build-dmg.sh
```

Public releases must use Developer ID signing, notarization, and stapling:

```bash
RELEASE_NOTARIZE=1 bash scripts/build-dmg.sh
bash scripts/publish-notarized-dmg.sh
```

Release defaults:

- `DEVELOPER_ID_APP`
- `NOTARY_PROFILE=localclaw-notary`
- `NOTARY_TIMEOUT_SECONDS=900`
- `NOTARY_POLL_SECONDS=15`

The notary profile must be created once in Keychain:

```bash
xcrun notarytool store-credentials "localclaw-notary" \
  --apple-id "<apple-id>" \
  --team-id "<team-id>" \
  --password "<app-specific-password>"
```

`publish-notarized-dmg.sh` validates the stapled DMG first, then calculates the manifest sha256 from that final stapled file.

## License API endpoint

Default endpoint:

`https://localclaw.io/api/license/activate`

Override for another backend:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="https://your-domain/api/license/activate"
swift run
```

## Local license mock server

```bash
node scripts/mock-license-server.js
```

In another terminal:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="http://127.0.0.1:8787/api/license/activate"
swift run
```

Mock credentials:
- Email: `cyril@test.local`
- License: `LOCALCLAW-V1-TEST`

## Project structure

- `Sources/LocalClawInstallerApp.swift` primary app state and product views
- `Sources/RuntimeState.swift` canonical OpenClaw runtime snapshot
- `Sources/RecoveryService.swift` private restore points and redacted reports
- `Sources/AutomationReceipt.swift` persisted automation outcomes
- `Sources/LocalModelCatalogService.swift` validated remote model catalog with offline cache
- `Tests/` test suite
- `scripts/` build, checks, local mock tools
- `release-bundle/` release handoff docs and integration notes

## Customer-safe change policy

Before publishing a release, prove both paths:

1. A new customer downloads the public DMG, activates, installs, and sends one request.
2. An existing customer updates from the currently published version using LocalClaw's Updates screen.

Run the full release matrix in `RELEASE_CHECKLIST.md`. A successful repository build alone is not release proof.

## Philosophy

- GitHub repo: transparent source and DIY setup
- Paid installer distribution: convenience, packaging, support
- Stability and recoverability take priority over adding new sections
