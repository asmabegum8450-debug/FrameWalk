import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/walk_photo_link.dart';
import '../../models/walk_record.dart';

// Every completed walk of one route, newest first.
class CompletedRouteSummary {
  final String routeId;
  final String routeTitle;
  final List<WalkRecord> walks;

  const CompletedRouteSummary({
    required this.routeId,
    required this.routeTitle,
    required this.walks,
  });

  DateTime get lastWalkedAt => walks.first.completedAt;
}

// Firestore storage for walk history and walk-to-photo links. Has no access
// to the device gallery and stores no image data.
//
//   users/{uid}/walks/{walkId}                        WalkRecord
//   users/{uid}/walks/{walkId}/photoLinks/{linkId}    WalkPhotoLink
class WalkHistoryService {
  final FirebaseFirestore _firestore;

  WalkHistoryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _walks(String userId) =>
      _firestore.collection('users').doc(userId).collection('walks');

  CollectionReference<Map<String, dynamic>> _photoLinks(
    String userId,
    String walkId,
  ) =>
      _walks(userId).doc(walkId).collection('photoLinks');

  // Saves a finished walk and adds it to the user's completed-route count in
  // one write, so the two can't disagree. Returns the walk with its new ID.
  Future<WalkRecord> saveCompletedWalk(WalkRecord walk) async {
    final walkDoc = _walks(walk.userId).doc();
    final batch = _firestore.batch()
      ..set(walkDoc, walk.toMap())
      ..update(_firestore.collection('users').doc(walk.userId), {
        'routesCompleted': FieldValue.increment(1),
      });
    await batch.commit();
    return walk.withId(walkDoc.id);
  }

  Future<List<WalkRecord>> fetchWalks(String userId) async {
    final snapshot = await _walks(userId)
        .orderBy('completedAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => WalkRecord.fromMap(doc.id, doc.data()))
        .toList();
  }

  // Groups walks by route. Routes are ordered by most recent walk.
  static List<CompletedRouteSummary> groupByRoute(List<WalkRecord> walks) {
    final byRoute = <String, List<WalkRecord>>{};
    for (final walk in walks) {
      byRoute.putIfAbsent(walk.routeId, () => []).add(walk);
    }
    final summaries = byRoute.entries.map((entry) {
      final routeWalks = [...entry.value]
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
      return CompletedRouteSummary(
        routeId: entry.key,
        routeTitle: routeWalks.first.routeTitle,
        walks: routeWalks,
      );
    }).toList()
      ..sort((a, b) => b.lastWalkedAt.compareTo(a.lastWalkedAt));
    return summaries;
  }

  Future<List<WalkPhotoLink>> fetchPhotoLinks(
    String userId,
    String walkId,
  ) async {
    final snapshot = await _photoLinks(userId, walkId).get();
    return snapshot.docs
        .map((doc) => WalkPhotoLink.fromMap(doc.id, doc.data()))
        .toList();
  }

  // Creates or replaces a link. Never affects the photo itself.
  Future<void> savePhotoLink(WalkPhotoLink link) {
    return _photoLinks(link.userId, link.walkId).doc(link.id).set(link.toMap());
  }

  Future<void> savePhotoLinks(List<WalkPhotoLink> links) async {
    if (links.isEmpty) return;
    final batch = _firestore.batch();
    for (final link in links) {
      batch.set(_photoLinks(link.userId, link.walkId).doc(link.id), link.toMap());
    }
    await batch.commit();
  }

  // Deletes link records only. Used to clean up links whose photo was deleted
  // from this device.
  Future<void> deletePhotoLinks(List<WalkPhotoLink> links) async {
    if (links.isEmpty) return;
    final batch = _firestore.batch();
    for (final link in links) {
      batch.delete(_photoLinks(link.userId, link.walkId).doc(link.id));
    }
    await batch.commit();
  }
}
