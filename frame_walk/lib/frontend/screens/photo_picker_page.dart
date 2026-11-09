import 'package:flutter/material.dart';

import '../../backend/services/gallery_pager.dart';
import '../../backend/services/local_photo_service.dart';
import '../../models/gallery_photo.dart';
import '../widgets/local_photo_thumbnail.dart';

// Browse the camera roll, newest first, and pick photos to add to a walk.
// Loads more as the user scrolls. Pops with the selected photos, or null if
// cancelled.
class PhotoPickerPage extends StatefulWidget {
  final LocalPhotoService photoService;
  final GalleryAccess access;

  const PhotoPickerPage({
    super.key,
    required this.photoService,
    required this.access,
  });

  @override
  State<PhotoPickerPage> createState() => _PhotoPickerPageState();
}

class _PhotoPickerPageState extends State<PhotoPickerPage> {
  late final GalleryPager _pager = GalleryPager(
    (page, pageSize) =>
        widget.photoService.fetchPhotos(page: page, pageSize: pageSize),
  );
  final _scrollController = ScrollController();
  final Map<String, GalleryPhoto> _selected = {};

  @override
  void initState() {
    super.initState();
    _pager.addListener(_onPagerChanged);
    _scrollController.addListener(_onScroll);
    _pager.loadNextPage();
  }

  @override
  void dispose() {
    _pager.removeListener(_onPagerChanged);
    _pager.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPagerChanged() => setState(() {});

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 600) {
      _pager.loadNextPage();
    }
  }

  void _toggle(GalleryPhoto photo) {
    setState(() {
      if (_selected.remove(photo.assetId) == null) {
        _selected[photo.assetId] = photo;
      }
    });
  }

  Future<void> _manageSelection() async {
    await widget.photoService.manageLimitedSelection();
    _selected.clear();
    await _pager.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _pager.photos;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selected.isEmpty ? 'Add photos' : '${_selected.length} selected',
        ),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected.values.toList()),
            child: const Text('Add'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.access == GalleryAccess.limited)
            MaterialBanner(
              content: const Text(
                'FrameWalk can only see the photos you selected.',
              ),
              actions: [
                TextButton(
                  onPressed: _manageSelection,
                  child: const Text('Change selection'),
                ),
              ],
            ),
          Expanded(
            child: photos.isEmpty
                ? Center(
                    child: _pager.isLoading
                        ? const CircularProgressIndicator()
                        : const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No photos found on this device.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                  )
                : GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: photos.length + (_pager.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= photos.length) {
                        // Covers a first page too short to scroll. Deferred
                        // because loading notifies listeners, which can't
                        // happen during build.
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _pager.loadNextPage(),
                        );
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      final photo = photos[index];
                      return LocalPhotoThumbnail(
                        key: ValueKey(photo.assetId),
                        photoService: widget.photoService,
                        assetId: photo.assetId,
                        size: 200,
                        isSelected: _selected.containsKey(photo.assetId),
                        onTap: () => _toggle(photo),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
