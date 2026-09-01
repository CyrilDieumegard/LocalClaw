# LocalClaw Mac Installer

Installateur macOS natif (SwiftUI) pour configurer LM Studio + OpenClaw rapidement.

## Ce que fait l'app

- Détecte le hardware (chip + RAM)
- Recommande un modèle local adapté
- Activation licence au premier lancement (email + clé)
- Exécute le setup guidé:
  - Homebrew
  - LM Studio
  - Node
  - OpenClaw
- Vérifie la santé OpenClaw après install
- Affiche les logs en direct

## Lancer en local

```bash
cd localclaw-mac-installer
swift run
```

## Tests

```bash
swift test
```

## Build release + DMG

```bash
bash scripts/build-dmg.sh
```

## Release check complet

```bash
bash scripts/release-check.sh
```

## Developer ID signing, notarization, and publishing

Local development builds stay ad-hoc signed by default:

```bash
bash scripts/build-dmg.sh
```

Public releases must use Developer ID signing, notarization, and stapling:

```bash
OPENCLAW_PACKAGE_ROOT=<verified-openclaw-2-package> \
  RELEASE_NOTARIZE=1 LOCALCLAW_BUILD_NUMBER=<monotonic-build> bash scripts/release-check.sh
bash scripts/publish-notarized-dmg.sh
```

Release defaults:

- `DEVELOPER_ID_APP`
- `LOCALCLAW_BUILD_NUMBER` (required positive, monotonic integer)
- `OPENCLAW_PACKAGE_ROOT` (required verified OpenClaw 2.0 compatibility fixture)
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

`publish-notarized-dmg.sh` validates the stapled DMG and its packaged app, stages
the validated copy, refuses a non-monotone build or an existing versioned path,
checks the current public manifest and requires an exact HTTP 404 for the new
versioned URL, then commits the update manifest last. Network errors, redirects,
authorization errors and ambiguous target responses block publication.
Both public probes are cache-busted without changing the canonical URL written
to the release manifest.

Optional publication overrides (HTTPS remains mandatory):

- `LOCALCLAW_PUBLIC_MANIFEST_URL`
- `LOCALCLAW_PUBLIC_DOWNLOAD_BASE_URL`
- `LOCALCLAW_PUBLISH_NETWORK_TIMEOUT_SECONDS`

## Endpoint licence

Par défaut l'app active la licence via:

`https://localclaw.io/api/license/v2/activate`

Pour un autre backend:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="https://ton-domaine/api/license/v2/activate"
swift run
```

### Test local rapide (sans backend prod)

```bash
cd localclaw-mac-installer
node scripts/mock-license-server.js
```

Dans un autre terminal:

```bash
cd localclaw-mac-installer
export LOCALCLAW_LICENSE_ENDPOINT="http://127.0.0.1:8787/api/license/v2/activate"
swift run
```

Identifiants de test mock:
- Email: `cyril@test.local`
- Licence: `LOCALCLAW-V1-TEST`
