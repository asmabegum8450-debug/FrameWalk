import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/services/local_photo_service.dart';
import '../../backend/services/walk_gallery_service.dart';
import '../../models/gallery_photo.dart';
import '../../models/walk_record.dart';
import '../utils/walk_formatting.dart';
import '../widgets/local_photo_thumbnail.dart';
import '../widgets/photo_access_card.dart';
import 'photo_picker_page.dart';

// Photos from one walk, read from the device gallery and grouped by stop and
// prompt. Users can assign, reassign, add, or remove photos. Removing only
// takes a photo out of the walk; it stays in the camera roll.
class WalkPhotosPage extends StatefulWidget {
  final WalkRecord walk;
  final WalkGalleryService galleryService;

  const WalkPhotosPage({
    super.key,
    required this.walk,
    required this.galleryService,
  });

  @override
  State<WalkPhotosPage> createState() => _WalkPhotosPageState();
}

class _WalkPhotosPageState extends State<WalkPhotosPage>
    with WidgetsBindingObserver {
  WalkGallery? _gallery;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _wasDenied = false;
  StreamSubscription<void>? _galleryChanges;
  Timer? _changeDebounce;

  // Ignores a load that finishes after a newer one has started.
  int _loadGeneration = 0;

  LocalPhotoService get _photos => widget.galleryService.photos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _galleryChanges?.cancel();
    _changeDebounce?.cancel();
    super.dispose();
  }

  // Users can change photo access in system settings, or take and delete
  // photos, while FrameWalk is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    // The first load runs from initState, where setState isn't allowed;
    // _isLoading already starts as true.
    if (_gallery != null || _loadFailed) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    try {
      final gallery = await widget.galleryService.loadGallery(widget.walk);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _gallery = gallery;
        _isLoading = false;
      });
      if (gallery.access.canRead) _listenForGalleryChanges();
    } catch (error) {
      debugPrint('Could not load walk photos: $error');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  void _listenForGalleryChanges() {
    // Changes arrive in bursts (one per file), so reload once they settle.
    _galleryChanges ??= _photos.changes.listen((_) {
      _changeDebounce?.cancel();
      _changeDebounce = Timer(const Duration(milliseconds: 800), _load);
    });
  }

  Future<void> _requestAccess() async {
    final access = await _photos.requestAccess();
    if (!mounted) return;
    setState(() => _wasDenied = !access.canRead);
    await _load();
  }

  Future<void> _runAndReload(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Could not update walk photos: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save that change. Try again.")),
        );
      }
    }
    await _load();
  }

  Future<void> _openPhotoActions(WalkGalleryItem item) async {
    final choice = await showModalBottomSheet<_PhotoChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PhotoChoiceSheet(
        walk: widget.walk,
        photoService: _photos,
        photo: item.photo,
        currentPromptId: item.promptId,
        isLinked: !item.isSuggested,
        isSuggested: item.isSuggested,
      ),
    );
    if (choice == null) return;

    await _runAndReload(() {
      if (choice.remove) {
        return widget.galleryService.removePhoto(widget.walk, item.photo);
      }
      return widget.galleryService.assignPhotos(
        widget.walk,
        [item.photo],
        promptId: choice.promptId,
      );
    });
  }

  Future<void> _addPhotos() async {
    final access = _gallery?.access ?? GalleryAccess.denied;
    final selected = await Navigator.push<List<GalleryPhoto>>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoPickerPage(photoService: _photos, access: access),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    final choice = await showModalBottomSheet<_PhotoChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PhotoChoiceSheet(
        walk: widget.walk,
        photoService: _photos,
        photoCount: selected.length,
        isLinked: false,
        isSuggested: false,
      ),
    );
    if (choice == null || choice.remove) return;

    await _runAndReload(() => widget.galleryService.assignPhotos(
          widget.walk,
          selected,
          promptId: choice.promptId,
        ));
  }

  Future<void> _manageLimitedSelection() async {
    await _photos.manageLimitedSelection();
    await _load();
  }

  Future<void> _forgetMissing() async {
    final missing = _gallery?.missing ?? const [];
    await _runAndReload(
      () => widget.galleryService.forgetMissingPhotos(missing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final walk = widget.walk;
    final gallery = _gallery;
    final canRead = gallery?.access.canRead ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(walk.routeTitle),
            Text(
              formatWalkDate(walk.startedAt),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          if (canRead)
            IconButton(
              tooltip: 'Add photos',
              onPressed: _addPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
        ],
      ),
      body: _buildBody(gallery),
    );
  }

  Widget _buildBody(WalkGallery? gallery) {
    if (gallery == null) {
      if (_loadFailed) {
        return _CenteredMessage(
          title: "Couldn't load this walk's photos",
          action: TextButton(onPressed: _load, child: const Text('Try again')),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (!gallery.access.canRead) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PhotoAccessCard(
            wasDenied: _wasDenied,
            onAllow: _requestAccess,
            onOpenSettings: _photos.openAccessSettings,
          ),
        ],
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final walk = gallery.walk;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          if (_isLoading)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (gallery.access == GalleryAccess.limited)
            SliverToBoxAdapter(
              child: _InfoBanner(
                icon: Icons.photo_library_outlined,
                message: "You've allowed FrameWalk to see selected photos "
                    'only. Photos outside your selection won\'t appear here.',
                actionLabel: 'Change selection',
                onAction: _manageLimitedSelection,
              ),
            ),
          if (gallery.missing.isNotEmpty)
            SliverToBoxAdapter(
              child: _InfoBanner(
                icon: Icons.hide_image_outlined,
                message: gallery.access == GalleryAccess.limited
                    ? '${_photoCount(gallery.missing.length)} added to this '
                        "walk aren't available. They may have been deleted, "
                        "or aren't in your selected photos."
                    : '${_photoCount(gallery.missing.length)} added to this '
                        'walk no longer exist on this device.',
                actionLabel: gallery.access == GalleryAccess.full
                    ? 'Remove from walk'
                    : null,
                onAction: _forgetMissing,
              ),
            ),
          if (gallery.otherDeviceCount > 0)
            SliverToBoxAdapter(
              child: _InfoBanner(
                icon: Icons.devices_outlined,
                message: '${_photoCount(gallery.otherDeviceCount)} were added '
                    'on another device and can only be viewed there.',
              ),
            ),
          if (!gallery.hasVisiblePhotos)
            SliverToBoxAdapter(child: _buildEmptyState(gallery)),
          for (final section in gallery.sections) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Stop ${_stopNumber(section.stop)} · '
                    '${section.stop.stopName}',
                subtitle: section.prompt?.text,
              ),
            ),
            if (section.items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'No photos for this prompt yet.',
                    style: textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                ),
              )
            else
              _buildGrid(section.items),
          ],
          if (gallery.unassigned.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Unassigned',
                subtitle: 'Part of this walk, not tied to a prompt.',
              ),
            ),
            _buildGrid(gallery.unassigned),
          ],
          if (gallery.suggestions.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Possibly from this walk',
                subtitle: 'Taken between '
                    '${formatWalkTime(walk.startedAt)} and '
                    '${formatWalkTime(walk.completedAt)}. Tap a photo to '
                    'add it to a prompt.',
              ),
            ),
            _buildGrid(gallery.suggestions),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _addPhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add photos from camera roll'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(WalkGallery gallery) {
    final walk = gallery.walk;
    final noMatches = gallery.timeWindowPhotoCount == 0;
    return _CenteredMessage(
      title: 'No photos associated with this walk',
      body: noMatches
          ? 'No photos in your camera roll match this walk\'s time window '
              '(${formatWalkTime(walk.startedAt)} – '
              '${formatWalkTime(walk.completedAt)}). You can still add '
              'photos yourself.'
          : 'Photos from this time were removed from the walk. You can add '
              'photos yourself.',
    );
  }

  SliverPadding _buildGrid(List<WalkGalleryItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return LocalPhotoThumbnail(
            key: ValueKey(item.photo.assetId),
            photoService: _photos,
            assetId: item.photo.assetId,
            isSuggested: item.isSuggested,
            onTap: () => _openPhotoActions(item),
          );
        },
      ),
    );
  }

  int _stopNumber(WalkStopSnapshot stop) =>
      widget.walk.stops.indexOf(stop) + 1;

  static String _photoCount(int count) =>
      count == 1 ? '1 photo' : '$count photos';
}

class _PhotoChoice {
  // Null means unassigned.
  final String? promptId;
  final bool remove;

  const _PhotoChoice.assign(this.promptId) : remove = false;
  const _PhotoChoice.remove()
      : promptId = null,
        remove = true;
}

// Bottom sheet for choosing which prompt a photo (or a set of new photos)
// belongs to, or removing a photo from the walk.
class _PhotoChoiceSheet extends StatelessWidget {
  final WalkRecord walk;
  final LocalPhotoService photoService;
  final GalleryPhoto? photo;
  final int photoCount;
  final String? currentPromptId;
  final bool isLinked;
  final bool isSuggested;

  const _PhotoChoiceSheet({
    required this.walk,
    required this.photoService,
    required this.isLinked,
    required this.isSuggested,
    this.photo,
    this.photoCount = 1,
    this.currentPromptId,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final photo = this.photo;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            if (photo != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: LocalPhotoThumbnail(
                        photoService: photoService,
                        assetId: photo.assetId,
                        size: 384,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Taken ${formatWalkDate(photo.takenAt)} at '
                        '${formatWalkTime(photo.takenAt)}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                photo == null
                    ? 'Add ${photoCount == 1 ? '1 photo' : '$photoCount photos'} to'
                    : 'Which prompt is this photo for?',
                style: textTheme.titleMedium,
              ),
            ),
            for (final stop in walk.stops)
              for (final prompt in stop.prompts)
                ListTile(
                  title: Text(stop.stopName),
                  subtitle: Text(prompt.text),
                  trailing: isLinked && prompt.id == currentPromptId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () =>
                      Navigator.pop(context, _PhotoChoice.assign(prompt.id)),
                ),
            ListTile(
              title: const Text('No prompt'),
              subtitle: const Text('Keep it with this walk, unassigned.'),
              trailing: isLinked && currentPromptId == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(context, const _PhotoChoice.assign(null)),
            ),
            if (photo != null && (isLinked || isSuggested)) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text(
                  isSuggested ? 'Not from this walk' : 'Remove from this walk',
                ),
                subtitle: const Text('The photo stays in your camera roll.'),
                onTap: () =>
                    Navigator.pop(context, const _PhotoChoice.remove()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoBanner({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: const Color(0xFFE2E9DF),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
              if (actionLabel != null)
                TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String title;
  final String? body;
  final Widget? action;

  const _CenteredMessage({required this.title, this.body, this.action});

  @override
  Widget build(BuildContext context) {
    final body = this.body;
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
          ?action,
        ],
      ),
    );
  }
}
