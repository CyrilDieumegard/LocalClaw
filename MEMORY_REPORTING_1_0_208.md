# LocalClaw 1.0.208 (365): memory reporting correction

Release date: 2026-09-10. Application code: `c03ae73`.

## Confirmed causes and correction

1. Whole-Mac RAM previously summed active, inactive, wired and compressed pages,
   counting reclaimable file cache as used. The shared parser now subtracts free,
   file-backed and purgeable pages from physical memory. It respects the reported
   page size and does not count speculative pages twice. Available RAM includes
   reclaimable cache; system allocations absent from the category sum remain used.
2. Home passed integer MB values to `%.0f`, a floating-point format. This produced
   zero labels despite nonzero measurements. Home now interpolates the integers.
3. Process matching required `/node` or `/openclaw`. The new parser recognizes bare
   names, Node entry scripts and Node options before the script. OpenClaw and
   LM Studio helper descendants are included and PIDs are deduplicated per group.

All resource panels explain whole-Mac usage and the RSS process metric. RSS is
not Activity Monitor's per-process physical footprint. Groups can overlap;
OpenClaw hosted by Node belongs to both groups. Sampling times can differ.

## Verification

- Final release gate: 354 tests across 18 suites passed; real OpenClaw 2026.9.2
  integration and 2026.8.1 migration fixtures passed without provider calls or
  changes to customer services. Seven memory/process parser tests cover cache,
  page size, malformed input, bare names, helpers, false positives and Node options.
- Reproduced the old Home bug in the installed 1.0.207 (364): RAM 30.6 / 32 GB,
  all three process labels 0 MB.
- Final notarized 1.0.208 (365) Home: RAM 26.7 / 32 GB, OpenClaw 173 MB,
  LM Studio 100 MB, Node 2206 MB. These are separate samples on the working Mac
  Studio, not a controlled before/after workload comparison or a measurement of
  the client's Mac mini. Activity Monitor was also inspected; exact simultaneous
  readings are not claimed.
- Confirmed that the real Gateway PID 11280 used Node with
  `--max-old-space-size=8192` before the OpenClaw entry script. A targeted read of
  this PID recognized it as both OpenClaw and Node.
- Final app/DMG passed Developer ID signing, Apple notarization and stapling,
  Gatekeeper and the production self-update signature verifier.
- Final DMG SHA-256:
  `0a221bfa4d63447f8a7a324b44e735046e31fd4bedf52d2600ed1c93ce09b988`.
- Public manifest, raw GitHub DMG, versioned localclaw.io DMG and latest DMG were
  fetched and verified against that hash. Download, pricing and release notes
  expose 1.0.208. Website commit: `4873250`.
- The previous 1.0.207 DMG is retained publicly and in the local evidence folder.

Evidence folder: `/private/tmp/localclaw-memory-release-20260910/`.
Final release log: `release-365-complete.log`; public proof: `public-proof.json`.
The client's target machine and a new purchase/activation were not exercised.

## Verified in-app update

The genuine installed 1.0.207 (364) fetched the public GitHub manifest and offered
1.0.208 (365) after its existing five-minute HTTP cache expired. Clicking only
**App update > Update** downloaded and installed the public DMG and relaunched
LocalClaw (PID 80758 -> 81346). The UI receipt states:
`LocalClaw 1.0.208 (365) was installed and relaunched successfully.`

All nine installed bundle files match the signed release exactly. Codesign and
Gatekeeper accept `/Applications/LocalClaw.app`. The OpenClaw configuration hash
is unchanged and OpenClaw itself remains at 2026.9.1. No dependency/runtime update
was requested. Proof: `self-update-proof.json` in the evidence folder.

After updating, Home displayed 26.5 / 32 GB and OpenClaw 328 MB, LM Studio 107 MB,
Node 1938 MB. The subsequent Activity Monitor sample showed 26.80 GB used.
These successive readings show the remaining sampling difference, not an exact
simultaneous match. The app stays open on the corrected Home panel.
