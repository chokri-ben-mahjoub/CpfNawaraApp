# Suivi Puits — CPF Nawara

App Flutter de suivi quotidien des analyses de puits (CPF Nawara) : connexion,
inscription, tableau de bord du jour, fiches puits, courbes de tendance et
saisie rapide — avec une **vraie base de données partagée (Firebase /
Firestore)** et un **fonctionnement hors-ligne natif** (le téléphone reste
utilisable sans réseau, les saisies se synchronisent toutes seules au retour
de la connexion).

Le style est repris du projet de référence `C:\mobile-locations` (Material 3,
Riverpod, go_router, Google Fonts) avec une nouvelle identité visuelle
(ambre énergie `#FF7A33` / bleu nuit `#0B1E2D`) adaptée à un contexte
industriel gaz/pétrole.

## Architecture

- **UI** : Flutter + Riverpod + go_router, Material 3 clair/sombre.
- **Backend partagé** : [Firebase](https://firebase.google.com) — Firestore
  (base de données) + Authentication, pensé pour être réutilisé tel quel par
  une future app web (le SDK Firebase Web existe pour ça).
- **Hors-ligne natif** : Firestore garde un cache local et synchronise tout
  seul dès que le réseau revient — pas de base locale ni de service de
  synchro à maintenir nous-mêmes (`lib/core/data/wells_repository.dart` lit
  et écrit directement les collections Firestore).
- **Authentification** : email + mot de passe (Firebase Auth), demandée
  **une seule fois par appareil** — ensuite l'app se déverrouille avec un
  **code à 4 chiffres ou l'empreinte digitale** (voir plus bas). Le numéro de
  téléphone est conservé comme info de profil, pas comme identifiant de
  connexion.

## Configurer Firebase (à faire une fois, avant de lancer l'app)

1. Créer un compte sur [console.firebase.google.com](https://console.firebase.google.com)
   (un compte Google suffit) et créer un nouveau projet.
2. Dans le projet → **Build → Authentication → Get started**, activer le
   fournisseur **Email/Password**.
3. Dans **Build → Firestore Database → Create database**, créer une base
   (mode production), puis dans l'onglet **Règles**, coller tout le contenu
   de [`firebase/firestore.rules`](firebase/firestore.rules) et **Publier**.
   Ces règles jouent le même rôle que les policies RLS : lecture ouverte à
   tout utilisateur connecté, écriture restreinte par rôle.
4. Ajouter une application : **Paramètres du projet (⚙️) → Vos applications
   → Ajouter une application → Web** (même pour une app mobile : on récupère
   juste les clés de config, pas besoin de `google-services.json`/plist).
   Notez les 5 valeurs affichées : `apiKey`, `appId`, `messagingSenderId`,
   `projectId`, `storageBucket`.
5. **Donner les droits Admin au premier compte** : une fois inscrit dans
   l'app, ouvrir **Firestore Database → Données → profiles** dans la
   console Firebase, trouver le document correspondant à votre compte (son
   id = votre UID Firebase, visible dans **Authentication → Users**) et
   changer le champ `role` de `"user"` à `"admin"`. C'est la seule façon de
   gérer les rôles pour l'instant (pas encore d'écran d'administration des
   rôles dans l'app).
6. (Optionnel) Pour retrouver des puits/types de démonstration, créer à la
   main quelques documents dans les collections `wells` (champs `code`,
   `name`, `active`) et `analysisTypes` (champs `label`, `unit`, `min`, `max`,
   `frequency` = `"daily"`/`"weekly"`/`"monthly"`) depuis **Firestore
   Database → Données → Démarrer une collection**.

## Lancer le projet

Sur votre machine avec le SDK Flutter installé :

```bash
flutter pub get
flutter run \
  --dart-define=FIREBASE_API_KEY=xxxx \
  --dart-define=FIREBASE_APP_ID=xxxx \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=xxxx \
  --dart-define=FIREBASE_PROJECT_ID=xxxx \
  --dart-define=FIREBASE_STORAGE_BUCKET=xxxx
```

Sans ces `--dart-define`, l'app affiche un écran d'erreur expliquant comment
les renseigner (voir `lib/core/config/env.dart`).

Les dossiers `android/` et `ios/` sont déjà générés (via `flutter create
--platforms=android,ios --org com.apbs --project-name cpf_nawara_suivi .`,
qui ne touche pas à `lib/`, `pubspec.yaml` ni aux fichiers déjà présents — à
relancer seulement si ces dossiers venaient à manquer).

## Ce qui est inclus

### Authentification (Firebase Auth) + déverrouillage rapide
- **Onboarding** (`onboarding_screen.dart`)
- **Connexion** par email + mot de passe (`login_screen.dart`) + carrousel de
  présentation — nécessaire **une seule fois** par appareil
- **Inscription** (`signup_screen.dart`) : nom, service, téléphone (optionnel),
  email + mot de passe — le compte est actif immédiatement (pas de
  confirmation par email à attendre)
- **Code à 4 chiffres + empreinte** (`pin_setup_screen.dart`,
  `unlock_screen.dart`, `lib/core/auth/app_lock.dart`) : après la première
  connexion, l'app ne redemande plus l'email/mot de passe — elle se
  déverrouille avec un code à 4 chiffres ou l'empreinte digitale, comme une
  app bancaire. Le code est redemandé à chaque retour au premier plan après
  mise en arrière-plan. "Code oublié ?" déconnecte et repasse par
  l'email/mot de passe. Modifiable depuis **Compte → Modifier mon code**.
- **Mot de passe oublié** (`forgot_password_screen.dart`) : envoie un email
  avec un lien géré directement par une page Firebase (pas besoin de deep
  link ni d'écran dédié dans l'app)
- **Multi-langue FR/EN** avec sélecteur (`lib/core/l10n/app_strings.dart`) —
  ajouter une langue = ajouter une entrée dans `supportedLocales` et dans la
  map de traductions
- **Rôles** (Admin / Utilisateur / Lecteur) stockés dans `profiles.role`
  (Firestore), changés depuis la console Firebase (voir ci-dessus)

### Fonctionnel (Firestore, hors-ligne natif)
- **Tableau de bord Jour / Semaine / Mois** (`dashboard_screen.dart`) :
  - Vue **Jour** : par puits actif, statut ✅ fait / ⏳ à faire / ⚠️ en retard
    pour chaque analyse attendue, avec l'opérateur et la valeur quand c'est
    fait
  - Vues **Semaine** / **Mois** : taux de complétion par puits (ex: 18/21
    analyses faites) + liste des occurrences manquantes (type + date
    attendue) — une occurrence compte comme faite si une valeur a été saisie
    le jour même où elle était due
- **Export Excel** (icône en haut à droite) :
  - Tableau de bord → toutes les analyses de la période affichée (jour/
    semaine/mois), tous puits
  - Alertes → les analyses en retard et les dernières valeurs hors seuil
  - Fiche puits → tout l'historique de ce puits
  - Dans les trois cas, le fichier `.xlsx` généré s'ouvre dans le volet de
    partage natif (enregistrer, envoyer par mail/WhatsApp...)
- **Liste des puits** (`wells_list_screen.dart`) : recherche, statut actif/
  arrêté, progression du jour
- **Fiche puits** (`well_detail_screen.dart`) : dernières valeurs par type
  d'analyse (avec alerte visuelle hors seuil) + historique récent
- **Saisie rapide** (`quick_entry_screen.dart`) : puits → type → valeur →
  service → commentaire, avec détection de doublon (analyse déjà saisie
  aujourd'hui) et confirmation si la valeur sort du seuil attendu —
  fonctionne hors-ligne, synchronisée automatiquement au retour du réseau
- **Courbes de tendance** (`trend_screen.dart`) : évolution d'un paramètre
  pour un puits, variation vs valeur précédente
- **Alertes** (`alerts_screen.dart`) : analyses en retard et dernières
  valeurs hors seuil, tous puits confondus
- **Types d'analyses paramétrables** (Admin, `analysis_types_screen.dart`) :
  ajout/modification (nom, unité, seuils, fréquence), synchronisé vers
  Firestore

### Design
- Thème clair/sombre Material 3 (`lib/core/theme/app_theme.dart`)

## Limites actuelles (hors scope de cette phase)

- Pas d'OTP SMS réel (coût/complexité) : l'authentification se fait par
  email + mot de passe, puis code à 4 chiffres/empreinte au quotidien
- Pas de pièces jointes photo/PDF sur une analyse
- Pas d'import Excel de l'historique (l'export existe, pas l'import)
- Pas de notifications push (rappels, alertes hors seuil)
- Pas d'écran d'administration des rôles : le rôle se change directement
  dans la collection `profiles` depuis la console Firebase
- Le lien "mot de passe oublié" ouvre la page de réinitialisation hébergée
  par Firebase (hors de l'app) ; personnaliser cette page est possible plus
  tard depuis **Authentication → Templates** si besoin
