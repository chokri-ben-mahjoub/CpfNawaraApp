// Conversion entre une ligne SQLite (texte, entier, réel, null) et les
// champs d'un document Firestore (format REST "Value").

Map<String, Object?> encodeFields(Map<String, Object?> row) => {
  for (final entry in row.entries) entry.key: encodeValue(entry.value),
};

Map<String, Object?> encodeValue(Object? value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': '$value'};
  if (value is double) return {'doubleValue': value};
  return {'stringValue': '$value'};
}

Map<String, Object?> decodeFields(Map<String, Object?>? fields) => {
  if (fields != null)
    for (final entry in fields.entries) entry.key: decodeValue(entry.value as Map<String, Object?>),
};

Object? decodeValue(Map<String, Object?> value) {
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('integerValue')) return int.parse('${value['integerValue']}');
  if (value.containsKey('doubleValue')) return (value['doubleValue'] as num).toDouble();
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('timestampValue')) return value['timestampValue'];
  return null;
}
