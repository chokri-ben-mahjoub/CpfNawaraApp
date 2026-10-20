/// Nom affiché de l'app (connexion, écran de démarrage, titre de l'onglet
/// navigateur, PDF générés...). Seul endroit à modifier pour la renommer :
/// ne change ni le nom du paquet Android/iOS, ni le dossier de
/// téléchargements, ni le projet Firebase.
const appDisplayName = 'CPF Laboratory NAWARA';

/// Version affichée dans Réglages › À propos — à garder alignée sur
/// `version:` dans pubspec.yaml.
const appVersion = '0.3.0';

/// Propriétaire de PuitsTrack : seul compte qui crée les codes d'activation
/// (écran Clients) et une entreprise sans code. Doit rester identique à
/// `isOwner()` dans `firestore.rules` (vérifié par les tests).
const platformOwnerEmail = 'chokribenmahjoub@gmail.com';
