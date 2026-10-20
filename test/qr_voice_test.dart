import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/qr/qr_labels_pdf.dart';
import 'package:puitstrack/core/qr/qr_links.dart';
import 'package:puitstrack/core/voice/spoken_number.dart';

void main() {
  test('dictée : décimaux et mots', () {
    expect(parseSpokenNumber('zéro virgule huit'), 0.8);
    expect(parseSpokenNumber('douze point cinq'), 12.5);
    expect(parseSpokenNumber('3,25'), 3.25);
    expect(parseSpokenNumber('0.8'), 0.8);
    expect(parseSpokenNumber('moins deux'), -2);
    expect(parseSpokenNumber('vingt et un'), 21);
    expect(parseSpokenNumber('soixante-quinze'), 75);
    expect(parseSpokenNumber('cent vingt virgule cinq'), 120.5);
    expect(parseSpokenNumber('deux mille cinq cents'), 2500);
    expect(parseSpokenNumber('seven point five'), 7.5);
    expect(parseSpokenNumber('virgule huit'), isNull, reason: 'pas de partie entière dictée');
    expect(parseSpokenNumber('bonjour'), isNull);
    expect(parseSpokenNumber(''), isNull);
  });

  test('QR : routes selon le rôle', () {
    final well = qrPayload(QrKind.well, 'w1');
    expect(routeForQr(well, canEnter: true, todayKey: '2026-10-20'), '/entry?wellId=w1');
    expect(routeForQr(well, canEnter: false, todayKey: '2026-10-20'), '/wells/w1');
    expect(
      routeForQr(qrPayload(QrKind.point, 'pp_c1'), canEnter: true, todayKey: '2026-10-20'),
      '/plant/entry/pp_c1?date=2026-10-20',
    );
    expect(routeForQr(qrPayload(QrKind.stock, 's1'), canEnter: false, todayKey: 'x'), '/stock/s1');
    expect(routeForQr('https://example.com', canEnter: true, todayKey: 'x'), isNull);
    expect(routeForQr('cpfnawara://inconnu/1', canEnter: true, todayKey: 'x'), isNull);
  });

  test('QR : planche etiquettes PDF', () async {
    final bytes = await buildQrLabelsPdf(
      labels: [
        for (var i = 0; i < 14; i++) QrLabel(kind: QrKind.well, id: 'w$i', title: 'Puits $i', subtitle: 'N-$i'),
        const QrLabel(kind: QrKind.stock, id: 's1', title: 'Huile'),
      ],
      title: 'Etiquettes',
      kindLabel: (k) => k.name,
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(3000));
  });
}
