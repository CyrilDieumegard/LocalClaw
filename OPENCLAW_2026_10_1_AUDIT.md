# LocalClaw et OpenClaw 2026.10.1 — 11 octobre 2026

## Corrections de compatibilité

Le candidat LocalClaw 1.0.211 corrige les deux défauts identifiés dans l'audit,
ainsi qu'un troisième défaut révélé par la migration réelle.

1. **Sauvegarde avant migration.** OpenClaw 10.1 fait passer le schéma global
   de 19 à 20 (agent : 24). LocalClaw exige désormais une sauvegarde complète
   vérifiée avant l'arrêt du Gateway et le remplacement de 9.7 ou 9.8.
   Un échec de sauvegarde conserve le moteur et le Gateway existants.
2. **Goals.** Les API natives ont été réparties dans plusieurs modules en 10.1.
   Le pont charge les nouvelles fonctions natives de mutation et de lecture
   des reçus. Il conserve les validations de schéma, de génération de session,
   de révision et d'identité des opérations. Le chemin 9.7 reste compatible.
3. **Reconnaissance d'une migration terminée.** Le vrai reçu npm 10.1 contient
   une attestation `recovery.serviceRestartSafe: true` pour la version installée
   et peut contenir l'avertissement connu `config.plaintext_secrets`.
   LocalClaw ne doit pas confondre ce reçu avec un échec de plugin. L'exception
   est limitée à ce message et à ces champs exacts ; une autre version de
   récupération, un refus natif, une permission manquante, une erreur de lint,
   une dérive d'intégrité ou une étape interrompue bloque toujours l'activation.
   Les migrations de plugins restantes, le Doctor final, la configuration et
   deux contrôles RPC doivent ensuite être vérifiés. L'avertissement reste visible.

## Paquets et isolation

- Source de départ : `b0e2476118404ccc43270cdb3d2597e4b8758250`, clone propre.
- Candidat officiel : OpenClaw **2026.10.1**, tag `v2026.10.1`, commit
  `e178c39e9aae3fa440735217f9aef9574f286677`.
- Node : **26.9.0**, compatible avec l'exigence du paquet.
- Intégrité SHA-512 du tarball npm vérifiée :
  `C072/lxy83KP1nMCnJbipr4O+EtIR9XXbjzQFM+ol7VE5ci2MkKk5XTxfSG70jxpEVaGFeXcEmObHxR/ZHLdHw==`.
- Installation globale, HOME, configuration, credentials et workspace de test
  sous `/private/tmp/localclaw-full-migration-*`.
- Identifiants factices et modèle simulé sur localhost ; aucun compte client
  ni fournisseur payant utilisé.
- Aucun remplacement de `/Applications/LocalClaw.app`, du moteur OpenClaw actif
  ou du LaunchAgent utilisateur pendant les contrôles.

## Preuves de migration réelle

Le scénario `scripts/test-openclaw-full-migration.mjs` a exécuté le vrai
`openclaw update --tag 2026.10.1 --yes --json --no-restart` depuis une
installation npm globale 9.7 isolée. Il a vérifié :

- sauvegarde native avec `--verify` avant remplacement ;
- admission et répétition de migration par le candidat natif ;
- paquet installé 10.1 et SQLite globale **19 → 20**, intégrité `ok` ;
- même Goal et même objectif après migration ;
- credential SQLite et fichier du workspace conservés ;
- Doctor post-upgrade : les cinq sondes plugins requises exécutées, aucun finding ;
- aucune migration de plugin différée en attente ;
- démarrage d'un Gateway temporaire, deux contrôles de santé réussis ;
- réponse de chat produite via ce Gateway et le fournisseur localhost.

Le reçu JSON natif expurgé des chemins de fixture et des diagnostics non utiles
est conservé dans `Tests/localclaw-mac-installerTests/Fixtures/`.
Les tests du contrôleur Swift l'utilisent pour vérifier l'ordre des contrôles,
l'absence de seconde mise à jour aveugle et le maintien du blocage lorsqu'une
migration reste inachevée.

## Autres contrôles exécutés

- Compatibilité complète sur le vrai paquet 10.1 : CLI, configuration,
  credentials, backup, Goals et reçus durables, activité Developer, config legacy.
- Même suite sur 9.7 pour vérifier la rétrocompatibilité du pont Goals.
- Chat via Gateway 10.1 après migration de configuration legacy, avec véritable
  appel d'outil `write`, fichier produit et réponse finale.
- Huit scénarios réels d'import des permissions historiques avec OpenClaw 8.1 :
  migration, reprise, idempotence et refus des cas invalides ou contradictoires.
- Refus natif de remplacement par un paquet temporaire sans propriétaire valide.
- Deux finalisations `update repair` consécutives sur 10.1, sans remplacement du
  cœur ni redémarrage de service. TCP/IP et lectures du HOME hôte interdits.
  Le nouveau broker SQLite utilise des sockets Unix privés et `/dev/null` ;
  la fixture autorise uniquement cet IPC dans son propre répertoire.

Les premières tentatives de migration ont détecté des contraintes trop strictes
du HOME de test lors des répétitions internes du nouvel updater. Elles ont été
corrigées uniquement dans les fixtures. Les défauts ne sont pas masqués par une
modification du paquet OpenClaw ou un contournement de ses contrôles natifs.

## Portée des résultats

Ces preuves couvrent les chemins de migration et les intégrations testées.
Elles ne certifient pas chaque plugin tiers, une nouvelle connexion OAuth,
les canaux externes, la facturation, ou toutes les installations clientes.
Les fixtures npm préparent les dépendances avec leurs scripts désactivés puis
exécutent le postinstall officiel OpenClaw ; chaque plugin natif optionnel n'est
pas validé. Les nouveautés MCP Apps et stockage R2 ne deviennent pas des
fonctionnalités SwiftUI LocalClaw par cette correction de compatibilité.

## Sources

- [Annonce OpenClaw](https://x.com/openclaw/status/2109347136328417718)
- [Release GitHub](https://github.com/openclaw/openclaw/releases/tag/v2026.10.1)
- [Notes officielles](https://docs.openclaw.ai/releases/2026.10.1)
- [Métadonnées npm exactes](https://registry.npmjs.org/openclaw/2026.10.1)

Les traces détaillées de cette exécution sont dans
`/private/tmp/localclaw-openclaw-audit-20261011/` et les répertoires
`/private/tmp/localclaw-full-migration-*` ; ce sont des preuves locales,
pas une preuve de publication.
