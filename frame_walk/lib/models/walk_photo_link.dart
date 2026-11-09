import 'package:cloud_firestore/cloud_firestore.dart';

import 'walk_record.dart';

enum PhotoLinkStatus {
  // Part of the walk's collection.
  linked,

  // The user removed it from the walk. Kept so automatic matching doesn't
  // suggest it again. The original photo is never touched.
  removed,
}

// A pointer from a walk to a photo that stays on the user's device. Stored at
// users/{userId}/walks/{walkId}/photoLinks/{id}. No image data is stored.
//
// [assetId] is only meaningful on the device (app install) recorded in
// [deviceInstallId]. Other devices must not assume they can resolve it; see
// WalkGalleryService for how links from other devices are handled. A future
// cross-device sync feature can add its own fields (for example a cloud copy
// or content hash) without changing these.
class WalkPhotoLink {
  final String id;
  final String userId;
  final String walkId;
  final String routeId;

  final String assetId;
  final String platform;
  final String deviceInstallId;

  // Recorded when linked, so a later lookup can confirm an asset ID still
  // points at the same photo rather than a different one that reused the ID.
  final DateTime takenAt;
  final int width;
  final int height;

  // Null means unassigned: part of the walk, but not tied to a stop or prompt.
  final String? stopId;
  final String? promptId;

  final PhotoLinkStatus status;

  const WalkPhotoLink({
    required this.id,
    required this.userId,
    required this.walkId,
    required this.routeId,
    required this.assetId,
    required this.platform,
    required this.deviceInstallId,
    required this.takenAt,
    this.width = 0,
    this.height = 0,
    this.stopId,
    this.promptId,
    this.status = PhotoLinkStatus.linked,
  });

  // One link per photo per device per walk, so relinking the same photo
  // updates the existing document. Asset IDs may contain '/' (iOS), which
  // Firestore document IDs can't.
  static String idFor({
    required String deviceInstallId,
    required String assetId,
  }) {
    final safeAssetId = assetId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${deviceInstallId}_$safeAssetId';
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'walkId': walkId,
        'routeId': routeId,
        'assetId': assetId,
        'platform': platform,
        'deviceInstallId': deviceInstallId,
        'takenAt': Timestamp.fromDate(takenAt),
        'width': width,
        'height': height,
        'stopId': stopId,
        'promptId': promptId,
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory WalkPhotoLink.fromMap(String id, Map<String, dynamic> map) {
    return WalkPhotoLink(
      id: id,
      userId: map['userId'] as String,
      walkId: map['walkId'] as String,
      routeId: map['routeId'] as String,
      assetId: map['assetId'] as String,
      platform: map['platform'] as String? ?? '',
      deviceInstallId: map['deviceInstallId'] as String? ?? '',
      takenAt: readFirestoreDate(map['takenAt']),
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      stopId: map['stopId'] as String?,
      promptId: map['promptId'] as String?,
      status: PhotoLinkStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => PhotoLinkStatus.linked,
      ),
    );
  }
}
