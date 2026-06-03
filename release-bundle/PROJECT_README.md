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

## Endpoint licence

Par défaut l'app active la licence via:

`https://localclaw.io/api/license/activate`

Pour un autre backend:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="https://ton-domaine/api/license/activate"
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
export LOCALCLAW_LICENSE_ENDPOINT="http://127.0.0.1:8787/api/license/activate"
swift run
```

Identifiants de test mock:
- Email: `cyril@test.local`
- Licence: `LOCALCLAW-V1-TEST`
