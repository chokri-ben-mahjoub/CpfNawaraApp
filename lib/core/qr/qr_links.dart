/// Contenu des QR codes collés sur le terrain : un puits, un point
/// d'échantillonnage ou un article de stock. Le préfixe permet de refuser les
/// QR codes d'autres applications.
const _scheme = 'cpfnawara://';

enum QrKind { well, point, stock }

String qrPayload(QrKind kind, String id) => '$_scheme${kind.name}/${Uri.encodeComponent(id)}';

/// Écran à ouvrir pour un QR code lu, ou `null` s'il ne vient pas de l'app.
/// [canEnter] : le rôle peut saisir — on ouvre alors directement la saisie.
String? routeForQr(String text, {required bool canEnter, required String todayKey}) {
  final value = text.trim();
  if (!value.startsWith(_scheme)) return null;
  final parts = value.substring(_scheme.length).split('/');
  if (parts.length != 2 || parts[1].isEmpty) return null;
  final id = Uri.decodeComponent(parts[1]);
  final kind = QrKind.values.where((k) => k.name == parts[0]).firstOrNull;
  return switch (kind) {
    QrKind.well => canEnter ? '/entry?wellId=${Uri.encodeQueryComponent(id)}' : '/wells/$id',
    QrKind.point => canEnter ? '/plant/entry/$id?date=$todayKey' : '/plant/point/$id',
    QrKind.stock => '/stock/$id',
    null => null,
  };
}
