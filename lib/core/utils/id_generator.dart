int _counter = 0;

/// Identifiant local simple (horodatage + compteur), suffisant tant que les
/// données ne sont pas synchronisées avec un backend.
String newLocalId() {
  _counter++;
  return '${DateTime.now().microsecondsSinceEpoch}-$_counter';
}
