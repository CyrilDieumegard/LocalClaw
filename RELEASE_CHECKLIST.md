# LocalClaw Installer - Release Checklist

## Quality Gate
- [ ] `swift test` passe
- [ ] `swift build -c release` passe
- [ ] DMG généré sans erreur
- [ ] Install testée sur machine propre

## Security & Trust
- [ ] App signée avec Developer ID (pas ad-hoc)
- [ ] DMG signé
- [ ] Notarization Apple validée
- [ ] Staple app + dmg appliqué
- [ ] Gatekeeper check OK (`spctl -a -vv`)

## Product
- [ ] Version semver alignée (Info.plist + site)
- [ ] Changelog publié
- [ ] FAQ install/erreurs publiée
- [ ] Politique refund claire

## Go/No-Go
- [ ] P0 bugs = 0
- [ ] Support channel prêt
- [ ] Artefacts uploadés sur le site
