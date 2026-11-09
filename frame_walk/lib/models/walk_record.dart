import 'package:cloud_firestore/cloud_firestore.dart';

import 'route_stop.dart';

// One occasion when a user walked a route. Stored at
// users/{userId}/walks/{id}.
//
// Stops and prompts are copied in at completion time, so history still makes
// sense if the route is later edited, and so photos can be matched to stop
// coordinates without looking the route up again.
class WalkRecord {
  final String id;
  final String userId;
  final String routeId;
  final String routeTitle;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<WalkStopSnapshot> stops;

  WalkRecord({
    required this.id,
    required this.userId,
    required this.routeId,
    required this.routeTitle,
    required this.startedAt,
    required this.completedAt,
    required List<WalkStopSnapshot> stops,
  }) : stops = List.unmodifiable(stops) {
    if (completedAt.isBefore(startedAt)) {
      throw ArgumentError('A walk cannot end before it starts');
    }
  }

  // Builds a record for a walk that has just finished. [id] is empty until
  // WalkHistoryService saves it.
  factory WalkRecord.fromRoute({
    required String userId,
    required String routeId,
    required String routeTitle,
    required List<RouteStop> stops,
    required DateTime startedAt,
    required DateTime completedAt,
  }) {
    return WalkRecord(
      id: '',
      userId: userId,
      routeId: routeId,
      routeTitle: routeTitle,
      startedAt: startedAt,
      completedAt: completedAt,
      stops: stops.map(WalkStopSnapshot.fromRouteStop).toList(),
    );
  }

  Duration get duration => completedAt.difference(startedAt);

  List<String> get stopIds => stops.map((stop) => stop.stopId).toList();

  List<String> get promptIds => [
        for (final stop in stops)
          for (final prompt in stop.prompts) prompt.id,
      ];

  // The stop that owns a prompt, or null if the prompt isn't on this walk.
  WalkStopSnapshot? stopForPrompt(String? promptId) {
    for (final stop in stops) {
      if (stop.prompts.any((prompt) => prompt.id == promptId)) return stop;
    }
    return null;
  }

  WalkRecord withId(String newId) => WalkRecord(
        id: newId,
        userId: userId,
        routeId: routeId,
        routeTitle: routeTitle,
        startedAt: startedAt,
        completedAt: completedAt,
        stops: stops,
      );

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'routeId': routeId,
        'routeTitle': routeTitle,
        'startedAt': Timestamp.fromDate(startedAt),
        'completedAt': Timestamp.fromDate(completedAt),
        'stopIds': stopIds,
        'promptIds': promptIds,
        'stops': stops.map((stop) => stop.toMap()).toList(),
      };

  factory WalkRecord.fromMap(String id, Map<String, dynamic> map) {
    return WalkRecord(
      id: id,
      userId: map['userId'] as String,
      routeId: map['routeId'] as String,
      routeTitle: map['routeTitle'] as String? ?? '',
      startedAt: readFirestoreDate(map['startedAt']),
      completedAt: readFirestoreDate(map['completedAt']),
      stops: ((map['stops'] as List?) ?? const [])
          .map((stop) =>
              WalkStopSnapshot.fromMap(Map<String, dynamic>.from(stop as Map)))
          .toList(),
    );
  }
}

class WalkStopSnapshot {
  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;
  final List<WalkPrompt> prompts;

  WalkStopSnapshot({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
    required List<WalkPrompt> prompts,
  }) : prompts = List.unmodifiable(prompts);

  factory WalkStopSnapshot.fromRouteStop(RouteStop stop) => WalkStopSnapshot(
        stopId: stop.id,
        stopName: stop.name,
        latitude: stop.latitude,
        longitude: stop.longitude,
        prompts: [
          WalkPrompt(id: WalkPrompt.idFor(stop.id, 0), text: stop.prompt),
        ],
      );

  Map<String, dynamic> toMap() => {
        'stopId': stopId,
        'stopName': stopName,
        'latitude': latitude,
        'longitude': longitude,
        'prompts': prompts.map((prompt) => prompt.toMap()).toList(),
      };

  factory WalkStopSnapshot.fromMap(Map<String, dynamic> map) =>
      WalkStopSnapshot(
        stopId: map['stopId'] as String,
        stopName: map['stopName'] as String? ?? '',
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        prompts: ((map['prompts'] as List?) ?? const [])
            .map((prompt) =>
                WalkPrompt.fromMap(Map<String, dynamic>.from(prompt as Map)))
            .toList(),
      );
}

class WalkPrompt {
  final String id;
  final String text;

  const WalkPrompt({required this.id, required this.text});

  // Prompts don't have their own IDs yet. PromptGenerator keys prompts by stop
  // ID and list position, so the same pair identifies a prompt here.
  static String idFor(String stopId, int index) => '$stopId#$index';

  Map<String, dynamic> toMap() => {'id': id, 'text': text};

  factory WalkPrompt.fromMap(Map<String, dynamic> map) => WalkPrompt(
        id: map['id'] as String,
        text: map['text'] as String? ?? '',
      );
}

// Firestore returns Timestamps; fakes and older writes may hold DateTimes.
DateTime readFirestoreDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  throw FormatException('Expected a timestamp but found $value');
}
