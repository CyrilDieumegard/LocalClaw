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

## Signature & notarization (obligatoire pour vente publique)

Le script `build-dmg.sh` supporte la signature/notarization via variables d'environnement:

- `DEVELOPER_ID_APP`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Exemple:

```bash
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

bash scripts/build-dmg.sh
```

Sans ces variables, le build reste en mode dev (ad-hoc signing).

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
