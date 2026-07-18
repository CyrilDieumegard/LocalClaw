# Roadmap

## Current focus: stability

- [x] Developer ID signing, Apple notarization, and stapling
- [x] License activation bound to a Mac
- [x] Public DMG manifest with post-stapling SHA-256
- [x] In-app update path for existing customers
- [x] Canonical runtime health across product sections
- [x] Private restore points before repair and update operations
- [x] Redacted support bundle export
- [x] Persistent Cron and Kanban execution receipts
- [x] Hardware-aware local model ranking
- [x] Validated remote model catalog with an offline fallback
- [ ] Prove the complete new-customer matrix on a clean Apple Silicon Mac
- [ ] Prove the complete existing-customer update matrix from the oldest supported build
- [ ] Finish keyboard and VoiceOver checks on every primary workflow
- [ ] Add privacy-safe crash reporting only if customer support data justifies it

## Product rule

No new major section is planned until activation, installation, updates, all three runtime routes, channels, and automations pass the release matrix consistently.
