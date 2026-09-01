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

`POST /api/license/v2/activate`

Le serveur répond `ok:true` uniquement avec un reçu signé vérifiable par
l'application (par exemple Ed25519/JWS), contenant au minimum `licenseKey`,
`email`, `machineId`, `issuedAt`, `expiresAt` et un identifiant de clé. Un token
opaque ou un JSON local non signé ne constitue pas une preuve de licence.

Le fichier `server-example-node.js` illustre uniquement le flux HTTP de
téléchargement. Ce n'est pas un serveur de licence de production.

## 4) Update installer

Publier ce fichier:

`/downloads/localclaw-installer-latest.json`

Exemple de schéma (ne jamais publier des valeurs fictives):

```json
{
  "latestVersion": "1.0.202",
  "latestBuild": "353",
  "dmgUrl": "https://localclaw.io/downloads/localclaw-1.0.202-353.dmg",
  "notesUrl": "https://localclaw.io/changelog/localclaw-installer-v1.0.202",
  "sha256": "64-caracteres-hexadecimaux-calcules-apres-signature-et-notarisation"
}
```

Le manifeste doit être publié en dernier, après validation de la signature du
DMG et de l'app interne, de la notarisation, du Team ID, du bundle ID, de la
version, du build et du SHA-256. Un build doit être strictement plus récent que
le manifeste déjà public. Avant toute écriture, le script de publication relit
ce manifeste public et exige que la future URL versionnée réponde exactement
HTTP 404. Les erreurs réseau, 2xx, 3xx, 403 et 5xx bloquent la publication.

## 5) URLs à donner à l'app

- `LOCALCLAW_LICENSE_ENDPOINT`
- `LOCALCLAW_INSTALLER_UPDATE_URL`

Exemple:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="https://localclaw.io/api/license/v2/activate"
export LOCALCLAW_INSTALLER_UPDATE_URL="https://localclaw.io/downloads/localclaw-installer-latest.json"
```
