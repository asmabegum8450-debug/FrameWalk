import 'dart:math';

import '../../models/gallery_photo.dart';
import '../../models/walk_record.dart';

enum MatchStrength {
  // Taken during the walk, within [WalkPhotoMatcher.stopRadiusMeters] of a stop.
  atStop,

  // Taken during the walk along the route, but not close to one stop.
  nearRoute,

  // Taken during the walk, with no GPS to confirm where.
  timeOnly,

  // Taken during the walk, but GPS puts it well away from the route.
  farFromRoute,

  // Not taken during the walk.
  outsideWindow,
}

class PhotoMatch {
  final GalleryPhoto photo;
  final MatchStrength strength;

  // Set only for [MatchStrength.atStop].
  final String? stopId;

  // Distance to the nearest stop, when the photo has GPS.
  final double? distanceMeters;

  const PhotoMatch({
    required this.photo,
    required this.strength,
    this.stopId,
    this.distanceMeters,
  });

  bool get isLikelyFromWalk =>
      strength == MatchStrength.atStop ||
      strength == MatchStrength.nearRoute ||
      strength == MatchStrength.timeOnly;
}

class TimeWindow {
  final DateTime start;
  final DateTime end;

  const TimeWindow(this.start, this.end);

  bool contains(DateTime time) => !time.isBefore(start) && !time.isAfter(end);
}

// Decides which gallery photos probably came from a walk. Time is required
// (every photo has a timestamp). GPS only adds detail, because many photos
// have none.
class WalkPhotoMatcher {
  // People often photograph a stop shortly before tapping "start", or after
  // finishing, so the window is a little wider than the recorded walk.
  final Duration leadIn;
  final Duration trailOut;
  final double stopRadiusMeters;
  final double routeCorridorMeters;

  const WalkPhotoMatcher({
    this.leadIn = const Duration(minutes: 5),
    this.trailOut = const Duration(minutes: 15),
    this.stopRadiusMeters = 75,
    this.routeCorridorMeters = 400,
  });

  TimeWindow windowFor(WalkRecord walk) => TimeWindow(
        walk.startedAt.subtract(leadIn),
        walk.completedAt.add(trailOut),
      );

  PhotoMatch match(WalkRecord walk, GalleryPhoto photo) {
    if (!windowFor(walk).contains(photo.takenAt)) {
      return PhotoMatch(photo: photo, strength: MatchStrength.outsideWindow);
    }

    final location = photo.location;
    if (location == null || walk.stops.isEmpty) {
      return PhotoMatch(photo: photo, strength: MatchStrength.timeOnly);
    }

    WalkStopSnapshot? nearestStop;
    var nearestDistance = double.infinity;
    for (final stop in walk.stops) {
      final distance = distanceMeters(
        location,
        GeoCoordinate(stop.latitude, stop.longitude),
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestStop = stop;
      }
    }

    if (nearestDistance <= stopRadiusMeters) {
      return PhotoMatch(
        photo: photo,
        strength: MatchStrength.atStop,
        stopId: nearestStop!.stopId,
        distanceMeters: nearestDistance,
      );
    }

    final strength = _distanceToRoute(walk, location) <= routeCorridorMeters
        ? MatchStrength.nearRoute
        : MatchStrength.farFromRoute;
    return PhotoMatch(
      photo: photo,
      strength: strength,
      distanceMeters: nearestDistance,
    );
  }

  // Shortest distance to the path between consecutive stops. Stops are
  // close together, so a flat projection is accurate enough.
  double _distanceToRoute(WalkRecord walk, GeoCoordinate point) {
    final stops = walk.stops;
    if (stops.length == 1) {
      return distanceMeters(
        point,
        GeoCoordinate(stops.first.latitude, stops.first.longitude),
      );
    }

    final metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        111320.0 * cos(point.latitude * pi / 180).abs();
    Point<double> project(double lat, double lng) => Point(
          (lng - point.longitude) * metersPerDegreeLng,
          (lat - point.latitude) * metersPerDegreeLat,
        );

    var shortest = double.infinity;
    for (var i = 0; i < stops.length - 1; i++) {
      final a = project(stops[i].latitude, stops[i].longitude);
      final b = project(stops[i + 1].latitude, stops[i + 1].longitude);
      shortest = min(shortest, _distanceFromOriginToSegment(a, b));
    }
    return shortest;
  }

  static double _distanceFromOriginToSegment(Point<double> a, Point<double> b) {
    final segment = b - a;
    final lengthSquared = segment.x * segment.x + segment.y * segment.y;
    if (lengthSquared == 0) return a.magnitude;
    final t = (-(a.x * segment.x + a.y * segment.y) / lengthSquared)
        .clamp(0.0, 1.0);
    return Point(a.x + segment.x * t, a.y + segment.y * t).magnitude;
  }

  // Great-circle distance using the haversine formula.
  static double distanceMeters(GeoCoordinate a, GeoCoordinate b) {
    const earthRadius = 6371000.0;
    double toRadians(double degrees) => degrees * pi / 180;
    final dLat = toRadians(b.latitude - a.latitude);
    final dLng = toRadians(b.longitude - a.longitude);
    final h = pow(sin(dLat / 2), 2) +
        cos(toRadians(a.latitude)) *
            cos(toRadians(b.latitude)) *
            pow(sin(dLng / 2), 2);
    return 2 * earthRadius * asin(sqrt(h));
  }
}
