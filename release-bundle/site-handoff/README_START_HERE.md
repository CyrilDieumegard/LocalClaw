# LocalClaw - Modèles d'intégration site

Ce dossier contient des modèles fail-closed. Il n'est pas prêt à copier
tel quel en production: les valeurs `0.0.0`, `REPLACE-ME` et les hashes nuls
sont volontairement non publiables.

## Fichiers inclus

- `localclaw-installer-latest.json`
  Exemple de schéma uniquement. Le manifeste de production doit être généré
  par `scripts/publish-notarized-dmg.sh` après toutes les validations.

- `API_CONTRACT_LICENSE.md`
  Contrat cible pour une activation avec reçu cryptographiquement signé.

- `INTEGRATION_GUIDE.md`
  Étapes d'intégration côté site (paiement, email, download, update).

- `EMAIL_TEMPLATE_CUSTOMER.md`
  Template email post-paiement prêt à l'emploi.

- `server-example-node.js`
  Démonstration HTTP non destinée à la production. Elle ne remplace ni une
  base de licences, ni un reçu asymétriquement signé, ni la révocation.

## Ce que tu dois faire maintenant

1. Construire et valider un nouveau build avec `scripts/release-check.sh`
2. Exécuter `scripts/publish-notarized-dmg.sh`; ne jamais copier le manifeste
   d'exemple manuellement. Le script doit pouvoir lire le manifeste public et
   obtenir exactement HTTP 404 pour la nouvelle URL versionnée; toute réponse
   réseau ambiguë bloque la publication
3. Implémenter `/api/license/v2/activate` avec reçu signé et révocation
4. Envoyer l'email client après paiement avec clé + lien
5. Prouver l'installation neuve et la mise à jour depuis la version publique

## Variables côté app

Pour tester un endpoint custom:

```bash
export LOCALCLAW_LICENSE_ENDPOINT="https://ton-domaine/api/license/v2/activate"
export LOCALCLAW_INSTALLER_UPDATE_URL="https://ton-domaine/downloads/localclaw-installer-latest.json"
swift run
```
