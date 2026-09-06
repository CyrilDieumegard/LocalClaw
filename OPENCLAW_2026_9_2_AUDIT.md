# Audit LocalClaw / OpenClaw 2026.9.2

Date : 6 septembre 2026. Branche : `codex/openclaw-2026-9-2-audit`.

## Conclusion

Les parcours testés sont compatibles avec le paquet npm réel OpenClaw 2026.9.2.
L'audit a aussi corrigé des problèmes de récupération, de sélection d'agent et de
modèle, de Goals, de disponibilité et d'interface. Il ne constitue pas une
certification de tous les fournisseurs, appareils et canaux réels.

Références : [notes de version](https://docs.openclaw.ai/releases/2026.9.2),
[configuration des agents](https://docs.openclaw.ai/gateway/config-agents),
[paquet npm exact](https://www.npmjs.com/package/openclaw/v/2026.9.2).
Le paquet testé annonce `OpenClaw 2026.9.2 (3928bad)` ; Node requis :
`>=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0`.

## Corrections

| Problème constaté | Comportement corrigé |
| --- | --- |
| Redémarrage LocalClaw après un refus de récupération natif | Respect de `recovery.serviceRestartSafe=false`, y compris après relance de l'app et remplacement de Node. Le blocage disparaît seulement après une réparation vérifiée. |
| Node du Gateway non contrôlé avant maintenance | Vérification de l'exécutable réellement sélectionné avant arrêt du service ou modification. |
| Agent `main` choisi malgré un autre propriétaire déclaré | Conservation du propriétaire explicite et de l'ancien agent par défaut ; refus d'un propriétaire invalide. |
| Modèle global affiché ou modifié à la place du modèle de l'agent | Lecture des formats chaîne/objet, priorité aux réglages de l'agent, conservation des fallbacks et des autres agents. Alignement des écrans. |
| Authentification recherchée dans le mauvais agent/profil | Répertoire de credentials et cache liés à l'agent/profil ; arrêt avant écriture si un fichier existant est invalide ou illisible. |
| Échec CLI affiché comme installation valide | Version reconnue uniquement après une sortie réussie contenant une version OpenClaw valide. |
| Modèle local absent affiché comme utilisable | État bloquant si absent ; un autre modèle chargé ne rend pas le modèle sélectionné prêt. |
| Erreur Gateway dirigée vers la connexion au fournisseur | Réparation Gateway pour les erreurs de token Gateway ; message adapté aux modèles cloud indisponibles. |
| Goal ou activité Developer basculant vers une installation ambiante | Respect du paquet sélectionné et de son Node ; absence/ambiguïté signalée. |
| Dossier Goal incorrect pour un agent nommé | Alignement sur l'héritage natif du workspace, vérifié avec le paquet réel. |
| Contrôleur Goal bloqué sans limite | Lecture bornée et délai de 30 secondes ; conservation de l'identifiant d'opération pour réconcilier une réponse perdue. |
| Automatisation encore affichée en cours après redémarrage de LocalClaw | Résultat `Unknown` quand la fin n'a pas été observée ; aucune réussite inventée ni relance automatique. |
| Credentials conservés dans certains diagnostics | Masquage dans les messages JSON imbriqués, les valeurs citées, les en-têtes HTTP et les logs JSON mixtes. |
| Catalogue acceptant la destination finale d'une redirection non autorisée | Contrôle de l'URL finale, du domaine, du protocole, du port et de la taille reçue. |
| Changement de modèle annoncé réussi malgré un échec | Succès et changement de session seulement après vérification ; suppression du redémarrage supplémentaire ; opération hors du thread d'interface. |
| Envoi ou seconde sélection pendant un changement de modèle | Sélecteur protégé, brouillon conservé, changement refusé pendant chat/installation/maintenance ; restauration cohérente du modèle, du fournisseur et du mode d'authentification après échec. |

## Validation

Les preuves détaillées sont conservées dans
`/private/tmp/localclaw-audit-2026.9.2/`.

| Vérification | Preuve |
| --- | --- |
| Suite Swift complète | `release-1.0.207-364.log` : **347 tests dans 17 suites, tous réussis** |
| CLI, configuration, modèles, plugins, Goals et workspace | `compat-goal.log` : succès avec 2026.9.2 |
| Reçus Goal SQLite après redémarrage et rejet des révisions périmées | `compat-goal.log` : succès |
| Réparation native Doctor/plugins, répétée deux fois | `post-update.log` : succès, réseau et lecture du home hôte interdits |
| Planification de mise à jour vers la bonne installation `.local` | `update-owner.log` : succès avec ancien package simulé et ancienne configuration |
| Tour avec outil, streaming, écriture et réponse finale | `turn-embedded.log`, `turn-gateway.log` : succès |
| Migration d'ancienne configuration puis tour via Gateway | `turn-gateway-legacy.log` : succès ; backup, credentials fictifs, politique d'outils et projet conservés |
| Ancienne migration des permissions 2026.8.1 | `legacy-approvals.log` : 8 scénarios réussis |
| Contrat du helper Goal | `goal-contract.log` : succès |
| Compilation optimisée, app et DMG de développement | `build-verified.log` : succès |
| App extraite du DMG de développement de la première passe | `dmg-verified.log` : signature ad-hoc valide, 6 scénarios de ressources, 4 scénarios de diagnostic et égalité des 3 scripts livrés |

Les tours utilisent un modèle déterministe sur localhost : deux réponses simulées
par tour. Ils prouvent le transport, le streaming et l'exécution d'outils ; ils ne
valident pas les comptes OpenAI/Anthropic/OpenRouter, une connexion OAuth réelle,
un téléchargement de modèle LM Studio ou la livraison vers un canal réel.

La planification et la finalisation native sont exécutées avec le paquet réel ;
les erreurs de mise à jour et de rollback sont couvertes par les fixtures Swift.
Aucune mise à jour de l'installation OpenClaw active n'a été exécutée.

Commandes de reproduction, depuis ce dépôt, avec `OPENCLAW_PACKAGE_ROOT` pointant
vers une installation de test du paquet exact 2026.9.2 :

```sh
swift test --scratch-path /private/tmp/localclaw-compat-swift -j 2
node scripts/test-goal-controller-contract.mjs
node scripts/test-openclaw-compat.mjs "$OPENCLAW_PACKAGE_ROOT"
node scripts/test-openclaw-post-update.mjs "$OPENCLAW_PACKAGE_ROOT"
node scripts/test-openclaw-update-owner.mjs "$OPENCLAW_PACKAGE_ROOT" --legacy-config
node scripts/test-openclaw-turn.mjs "$OPENCLAW_PACKAGE_ROOT"
node scripts/test-openclaw-turn.mjs "$OPENCLAW_PACKAGE_ROOT" --gateway --legacy-config
RELEASE_NOTARIZE=0 bash scripts/build-dmg.sh
```

## Mise à jour intégrée et livraison 1.0.207

Version de livraison : **1.0.207, build 364**. La publication utilise
`scripts/release-check.sh` puis `scripts/publish-notarized-dmg.sh` : compilation,
contrats natifs, tests Swift, signature Developer ID, notarisation Apple,
vérification du DMG extrait et calcul SHA-256 après agrafage du ticket Apple.
Le paquet final exécute aussi le vérificateur de signature de l'updater sur une
app réellement signée et notarisée : un refus systématique échoue à ce contrôle.

Le bouton App update installe la nouvelle app et la relance sans glisser le DMG.
Le helper vérifie l'identité du processus parent, le dossier Applications et la
signature de la nouvelle app ; le remplacement est atomique. En cas d'échec de
validation ou de relance, il restaure l'ancienne app quand cela est sûr et expose
un diagnostic. Le dossier Applications doit être accessible en écriture au compte
courant ; le dossier Applications personnel est également pris en charge.

Update all traite les dépendances et OpenClaw avant l'app, conserve la version de
manifest vérifiée et s'arrête sur un échec. Les mises à jour sont bloquées pendant
un chat, un changement de modèle ou une autre maintenance. Un échec de création
du point de récupération arrête la maintenance.

Les anciennes versions jusqu'à 1.0.206 nécessitent une dernière installation du
DMG pour recevoir ce mécanisme. Les versions suivantes utilisent le bouton.

Le précédent DMG signé 1.0.206 est préservé dans
`/private/tmp/localclaw-audit-2026.9.2/previous-dist/`.
Les validations d'achat, d'activation client et d'installation sur un Mac vierge
restent distinctes de ces tests.

## Preuve de mise à jour réelle

Le bouton **App update > Update** a été utilisé sur le Mac Studio de travail.
Une copie de transition signée, contenant le code final avec un numéro de build
361 de test, a téléchargé le vrai DMG notarisé 364 depuis la branche candidate.
Le processus 75800 a été remplacé par le processus 76157 sans intervention de
Finder. L'app relancée affiche `LocalClaw 1.0.207 (364) was installed and relaunched
successfully.` Le dossier du helper a été nettoyé automatiquement.

Les 9 fichiers de `/Applications/LocalClaw.app` sont identiques à ceux de l'app
signée distribuée ; codesign et Gatekeeper acceptent l'installation. Le checksum
`~/.openclaw/openclaw.json` est inchangé. L'installation OpenClaw active reste en
2026.9.1 ; les tests de compatibilité 2026.9.2 ont utilisé un état isolé.

Preuves : `self-update-live-proof.json`, `self-update-signature-positive-negative.log`,
`self-update-parent-identity.log`, `release-1.0.207-364.log`, dans le dossier d'audit.
SHA-256 du DMG final :
`d5bc2d2525fb03817eaddc24e8fbff2e44c34f4eecb6fe52e3e5ea282f0c80e1`.

Le site public distribue désormais cette version :
[téléchargement](https://localclaw.io/downloads/localclaw-1.0.207-364.dmg) et
[notes de version](https://localclaw.io/changelog/localclaw-installer-v1.0.207).
