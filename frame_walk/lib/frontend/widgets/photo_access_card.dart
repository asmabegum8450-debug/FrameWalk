import 'package:flutter/material.dart';

// Explains why FrameWalk wants photo access before the system prompt appears,
// and offers system settings once the OS stops showing the prompt.
class PhotoAccessCard extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onOpenSettings;

  // True after a request in this session was refused. Android stops showing
  // the prompt after repeated refusals, so settings is the only way left.
  final bool wasDenied;

  const PhotoAccessCard({
    super.key,
    required this.onAllow,
    required this.onOpenSettings,
    this.wasDenied = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.photo_library_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              wasDenied ? 'Photo access is off' : 'See the photos from your walk',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'FrameWalk shows the photos you took on this walk, sorted by '
              'stop and prompt. It finds them by when and where they were '
              'taken.\n\n'
              'Your photos stay on this phone. FrameWalk never uploads them '
              'and never changes or deletes them.',
            ),
            if (wasDenied) ...[
              const SizedBox(height: 8),
              const Text(
                'To turn it on, open Settings and allow access to photos. '
                'You can allow all photos or only the ones you choose.',
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: onAllow,
                  child: const Text('Allow photo access'),
                ),
                if (wasDenied)
                  OutlinedButton(
                    onPressed: onOpenSettings,
                    child: const Text('Open Settings'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
