# LocalClaw Release Checklist

## Build gate

- [ ] `swift test` passes
- [ ] `swift build -c release` passes
- [ ] `bash scripts/release-check.sh` passes
- [ ] Version and build are aligned across the app, manifest, and website

## Runtime matrix

- [ ] Cloud route sends a short OpenClaw Chat request
- [ ] OAuth route lists the authenticated models and sends a request
- [ ] Local route downloads or selects a recommended model, loads it in LM Studio, and sends a request
- [ ] Home, Models, Help, and Control Center report the same route, model, auth, and Gateway status
- [ ] Chat and Developer keep separate drafts, images, and sessions

## Customer flows

- [ ] New customer: buy, download public DMG, activate, install, and send a first request
- [ ] Existing customer: click Update, install the new app, relaunch, and keep activation/configuration
- [ ] Recovery point exists before update or repair
- [ ] Restore Latest successfully restores a test configuration
- [ ] Support report contains diagnostics and no token, API key, or credential

## Automation and channels

- [ ] Connected channel receives a test message
- [ ] Cron Run creates a successful receipt with the correct agent, model, and destination
- [ ] Kanban Run creates a receipt and moves the card to Review
- [ ] A failed automation produces a visible failed receipt with a useful redacted error

## Signing and distribution

- [ ] App bundle is signed with Developer ID and hardened runtime
- [ ] DMG is signed, notarized, and stapled
- [ ] `xcrun stapler validate` and Gatekeeper checks pass
- [ ] Manifest SHA-256 is calculated from the final stapled DMG
- [ ] Public DMG and manifest return HTTP 200
- [ ] Remote model catalog returns valid schema v1 JSON

## Go or no-go

- [ ] No P0 or P1 customer-flow bug remains
- [ ] Public rollback DMG and previous manifest are retained
- [ ] Changelog and support notes are ready
