# LocalClaw Field Test - Bug Report
## Date: 2026-02-20
## Machine: iMac 24-inch (2021), Apple M1, 8 Go RAM, macOS Tahoe 26.3
## Testeur: Cyril (via iMac de sa mère, compte utilisateur "bernadettedieumegard")
## Build testé: LocalClaw v1.0.0

---

## Contexte

Test terrain réel d'installation complète de LocalClaw sur une machine vierge (aucun outil dev préinstallé). L'objectif est un parcours 100% GUI, zéro terminal. Le client final ne doit JAMAIS ouvrir le Terminal.

---

## Bug 1: Homebrew non installé automatiquement (BLOQUANT)

**Où:** Step 3 Installing (flow "Install Local LLM" ou "Install OpenClaw")

**Ce qui se passe:** L'installateur tente d'exécuter `brew install ...` mais Homebrew n'est pas présent sur la machine. Le log affiche:
```
[FAIL] Homebrew
  Warning: Running in non-interactive mode because 'stdin' is not a TTY.
  ==> Checking for 'sudo' access (which may request your password)...
  Need sudo access on macOS (e.g. the user bernadettedieumegard needs to be an Administrator)!
[FAIL] LM Studio
  zsh:1: command not found: brew
[FAIL] Node
  zsh:1: command not found: brew
```

**Ce qu'il faut corriger:**
- Détecter si Homebrew est installé AVANT de lancer le flow d'installation.
- Si absent, proposer un bouton "Installer Homebrew" dans l'app avec élévation admin native macOS (popup mot de passe système), pas de shell manuel.
- Homebrew est le prérequis n°1 absolu: sans lui, Node, LM Studio, OpenClaw et le modèle ne peuvent pas s'installer.

**Fichier source concerné:** `Sources/InstallerEngine.swift` (fonction d'installation) et `Sources/LocalClawInstallerApp.swift` (flow UI Step 3).

---

## Bug 2: Badges d'état trompeurs "Already installed" (UX CRITIQUE)

**Où:** Step 3 Installing, colonne de droite des statuts

**Ce qui se passe:** Les badges affichent "Already installed" (en rouge/check) pour LM Studio, Node, OpenClaw alors que le log dit clairement:
```
[SKIP] LM Studio
  LM Studio not installed
[SKIP] Node
  Node not installed
[SKIP] OpenClaw
  OpenClaw not installed
```

**Ce qu'il faut corriger:**
- Quand le statut est `SKIP` et que le composant n'est pas installé, afficher "Skipped" ou "Not installed" au lieu de "Already installed".
- Le badge "Already installed" ne doit apparaître QUE si le composant est réellement détecté comme présent sur la machine.

**Fichier source concerné:** `Sources/LocalClawInstallerApp.swift` (logique de rendu des badges de statut dans Step 3).

---

## Bug 3: Sélecteur de canal limité à WhatsApp uniquement (UX)

**Où:** Step 2 Confirm Options, section "OpenClaw Setup"

**Ce qui se passe:** L'écran ne propose qu'un toggle "Enable WhatsApp channel". Pas de mention de Discord, Telegram, Signal, iMessage ou autres canaux supportés par OpenClaw.

**Ce qu'il faut corriger:**
- Ajouter un sélecteur multi-canaux (checkboxes ou liste) permettant de choisir parmi: WhatsApp, Discord, Telegram, Signal, iMessage, etc.
- OU ajouter un texte clair "Vous pourrez configurer d'autres canaux après l'installation" avec un lien vers la doc.
- L'utilisateur doit comprendre immédiatement qu'il a le choix du mode de communication avec son IA.

**Fichier source concerné:** `Sources/LocalClawInstallerApp.swift` (section OpenClaw Setup dans l'écran Options).

---

## Bug 4: Pas de bouton "Ouvrir OpenClaw" après installation (UX CRITIQUE)

**Où:** Fin du flow d'installation (après Step 3 / Step 4)

**Ce qui se passe:** Une fois l'installation terminée, l'utilisateur ne sait pas quoi faire. Pas de bouton "Open OpenClaw", pas de "Lancer le dashboard", pas de prochaine étape claire. L'utilisateur est perdu.

**Ce qu'il faut corriger:**
- Ajouter un écran de fin avec:
  1. Statut clair de chaque composant (vert/rouge)
  2. Bouton principal "Ouvrir OpenClaw" (lance le gateway + ouvre le dashboard dans le navigateur)
  3. Bouton secondaire "Ouvrir LM Studio"
  4. Mini checklist "prochaines actions" (tester un message, connecter un canal, etc.)

**Fichier source concerné:** `Sources/LocalClawInstallerApp.swift` (écran Ready / post-install).

---

## Bug 5: Gateway crash en boucle après install (BLOQUANT)

**Où:** Après installation OpenClaw via LocalClaw, au lancement du service gateway

**Ce qui se passe:** Le LaunchAgent est installé et chargé, mais le process gateway crash immédiatement à chaque tentative de démarrage. Le log d'erreur (`~/.openclaw/logs/gateway.err.log`) montre en boucle:
```
Gateway start blocked: set gateway.mode=local (current: unset) or pass --allow-unconfigured.
Config write audit: /Users/bernadettedieumegard/.openclaw/logs/config-audit.jsonl
```

Le champ `gateway.mode` n'est jamais écrit dans la config par LocalClaw.

**Workaround trouvé:** Lancer manuellement `openclaw gateway --allow-unconfigured` dans le terminal (ce qui est inacceptable pour un client).

**Ce qu'il faut corriger:**
- Lors de l'installation OpenClaw, LocalClaw DOIT écrire `gateway.mode=local` dans le fichier de config `~/.openclaw/openclaw.json`.
- OU passer le flag `--allow-unconfigured` dans le LaunchAgent plist automatiquement.
- Le gateway doit démarrer sans intervention terminal après l'installation.

**Fichier source concerné:** `Sources/InstallerEngine.swift` (fonction d'installation OpenClaw, écriture config) et `Sources/LocalClawInstallerApp.swift` (Apply Changes).

---

## Bug 6: Modèle IA non injecté dans la config après install (BLOQUANT)

**Où:** Dashboard OpenClaw > Agents > main > Primary Model

**Ce qui se passe:** Après installation via LocalClaw avec "Kimi K2.5 Free" sélectionné, le champ Primary Model dans le dashboard est vide ("No configured models"). L'utilisateur doit aller manuellement configurer le modèle dans le dashboard.

**Ce qu'il faut corriger:**
- Lors du "Apply Changes", LocalClaw doit écrire le modèle choisi (ex: `kimi` ou `openrouter/moonshotai/kimi-k2.5`) dans la config OpenClaw (`~/.openclaw/openclaw.json`), section agents > main > model.
- Vérifier que le `.env` contient aussi `OPENCLAW_MODEL=kimi` si c'est le provider choisi.

**Fichier source concerné:** `Sources/LocalClawInstallerApp.swift` (fonction `copyEnvTemplate` et logique Apply Changes).

---

## Bug 7: Token gateway demandé avant install (UX MINEUR)

**Où:** Step 2 Confirm Options, section "Fill only required secrets"

**Ce qui se passe:** Le champ `OPENCLAW_GATEWAY_TOKEN` est demandé avant même qu'OpenClaw soit installé. C'est déroutant pour l'utilisateur qui ne comprend pas pourquoi on lui demande un token pour un logiciel pas encore installé.

**Ce qu'il faut corriger:**
- Soit expliquer clairement que c'est une pré-configuration ("Ce token sera utilisé après l'installation").
- Soit déplacer cette étape APRÈS l'installation d'OpenClaw.
- Soit générer automatiquement le token sans le montrer à l'utilisateur (flow simplifié).

---

## Bug 8: Incohérence log Update Center vs badges (UX)

**Où:** Update Center

**Ce qui se passe:** Les badges en haut montrent tout en vert (check), mais le log en bas affiche:
```
[SKIP] LM Studio not installed
[SKIP] Node not installed
[SKIP] OpenClaw not installed
```
C'est la même incohérence que le Bug 2 mais dans l'Update Center.

**Ce qu'il faut corriger:**
- Synchroniser les badges visuels avec le contenu réel du log.
- Un composant "not installed" ne doit jamais avoir un badge vert/check.

---

## Exigence produit fondamentale

**Le client ne doit JAMAIS ouvrir le Terminal.**

Tout le parcours (installation Homebrew, Node, LM Studio, OpenClaw, configuration gateway, injection modèle, démarrage service, ouverture dashboard) doit être géré intégralement depuis l'interface LocalClaw.

Chaque fois que l'utilisateur doit toucher au terminal, c'est un échec produit.

---

## Priorité de correction recommandée

1. **Bug 5** - Gateway crash (bloquant, empêche toute utilisation)
2. **Bug 6** - Modèle non injecté (bloquant, chat inutilisable)
3. **Bug 1** - Homebrew prérequis (bloquant, rien ne s'installe)
4. **Bug 4** - Pas de CTA post-install (UX critique, utilisateur perdu)
5. **Bug 2/8** - Badges trompeurs (UX critique, confusion client)
6. **Bug 3** - Sélecteur canal unique (UX, limitation perçue)
7. **Bug 7** - Token avant install (UX mineur)
