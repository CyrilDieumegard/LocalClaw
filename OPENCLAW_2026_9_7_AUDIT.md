# Audit OpenClaw 2026.9.7 — 1 octobre 2026

## Conclusion

Le fonctionnement courant testé de LocalClaw reste compatible avec OpenClaw
2026.9.7. Une correction de la sauvegarde avant mise à jour est nécessaire
avant de certifier le passage 2026.9.6 → 2026.9.7 depuis l'application.

Cet audit n'a modifié ni les sources de l'application, ni l'installation
OpenClaw active, ni sa configuration, ni ses services. Aucun binaire n'a été
publié. Ce document est le seul ajout au dépôt.

## Périmètre vérifié

- Dépôt : branche `codex/local-router-beta`, commit `7509a0b` ; état initial propre.
- Application installée : LocalClaw **1.0.209, build 388**.
- Paquet OpenClaw actif inspecté : **2026.9.6**.
- Paquet candidat : **2026.9.7**, stable, publié le 30 septembre à 04:44:14 UTC.
- Node utilisé pour les tests : **26.9.0**.
- Exigence Node du candidat : `>=24.16.0 <25 || >=26.1.0`, déjà prise en charge.
- Paquet npm téléchargé et contrôlé contre son intégrité SHA-512 officielle.
- Exécution dans des états temporaires, avec fournisseurs simulés sur localhost
  pour les tests de chat ; aucun appel à un fournisseur payant.

L'annonce X a été confirmée via son endpoint public de syndication : elle
annonce bien la version 2026.9.7. Les détails techniques viennent des notes
officielles, des métadonnées npm et du paquet réellement exécuté.

## Défaut confirmé : sauvegarde avant migration

Les métadonnées des deux paquets indiquent :

| Base | OpenClaw 2026.9.6 | OpenClaw 2026.9.7 |
| --- | ---: | ---: |
| État global | 18 | 19 |
| Agent | 23 | 24 |

`Sources/OpenClawRuntimeMaintenance.swift:613` décide si une mise à jour exige
une sauvegarde complète. À la ligne 627, les seules frontières recensées sont
`2026.8.1` et `2026.9.6`. Le passage **9.6 → 9.7 retourne donc faux** dans le
cas normal. Le test
`fullStateBackupOccursOnceAtEachKnownSchemaBoundaryAndForRecovery` contient
même une assertion qui attend cette absence de sauvegarde.

Le résultat est une mise à jour avec un petit instantané de configuration,
sans l'archive complète LocalClaw préalable à cette nouvelle migration.
OpenClaw 9.7 améliore ses propres instantanés et son rollback, mais sa
documentation précise que ces protections ne complètent pas rétroactivement
les sauvegardes d'une mise à jour exécutée par un ancien moteur. Un retour au
paquet 9.6 seul ne doit pas être assimilé à la restauration des bases migrées.

**Correction recommandée :** reconnaître 2026.9.7 comme frontière de migration
et exiger une sauvegarde complète vérifiée avant de remplacer le moteur 9.6 ;
adapter le test actuellement contraire. À plus long terme, baser cette
décision sur les schémas annoncés par le paquet cible, plutôt que seulement
sur une liste de versions.

Une migration réelle isolée **9.6 → 9.7**, avec sauvegarde vérifiée avant
Doctor, a réussi : schéma global **18 → 19**, contrôle d'intégrité SQLite OK
et lecture des modèles de l'agent après migration.

## Vérifications exécutées

| Contrôle | Résultat |
| --- | --- |
| Suite Swift LocalClaw | 375 tests passés, 18 suites |
| Suite XCTest du routage | 15 tests passés |
| Chat intégré avec outil d'écriture et réponse finale | Passé |
| Chat via vrai Gateway temporaire, modèle simulé et fichier produit | Passé |
| CLI agents, modèles, Gateway, Cron, canaux, plugins, compaction | Passé |
| Configuration et héritage des workspaces d'agents explicites | Passé |
| Goals : création, lecture, pause, reprise, édition, clôture, suppression | Passé |
| Rejeu des reçus Goals et rejet des révisions périmées sur vraie SQLite | Passé |
| Sauvegarde native vérifiée | Passé |
| Import d'une clé de fixture par stdin dans le stockage SQLite | Passé |
| Suivi Developer incrémental sans corps privés dans la sortie | Passé |
| `update repair` 9.7, JSON de finalisation, Doctor et plugins | Passé deux fois |
| Migration d'une configuration legacy dans un état neuf | Passé |
| Migration réelle du schéma global 9.6 → 9.7 | Passé avec sauvegarde préalable |

Les tests `update repair` interdisent le réseau et les lectures du dossier
personnel hôte. Ils confirment l'absence de remplacement du cœur et de
redémarrage de service dans ce scénario de finalisation.

## Changements fonctionnels et impact produit

- **Performances et reprise après redémarrage :** améliorations du moteur
  OpenClaw dont LocalClaw peut bénéficier après mise à jour. Les changements
  de rendu de l'interface web OpenClaw ne constituent pas une amélioration
  automatiquement vérifiée de l'interface SwiftUI LocalClaw.
- **Retrait de Tasks/TaskFlow et migration Tool Search :** aucune dépendance
  directe aux API retirées n'a été trouvée dans les sources inspectées de
  LocalClaw. Goals et le Kanban/Cron LocalClaw sont distincts. Des plugins ou
  configurations propres aux utilisateurs peuvent néanmoins nécessiter Doctor.
- **Sign in with ChatGPT (Beta) :** nouvelle méthode distincte de la connexion
  Codex actuellement proposée par LocalClaw. Une interface dédiée et une
  explication des comptes, droits et limites seraient nécessaires pour la
  proposer proprement. Pas de remplacement automatique de la connexion existante.
- **Agents API :** runtime optionnel, avec choix explicite, clé API et
  environnement d'exécution à expliquer. Aucune activation n'a été effectuée.
- **Decision Models / Routed Chat :** la version poursuit cette intégration.
  La signature utilisée par le plugin LocalClaw n'a pas révélé de rupture à
  l'inspection ; l'inférence ONNX réelle du routeur n'a pas été exécutée dans
  cet audit et n'est donc pas certifiée ici.

## Limites et fixtures à actualiser

Le script de compatibilité existant a passé ses contrôles courants puis échoué
sur la migration legacy : il réécrit une configuration legacy dans un état
déjà initialisé par les contrôles précédents. La même migration a passé dans
une fixture neuve. Il faut séparer ces scénarios ; l'échec de la suite originale
n'est pas masqué ni présenté comme une réussite complète.

Le test de propriétaire d'un updater temporaire a échoué sur son attente
`dryRun: true`. Le diagnostic 9.7 renvoie désormais `status: skipped` et
`reason: unmanaged-package-install` pour ce paquet temporaire, faute de
propriétaire global identifiable. Cela confirme un refus, pas une mise à jour
réussie ni une modification du paquet Gateway de la fixture. Ce scénario doit
être remis en adéquation avec une vraie installation npm globale isolée avant
certification des récupérations d'anciens moteurs.

Le premier test de finalisation a également détecté un cycle d'installation
incomplet dans le paquet temporaire installé avec scripts désactivés. Après
exécution du cycle officiel du paquet OpenClaw dans cette fixture, les deux
finalisations ont passé. Il ne s'agissait pas d'un défaut de LocalClaw.

Le bouton de mise à jour de l'application installée n'a pas été utilisé pour
modifier le runtime actif. L'installation sur un Mac neuf, l'authentification
réelle des comptes, la convergence de tous les plugins clients et un rollback
complet de mise à jour échouée restent hors des preuves de cet audit.
Le manifeste public LocalClaw n'a pas pu être revérifié : HTTP 403.

## Sources et preuves

- [Annonce OpenClaw](https://x.com/openclaw/status/2105356656846786748)
- [Release stable GitHub](https://github.com/openclaw/openclaw/releases/tag/v2026.9.7)
- [Notes officielles](https://docs.openclaw.ai/releases/2026.9.7)
- [Métadonnées exactes npm](https://registry.npmjs.org/openclaw/2026.9.7)
- [Changelog du tag](https://github.com/openclaw/openclaw/blob/v2026.9.7/CHANGELOG/2026.9.7.md)

Preuves locales de cette exécution :

- `/private/tmp/localclaw-9-7-audit-swift-20261001.log`
- `/private/tmp/localclaw-9-7-compat.log`
- `/private/tmp/localclaw-9-7-embedded-turn.log`
- `/private/tmp/localclaw-9-7-gateway-turn.log`
- `/private/tmp/localclaw-9-7-post-update.log`
- `/private/tmp/localclaw-9-7-legacy-fresh-state.log`
- `/private/tmp/localclaw-9-7-schema-migration.log`
- `/private/tmp/localclaw-9-7-update-owner-diagnostic.log`

Ces fichiers temporaires sont des traces d'audit, pas des artefacts de release.

## Suite autorisée : LocalClaw 1.0.210

Après l'audit, l'utilisateur a autorisé la correction, le push et la mise à
jour. La version 2026.9.7 est désormais une frontière de sauvegarde complète.
Deux tests vérifient la sauvegarde avant remplacement du cœur et l'arrêt de
la mise à jour avant toute interruption du Gateway lorsque la sauvegarde échoue.
La fixture de migration legacy commence dans un état neuf. Le test de
propriétaire accepte uniquement le nouveau refus précis d'une installation
temporaire non identifiée, ou le plan de rebind antérieurement vérifié.
Les résultats de publication et de migration active seront consignés dans
le relevé de release après vérification.

## Validation de release et blocage Apple

La correction de sauvegarde et les fixtures sont poussées sur
`codex/local-router-beta`. Le commit de code final testé est `ad07319`.
Le test de présence des ressources utilise maintenant le bundle de tests réel,
y compris avec `--scratch-path /private/tmp/localclaw-release-swift`.

La validation du 1 octobre a passé les **377 tests Swift Testing et les
15 tests XCTest**, les probes OpenClaw 9.7, les huit migrations legacy,
le chat via Gateway temporaire, deux finalisations natives isolées et le
contrôle de propriétaire. Le binaire de production 1.0.210 / 389 a été
compilé et signé Developer ID. Les six contrôles des ressources empaquetées
et les quatre contrôles du parseur empaqueté ont passé.

La soumission à Apple a ensuite été refusée avec HTTP **403** :
`A required agreement is missing or has expired.` La consultation de
l'historique de notarisation reçoit le même refus, indépendamment du DMG.
Il faut vérifier les accords du compte développeur de l'équipe `923MBLC4X4`.
Aucune acceptation d'accord n'a été effectuée par l'agent.

Cette tentative n'a donc pas produit de DMG notarise certifié pour publication.
Le site préparé vise 1.0.210 / 389, mais son nouveau manifeste et sa somme
SHA-256 ne seront créés qu'après notarisation et stapling réussis.
L'application installée reste **1.0.209 / 388**, et le moteur actif reste
**OpenClaw 2026.9.6**. La publication client et la migration active attendent
la levée de ce blocage Apple.

Preuves : `/private/tmp/localclaw-1-0-210-release-gate.log` et
`/private/tmp/localclaw-1-0-210-notary-history.log`.
