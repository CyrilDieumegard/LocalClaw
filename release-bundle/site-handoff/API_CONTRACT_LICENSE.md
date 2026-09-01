# API Contract - Activation Licence

Endpoint attendu par l'app:

`POST /api/license/v2/activate`

## Request JSON

```json
{
  "email": "client@example.com",
  "licenseKey": "LCW-XXXX-XXXX-XXXX",
  "machineId": "UUID-MAC",
  "appVersion": "1.0.0"
}
```

## Success (200)

```json
{
  "ok": true,
  "token": "ed25519-or-jws-signed-receipt",
  "message": "Activated",
  "expiresAt": "2027-02-19T00:00:00Z"
}
```

## Refus (403)

```json
{
  "ok": false,
  "message": "Invalid license"
}
```

## Erreur serveur (500)

```json
{
  "ok": false,
  "message": "Server error"
}
```

## Règles recommandées

- email doit matcher l'achat
- clé licence unique par achat
- limite d'activation machine: 1 ou 2
- enregistrer IP + user agent + timestamp
- possibilité de révoquer une clé
- le reçu doit être signé par une clé serveur; l'app embarque seulement la clé publique
- l'app vérifie signature, `machineId`, email, licence, expiration et identifiant de clé
- aucune absence d'expiration ne doit être interprétée comme une licence permanente
- prévoir rotation de clé, révocation et une grâce hors ligne explicitement bornée
