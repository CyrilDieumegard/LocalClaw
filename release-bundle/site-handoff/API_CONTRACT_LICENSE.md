# API Contract - Activation Licence

Endpoint attendu par l'app:

`POST /api/license/activate`

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
  "token": "signed-token",
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
