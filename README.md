# PuitsTrack — suivi des puits CPF Nawara

App Flutter de suivi quotidien des analyses de puits (CPF Nawara) : profil
local, tableau de bord du jour/semaine/mois, gestion des puits par zone,
statistiques, courbes de tendance et saisie rapide.

Le style est repris du projet de référence `C:\mobile-locations` (Material 3,
Riverpod, go_router, Google Fonts) avec une nouvelle identité visuelle
(ambre énergie `#FF7A33` / bleu nuit `#0B1E2D`) adaptée à un contexte
industriel gaz/pétrole.

## Mode local actuel

**Aucune configuration de backend n'est nécessaire pour l'instant.** Toutes
les données (puits, types d'analyse, historique) sont stockées dans une base
SQLite locale sur l'appareil (`lib/core/data/local_database.dart`, via
`sqflite`) — `flutter run` / `flutter build apk` fonctionnent directement,
sans `--dart-define`, sans compte à créer.

C'était initialement branché sur Supabase puis sur Firebase (base de données
partagée pour préparer une future app web) ; ce travail n'a pas été perdu,
il est conservé dans l'historique git de ce dépôt (`git log`) et pourra être
réactivé plus tard — seul `lib/core/data/wells_repository.dart` (et
`lib/core/auth/auth_providers.dart` pour l'identité) change d'implémentation
d'une version à l'autre : le reste de l'app (tous les écrans) n'a pas besoin
d'être retouché.

**Limite du mode local** : les données ne sont présentes que sur cet
appareil — pas de partage entre téléphones, pas de sauvegarde si l'appareil
est perdu ou réinitialisé.

## Lancer le projet

Sur votre machine avec le SDK Flutter installé :

```bash
flutter pub get
flutter run
```

Les dossiers `android/` et `ios/` sont déjà générés (via `flutter create
--platforms=android,ios --org com.apbs --project-name cpf_nawara_suivi .`,
qui ne touche pas à `lib/`, `pubspec.yaml` ni aux fichiers déjà présents — à
relancer seulement si ces dossiers venaient à manquer).

Pour générer un APK installable :

```bash
flutter build apk --release
```

## Ce qui est inclus

### Profil local + déverrouillage rapide
- **Onboarding** (`onboarding_screen.dart`)
- **Configuration du profil** (`profile_setup_screen.dart`) : nom, service,
  téléphone (optionnel) — une seule fois par appareil, sert à identifier
  l'opérateur dans l'historique
- **Code à 4 chiffres + empreinte** (`pin_setup_screen.dart`,
  `unlock_screen.dart`, `lib/core/auth/app_lock.dart`) : après la
  configuration du profil, l'app se déverrouille avec un code à 4 chiffres
  ou l'empreinte digitale, comme une app bancaire. Redemandé à chaque retour
  au premier plan après mise en arrière-plan. "Code oublié ?" permet d'en
  recréer un sans perdre le profil ni les données. Modifiable depuis
  **Compte → Modifier mon code**.
- **Multi-langue FR/EN** avec sélecteur (`lib/core/l10n/app_strings.dart`) —
  ajouter une langue = ajouter une entrée dans `supportedLocales` et dans la
  map de traductions
- Accès complet (saisie + configuration) tant que l'app tourne en mode local
  mono-appareil — pas encore de notion de rôles distribués (reviendra avec
  un backend partagé, voir ci-dessus)

### Fonctionnel (base locale)
- **Tableau de bord Jour / Semaine / Mois** (`dashboard_screen.dart`) :
  - Vue **Jour** : par puits actif, statut ✅ fait / ⏳ à faire / ⚠️ en retard
    pour chaque analyse attendue, avec l'opérateur et la valeur quand c'est
    fait
  - Vues **Semaine** / **Mois** : taux de complétion par puits (ex: 18/21
    analyses faites) + liste des occurrences manquantes (type + date
    attendue) — une occurrence compte comme faite si une valeur a été saisie
    le jour même où elle était due
- **Export Excel ou CSV** (icône en haut à droite — un choix de format est
  proposé à chaque export) :
  - Tableau de bord → toutes les analyses de la période affichée (jour/
    semaine/mois), tous puits
  - Alertes → les analyses en retard et les dernières valeurs hors seuil
  - Fiche puits → tout l'historique de ce puits
  - Liste des puits → icône par zone, exporte tout l'historique des puits de
    cette zone
  - Dans tous les cas, le fichier généré s'ouvre dans le volet de partage
    natif (enregistrer, envoyer par mail/WhatsApp...)
- **Liste des puits** (`wells_list_screen.dart`) : recherche, regroupement par
  zone/champ, statut actif/arrêté, progression du jour
- **Gestion des puits** (Admin, `wells_manage_screen.dart`, Compte → Gestion
  des puits) : ajout/modification/suppression d'un puits (nom, code, zone,
  actif/arrêté) — les zones sont libres, suggérées depuis celles déjà
  utilisées
- **Statistiques** (onglet dédié, `stats_screen.dart`), deux vues :
  - **Conformité** : par zone puis par puits, sur 7 jours / 30 jours / tout
    l'historique — nombre d'analyses saisies, taux de conformité aux seuils
  - **Seuils** : diagramme par puits actif montrant, pour chaque analyse,
    où se situe la dernière valeur par rapport à son seuil attendu (jauge
    horizontale, vert = dans la plage, rouge = hors seuil) — vue d'ensemble
    sans historique, juste l'état actuel
- **Tendance de production** (sur le tableau de bord, vue d'ensemble) :
  mini-courbe de la production totale (tous puits actifs) des 7 derniers
  jours, au choix huile/gaz/eau — un coup d'œil sur l'évolution générale
  sans entrer dans le détail puits par puits
- **Fiche puits** (`well_detail_screen.dart`) : carte **Production** (débits
  huile/gaz/eau, dernières valeurs + courbes superposées sur 30 jours),
  dernières valeurs par type d'analyse (avec alerte visuelle hors seuil) +
  aperçu des 20 dernières analyses — **chaque ligne est modifiable ou
  supprimable** (correction d'une saisie d'un jour précédent, pas seulement
  celle du jour même)
- **Historique complet** (`well_history_screen.dart`, "Voir tout
  l'historique" depuis la fiche puits) : toutes les analyses d'un puits,
  groupées par jour (Aujourd'hui / Hier / date), avec filtre par type
  d'analyse, statut vert/rouge selon le seuil, service/opérateur/heure et
  commentaire affichés pour chaque ligne, et export Excel/CSV dédié
- **Saisie rapide** (`quick_entry_screen.dart`) : puits → type → valeur →
  service → commentaire, avec détection de doublon (analyse déjà saisie
  aujourd'hui) et confirmation si la valeur sort du seuil attendu
- **Courbes de tendance** (`trend_screen.dart`) : évolution d'un paramètre
  pour un puits, variation vs valeur précédente — menu **"Comparer avec"**
  pour superposer un second paramètre (ex: Huile + BSW) sur le même
  graphique, légendé, chaque courbe à sa propre échelle
- **Alertes** (`alerts_screen.dart`) : analyses en retard et dernières
  valeurs hors seuil, tous puits confondus
- **Types d'analyses paramétrables** (`analysis_types_screen.dart`) :
  ajout/modification/**suppression** (nom, unité, seuils, fréquence) — la
  suppression efface aussi tout l'historique associé, pour éviter les
  références orphelines
- 5 puits (Puits Nord 1/2, Puits Sud 1/2/3) et 10 types d'analyse pré-remplis
  au premier lancement, dont les 3 débits de production huile/gaz/eau (voir
  `local_database.dart`) pour ne pas démarrer sur un écran vide ; aucun
  historique de démonstration n'est inventé. Renommables/supprimables à tout
  moment depuis **Compte → Gestion des puits**.

### Design
- Thème clair/sombre Material 3 (`lib/core/theme/app_theme.dart`)
- Icône de l'app : derrick stylisé (généré par `tool/generate_icon.py` avec
  Pillow, appliqué aux deux plateformes via `flutter_launcher_icons` — relancer
  `python tool/generate_icon.py && dart run flutter_launcher_icons` après toute
  modification du dessin)

## Limites actuelles (hors scope de cette phase)

- Pas de partage de données entre appareils (voir "Mode local actuel")
- Pas de pièces jointes photo/PDF sur une analyse
- Pas d'import Excel de l'historique (l'export existe, pas l'import)
- Pas de notifications push (rappels, alertes hors seuil)
- Pas de gestion de rôles distincts (Admin/Utilisateur/Lecteur) tant que
  l'app tourne en local mono-appareil
