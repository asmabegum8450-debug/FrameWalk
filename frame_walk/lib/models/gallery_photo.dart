// A photo in the user's on-device gallery, described without any
// platform-plugin types so matching and UI code stay platform-neutral.
//
// The image itself never leaves the device. [assetId] is the gallery's own
// identifier (a MediaStore ID on Android, a PHAsset local identifier on iOS)
// and only means something on the device that produced it.
class GalleryPhoto {
  final String assetId;
  final DateTime takenAt;
  final int width;
  final int height;

  // Null when the photo has no GPS metadata, or the OS withheld it.
  final GeoCoordinate? location;

  const GalleryPhoto({
    required this.assetId,
    required this.takenAt,
    this.width = 0,
    this.height = 0,
    this.location,
  });
}

class GeoCoordinate {
  final double latitude;
  final double longitude;

  const GeoCoordinate(this.latitude, this.longitude);

  // Returns null for missing or placeholder values. Many galleries report
  // (0, 0) for photos without location data, so that is treated as missing.
  static GeoCoordinate? tryCreate(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return null;
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude == 0 && longitude == 0) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return GeoCoordinate(latitude, longitude);
  }

  @override
  bool operator ==(Object other) =>
      other is GeoCoordinate &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}
