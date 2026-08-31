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

LocalClaw 1.0.194 targets OpenClaw 2026.8.1 and retains the 2026.7.1 runtime path.
Update LocalClaw first, then use Updates to upgrade OpenClaw. Before replacing
the runtime, LocalClaw creates and verifies a state backup under
`~/Library/Application Support/LocalClaw/runtime-backups/`. The normal portable
backup excludes project workspaces. If the old runtime cannot read an already
migrated database, LocalClaw stops the identified Gateway, checks for other open
state files, and archives the entire state directory instead (including nested
workspaces, so allow extra disk space). It never deletes or downgrades SQLite.

Updates target the npm package and Node used by the LaunchAgent, including the
new generated environment-wrapper format. An incompatible old CLI is replaced
through a staged, newer updater after backup; the staged updater must first
confirm it targets the original service installation. OpenClaw manages plugin
convergence and restart, and LocalClaw requires the expected Gateway version
and healthy RPC before reporting success. Quick Repair uses the same recovery
for schema mismatches. Unknown agent-delivery outcomes are not replayed.
Custom/unidentified service layouts or unsafe backups stop with diagnostics.

Chat and Developer now launch the CLI with the service's Node, package, config,
state directory, and port rather than whichever OpenClaw appears first on PATH.
Every request checks Gateway RPC first. A stopped service must pass two health
checks after startup; a start command alone does not count as recovery.
The in-chat Repair Gateway action restores connectivity without resending a
possibly running task. If startup fails, it includes the service diagnostics
and redacted startup errors instead of silently opening Help or retrying.

This release handles canonical `openai/*` routes, keyed agent ownership, SQLite
credential imports, Goals, and incremental Developer activity. Existing explicit
model policies and selected model suffixes are preserved; authentication alone
does not replace the default model.

Run isolated compatibility checks against an installed npm package:

```bash
node scripts/test-openclaw-compat.mjs /path/to/node_modules/openclaw
node scripts/test-openclaw-turn.mjs /path/to/node_modules/openclaw
node scripts/test-openclaw-turn.mjs /path/to/node_modules/openclaw --gateway
node scripts/test-openclaw-update-owner.mjs /path/to/new/node_modules/openclaw
```

The first check supports 2026.7.1 and 2026.8.1. The turn checks target 2026.8.1,
use a deterministic localhost model and temporary HOME, and create a real file
through OpenClaw's write tool. They do not use customer accounts or paid models.
The migration check may resolve official plugins from the network. These checks
do not replace manual validation of provider logins, external channels, or billing.
The update-owner check is a dry-run of the real updater with a test-only OS
account fixture. It checks install targeting, not a live customer migration.

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
