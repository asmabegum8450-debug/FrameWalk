import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../backend/services/local_photo_service.dart';

// A square thumbnail of a photo from the device gallery, loaded on demand.
// Shows a placeholder while loading and an icon if the photo can't be read.
class LocalPhotoThumbnail extends StatefulWidget {
  final LocalPhotoService photoService;
  final String assetId;
  final int size;
  final bool isSuggested;
  final bool isSelected;
  final VoidCallback? onTap;

  const LocalPhotoThumbnail({
    super.key,
    required this.photoService,
    required this.assetId,
    this.size = 256,
    this.isSuggested = false,
    this.isSelected = false,
    this.onTap,
  });

  @override
  State<LocalPhotoThumbnail> createState() => _LocalPhotoThumbnailState();
}

class _LocalPhotoThumbnailState extends State<LocalPhotoThumbnail> {
  late Future<Uint8List?> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(LocalPhotoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId ||
        oldWidget.size != widget.size) {
      _bytes = _load();
    }
  }

  Future<Uint8List?> _load() =>
      widget.photoService.loadThumbnail(widget.assetId, size: widget.size);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: widget.isSuggested ? 'Suggested photo' : 'Photo',
      selected: widget.isSelected,
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xFFE2E9DF),
                child: FutureBuilder<Uint8List?>(
                  future: _bytes,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const SizedBox.shrink();
                    }
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey),
                      );
                    }
                    return Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey),
                      ),
                    );
                  },
                ),
              ),
              if (widget.isSuggested)
                Positioned(
                  top: 4,
                  left: 4,
                  child: _Badge(
                    icon: Icons.auto_awesome,
                    color: colorScheme.surface,
                    iconColor: colorScheme.primary,
                  ),
                ),
              if (widget.isSelected) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.primary, width: 3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _Badge(
                    icon: Icons.check,
                    color: colorScheme.primary,
                    iconColor: colorScheme.onPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;

  const _Badge({
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 14, color: iconColor),
    );
  }
}
