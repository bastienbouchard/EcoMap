# EcoMap — Consignes pour Claude

## Projet
Application Flutter iOS (TestFlight / App Store) — OrignalScan.
Dépôt : `bastienbouchard/EcoMap`

## Build & déploiement
- **Branche de travail : `master`** — Bastien build toujours depuis master dans Codemagic.
- Toujours merger les branches de travail sur `master` avant de terminer.
- **Incrémenter le build number** (`pubspec.yaml` → `version: x.y.z+N`) à chaque série de modifications avant de pousser, sinon Apple rejette le build.
  - Format : `1.0.0+N` où N est le numéro séquentiel.
  - Build actuel : **415** — prochain build doit être **416+**.
  - Version actuelle : **1.0.30**
  - Codemagic auto-incrémente ET repousse dans git — pas besoin de bumper manuellement.

## Procédure avant chaque push (checklist)
1. `git status` — vérifier qu'il n'y a pas de fichiers non voulus (`.env`, secrets, binaires)
2. `pubspec.yaml` → confirmer que le build number est **supérieur au dernier build uploadé**
   - Si Codemagic a auto-incrémenté depuis le dernier push, le numéro dans git est déjà à jour
   - Si on push sans passer par Codemagic, bumper manuellement : `version: 1.0.30+N`
3. Si la **version string** (ex: `1.0.30`) a déjà été **approuvée sur l'App Store**, la bumper à `1.0.31`
4. `git push` → lancer le build sur Codemagic

## Stack technique
- Flutter / Dart
- iOS natif (flutter_compass pour le magnétomètre)
- Firebase (observations, groupes)
- Open-Meteo API (météo/vent)
- flutter_map + OpenStreetMap / Satellite
- Codemagic CI/CD → TestFlight → App Store

## Conventions
- Langue de l'interface : **français canadien**
- Pas de commentaires évidents dans le code
- Pas de fichiers README ou docs sauf si demandé
- Commits en anglais, messages courts et descriptifs
