
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/walked_route.dart';
import '../../backend/providers/profile_provider.dart';
import '../screens/walk_gallery_page.dart';

// Displays the signed-in user's completed walks, newest first.
// Tapping a walk opens its photo gallery.
class CompletedWalksList extends StatelessWidget {
  const CompletedWalksList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profile, child) {

        checkValidProfile(profile);

        final walks = profile.walkedRoutes;

        return RefreshIndicator(
          onRefresh: profile.refresh,
          child: walks.isEmpty
              // Keep the list scrollable so pull-to-refresh works.
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Text('No previous walks yet.'),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  itemCount: walks.length,
                  itemBuilder: (context, index) {
                    return _WalkTile(
                      walk: walks[index],
                      onTap: () async {
                        await WalkGalleryPage.open(
                          context,
                          walks[index].id,
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  // Checks if the ProfileProvider is passing in valid information to be displayed
  Center checkValidProfile(ProfileProvider profile){
    // Still loading account and walk information.
        if (profile.isLoading ||
            profile.status == ProfileStatus.initial) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        // Nobody is signed in.
        if (profile.status == ProfileStatus.signedOut) {
          return const Center(
            child: Text('Please log in to view your walks.'),
          );
        }

        // Something went wrong while loading.
        if (profile.status == ProfileStatus.error) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.errorMessage ??
                      'Could not load your walks.',
                ),
                TextButton(
                  onPressed: profile.refresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
      return const Center(child: Text('Something went wrong - reload and try again'));
  }
}

class _WalkTile extends StatelessWidget {
  const _WalkTile({
    required this.walk,
    required this.onTap,
  });

  final WalkedRoute walk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(
          walk.completedAt!.toLocal(),
        );

    final stops = walk.stops.length;

    return Card(
      child: ListTile(
        title: Text(
          walk.routeTitle.isEmpty ? 'Walk' : walk.routeTitle,
        ),
        subtitle: Text(
          '$date · $stops stop${stops == 1 ? '' : 's'}',
        ),
        trailing: const Icon(
          Icons.photo_library_outlined,
        ),
        onTap: onTap,
      ),
    );
  }
}
