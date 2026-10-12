/// Version affichée dans Réglages › À propos — à garder alignée sur
/// `version:` dans pubspec.yaml.
const appVersion = '0.2.0';

/// Propriétaire de PuitsTrack : seul compte qui crée les codes d'activation
/// (écran Clients) et une entreprise sans code. Doit rester identique à
/// `isOwner()` dans `firestore.rules` (vérifié par les tests).
const platformOwnerEmail = 'chokribenmahjoub@gmail.com';
