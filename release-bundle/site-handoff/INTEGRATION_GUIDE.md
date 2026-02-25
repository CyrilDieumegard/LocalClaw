# Integration Guide - Site + Paiement + Livraison

## 1) Après paiement Stripe

Au webhook `checkout.session.completed`:

1. Récupérer email client
2. Générer clé licence (format: `LCW-XXXX-XXXX-XXXX`)
3. Enregistrer en base
4. Générer lien download signé, expirant (ex: 10 min)
5. Envoyer email client

## 2) Download sécurisé

Option simple V1:
- URL non indexée + token + expiration

Option mieux:
- endpoint `/api/download?token=...`
- vérifie signature + expiration + compteur max
- redirige vers fichier DMG

## 3) Activation in-app

L'app envoie email + licence + machineId sur:

`POST /api/license/activate`

Le serveur répond `ok:true` si valide.

## 4) Update installer

Publier ce fichier:

`/downloads/localclaw-installer-latest.json`

Exemple:

```json
{
  "latestVersion": "1.0.1",
  "dmgUrl": "https://localclaw.io/downloads/builds/LocalClawInstaller-v1.0.1.dmg",
  "notesUrl": "https://localclaw.io/changelog/localclaw-installer-v1.0.1"
}
```

## 5) URLs à donner à l'app

- `LOCALCLAW_LICENSE_ENDPOINT`
- `LOCALCLAW_INSTALLER_UPDATE_URL`

Exemple:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="https://localclaw.io/api/license/activate"
export LOCALCLAW_INSTALLER_UPDATE_URL="https://localclaw.io/downloads/localclaw-installer-latest.json"
```
