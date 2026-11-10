import 'package:flutter/foundation.dart';

import '../../models/mock_route_data.dart';
import '../services/route_manager.dart';

// Single source of truth for routes and bookmarks.
class RouteProvider extends ChangeNotifier {
  // Defaults must match the strings used by RouteFilterChips.
  // These will be used for the placeholder "any" filter option for duration, distance, and scenery
  static const anyDuration = 'Any duration';
  static const anyDistance = 'Any distance';
  static const anyScenery = 'Any scenery';

  /// Creates a RouteProvider 
  /// Params:
  ///  manager - the RouteManager associated with this RouteProvider. can be null for testing
  ///  purposes (unit tests can build their own RouteManagers with their own routes/mock data)
  ///  seedMockData - true if we're using mock data, for now true until we add in other data
  RouteProvider({RouteManager? manager, bool seedMockData = true})
    : _manager = manager ?? RouteManager() {
    if (seedMockData) {
      for (final route in MockRouteData.routes) {
        _manager.addRoute(route);
      }
    }
  }

  final RouteManager _manager;

  List<WalkingRoute> get routes => _manager.getAllRoutes();

  List<WalkingRoute> get bookmarkedRoutes => _manager.getBookmarkedRoutes();

  // gets a WalkingRoute by ID
  WalkingRoute? byId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    return _manager.getRoute(id);
  }

  bool isBookmarked(String id) => byId(id)?.isBookmarked ?? false;

  /// Routes matching the search text and every selected filter.
  /// Each page keeps its own filter selections and passes them in.
  /// parameters default to default values
  List<WalkingRoute> search({
    String query = '',
    String duration = anyDuration,
    String distance = anyDistance,
    String scenery = anyScenery,
  }) {
    final q = query.trim().toLowerCase();

    final sceneryMatches = _manager.filterBySceneryTags(
      scenery == anyScenery ? const [] : [scenery],
    );

    return sceneryMatches.where((route) {
      final matchesQuery = route.name.toLowerCase().contains(q);

      final minutes = route.estimatedMinutes;
      final matchesDuration = switch (duration) {
        '0-15 min' => minutes <= 15,
        '15-30 min' => minutes > 15 && minutes <= 30,
        '30+ min' => minutes > 30,
        _ => true,
      };

      final miles = route.distanceMiles;
      final matchesDistance = switch (distance) {
        'Under 1 mi' => miles < 1,
        '1-2 mi' => miles >= 1 && miles <= 2,
        '2+ mi' => miles > 2,
        _ => true,
      };

      return matchesQuery && matchesDuration && matchesDistance;
    }).toList();
  }

  // notifies listeners to rebuild if the bookmark toggle was successful
  void toggleBookmark(String routeId) {
    if (_manager.toggleBookmark(routeId)) notifyListeners();
  }

  void addRoute(WalkingRoute route) {
    _manager.addRoute(route);
    notifyListeners();
  }

  //unsure if we need this
  void removeRoute(String routeId) {
    if (_manager.removeRoute(routeId)) notifyListeners();
  }

  //unsure if we need this
  void updateRoute(WalkingRoute route) {
    if (_manager.updateRoute(route)) notifyListeners();
  }
}