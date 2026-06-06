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

## Try an OpenClaw workflow after setup

After LocalClaw reports OpenClaw ready, you can install regular OpenClaw plugins from Terminal. [TweetClaw](https://github.com/Xquik-dev/tweetclaw) is a practical X/Twitter workflow check because it exercises plugin install, optional tool allowlisting, local config, and approval prompts:

```bash
openclaw plugins install @xquik/tweetclaw
openclaw config set tools.alsoAllow '["explore", "tweetclaw"]'
```

TweetClaw supports scrape tweets, search tweets, search tweet replies, follower export, user lookup, media upload, media download, direct messages, monitor tweets, webhooks, giveaway draws, and approval-gated post tweets or post tweet replies through Xquik.

- GitHub: https://github.com/Xquik-dev/tweetclaw
- npm: https://www.npmjs.com/package/@xquik/tweetclaw
- ClawHub browsing page: https://clawhub.ai/plugins/@xquik/tweetclaw

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

- `Sources/` SwiftUI app and installer logic
- `Tests/` test suite
- `scripts/` build, checks, local mock tools
- `release-bundle/` release handoff docs and integration notes

## Philosophy

- GitHub repo: transparent source and DIY setup
- Paid installer distribution: convenience, packaging, support
