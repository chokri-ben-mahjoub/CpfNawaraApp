class AnalysisRecord {
  final String id;
  final String wellId;
  final String typeId;
  final double value;

  /// Clé de service (ex: `serviceLaboratoire`), voir `app_strings.dart`.
  final String serviceKey;
  final String operatorName;
  final String? operatorId;
  final DateTime dateTime;
  final String? comment;

  const AnalysisRecord({
    required this.id,
    required this.wellId,
    required this.typeId,
    required this.value,
    required this.serviceKey,
    required this.operatorName,
    this.operatorId,
    required this.dateTime,
    this.comment,
  });

  bool isSameDay(DateTime other) =>
      dateTime.year == other.year && dateTime.month == other.month && dateTime.day == other.day;
}
