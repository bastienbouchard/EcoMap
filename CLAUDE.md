# EcoMap — Consignes pour Claude

## Projet
Application Flutter iOS (TestFlight / App Store) — OrignalScan.
Dépôt : `bastienbouchard/EcoMap`

## Build & déploiement
- **Branche de travail : `master`** — Bastien build toujours depuis master dans Codemagic.
- Toujours merger les branches de travail sur `master` avant de terminer.
- **Incrémenter le build number** (`pubspec.yaml` → `version: x.y.z+N`) à chaque série de modifications avant de pousser, sinon Apple rejette le build.
  - Format : `1.0.0+N` où N est le numéro séquentiel.
  - Build actuel : **6** — prochain build doit être **7+**.

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
