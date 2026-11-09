import 'package:flutter/material.dart';

import '../../backend/services/walk_gallery_service.dart';
import '../../backend/services/walk_history_service.dart';
import '../utils/walk_formatting.dart';
import 'walk_photos_page.dart';

// Lists each time the user walked one route. Tapping a walk opens its photos.
class WalkedRoutePage extends StatelessWidget {
  final CompletedRouteSummary summary;
  final WalkGalleryService galleryService;

  const WalkedRoutePage({
    super.key,
    required this.summary,
    required this.galleryService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(summary.routeTitle)),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: summary.walks.length,
        itemBuilder: (context, index) {
          final walk = summary.walks[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: Colors.white,
              elevation: 1,
              child: ListTile(
                leading: const Icon(Icons.directions_walk),
                title: Text(formatWalkDate(walk.startedAt)),
                subtitle: Text(
                  '${formatWalkTime(walk.startedAt)} – '
                  '${formatWalkTime(walk.completedAt)} · '
                  '${formatWalkDuration(walk.duration)} · '
                  '${walk.stops.length} stops',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WalkPhotosPage(
                      walk: walk,
                      galleryService: galleryService,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
