import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/branding/app_logo.dart';

void main() {
  tearDown(() => applySharedLogo(null));

  test('logo partagé : repli quand aucun logo local', () {
    final png = Uint8List.fromList([1, 2, 3, 4]);
    expect(decodeSharedLogo(null), isNull);
    expect(decodeSharedLogo(''), isNull);
    expect(decodeSharedLogo('%%pas-du-base64%%'), isNull);
    expect(decodeSharedLogo(base64Encode(png)), png);

    applySharedLogo(png);
    expect(currentAppLogo, png, reason: 'le logo de l\'équipe sert aux PDF de cet appareil');
    applySharedLogo(null);
    expect(currentAppLogo, isNull);
  });
}
