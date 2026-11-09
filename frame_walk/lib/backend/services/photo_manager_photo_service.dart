import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/gallery_photo.dart';
import 'install_id_store.dart';
import 'local_photo_service.dart';

// LocalPhotoService backed by the photo_manager plugin.
//
// On Android it reads MediaStore through the scoped media permissions declared
// in AndroidManifest.xml (READ_MEDIA_IMAGES, READ_MEDIA_VISUAL_USER_SELECTED,
// and READ_EXTERNAL_STORAGE on Android 12 and below). It never asks for
// broad file access and never writes to the gallery.
//
// iOS will also work through this class once Info.plist has
// NSPhotoLibraryUsageDescription. That setup hasn't been done yet.
class PhotoManagerPhotoService implements LocalPhotoService {
  PhotoManagerPhotoService({InstallIdStore? installIdStore})
      : _installIdStore = installIdStore ?? InstallIdStore();

  // Images only. Location lets matching use GPS from photos: on Android 10+
  // the OS removes it from photo metadata without ACCESS_MEDIA_LOCATION.
  static const _permissionOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: true,
    ),
  );

  // MediaStore filters on DATE_ADDED, but photos are matched on DATE_TAKEN.
  // These usually agree for camera photos. The extra margin catches photos
  // indexed a little late; exact filtering on the taken time happens in Dart.
  static const _dateAddedSlack = Duration(hours: 6);
  static const _windowPageSize = 100;
  static const _windowMaxPhotos = 500;
  static const _thumbnailCacheSize = 200;

  final InstallIdStore _installIdStore;
  final _thumbnailCache = <String, Uint8List>{}; // Insertion-ordered, used as an LRU.
  StreamController<void>? _changes;

  @override
  String get platformName => kIsWeb ? 'web' : Platform.operatingSystem;

  @override
  Future<GalleryAccess> checkAccess() async {
    try {
      final state = await PhotoManager.getPermissionState(
        requestOption: _permissionOption,
      );
      return mapPermissionState(state);
    } on PlatformException catch (error) {
      debugPrint('Could not check photo access: $error');
      return GalleryAccess.denied;
    }
  }

  @override
  Future<GalleryAccess> requestAccess() async {
    try {
      final state = await PhotoManager.requestPermissionExtend(
        requestOption: _permissionOption,
      );
      // Permission changes can make cached thumbnails stale or unreadable.
      _thumbnailCache.clear();
      return mapPermissionState(state);
    } on PlatformException catch (error) {
      debugPrint('Could not request photo access: $error');
      return GalleryAccess.denied;
    }
  }

  // Public so tests can check the mapping without a device.
  static GalleryAccess mapPermissionState(PermissionState state) {
    switch (state) {
      case PermissionState.authorized:
        return GalleryAccess.full;
      case PermissionState.limited:
        return GalleryAccess.limited;
      case PermissionState.notDetermined:
      case PermissionState.denied:
      case PermissionState.restricted:
        return GalleryAccess.denied;
    }
  }

  @override
  Future<void> openAccessSettings() => PhotoManager.openSetting();

  @override
  Future<void> manageLimitedSelection() async {
    try {
      await PhotoManager.presentLimited(type: RequestType.image);
      _thumbnailCache.clear();
    } on PlatformException catch (error) {
      // Android 13 and below have no reselection picker.
      debugPrint('Limited photo picker unavailable: $error');
    }
  }

  @override
  Future<String> deviceInstallId() => _installIdStore.read();

  @override
  Future<GalleryPage> fetchPhotos({
    required int page,
    required int pageSize,
  }) async {
    try {
      final assets = await PhotoManager.getAssetListPaged(
        page: page,
        pageCount: pageSize,
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          orders: const [OrderOption(type: OrderOptionType.createDate)],
        ),
      );
      return GalleryPage(
        // Browsing doesn't need GPS, so skip the per-photo location lookup.
        photos: assets.map((asset) => _toGalleryPhoto(asset, null)).toList(),
        page: page,
        hasMore: assets.length == pageSize,
      );
    } on PlatformException catch (error) {
      debugPrint('Could not load gallery page $page: $error');
      return GalleryPage(photos: const [], page: page, hasMore: false);
    }
  }

  @override
  Future<List<GalleryPhoto>> fetchPhotosTakenBetween(
    DateTime start,
    DateTime end,
  ) async {
    final filter = FilterOptionGroup(
      createTimeCond: DateTimeCond(min: start, max: end.add(_dateAddedSlack)),
      orders: const [OrderOption(type: OrderOptionType.createDate, asc: true)],
    );
    final matches = <GalleryPhoto>[];
    try {
      for (var page = 0; page * _windowPageSize < _windowMaxPhotos; page++) {
        final assets = await PhotoManager.getAssetListPaged(
          page: page,
          pageCount: _windowPageSize,
          type: RequestType.image,
          filterOption: filter,
        );
        for (final asset in assets) {
          final takenAt = asset.createDateTime;
          if (takenAt.isBefore(start) || takenAt.isAfter(end)) continue;
          matches.add(_toGalleryPhoto(asset, await _readLocation(asset)));
        }
        if (assets.length < _windowPageSize) break;
      }
    } on PlatformException catch (error) {
      debugPrint('Could not search the gallery by date: $error');
    }
    return matches;
  }

  @override
  Future<GalleryPhoto?> findPhoto(String assetId) async {
    try {
      final asset = await AssetEntity.fromId(assetId);
      if (asset == null || asset.type != AssetType.image) return null;
      return _toGalleryPhoto(asset, await _readLocation(asset));
    } on PlatformException catch (error) {
      debugPrint('Could not look up photo $assetId: $error');
      return null;
    }
  }

  @override
  Future<Uint8List?> loadThumbnail(String assetId, {int size = 256}) async {
    final key = '$assetId@$size';
    final cached = _thumbnailCache.remove(key);
    if (cached != null) {
      _thumbnailCache[key] = cached; // Mark as most recently used.
      return cached;
    }
    try {
      final asset = await AssetEntity.fromId(assetId);
      final bytes = await asset?.thumbnailDataWithSize(
        ThumbnailSize.square(size),
      );
      if (bytes == null || bytes.isEmpty) return null;
      _thumbnailCache[key] = bytes;
      if (_thumbnailCache.length > _thumbnailCacheSize) {
        _thumbnailCache.remove(_thumbnailCache.keys.first);
      }
      return bytes;
    } on PlatformException catch (error) {
      debugPrint('Could not load thumbnail for $assetId: $error');
      return null;
    }
  }

  @override
  Stream<void> get changes {
    return (_changes ??= StreamController<void>.broadcast(
      onListen: () {
        PhotoManager.addChangeCallback(_onGalleryChanged);
        PhotoManager.startChangeNotify();
      },
      onCancel: () {
        PhotoManager.removeChangeCallback(_onGalleryChanged);
        PhotoManager.stopChangeNotify();
      },
    ))
        .stream;
  }

  void _onGalleryChanged(MethodCall _) {
    _thumbnailCache.clear();
    _changes?.add(null);
  }

  Future<GeoCoordinate?> _readLocation(AssetEntity asset) async {
    try {
      final latLng = await asset.latlngAsync();
      return GeoCoordinate.tryCreate(latLng?.latitude, latLng?.longitude);
    } on PlatformException {
      return null;
    }
  }

  GalleryPhoto _toGalleryPhoto(AssetEntity asset, GeoCoordinate? location) {
    return GalleryPhoto(
      assetId: asset.id,
      takenAt: asset.createDateTime,
      width: asset.width,
      height: asset.height,
      location: location,
    );
  }
}
