# LocalClaw macOS Installer

Native macOS installer app (SwiftUI) to set up LM Studio + OpenClaw on Apple Silicon with minimal friction.

## Why this repo exists

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

## Run locally

```bash
cd localclaw-mac-installer
swift run
```

## Run tests

```bash
cd localclaw-mac-installer
swift test
```

## Build release DMG (local)

```bash
cd localclaw-mac-installer
bash scripts/build-dmg.sh
```

Build artifacts are generated in `dist/` and are ignored by git.

## Signing and notarization

`build-dmg.sh` supports Apple signing/notarization through env vars:

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

Without these variables, the build runs in dev mode (ad-hoc signing).

## License API endpoint

Default endpoint:

`https://localclaw.io/api/license/activate`

Override for another backend:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="https://your-domain/api/license/activate"
swift run
```

## Local test server for licensing

```bash
cd localclaw-mac-installer
node scripts/mock-license-server.js
```

In another terminal:

```bash
cd localclaw-mac-installer
export LOCALCLAW_LICENSE_ENDPOINT="http://127.0.0.1:8787/api/license/activate"
swift run
```

Mock test credentials:
- Email: `cyril@test.local`
- License: `LOCALCLAW-V1-TEST`
