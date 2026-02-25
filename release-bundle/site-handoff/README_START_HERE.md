# LocalClaw V1 - Dossier intégration site

Ce dossier est prêt à copier sur Genspark/site.

## Fichiers inclus

- `localclaw-installer-latest.json`
  Manifest utilisé par l'app pour savoir si une mise à jour est dispo.

- `API_CONTRACT_LICENSE.md`
  Contrat API exact pour l'activation licence dans l'app.

- `INTEGRATION_GUIDE.md`
  Étapes d'intégration côté site (paiement, email, download, update).

- `EMAIL_TEMPLATE_CUSTOMER.md`
  Template email post-paiement prêt à l'emploi.

- `server-example-node.js`
  Exemple backend minimal Node.js (activation licence + lien download signé).

## Ce que tu dois faire maintenant

1. Uploader ton DMG dans un chemin stable (ou versionné)
2. Publier `localclaw-installer-latest.json`
3. Implémenter l'endpoint `/api/license/activate`
4. Envoyer email client après paiement avec clé + lien
5. Tester l'activation depuis l'app

## Variables côté app

Pour tester un endpoint custom:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="https://ton-domaine/api/license/activate"
export LOCALCLAW_INSTALLER_UPDATE_URL="https://ton-domaine/downloads/localclaw-installer-latest.json"
swift run
```
