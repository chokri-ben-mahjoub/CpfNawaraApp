import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:puitstrack/core/auth/auth_providers.dart';
import 'package:puitstrack/core/auth/profile_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('photo de profil : recadrée en carré, réduite, en JPEG', () {
    final wide = img.Image(width: 1200, height: 600);
    img.fill(wide, color: img.ColorRgb8(200, 80, 40));
    final out = compressProfilePhoto(img.encodePng(wide))!;
    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, profilePhotoSize);
    expect(decoded.height, profilePhotoSize);
    expect(out.length, lessThan(60000));
    expect(compressProfilePhoto(Uint8List.fromList([1, 2, 3])), isNull, reason: 'pas une image');
  });

  test('photo de profil : enregistrée, rechargée, retirée', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ProfileController();
    await controller.createProfile(fullName: 'Chokri', phone: '', serviceKey: 'serviceProduction');
    final photo = compressProfilePhoto(img.encodePng(img.Image(width: 100, height: 100)))!;
    await controller.setPhoto(photo);
    expect(controller.state!.photo, photo);

    final reloaded = ProfileController();
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
    expect(reloaded.state!.photo, photo, reason: 'relue au démarrage');
    expect(reloaded.state!.fullName, 'Chokri');

    await controller.updateProfile(fullName: 'Chokri B.', phone: '', serviceKey: 'serviceProduction');
    expect(controller.state!.photo, photo, reason: 'conservée quand on modifie le nom');
    await controller.setPhoto(null);
    expect(controller.state!.photo, isNull);
  });
}
