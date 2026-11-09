import 'package:flutter/foundation.dart';

import '../../models/gallery_photo.dart';
import 'local_photo_service.dart';

typedef GalleryPageFetcher = Future<GalleryPage> Function(
  int page,
  int pageSize,
);

// Loads gallery photos one page at a time as the user scrolls, so the whole
// camera roll is never held in memory at once.
class GalleryPager extends ChangeNotifier {
  final GalleryPageFetcher _fetchPage;
  final int pageSize;

  final List<GalleryPhoto> _photos = [];
  final Set<String> _seenIds = {};
  int _nextPage = 0;
  bool _hasMore = true;
  bool _isLoading = false;

  // Bumped by refresh() so a page still loading from before is discarded.
  int _generation = 0;

  GalleryPager(this._fetchPage, {this.pageSize = 60});

  List<GalleryPhoto> get photos => List.unmodifiable(_photos);
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    final generation = _generation;
    final GalleryPage result;
    try {
      result = await _fetchPage(_nextPage, pageSize);
    } catch (error) {
      debugPrint('Could not load gallery page $_nextPage: $error');
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
      return;
    }
    if (generation != _generation) return;

    // Photos added while scrolling shift later pages, which can repeat a
    // photo from an earlier page.
    for (final photo in result.photos) {
      if (_seenIds.add(photo.assetId)) _photos.add(photo);
    }
    _nextPage++;
    _hasMore = result.hasMore;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() {
    _generation++;
    _photos.clear();
    _seenIds.clear();
    _nextPage = 0;
    _hasMore = true;
    _isLoading = false;
    return loadNextPage();
  }
}
