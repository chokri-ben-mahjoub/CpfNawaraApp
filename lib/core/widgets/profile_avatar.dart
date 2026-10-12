import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/app_lock.dart';
import '../auth/auth_providers.dart';
import '../auth/profile_photo.dart';
import '../l10n/app_strings.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import 'app_loader.dart';

/// Avatar du profil de l'appareil : la photo si elle existe, sinon
/// l'initiale du nom. Avec [editable], un petit appareil photo invite à la
/// changer (toucher l'avatar).
class ProfileAvatar extends ConsumerWidget {
  final double radius;
  final bool editable;
  final Color color;

  const ProfileAvatar({super.key, this.radius = 24, this.editable = false, this.color = accentColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final locale = ref.watch(localeProvider);
    final profile = ref.watch(profileProvider);
    final name = profile?.fullName ?? '';
    final photo = profile?.photo;
    final initial = (name.isEmpty ? tr(locale, 'accountNoName') : name)[0].toUpperCase();

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.14),
      foregroundImage: photo == null ? null : MemoryImage(photo),
      child: Text(
        initial,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: radius * 0.75),
      ),
    );
    if (!editable) return avatar;
    return Tooltip(
      message: tr(locale, 'profilePhotoChange'),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: profile == null ? null : () => showProfilePhotoSheet(context, ref),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(Icons.photo_camera, size: radius * 0.42, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choix de la photo de profil : appareil photo (si disponible), galerie /
/// fichiers, ou retrait de la photo actuelle.
Future<void> showProfilePhotoSheet(BuildContext context, WidgetRef ref) async {
  final locale = ref.read(localeProvider);
  String s(String key) => tr(locale, key);
  final picker = ImagePicker();
  final camera = picker.supportsImageSource(ImageSource.camera);
  final hasPhoto = ref.read(profileProvider)?.photo != null;

  final choice = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              s('profilePhotoTitle'),
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (camera)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s('profilePhotoCamera')),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(s('profilePhotoGallery')),
            onTap: () => Navigator.of(sheetContext).pop('gallery'),
          ),
          if (hasPhoto)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(sheetContext).colorScheme.error),
              title: Text(s('profilePhotoRemove'), style: TextStyle(color: Theme.of(sheetContext).colorScheme.error)),
              onTap: () => Navigator.of(sheetContext).pop('remove'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final controller = ref.read(profileProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final sync = ref.read(syncControllerProvider.notifier);
  if (choice == 'remove') {
    await controller.setPhoto(null);
    unawaited(sync.syncProfilePhoto());
    return;
  }
  XFile? file;
  try {
    file = await LockGuard.run(
      () => picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1600,
        maxHeight: 1600,
      ),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s('profilePhotoError'))));
    return;
  }
  if (file == null || !context.mounted) return;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return;
  final photo = await runWithLoading(context, s('profilePhotoLoading'), () => compute(compressProfilePhoto, bytes));
  if (photo == null) {
    messenger.showSnackBar(SnackBar(content: Text(s('profilePhotoError'))));
    return;
  }
  await controller.setPhoto(photo);
  // Aussi sur la fiche de membre : visible sur les autres appareils du compte.
  unawaited(sync.syncProfilePhoto());
  messenger.showSnackBar(SnackBar(content: Text(s('profilePhotoSaved'))));
}
