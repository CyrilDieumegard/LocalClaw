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
