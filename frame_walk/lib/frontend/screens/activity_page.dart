
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../backend/services/local_photo_service.dart';
import '../../backend/services/photo_manager_photo_service.dart';
import '../../backend/services/walk_gallery_service.dart';
import '../../backend/services/walk_history_service.dart';
import '../../models/photo_route.dart';
import '../utils/walk_formatting.dart';
import '../widgets/route_card.dart';
import '../../models/mock_route_data.dart';
import 'route_info_page.dart';
import 'walked_route_page.dart';

class ActivityPage extends StatefulWidget {
  // Services and user ID default to the real Firebase and gallery versions.
  // Tests pass fakes.
  final WalkHistoryService? walkHistoryService;
  final LocalPhotoService? photoService;
  final String? userId;

  // Fires when the Activity tab is selected, so walk history is refreshed.
  final Listenable? refreshSignal;

  const ActivityPage({
    super.key,
    this.walkHistoryService,
    this.photoService,
    this.userId,
    this.refreshSignal,
  });

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with WidgetsBindingObserver {
  // starts on the previous walks tab, which is 0. saved walks is 1
  int _selectedTab = 0;

  // Completed walks from Firestore, grouped by route. Null while loading.
  List<CompletedRouteSummary>? _completedRoutes;
  bool _walksFailed = false;
  WalkHistoryService? _walkHistory;
  WalkGalleryService? _galleryService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.refreshSignal?.addListener(_loadWalks);
    _loadWalks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.refreshSignal?.removeListener(_loadWalks);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadWalks();
  }

  // Services are created on first use, not in the constructor, so the page
  // can be built where Firebase isn't set up (for example in widget tests).
  WalkHistoryService get _history =>
      _walkHistory ??= widget.walkHistoryService ?? WalkHistoryService();

  WalkGalleryService get _gallery => _galleryService ??= WalkGalleryService(
        photos: widget.photoService ?? PhotoManagerPhotoService(),
        history: _history,
      );

  Future<void> _loadWalks() async {
    try {
      final userId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
      final walks =
          userId == null ? const <Never>[] : await _history.fetchWalks(userId);
      if (!mounted) return;
      setState(() {
        _completedRoutes = WalkHistoryService.groupByRoute(walks);
        _walksFailed = false;
      });
    } catch (error) {
      debugPrint('Could not load walk history: $error');
      if (!mounted) return;
      setState(() => _walksFailed = true);
    }
  }

  void _openCompletedRoute(CompletedRouteSummary summary) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WalkedRoutePage(
          summary: summary,
          galleryService: _gallery,
        ),
      ),
    );
  }

 // Temporary saved-route data.
  // These should eventually be shared with HomePage.
  final List<PhotoRoute> _savedRoutes = [
    const PhotoRoute(
      id: '1',
      title: 'Red Square Walk',
      durationMinutes: 10,
      distanceMiles: 0.5,
      sceneryTags: ['Architecture', 'Urban'],
      isBookmarked: true,
    ),
    const PhotoRoute(
      id: '2',
      title: 'UW Nature Walk',
      durationMinutes: 20,
      distanceMiles: 1.2,
      sceneryTags: ['Nature', 'Urban'],
      isBookmarked: true,
    ),
    const PhotoRoute(
      id: '3',
      title: 'Waterfront Views',
      durationMinutes: 30,
      distanceMiles: 1.8,
      sceneryTags: ['Water', 'Nature'],
      isBookmarked: true,
    ),
  ];

  // for now replaces the route with a copy that isn't bookmarked - change in future
  void _toggleBookmark(PhotoRoute route) {
    setState(() {
      final index = _savedRoutes.indexWhere(
        (savedRoute) => savedRoute.id == route.id,
      );

      if (index != -1) {
        _savedRoutes[index] = _savedRoutes[index].copyWith(
          isBookmarked: !_savedRoutes[index].isBookmarked,
        );
      }
    });
  }

  void _openRoute(PhotoRoute route) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => RouteInfoPage(
        route: route,
        stops: MockRouteData.getStops(route.id),
        routePoints: MockRouteData.getRoutePoints(route.id),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final savedRoutes = _savedRoutes
        .where((route) => route.isBookmarked)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            'FrameWalk',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),

        // Previous Walks / Saved Walks tabs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E9DF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                _buildTabButton(
                  label: 'Previous Walks',
                  index: 0,
                ),
                _buildTabButton(
                  label: 'Saved Walks',
                  index: 1,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 32),

        // Tab content
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _selectedTab == 0 ? 'Previous Walks' : 'Saved Walks',
            style: Theme.of(context).textTheme.titleLarge
          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          child: _selectedTab == 0
              ? _buildPreviousWalks()

              // Saved routes use the same cards as Home.
              : savedRoutes.isEmpty
                  ? const Center(
                      child: Text('No saved walks yet.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      itemCount: savedRoutes.length,
                      itemBuilder: (context, index) {
                        final route = savedRoutes[index];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RouteCard(
                            route: route,
                            onTap: () => _openRoute(route),
                            onBookmarkTap: () {
                              _toggleBookmark(route);
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildPreviousWalks() {
    final routes = _completedRoutes;
    if (routes == null) {
      return _walksFailed
          ? Center(
              child: TextButton(
                onPressed: _loadWalks,
                child: const Text("Couldn't load your walks. Try again"),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadWalks,
      child: routes.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No previous walks yet. Finish a walk and it will show '
                    'up here with your photos.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final summary = routes[index];
                final count = summary.walks.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: Colors.white,
                    elevation: 1,
                    child: ListTile(
                      title: Text(
                        summary.routeTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Walked ${count == 1 ? 'once' : '$count times'} · '
                        'Last on ${formatWalkDate(summary.lastWalkedAt)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openCompletedRoute(summary),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required int index,
  }) {
    final isSelected = _selectedTab == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
        },
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF195B50)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: isSelected ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
