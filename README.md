# Suivi Puits — CPF Nawara

App Flutter de suivi quotidien des analyses de puits (CPF Nawara) : connexion,
inscription, tableau de bord du jour, fiches puits et saisie rapide.

Le style est repris du projet de référence `C:\mobile-locations` (Material 3,
Riverpod, go_router, Google Fonts) avec une nouvelle identité visuelle
(ambre énergie `#FF7A33` / bleu nuit `#0B1E2D`) adaptée à un contexte
industriel gaz/pétrole.

## Ce qui est inclus

### Authentification
- **Onboarding** (`onboarding_screen.dart`)
- **Connexion par numéro de téléphone** (`login_screen.dart`) + carrousel de présentation
- **Inscription** (`signup_screen.dart`) : nom, service, téléphone
- **Vérification par code à 4 chiffres** (`code_screen.dart`), code de démo **`1234`**
  (réutilisé pour la connexion et pour la réinitialisation de mot de passe)
- **Mot de passe oublié** (`forgot_password_screen.dart` → code → `reset_password_screen.dart`)
- **Multi-langue FR/EN** avec sélecteur (`lib/core/l10n/app_strings.dart`) —
  ajouter une langue = ajouter une entrée dans `supportedLocales` et dans la map
  de traductions

### Fonctionnel (données de démonstration en mémoire)
- **Tableau de bord du jour** (`dashboard_screen.dart`) : par puits actif, statut
  ✅ fait / ⏳ à faire / ⚠️ en retard pour chaque analyse attendue, avec
  l'opérateur et la valeur quand c'est fait
- **Liste des puits** (`wells_list_screen.dart`) : recherche, statut actif/arrêté,
  progression du jour
- **Fiche puits** (`well_detail_screen.dart`) : dernières valeurs par type
  d'analyse (avec alerte visuelle hors seuil) + historique récent
- **Saisie rapide** (`quick_entry_screen.dart`) : puits → type → valeur → service
  → commentaire, avec détection de doublon (analyse déjà saisie aujourd'hui) et
  confirmation si la valeur sort du seuil attendu
- 7 types d'analyses de démo : BSW, salinité, densité, H2S, pression,
  température, débit (`lib/core/data/wells_repository.dart`), avec seuils et
  fréquence (quotidienne/hebdo/mensuelle)

### Design
- Thème clair/sombre Material 3 (`lib/core/theme/app_theme.dart`)

## Lancer le projet

Sur votre machine avec le SDK Flutter installé :

```bash
cd D:\new\CpfNawaraApp
flutter create --platforms=android,ios --org com.apbs --project-name cpf_nawara_suivi .
flutter pub get
flutter run
```

La commande `flutter create .` ne touche pas aux fichiers déjà présents dans
`lib/`, `pubspec.yaml` ou `analysis_options.yaml` : elle ne fait que générer
les dossiers de plateforme manquants (`android/`, `ios/`, etc.).

## Limites actuelles (hors scope de cette phase)

- Les analyses saisies ne sont conservées qu'en mémoire (perdues au
  redémarrage de l'app) : pas encore de base locale SQLite ni de
  synchronisation cloud
- Pas de vrai backend SMS/OTP (code de démo fixe `1234`)
- Pas encore de courbes de tendance, d'export Excel/PDF, de gestion des rôles
  (Admin/Utilisateur/Lecteur), ni de pièces jointes photo/PDF
- Pas de gestion de plusieurs numéros autorisés par compte
