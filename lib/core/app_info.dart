/// Nom affichÃ© de l'app (connexion, Ã©cran de dÃ©marrage, titre de l'onglet
/// navigateur, PDF gÃ©nÃ©rÃ©s...). Seul endroit Ã  modifier pour la renommer :
/// ne change ni le nom du paquet Android/iOS, ni le dossier de
/// tÃ©lÃ©chargements, ni le projet Firebase.
const appDisplayName = 'CPF Laboratory NAWARA';

/// Version affichÃ©e dans RÃ©glages â€º Ã€ propos â€” Ã  garder alignÃ©e sur
/// `version:` dans pubspec.yaml.
const appVersion = '0.29.0';

/// PropriÃ©taire de PuitsTrack : seul compte qui crÃ©e les codes d'activation
/// (Ã©cran Clients) et une entreprise sans code. Doit rester identique Ã 
/// `isOwner()` dans `firestore.rules` (vÃ©rifiÃ© par les tests).
const platformOwnerEmail = 'chokribenmahjoub@gmail.com';
