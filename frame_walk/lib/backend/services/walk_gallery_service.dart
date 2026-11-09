import '../../models/gallery_photo.dart';
import '../../models/walk_photo_link.dart';
import '../../models/walk_record.dart';
import 'local_photo_service.dart';
import 'walk_history_service.dart';
import 'walk_photo_matcher.dart';

// A photo shown on a walk's gallery page. Either the user linked it to the
// walk ([link] is set), or matching suggested it ([link] is null).
class WalkGalleryItem {
  final GalleryPhoto photo;
  final WalkPhotoLink? link;
  final PhotoMatch? match;

  const WalkGalleryItem({required this.photo, this.link, this.match});

  bool get isSuggested => link == null;
  String? get promptId => link?.promptId;
}

// Photos for one prompt at one stop. [prompt] is null only for a stop that
// has no prompts.
class WalkGallerySection {
  final WalkStopSnapshot stop;
  final WalkPrompt? prompt;
  final List<WalkGalleryItem> items;

  const WalkGallerySection({
    required this.stop,
    required this.prompt,
    required this.items,
  });
}

class WalkGallery {
  final WalkRecord walk;
  final GalleryAccess access;

  // One section per prompt, in route order, including empty ones.
  final List<WalkGallerySection> sections;

  // Linked to the walk but not to a stop or prompt.
  final List<WalkGalleryItem> unassigned;

  // Taken during the walk, but no GPS places them at a particular stop.
  final List<WalkGalleryItem> suggestions;

  // Linked on this device, but no longer readable here: deleted, or outside
  // a limited-access selection.
  final List<WalkPhotoLink> missing;

  // Linked on another device or app install, and not found here. Asset IDs
  // are device-specific, so these can't be shown and aren't treated as
  // deleted.
  final int otherDeviceCount;

  // How many gallery photos fall inside the walk's time window, counting
  // ones already linked or removed.
  final int timeWindowPhotoCount;

  const WalkGallery({
    required this.walk,
    required this.access,
    this.sections = const [],
    this.unassigned = const [],
    this.suggestions = const [],
    this.missing = const [],
    this.otherDeviceCount = 0,
    this.timeWindowPhotoCount = 0,
  });

  bool get hasVisiblePhotos =>
      unassigned.isNotEmpty ||
      suggestions.isNotEmpty ||
      sections.any((section) => section.items.isNotEmpty);
}

// Combines walk history (Firestore), the device gallery (LocalPhotoService)
// and WalkPhotoMatcher into what the walk gallery page displays, and saves
// the user's photo choices. Contains no widget or platform code.
class WalkGalleryService {
  final LocalPhotoService _photos;
  final WalkHistoryService _history;
  final WalkPhotoMatcher _matcher;

  // How far a stored timestamp may differ from the photo's current one and
  // still count as the same photo. Allows for second-level rounding.
  static const _sameTakenAtTolerance = Duration(seconds: 2);

  WalkGalleryService({
    required this._photos,
    required this._history,
    this._matcher = const WalkPhotoMatcher(),
  });

  LocalPhotoService get photos => _photos;

  Future<WalkGallery> loadGallery(WalkRecord walk) async {
    final access = await _photos.checkAccess();
    if (!access.canRead) {
      return WalkGallery(walk: walk, access: access);
    }

    final links = await _history.fetchPhotoLinks(walk.userId, walk.id);
    final installId = await _photos.deviceInstallId();
    final window = _matcher.windowFor(walk);
    final candidates =
        await _photos.fetchPhotosTakenBetween(window.start, window.end);
    final candidatesById = {for (final p in candidates) p.assetId: p};

    final linkedItems = <WalkGalleryItem>[];
    final missing = <WalkPhotoLink>[];
    final handledAssetIds = <String>{};
    var otherDeviceCount = 0;

    for (final link in links) {
      // The same photo can be linked from two installs on one device.
      if (handledAssetIds.contains(link.assetId)) continue;
      final isThisInstall = link.deviceInstallId == installId;
      final samePlatform = link.platform == _photos.platformName;
      GalleryPhoto? photo;
      if (samePlatform) {
        photo = candidatesById[link.assetId] ?? await _photos.findPhoto(link.assetId);
        if (photo != null && !_isSamePhoto(link, photo)) photo = null;
      }

      if (photo != null) {
        handledAssetIds.add(photo.assetId);
        if (link.status == PhotoLinkStatus.linked) {
          linkedItems.add(WalkGalleryItem(photo: photo, link: link));
        }
      } else if (link.status == PhotoLinkStatus.linked) {
        if (isThisInstall) {
          missing.add(link);
        } else {
          otherDeviceCount++;
        }
      }
    }

    final autoAtStop = <WalkGalleryItem>[];
    final suggestions = <WalkGalleryItem>[];
    for (final photo in candidates) {
      if (handledAssetIds.contains(photo.assetId)) continue;
      final match = _matcher.match(walk, photo);
      final item = WalkGalleryItem(photo: photo, match: match);
      if (match.strength == MatchStrength.atStop) {
        autoAtStop.add(item);
      } else if (match.isLikelyFromWalk) {
        suggestions.add(item);
      }
    }

    final sections = <WalkGallerySection>[];
    final placed = <WalkGalleryItem>{};
    for (final stop in walk.stops) {
      final prompts = stop.prompts.isEmpty ? <WalkPrompt?>[null] : stop.prompts;
      for (var i = 0; i < prompts.length; i++) {
        final prompt = prompts[i];
        final items = <WalkGalleryItem>[
          ...linkedItems.where((item) =>
              prompt != null
                  ? item.promptId == prompt.id
                  : item.link!.stopId == stop.stopId),
          // A GPS match identifies the stop, not the prompt, so it goes under
          // the stop's first prompt until the user says otherwise.
          if (i == 0)
            ...autoAtStop.where((item) => item.match!.stopId == stop.stopId),
        ]..sort(_byTakenAt);
        placed.addAll(items);
        sections.add(
          WalkGallerySection(stop: stop, prompt: prompt, items: items),
        );
      }
    }

    // Linked items whose stop or prompt isn't on this walk are unassigned.
    final unassigned = linkedItems.where((item) => !placed.contains(item)).toList()
      ..sort(_byTakenAt);
    suggestions.sort(_byTakenAt);

    return WalkGallery(
      walk: walk,
      access: access,
      sections: sections,
      unassigned: unassigned,
      suggestions: suggestions,
      missing: missing,
      otherDeviceCount: otherDeviceCount,
      timeWindowPhotoCount: candidates.length,
    );
  }

  // Adds photos to the walk, all under [promptId], or unassigned when it's
  // null. Re-adds photos the user removed earlier. Use this to add several
  // photos to one prompt, or to move a photo to another prompt.
  Future<void> assignPhotos(
    WalkRecord walk,
    List<GalleryPhoto> photos, {
    String? promptId,
  }) async {
    final stop = walk.stopForPrompt(promptId);
    if (promptId != null && stop == null) {
      throw ArgumentError('Prompt $promptId is not part of this walk');
    }
    final links = await Future.wait(photos.map((photo) => _buildLink(
          walk,
          photo,
          stopId: stop?.stopId,
          promptId: promptId,
          status: PhotoLinkStatus.linked,
        )));
    await _history.savePhotoLinks(links);
  }

  // Takes a photo out of the walk and stops it being suggested again.
  // Only the Firestore link changes; the photo stays in the camera roll.
  Future<void> removePhoto(WalkRecord walk, GalleryPhoto photo) async {
    final link = await _buildLink(
      walk,
      photo,
      status: PhotoLinkStatus.removed,
    );
    await _history.savePhotoLink(link);
  }

  // Deletes links to photos that are gone from this device. The photos
  // themselves are already gone, so only the links are deleted.
  Future<void> forgetMissingPhotos(List<WalkPhotoLink> links) =>
      _history.deletePhotoLinks(links);

  Future<WalkPhotoLink> _buildLink(
    WalkRecord walk,
    GalleryPhoto photo, {
    String? stopId,
    String? promptId,
    required PhotoLinkStatus status,
  }) async {
    final installId = await _photos.deviceInstallId();
    return WalkPhotoLink(
      id: WalkPhotoLink.idFor(deviceInstallId: installId, assetId: photo.assetId),
      userId: walk.userId,
      walkId: walk.id,
      routeId: walk.routeId,
      assetId: photo.assetId,
      platform: _photos.platformName,
      deviceInstallId: installId,
      takenAt: photo.takenAt,
      width: photo.width,
      height: photo.height,
      stopId: stopId,
      promptId: promptId,
      status: status,
    );
  }

  // Guards against an asset ID that now belongs to a different photo, which
  // can happen on another device or after the media database is rebuilt.
  static bool _isSamePhoto(WalkPhotoLink link, GalleryPhoto photo) {
    final drift = link.takenAt.difference(photo.takenAt).abs();
    if (drift > _sameTakenAtTolerance) return false;
    if (link.width == 0 || photo.width == 0) return true;
    // Allow for rotation, which swaps width and height.
    return (link.width == photo.width && link.height == photo.height) ||
        (link.width == photo.height && link.height == photo.width);
  }

  static int _byTakenAt(WalkGalleryItem a, WalkGalleryItem b) =>
      a.photo.takenAt.compareTo(b.photo.takenAt);
}
