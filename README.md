# LocalClaw macOS Installer

![LocalClaw](https://localclaw.io/images/twitter-card.png)

Native macOS installer app (SwiftUI) to set up LM Studio + OpenClaw on Apple Silicon, fast and clean.

<p align="center">
  <img src="https://localclaw.io/images/crab-logo.png" alt="LocalClaw Logo" width="180" />
</p>

## What this repo contains

This repository ships **source code only**.
No DMG or prebuilt binaries are committed here.

## Features

- Hardware detection (chip + RAM)
- Local model recommendation
- License activation flow (email + key)
- Guided setup for:
  - Homebrew
  - LM Studio
  - Node.js
  - OpenClaw
- Post-install health checks
- Real-time install logs

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

## Signing and notarization

`build-dmg.sh` supports Apple signing and notarization through env vars:

- `DEVELOPER_ID_APP`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Example:

```bash
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

bash scripts/build-dmg.sh
```

Without these variables, build runs in dev mode (ad-hoc signing).

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

- `Sources/` SwiftUI app and installer logic
- `Tests/` test suite
- `scripts/` build, checks, local mock tools
- `release-bundle/` release handoff docs and integration notes

## Philosophy

- GitHub repo: transparent source and DIY setup
- Paid installer distribution: convenience, packaging, support
