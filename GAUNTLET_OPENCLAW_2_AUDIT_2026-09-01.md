# Gauntlet ledger — OpenClaw 2.0 total audit

Date: 2026-09-01 (Europe/Zurich)

## Contract

- Goal: make LocalClaw reliably install, update, diagnose, and repair fresh or existing OpenClaw 2.0 setups while keeping Goal, Kanban, models, accounts, projects, credentials, and user data safe.
- Inspection surface: the SwiftPM macOS app, bundled JavaScript/shell recovery resources, fresh-setup and maintenance flows, release scripts, updater manifest, and executable test suites.
- Upstream target: official stable OpenClaw `2026.8.1` (the current release behind “OpenClaw 2.0” during this audit).
- Hard constraints: no mutation of the user's live OpenClaw installation, services, accounts, Gmail/channel connections, projects, data, or licence; no production publish; no customer contact; no paid provider calls.
- Quality bar: authoritative isolated Swift tests and release build, real OpenClaw 2026.8.1 CLI/Gateway fixtures, failure/rollback tests, source-backed Goal/Workboard compatibility review, and explicit release vetoes.

## Reproducible baseline

- Repository: branch `main`, base `a7a355057f5535bb93e78d544a3a397bd42dd3b4` (equal to `origin/main` when inspected), plus the uncommitted audit changes listed by `git status`.
- Release candidate source version: `1.0.202`; the intended monotonic release build is `353`.
- User's observed OpenClaw version: `2026.7.1-2`; it was inspected but not changed.
- Isolated upstream fixture: `/private/tmp/localclaw-openclaw2-audit.6WFzkB/openclaw-2026.8.1`.
- Authoritative Swift scratch paths:
  - debug/tests: `/private/tmp/localclaw-openclaw2-final-build`
  - release build: `/private/tmp/localclaw-openclaw2-final-release`
- Known noise: SwiftPM shared build directories can race. Final Swift gates use an isolated scratch path and `-j 1`.
- Safety note: one early OpenClaw help invocation was run before the isolated environment was applied. Its attempted migration/hardening writes were denied with `EPERM`; follow-up inspection found no live-state write. Every stateful compatibility test after that used a temporary HOME/state/config.

## Upstream contract proved

- Official release: <https://github.com/openclaw/openclaw/releases/tag/v2026.8.1>
- Native Goal: <https://docs.openclaw.ai/tools/goal>
  - one durable Goal per session;
  - native `get_goal`, `create_goal`, and `update_goal` lifecycle;
  - `blocked` only after the same condition recurs for three consecutive turns.
- Native Workboard: <https://docs.openclaw.ai/cli/workboard>
  - separate bundled plugin and SQLite store;
  - LocalClaw Board/Kanban must not claim to be or overwrite native Workboard.
- Multiple Gateways: <https://docs.openclaw.ai/gateway/multiple-gateways>
  - each profile needs its own state, config, workspace, port, and service identity.
- Current Qwen 3.8 model references:
  - <https://lmstudio.ai/models/qwen/qwen3.8-27b>
  - <https://openrouter.ai/qwen/qwen3.8-flash>
  - <https://openrouter.ai/qwen/qwen3.8-27b>
  - <https://openrouter.ai/qwen/qwen3.8-max>

## Concern map

| Concern | Result | Proven boundary | Residual |
|---|---|---|---|
| OpenClaw 2.0 runtime selection | PASS in code/fixtures | exact executable, package, state, config, profile, service label, and port are propagated; ambiguous/mismatched profiles fail closed | no physical multi-user Mac lab run |
| Existing-user update and repair | PASS in isolated OpenClaw + transactional fixtures | backup-first migration, stable-target guard, legacy approval import, config repair, resumable checkpoint, rollback/service compensation, two idempotent repair runs, and exact-profile shared-core repair without replacing the core | no mutation of a real customer's runtime by design |
| Fresh install | PASS in code/fixtures | LM Studio install, model download/load, >=16K context, `/v1/models` readiness, safe config/token/dashboard, port collision checks; current public 1.0.201 DMG passes Apple signature/notarization checks | no clean physical Mac installation or real multi-GB model download was performed |
| Native Goal conflict | PASS with architectural residuals | LocalClaw plan is bound to native Goal ID/agent/session/state/workspace/revision; atomic receipts make lost-response retry durable; stale revisions fail; three-turn blocker rule and bounded auto-runs enforced | private hashed OpenClaw chunks are used because no public atomic Goal CLI exists; a model may call native Goal tools before LocalClaw detects it; final semantic evidence is not independently provable in every task |
| Kanban / Cron | PASS in code/fixtures | LocalClaw Board is named separately from Workboard; official Cron add/edit/remove, exact declarations, profile namespace, per-job in-flight lock, timeout/UNKNOWN reconciliation, one-shot receipt guard | no claim that LocalClaw Board is native Workboard; customer delivery outcome still needs runtime evidence |
| Models | PASS for verified built-ins/fallbacks | Qwen 3.8 27B added for high-memory Macs; Qwen 3.8 cloud fallbacks added; lower-RAM models retained; remote catalogue cannot hide the verified Latest built-in | remote HTTPS catalogue is validated for syntax but is not cryptographically signed/pinned |
| App updater | PASS in code/tests | 1 GiB cap, streaming SHA-256, signature verification off main actor, invalid temp cleanup, verified DMG opened for manual install | intentionally does not silently replace a running app |
| Release pipeline | PASS in code/fixtures; new release still gated | same validated snapshot is signed/stapled/app-checked/hashed/published; local and public version/build monotonicity; cache-busted public-manifest preflight; independent HEAD and one-byte-bounded GET must both return 404; versioned no-clobber; manifest committed last | the candidate is not yet contained in the valid public 1.0.201 DMG |
| Licence | PASS for legacy compatibility, local cryptography and hidden production backend | historical `/success` and `/api/license/activate` remain isolated for 1.0.201; v2 requires a Stripe-signature-verified paid session, stores only hashes in D1 and issues an Ed25519 receipt bound to app/email/key/machine | no paid end-to-end purchase was made; refunds/disputes require manual revocation; the secure CTA remains gated until the signed 1.0.202 DMG is public |

## Implemented changes

### Runtime, installation, update, and recovery

- Bound all OpenClaw commands to the selected runtime/profile/state/config/port instead of ambient Homebrew/PATH state.
- Refused ambiguous multiple Gateways, unsafe shared npm-runtime updates, invalid profile names, mismatched state/config, and occupied ports.
- Canonicalized `/var` and `/private/var` even when the selected `.openclaw` suffix does not exist yet, fixing missing-service repair on macOS.
- Moved blocking LM Studio/model/install probes off the main actor and required a loaded model with at least 16K context before fresh setup can report ready.
- Added backup integrity receipts, archive SHA verification, resumable checkpoints, same-runtime namespacing, post-failure service compensation, and recovery staging that never deletes an untouched live app.
- Restricted automatic updates to stable OpenClaw releases at or above `2026.8.1`; beta/downgrade/newer-config mismatches fail closed.
- Preserved legacy execution policies through the official OpenClaw migration instead of resetting permissions.
- Added a narrow repair path for an existing shared core only when the selected runtime/profile is exact and already at the current version; it backs up first, repairs only the selected service/config, proves the final state, and still blocks upgrades, overlaps, ambiguity, and unscoped mutation.

### Goal and Kanban

- Kept LocalClaw's plan UX while making native OpenClaw Goal the durable authority for identity, lifecycle, revision, status, and retry receipts.
- Added strict compare-and-swap behavior: exact operation receipts may replay safely; coincident state without the receipt cannot bypass a stale revision.
- Bound every work turn to the selected agent and stable Goal session; rejected premature native complete/blocked states and completion without evidence.
- Limited automatic Goal continuation to 20 turns and implemented the official same-blocker three-turn rule.
- Required local artifacts to stay inside approved workspaces and verified final files exist and are non-empty.
- Separated “LocalClaw Board” from OpenClaw Workboard and made Cron mutations bounded and reconciliable after uncertain outcomes.
- Prevented missing one-shot Cron jobs from being marked Done without a LocalClaw execution receipt or OpenClaw run-history verification.
- Made manual Cron and Kanban executions return an explicit `UNKNOWN` receipt on timeout, never retry automatically, and leave the card in progress until inventory/history reconciles the outcome.
- Added an atomic per-job Cron run lock before receipt creation, guaranteed release on every completion path, and a disabled `Running...` UI state so double-clicks cannot start duplicate manual runs.

### Models, updater, licence handoff, and release

- Added verified Qwen 3.8 27B local metadata and Qwen 3.8 Flash/27B/Max cloud fallbacks; preserved smaller Qwen 3.5 options for constrained Macs.
- Validated catalogue query/provider identifiers before shell use and shell-quoted LM Studio downloads.
- Removed the unsafe/dead Git updater path; the surviving DMG updater hashes streams, caps file size, verifies signatures, and opens the verified DMG manually.
- Removed the hardcoded plaintext customer licence override. Existing same-Mac cached licences remain grandfathered and are never rewritten or revoked during migration.
- Added a versioned `/api/license/v2/activate` contract with strict Ed25519 JWS verification in the app, receipt/key/email/machine/app binding, a three-machine cap, 180-day refresh receipts and a 14-day signed-receipt network grace period.
- Deployed the hidden Stripe-signature-verified claim backend and separate `/license-success` page without changing the five public purchase CTAs or the historical `/success` flow. The D1 migration is additive, Time Travel was confirmed, all five new tables are empty after synthetic rejection probes, and the public signing key matches the app trust root.
- Release checks now execute the real OpenClaw compatibility, migration, Gateway-turn, post-update, ownership, Goal-contract, Swift-test, and signed/notarized-build gates rather than allowing fixture omission.
- Release scripts now require a positive monotonic build, inspect the packaged app inside the DMG, freeze one snapshot before validation, compare against the cache-busted public manifest, require independent cache-busted HEAD and strictly one-byte-bounded GET probes to both return exact public `404` for the future immutable URL, publish versioned artifacts atomically, and write the update manifest last.
- The bounded GET probe forces HTTP/1.1 because macOS curl 8.7 maps an HTTP/2 `--max-filesize` stop to transport exit 56 instead of the documented size-limit exit 63 even when GitHub returned an exact 404; the byte ceiling and exact-status requirement remain enforced.
- Handoff manifest/checksum files are fail-safe templates rather than stale release claims.

## Executable evidence

### Swift app

- `swift test -j 1`
  - PASS: `276 tests in 13 suites`, zero issue.
- `swift build -c release --scratch-path /private/tmp/localclaw-openclaw2-release-candidate-20260901 -j 1`
  - PASS: optimized executable linked, `Build complete! (124.59s)`.
- Focused runtime/profile repair after the macOS path-alias fix:
  - PASS: `77 tests in 3 suites`, including seven new shared-core repair scenarios plus `GatewayConnectionRecoveryTests` and `OpenClawRuntimeMaintenanceTests`.

### Real OpenClaw 2026.8.1 isolated fixture

- `node scripts/test-openclaw-compat.mjs <fixture>`
  - PASS: CLI agent/models/Gateway/Cron/channels/agents/plugins/sessions, configuration schema, native named-agent Goal lifecycle, verified backup, SQLite credential import, privacy-filtered activity, and legacy Doctor migration.
- `node scripts/test-openclaw-exec-migration.mjs <fixture>`
  - PASS: 8 migration cases, including idempotence, resume, invalid input preservation, restrictive conflict handling, symlink refusal, and no schema downgrade.
- `node scripts/test-openclaw-turn.mjs <fixture> --gateway --legacy-config`
  - PASS: real config migration and real Gateway turn using a fake local model, streamed write tool, on-disk artifact, and final reply.
- `node scripts/test-openclaw-post-update.mjs <fixture>`
  - PASS: two native post-update repair runs, no core replacement or service restart.
- `node scripts/test-openclaw-update-owner.mjs <fixture> --legacy-config`
  - PASS: selected `.local` runtime ownership and schema 15 in dry-run; no package/service/provider mutation.
- `node scripts/test-goal-controller-contract.mjs`
  - PASS: atomic Goal revision guard and durable lost-response replay.

### Release-script fixture and static gates

- Isolated publish fixture: PASS for source mutation after snapshot, exact snapshot SHA, build/version regressions, public manifest newer than local state, existing public versioned targets, HEAD/GET disagreement, bounded 404 response bodies, public-network failure, injected publication race, distinct cache-busted probes, canonical manifest URL, manifest placement, and manifest-last ordering.
- `bash -n scripts/build-dmg.sh scripts/publish-notarized-dmg.sh scripts/release-check.sh`: PASS.
- `node --check release-bundle/site-handoff/server-example-node.js`: PASS.
- `python3 -m json.tool release-bundle/site-handoff/localclaw-installer-latest.json`: PASS.
- `git diff --check`: PASS.

## Production artifact inspection

- Public manifest observed: LocalClaw `1.0.201`, build `352`, SHA-256 `ef62948313230cba448728fe1dd7fe14ac415ee6a19f717f781a004da2a63286`.
- The downloaded public DMG matched that SHA exactly.
- Final separated recheck: `codesign` accepted the DMG, mounted `LocalClaw.app`, and its executable; `xcrun stapler validate` passed; `spctl` accepted both DMG and app as `Notarized Developer ID`, team `923MBLC4X4`.
- Consequence: the current public 1.0.201 package is Apple-valid, but it predates and therefore does not contain this audit's compatibility/repair changes. The next build must still receive a new monotonic build number and pass the same signing, notarization, stapling, fresh-install, and update gates.

## Residual risk register

1. **P2 — commercial licence operations:** no paid end-to-end checkout was performed. Refunds and disputes need manual revocation, claim/activation rely on Cloudflare perimeter controls rather than an app-specific rate limiter, and refreshing the secure result page after the one-time session bearer is scrubbed requires support recovery.
2. **P2 — Goal integration surface:** no public OpenClaw atomic Goal CLI exists for LocalClaw's budgeted workflow, so the controller discovers private hashed chunks. Upstream chunk changes must be caught by compatibility tests on every OpenClaw release.
3. **P2 — Goal tool scope/evidence:** LocalClaw detects native Goal mutation after a turn but cannot remove those tools per turn from every model. Semantic completion evidence may still be model-reported; deterministic file/tests are stronger but not universal.
4. **P2 — remote model catalogue:** strict parsing blocks command injection, but semantic authenticity needs a signed catalogue or embedded trust root.
5. **E2E boundary:** fresh install logic is thoroughly fixture-tested, but no clean physical Mac installation or real multi-gigabyte model download has yet certified the new audited build.

## Stop record and verdict

- Code/fixture verdict: **GO for the 1.0.202 signed-release pipeline**.
- Customer release verdict at this checkpoint: **NO-GO until the build 353 DMG is signed, notarized, stapled, published and verified**.
- Reason: application, Goal, Kanban, recovery, updater and licence gates pass; the hidden production backend is live and the old customer path is unchanged. The release artifact itself does not exist yet.
- Live/deployed status: the isolated licence v2 backend and page are deployed from site commit `4fc86fe3`; D1 migration `0008` is applied with zero licence rows. The five public $49 CTAs still point to the historical checkout by design. No customer data, OpenClaw runtime, account or connected service was changed.
- Next work: commit/push the app source, produce and verify build 353, publish the immutable DMG plus manifest, then switch exactly the five LocalClaw $49 CTAs to the new isolated Stripe Payment Link and prove the custom-domain result.
