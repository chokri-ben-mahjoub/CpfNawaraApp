# PuitsTrack — suivi personnel des analyses de puits

App Flutter personnelle de suivi quotidien des analyses de puits : profil
local, tableau de bord du jour/semaine/mois, gestion des puits par zone,
statistiques, courbes de tendance et saisie rapide.

Le style est repris du projet de référence `C:\mobile-locations` (Material 3,
Riverpod, go_router, Google Fonts) avec une nouvelle identité visuelle
(ambre énergie `#FF7A33` / bleu nuit `#0B1E2D`) adaptée à un contexte
industriel gaz/pétrole.

## Mode local (par défaut)

**Aucune configuration n'est nécessaire pour utiliser l'app seule.** La
synchronisation entre appareils est optionnelle (voir plus bas). Toutes
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

Les dossiers `android/` et `ios/` sont déjà générés. S'ils venaient à
manquer : `flutter create --platforms=android,ios --project-name puitstrack .`
(ne touche pas à `lib/` ni à `pubspec.yaml`), puis remettre l'identifiant
**`com.puitstrack.app`** (`applicationId`/`namespace` dans
`android/app/build.gradle.kts`, `PRODUCT_BUNDLE_IDENTIFIER` côté iOS) et
`MainActivity.kt` (canal de téléchargement, écran protégé).

> Identifiant changé le 09/10/2026 (`com.apbs.cpf_nawara_suivi` →
> `com.puitstrack.app`, application personnelle). Android considère
> l'ancienne et la nouvelle comme deux apps distinctes : migrer les données
> par Réglages › Sauvegarde (Envoyer dans l'ancienne, Restaurer dans la
> nouvelle), puis désinstaller l'ancienne.

Pour générer un APK installable :

```bash
flutter build apk --release
```

## Module Usine CPF (onglet « Usine »)

Points de prélèvement et analyses de laboratoire de l'usine de traitement de
gaz, par circuit (`lib/core/plant/`, `lib/features/plant/`).

- **Points** (table `sample_points`) : condensat C1 Inlet Separator, C2 Test
  Separator, C3 avant rebouilleur, C4 bac de stockage ; eau produite W1 Test
  Separator, W2 Inlet Separator, W3 séparateur W/C, W4 eau du séparateur
  d'entrée vers W/C ; gaz G1 Test Separator, G2 Inlet Separator, G3 gaz
  export ; amine LA (pauvre, pompe HP) et RA (riche, flash drum).
- **Paramètres** (`plant_catalog.dart`, une valeur numérique par paramètre) :
  condensat densité, BSW, water cut, salinité, chlorures ; eau pH, densité,
  salinité, TDS, TSS, aspect (choix), fer, TPH ; gaz composition (C1, C2,
  C3, C4+, CO2, N2 en mol %) + H2S, et pour G3 points de rosée HC et eau ;
  amine concentration, moussage, pH, %PZ, conductivité, salinité, CO2
  loading, TDS, TSS.
- **Données** : `plant_analyses` (valeurs en JSON, source, opérateur ; une
  analyse par point et par jour, id = `<point>_<date>`), `plant_thresholds`
  (min/max par point et paramètre). Base SQLite locale (schéma v7),
  synchronisée par Firebase comme le reste.
- **Écrans** : schéma de procédé interactif (toucher un point → dernières
  analyses ; vert = dans les seuils, rouge = hors seuil, gris = pas d'analyse
  ce jour), liste par circuit, fiche point (valeurs, historique, seuils),
  saisie (valeur hors seuil signalée en direct, total de composition),
  courbes de tendance avec bande de seuil, alertes (onglet Alertes : hors
  seuil et non analysés du jour), rapport journalier PDF par circuit ou
  complet (`plant_report.dart`, paquet `pdf`), export Excel/CSV de toutes
  les analyses (une feuille par circuit).
- **Schémas configurables** (table `plant_schemas`, v11,
  `plant_schema_screens.dart`) : schéma de procédé intégré, **image
  importée** (photo, scan ou capture du PFD, réduite et compressée en JPEG
  < 700 Ko pour tenir dans un document Firestore, `schema_image.dart`) ou
  fond quadrillé. L'admin ajoute un schéma (Usine › Schéma › icône image, ou
  Administration › Schémas de l'usine), puis place les points en les faisant
  glisser ; positions en fractions de la largeur / hauteur
  (`positions_json`).
- **Paramètres et modèles** (Administration, `params_screen.dart`, v12) :
  paramètres personnalisés (table `plant_params` : nom, unité libre non
  convertie, nombre ou liste de choix avec choix conformes) et modèles de
  paramètres (`plant_profiles` : nouveaux modèles, ou modèle intégré modifié
  sous le même id, remis d'origine en supprimant la ligne). Les points qui
  suivent un modèle sans changement suivent ses modifications. Suppression
  refusée tant qu'un point ou un modèle s'en sert.
- **Vue « Courbes »** (`plant_trends_view.dart`) : plus fortes variations
  entre les deux dernières analyses, puis par circuit (groupe de points) les
  courbes lissées d'un paramètre pour tous les points ; hausse en orange,
  baisse en bleu (pastille ▲/▼ en %, aussi dans le tableau des valeurs).
- Aucun seuil n'est prédéfini : à régler par point (icône réglages de la
  fiche point), selon les spécifications de l'usine.

## Entreprises, synchronisation et Administration (Firebase)

Tout se gère dans l'app : aucun fichier à modifier, aucune console pour les
clients. Un seul projet Firebase (`puitstrack`, intégré) héberge toutes les
entreprises, chacune isolée par les règles Firestore.

### Installation (premier lancement)

- **Créer mon entreprise** : nom de l'entreprise + e-mail + mot de passe ;
  le créateur devient **admin**.
- **Rejoindre mon entreprise** : code d'invitation `ABCD-EFGH` (ou QR code)
  créé par l'admin dans Administration › Utilisateurs › **Inviter** (usage
  unique, 7 jours, e-mail imposé facultatif, rôle fixé par l'admin).
- **J'ai déjà un compte** : l'entreprise et ses données sont retrouvées.
- **Personnel (sur cet appareil)** : local, sans compte.
- *Options avancées* : projet Firebase personnalisé (coller la configuration
  ou scanner un QR) ; il faut alors y publier `firestore.rules`.

Un appareil est lié à une entreprise : s'il passe à une autre, une
sauvegarde JSON est faite puis la base locale est remise à zéro.

### Mise en ligne (propriétaire du projet, une fois par version)

```
firebase login
powershell -ExecutionPolicy Bypass -File tool\deploy.ps1            # règles + site web
powershell -ExecutionPolicy Bypass -File tool\deploy.ps1 -Functions # + Cloud Functions (forfait Blaze)
```

Les **Cloud Functions** (`functions/index.js`, Admin SDK, europe-west1 :
`createMember`, `setMemberActive`, `deleteMember`, `setMemberPassword`) sont
facultatives. Sans elles (forfait Spark gratuit), l'app passe en « mode
simple » : comptes créés par inscription REST, désactivation par
`actif: false` (plus aucun accès aux données, mais la connexion reste
possible). Chaque fonction vérifie que l'appelant est admin actif de la même
entreprise que le compte visé.

### Rôles (`companies/{cid}/members/{uid}` : email, nom, role, actif)

| Rôle | Droits |
|---|---|
| `admin` | tout, dont l'Administration |
| `ingenieur` | analyses (puits + usine) et interventions |
| `operateur` | analyses (puits + usine) |
| `lecteur` | consultation |

Compte `actif: false` : plus aucun accès. Les règles Firestore lisent le
rôle (`companies/{cid}/members/{uid}.role`) ; l'app masque et bloque aussi les écrans
(`/admin/*` réservé à l'admin, saisie masquée au lecteur, interventions
réservées à l'ingénieur et à l'admin). Sans compte d'équipe, l'utilisateur
de l'appareil est administrateur de ses données locales.

### Modèle Firestore

```
accounts/{uid}                         { companyId }            une entreprise par compte
inviteCodes/{code}                     { companyId, companyName, role, expiresAt }   aperçu public
config/rules_v3                        sonde de version des règles
companies/{cid}                        { name, ownerUid, createdAt }
companies/{cid}/members/{uid}          { email, nom, role, actif, service, invite, updatedAt }
companies/{cid}/invites/{code}         { role, email, expiresAt, used, usedBy, usedAt, createdBy }
companies/{cid}/meta/sync              { lastChange }   repère : une seule lecture si rien n'a changé
companies/{cid}/audit/{id}             { uid, email, nom, action, table, docId, label, at }
companies/{cid}/{table}/{id}           données : wells, analysis_types, analysis_records,
                                       interventions, sample_points, plant_circuits,
                                       plant_analyses, plant_thresholds, app_config
```

Une collection par table de la base locale, sous l'entreprise. Valeurs toujours en SI ; l'affichage SI/API se règle par
appareil.

### Administration (icône bouclier en haut, ou Réglages › Administration)

`lib/features/admin/presentation/` :

- **Utilisateurs et rôles** (`users_screen.dart`) : entreprise (renommer,
  état des fonctions serveur), invitations en attente, membres ; **Inviter**
  (code + QR + partage), ajout direct avec mot de passe provisoire,
  rôle, désactivation, retrait, nouveau mot de passe (fonctions) ou e-mail
  de réinitialisation.
- **Puits** (`wells_manage_screen.dart`) : nom, code, champ, type, statut,
  latitude/longitude (lien carte), Pr.
- **Points de prélèvement** (`sample_points_screen.dart`) : code, circuit,
  équipement, paramètres analysés au choix (pH, densité, BSW, salinité,
  H2S...).
- **Seuils et alertes** (`thresholds_screen.dart`) : min / max / alerte
  activée par point et paramètre ; heure limite des analyses « non
  reçues » (onglet Alertes).
- **Données** (`data_admin_screen.dart`) : import CSV/Excel (formats long,
  large et usine, aperçu, doublons ignorés, modèles téléchargeables ; les
  exports de l'app se réimportent), export complet, sauvegarde JSON.
- **Projet Firebase** (`firebase_project_screen.dart`) : projet utilisé,
  test réseau / compte / base / règles / fonctions, règles à copier
  (projet personnalisé).
- **Journal d'audit** (`audit_screen.dart`) : chaque envoi à l'équipe est
  enregistré (qui, quoi, quand), filtres par utilisateur et par donnée.

Réglages de l'appareil : unités **SI / API** (psi, °F, bbl/j, scf/j,
°API — conversion au chargement et à l'enregistrement,
`lib/core/units/unit_system.dart`), langue FR/EN, thème sombre, état de la
connexion et de la synchronisation.

### Synchronisation (`lib/core/sync/`)

- La base locale SQLite reste la source des écrans (l'app marche hors
  ligne). Chaque ligne porte `updated_at` + `dirty`, les suppressions vont
  dans `sync_deletions`. Lecture des changements du serveur (`syncedAt` >
  dernière lecture, 2 min de recouvrement) puis envoi des modifications
  locales que le rôle autorise (les autres sont abandonnées au profit de la
  version de l'équipe) ; le plus récent gagne en cas de conflit.
  Déclenchée 2 s après chaque saisie, toutes les 60 s, et au retour au
  premier plan.
- **Sans SDK natif** : API REST Firebase (Identity Toolkit + Firestore) en
  pur Dart → même code sur Android, Windows et web.
- **Tests** : `test/sync_emulator_test.dart` (entreprise, invitations,
  isolation entre entreprises, rôles, Cloud Functions, deux appareils,
  conflit, repère) contre les émulateurs : `cd functions && npm install`,
  puis `firebase emulators:start --only auth,firestore,functions --project
  puitstrack` (Java requis), puis `flutter test`. App branchée sur les
  émulateurs : `--dart-define=SYNC_EMULATOR=true`. Après modification de
  `firestore.rules` : `python tool/gen_rules_dart.py`.

## Windows (installateur Setup.exe)

Une seule commande (PowerShell, depuis la racine du projet) :

```powershell
powershell -ExecutionPolicy Bypass -File installer\build_setup.ps1
```

→ `installer\Output\PuitsTrack-Setup-<version>.exe` (≈12 Mo), installable sur
un PC neuf sans rien d'autre (DLL Visual C++ `msvcp140`, `vcruntime140`,
`vcruntime140_1` et `sqlite3.dll` incluses). Le script fait
`flutter build windows --release`, copie les DLL VC++ depuis Visual Studio
(`VC\Redist`), puis compile `installer\puitstrack.iss` (Inno Setup 6 :
`winget install JRSoftware.InnoSetup`).

- Installation sans droits admin dans `%LOCALAPPDATA%\Programs\PuitsTrack`
  (`Setup.exe /ALLUSERS` pour `C:\Program Files\PuitsTrack`, droits admin).
- Raccourcis Bureau + Menu Démarrer, « Lancer PuitsTrack » à la fin,
  désinstallateur dans « Applications installées ».
- Mise à jour : relancer un Setup plus récent (même `AppId`), l'app ouverte
  est fermée automatiquement. Données dans `%APPDATA%\PuitsTrack\PuitsTrack`,
  conservées à la désinstallation.
- Base locale via `sqflite_common_ffi` (`lib/core/data/db_factory_io.dart`),
  « Télécharger » → `Téléchargements\PuitsTrack`.
- `windows/CMakeLists.txt` définit `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`
  : `local_auth_windows` compile encore avec `/await`, refusé par défaut par
  Visual Studio 2026.

## Web

```bash
powershell -ExecutionPolicy Bypass -File tool\build_web.ps1   # build + mode hors ligne
python tool/serve_web.py        # test local : http://localhost:8765
```

- **Hors ligne** : `web/offline_sw.js` (service worker) garde l'app en
  cache dès la première ouverture ; ensuite elle s'ouvre et fonctionne sans
  réseau (saisies enregistrées dans le navigateur, envoyées à l'équipe au
  retour du réseau). `tool/gen_offline_sw.py` (appelé par
  `tool/build_web.ps1`) y inscrit la liste des fichiers et une version :
  chaque nouveau build remplace le cache. `web/flutter_bootstrap.js`
  l'enregistre (à la place du service worker Flutter, obsolète) et demande
  au navigateur un stockage persistant. Sans `gen_offline_sw.py`, le cache
  se remplit simplement au fil des chargements.

- Base SQLite en WebAssembly (`web/sqlite3.wasm` + `web/sqflite_sw.js`,
  générés par `dart run sqflite_common_ffi_web:setup`), données dans le
  navigateur (IndexedDB) — propres à chaque navigateur/PC.
- Exports et sauvegardes = téléchargements du navigateur ; pas de
  sauvegarde automatique ni de rappel (non pertinents dans un onglet).
- Grand écran (web, PC, tablette ≥ 900 px) : menu latéral, contenu centré,
  grilles multi-colonnes (`lib/core/widgets/responsive.dart`) ; installable
  comme une app (PWA, `web/manifest.json`).
- Mise en ligne sur Firebase Hosting (projet `puitstrack`, `firebase.json`
  déjà prêt) : `npm install -g firebase-tools`, `firebase login`, puis
  `tool\deploy.ps1` (voir « Mise en ligne »).

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
- **Export Excel ou CSV, à télécharger ou à partager** (icône ⬇ en haut à
  droite) : une feuille propose le format (Excel ou CSV, le dernier choix est
  mémorisé) puis **Télécharger** — le fichier est enregistré directement dans
  **Téléchargements › PuitsTrack** sur le téléphone, avec un bouton « Ouvrir »
  — ou **Partager** (WhatsApp, e-mail, Drive...). Côté Android, le
  téléchargement passe par MediaStore (aucune permission à partir
  d'Android 10, permission de stockage demandée une fois jusqu'à Android 9),
  voir `MainActivity.kt` + `lib/core/export/download_saver.dart`. Sur iOS, seul
  le partage existe (il propose « Enregistrer dans Fichiers »).
  - En Excel, une feuille par thème ; en CSV (séparateur `;`, virgule
    décimale, pour Excel FR), un fichier par thème. Les nombres et dates sont
    exportés comme de vraies valeurs (triables, utilisables en formules)
  - Tableau de bord → analyses + production/ratios + interventions de la
    période affichée (jour/semaine/mois), tous puits
  - Alertes → les analyses en retard et les dernières valeurs hors seuil
  - Fiche puits → analyses, production + ratios (GOR, WOR, GLR, PI) et
    journal des interventions de ce puits
  - Liste des puits → icône par zone, mêmes 3 thèmes pour les puits de la
    zone (après filtres), sur la période filtrée (tout l'historique quand la
    période est « Aujourd'hui »)
  - Comparaison, courbe de déclin, journal des interventions → synthèse +
    données détaillées
- **Liste des puits** (`wells_list_screen.dart`) : recherche par nom/code et
  filtres **champ/zone**, **statut** (actifs/arrêtés) et **période**
  (aujourd'hui, 7/30/90 jours, 12 mois, tout, dates personnalisées) ;
  regroupement par zone ; chaque puits affiche la progression du jour ou,
  sur une période, le nombre d'analyses, de valeurs hors seuil et
  d'interventions
- **Gestion des puits** (Admin, `wells_manage_screen.dart`, Compte → Gestion
  des puits) : ajout/modification/suppression d'un puits (nom, code, zone,
  actif/arrêté) — les zones sont libres, suggérées depuis celles déjà
  utilisées
- **Statistiques** (onglet dédié, `stats_screen.dart`) : accès à
  **Comparer**, mêmes filtres (recherche, champ, statut, période), deux vues :
  - **Conformité** : par zone puis par puits, sur la période choisie —
    nombre d'analyses saisies, taux de conformité aux seuils
  - **Seuils** : diagramme par puits actif montrant, pour chaque analyse,
    où se situe la dernière valeur par rapport à son seuil attendu (jauge
    horizontale, vert = dans la plage, rouge = hors seuil) — vue d'ensemble
    sans historique, juste l'état actuel
- **Tendance de production** (sur le tableau de bord, vue d'ensemble) :
  mini-courbe de la production totale (tous puits actifs) des 7 derniers
  jours, au choix huile/gaz/eau — un coup d'œil sur l'évolution générale
  sans entrer dans le détail puits par puits
- **Fiche puits** (`well_detail_screen.dart`) : carte **Production** (débits
  huile/gaz/eau, dernières valeurs + courbes superposées sur 30 jours, avec
  les interventions en marqueurs), **Indicateurs calculés**, **Courbe de
  déclin**, **Interventions** (voir « Analyse » ci-dessous),
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
### Analyse (`lib/core/analysis/`, `lib/features/analysis/`, `lib/features/interventions/`)
- **Indicateurs calculés automatiquement** (`production_metrics.dart`), par
  jour, à partir de la dernière saisie du jour de chaque débit :
  GOR = Qg/Qo, WOR = Qw/Qo, GLR = Qg/(Qo+Qw), PI = (Qo+Qw)/(Pr − Pwf).
  Le PI utilise la **pression de gisement Pr** du puits (champ optionnel dans
  Gestion des puits, ou « Renseigner » sur la fiche puits) et le type
  d'analyse **Pression de fond (Pwf)**, ajouté en fréquence « À la demande »
  (jamais compté « à faire » ni en retard) ; le débit utilisé est celui du
  même jour ou des 3 jours précédents. Chaque indicateur a sa courbe
  (`ratio_trend_screen.dart`)
- **Courbe de déclin** (`decline.dart`, `decline_screen.dart`) : déclin
  exponentiel d'Arps (b = 0) ajusté par régression de ln(q) sur le temps —
  déclin effectif annuel/mensuel, nominal, D, qi, R², prévision à 30/90/180
  jours, cumul prévu, date d'atteinte d'un débit limite ; échelle log ; en
  mode Auto, l'ajustement repart du lendemain de la dernière intervention
- **Comparaison** (`compare_screen.dart`, Stats › Comparer ou ⇄ sur la fiche
  puits) : deux puits sur une même période, ou un puits sur deux périodes —
  dates libres ou **avant/après une intervention** (± 7 à 90 jours), sur
  n'importe quel paramètre (débits, ratios, analyses) : courbes superposées,
  tableau mesures/moyenne/min/max/première/dernière avec écart %, phrase de
  synthèse
- **Journal des interventions** (`interventions_screen.dart`) : date, type
  (workover, stimulation, fracturation, changement de duse...), coût + devise,
  résultat (succès/partiel/échec/à évaluer), description ; coût total ;
  marqueurs violets sur toutes les courbes du puits (table `interventions`,
  migration de base v5)
- Tests : `test/analysis_test.dart` (calculs, filtres, CSV/Excel) et
  `test/screens_smoke_test.dart` (rendu des écrans sur un téléphone avec des
  données réalistes, échoue en cas de débordement) — `flutter test`

### Suite du fonctionnel
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

### Réglages (`lib/features/settings/`, icône ⚙ en haut à droite ou Compte › Réglages)
Inspirés de l'app de référence `E:\mobile-locations`, stockés sur l'appareil
(`lib/core/settings/app_settings.dart`, SharedPreferences) :
- **Profil** : modifier nom, service, téléphone (le code à 4 chiffres reste
  valable)
- **Apparence** : thème Clair / Auto (suit le téléphone) / Sombre, langue
- **Sécurité** : déverrouillage par empreinte (activable), changer le code,
  **verrouillage automatique** (immédiat, 30 s, 1, 5 ou 15 min en
  arrière-plan), **écran protégé** (bloque les captures, masque l'app dans les
  applications récentes — Android FLAG_SECURE)
- **Sauvegarde** (`lib/core/backup/backup_service.dart`) : sauvegarde complète
  (puits, types et seuils, analyses, interventions) en JSON —
  « Enregistrer sur le téléphone » (Téléchargements › PuitsTrack ›
  Sauvegardes) ou « Envoyer » (Drive, e-mail, WhatsApp) ; **restauration**
  avec aperçu (date, nombre de puits/analyses/interventions) et copie de
  sécurité automatique des données actuelles avant remplacement ;
  **sauvegarde automatique** chaque jour ou chaque semaine (par défaut) à
  l'ouverture de l'app, dans 2 fichiers utilisés à tour de rôle ; date de la
  dernière sauvegarde mise en évidence si elle date de plus de 7 jours
- **Rappels** (`lib/core/notifications/reminder_service.dart`) : notification
  quotidienne de saisie à l'heure choisie (notification locale, sans
  serveur), sautée si toutes les analyses du jour sont déjà saisies
- **Saisie et export** : service pré-sélectionné à la saisie (celui du profil
  par défaut), devise par défaut des interventions, format CSV (Excel FR
  `;` + virgule décimale, ou international `,` + point)
- **Paramétrage** (puits, types et seuils), **Données** (nombre de puits,
  analyses, interventions, taille de la base), **À propos** (version)

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
- Pas de notifications d'alerte hors seuil (seul le rappel quotidien de
  saisie existe, en notification locale)
- Pas de gestion de rôles distincts (Admin/Utilisateur/Lecteur) tant que
  l'app tourne en local mono-appareil
