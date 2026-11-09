import 'dart:typed_data';

import '../../models/gallery_photo.dart';

// How much of the photo library FrameWalk may read.
enum GalleryAccess {
  // Every photo.
  full,

  // Only photos the user picked (Android 14+ "Allow limited access", or iOS
  // limited library). Photos outside the selection look like they don't exist.
  limited,

  // No access: never granted, denied, or revoked in system settings. Android
  // doesn't say whether the user has been asked before, so this covers all
  // three.
  denied,
}

extension GalleryAccessX on GalleryAccess {
  bool get canRead => this != GalleryAccess.denied;
}

class GalleryPage {
  final List<GalleryPhoto> photos;
  final int page;
  final bool hasMore;

  const GalleryPage({
    required this.photos,
    required this.page,
    required this.hasMore,
  });
}

// Reads photos from the device's own gallery. Implementations must never
// copy, upload, modify, or delete the user's photos.
//
// Every platform-specific detail (photo_manager, MediaStore, PhotoKit) belongs
// behind this interface so widgets and matching logic never depend on it, and
// an iOS implementation can be added without touching them.
abstract class LocalPhotoService {
  // Checks access without prompting the user.
  Future<GalleryAccess> checkAccess();

  // Shows the system permission prompt if the OS still allows it.
  Future<GalleryAccess> requestAccess();

  Future<void> openAccessSettings();

  // Lets a user with limited access change which photos FrameWalk can see.
  // Does nothing where the platform has no such picker.
  Future<void> manageLimitedSelection();

  // Identifies this app install. Stored with photo links because asset IDs
  // are only valid on the device that produced them.
  Future<String> deviceInstallId();

  String get platformName;

  // Newest photos first, [pageSize] at a time. [page] starts at 0.
  Future<GalleryPage> fetchPhotos({required int page, required int pageSize});

  // Photos taken between [start] and [end], oldest first.
  Future<List<GalleryPhoto>> fetchPhotosTakenBetween(
    DateTime start,
    DateTime end,
  );

  // Null if the photo was deleted, isn't in a limited selection, or can't be
  // read.
  Future<GalleryPhoto?> findPhoto(String assetId);

  // Null if the photo is missing or its format can't be decoded.
  Future<Uint8List?> loadThumbnail(String assetId, {int size = 256});

  // Fires when photos are added, edited, or deleted outside the app.
  Stream<void> get changes;
}
