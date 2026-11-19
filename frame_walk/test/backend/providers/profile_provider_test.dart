import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/providers/profile_provider.dart';
import 'package:frame_walk/backend/services/auth_service.dart';
import 'package:frame_walk/backend/services/walk_photo_service.dart';
import 'package:frame_walk/backend/services/walk_repository.dart';
import 'package:frame_walk/models/route_stop.dart';
import 'package:frame_walk/models/walked_route.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

import '../../fakes/fake_photo_storage.dart';

const uid = 'user-1';
const email = 'walker@example.com';

const stops = [
  RouteStop(
    id: 'red_1',
    name: 'Red Square',
    prompt: 'Find a pattern.',
    latitude: 47.6559,
    longitude: -122.3078,
  ),
  RouteStop(
    id: 'red_2',
    name: 'Suzzallo Library',
    prompt: 'Light and shadow.',
    latitude: 47.6553,
    longitude: -122.3099,
  ),
];

MockFirebaseAuth signedInAuth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: uid, email: email),
);

// Writes the account document the way AuthService.createAccount does.
Future<void> seedAccount(
  FakeFirebaseFirestore firestore, {
  String username = 'walker',
  int routesCompleted = 0,
  int photosTaken = 0,
}) {
  return firestore.collection('users').doc(uid).set({
    'username': username,
    'email': email,
    'routesCompleted': routesCompleted,
    'photosTaken': photosTaken,
  });
}

// Starts and finishes a walk through WalkRepository, as ActiveWalkPage does.
Future<WalkedRoute> completeWalk(
  WalkRepository repository, {
  required DateTime startedAt,
  String routeId = 'red',
}) async {
  final walk = WalkedRoute.start(
    id: repository.newWalkId(uid),
    userId: uid,
    routeId: routeId,
    routeTitle: 'Route $routeId',
    stops: stops,
    startedAt: startedAt,
  );
  await repository.createWalk(walk);
  final done = walk.copyWith(
    status: WalkStatus.completed,
    completedAt: startedAt.add(const Duration(minutes: 30)),
  );
  await repository.completeWalk(done);
  return done;
}

// Bytes WalkPhotoService.preparePhoto accepts as a JPEG.
Uint8List jpeg() => Uint8List(64)..setAll(0, [0xFF, 0xD8, 0xFF, 0xE0]);

List<String> ids(List<WalkedRoute> walks) => walks.map((w) => w.id).toList();

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late WalkRepository repository;

  // Provider that only loads when refresh is called, so tests control timing.
  ProfileProvider makeProvider({WalkRepository? walkRepository}) =>
      ProfileProvider(
        authService: AuthService(auth: auth, firestore: firestore),
        walkRepository: walkRepository ?? repository,
        listenToAuthChanges: false,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = signedInAuth();
    repository = WalkRepository(firestore: firestore);
  });

  // This group tests that ProfileProviders are constructed as expected
  group('construction', () {
    test('starts with no data before the first refresh', () {
      final provider = makeProvider();
      expect(provider.status, ProfileStatus.initial);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.account, isNull);
      expect(provider.username, isNull);
      expect(provider.email, isNull);
      expect(provider.walkedRoutes, isEmpty);
      expect(provider.routesCompleted, 0);
      expect(provider.photosUploaded, 0);
    });
  });

  // Tests that the account and walks load for the signed-in user
  group('loading', () {
    test('exposes the account information', () async {
      await seedAccount(firestore, username: 'walker');
      final provider = makeProvider();

      await provider.refresh();

      expect(provider.status, ProfileStatus.loaded);
      expect(provider.account?.uid, uid);
      expect(provider.username, 'walker');
      expect(provider.email, email);
      expect(provider.errorMessage, isNull);
    });

    test('exposes completed walks, newest first', () async {
      await seedAccount(firestore);
      final older = await completeWalk(
        repository,
        startedAt: DateTime(2026, 11, 1, 9),
      );
      final newer = await completeWalk(
        repository,
        startedAt: DateTime(2026, 11, 2, 9),
        routeId: 'blue',
      );
      final provider = makeProvider();

      await provider.refresh();

      expect(ids(provider.walkedRoutes), [newer.id, older.id]);
    });

    test('leaves out walks that are still active', () async {
      await seedAccount(firestore);
      await repository.createWalk(
        WalkedRoute.start(
          id: repository.newWalkId(uid),
          userId: uid,
          routeId: 'red',
          routeTitle: 'Route red',
          stops: stops,
          startedAt: DateTime(2026, 11, 1, 9),
        ),
      );
      final provider = makeProvider();

      await provider.refresh();

      expect(provider.walkedRoutes, isEmpty);
    });

    test(
      'a new account with no walks has empty history and zero stats',
      () async {
        await seedAccount(firestore);
        final provider = makeProvider();

        await provider.refresh();

        expect(provider.walkedRoutes, isEmpty);
        expect(provider.routesCompleted, 0);
        expect(provider.photosUploaded, 0);
      },
    );

    test('walkedRoutes cannot be modified by the UI', () async {
      await seedAccount(firestore);
      await completeWalk(repository, startedAt: DateTime(2026, 11, 1, 9));
      final provider = makeProvider();
      await provider.refresh();

      expect(() => provider.walkedRoutes.clear(), throwsUnsupportedError);
    });

    test('is loading while a refresh is in progress', () async {
      await seedAccount(firestore);
      final provider = makeProvider();

      final pending = provider.refresh();
      expect(provider.isLoading, isTrue);
      await pending;
      expect(provider.isLoading, isFalse);
    });
  });

  // Tests that the statistics come from the account's counters
  group('statistics', () {
    test('expose the stored route and photo counts', () async {
      await seedAccount(firestore, routesCompleted: 4, photosTaken: 11);
      final provider = makeProvider();

      await provider.refresh();

      expect(provider.routesCompleted, 4);
      expect(provider.photosUploaded, 11);
    });

    test(
      'count defaults to zero for an account saved without counters',
      () async {
        await firestore.collection('users').doc(uid).set({
          'username': 'walker',
          'email': email,
        });
        final provider = makeProvider();

        await provider.refresh();

        expect(provider.status, ProfileStatus.loaded);
        expect(provider.routesCompleted, 0);
        expect(provider.photosUploaded, 0);
      },
    );
  });

  // Tests that missing sign-in or account data is reported, not thrown
  group('missing data', () {
    test('signed out: no data and signedOut status', () async {
      auth = MockFirebaseAuth();
      final provider = makeProvider();

      await provider.refresh();

      expect(provider.status, ProfileStatus.signedOut);
      expect(provider.account, isNull);
      expect(provider.walkedRoutes, isEmpty);
      expect(provider.errorMessage, isNull);
    });

    test('signed in with no account document: error with a message', () async {
      final provider = makeProvider();

      await provider.refresh();

      expect(provider.status, ProfileStatus.error);
      expect(provider.account, isNull);
      expect(provider.errorMessage, isNotNull);
    });

    test('signing out clears the previous user\'s data', () async {
      await seedAccount(firestore);
      await completeWalk(repository, startedAt: DateTime(2026, 11, 1, 9));
      final provider = makeProvider();
      await provider.refresh();

      await auth.signOut();
      await provider.refresh();

      expect(provider.status, ProfileStatus.signedOut);
      expect(provider.account, isNull);
      expect(provider.walkedRoutes, isEmpty);
      expect(provider.routesCompleted, 0);
    });
  });

  // Tests that read failures become an error state instead of an exception
  group('errors', () {
    test('a failed account read reports an error', () async {
      await seedAccount(firestore);
      whenCalling(Invocation.method(#get, null))
          .on(firestore.collection('users').doc(uid))
          .thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
      final provider = makeProvider();

      await provider.refresh();

      expect(provider.status, ProfileStatus.error);
      expect(provider.errorMessage, isNotNull);
    });

    test('a failed walks read reports an error', () async {
      await seedAccount(firestore);
      final provider = makeProvider(
        walkRepository: _FailingWalkRepository(firestore),
      );

      await provider.refresh();

      expect(provider.status, ProfileStatus.error);
      expect(provider.errorMessage, isNotNull);
    });

    test('a failed refresh keeps the last loaded data', () async {
      await seedAccount(firestore, routesCompleted: 2);
      final failing = _FailingWalkRepository(firestore)..shouldFail = false;
      final provider = makeProvider(walkRepository: failing);
      await provider.refresh();

      failing.shouldFail = true;
      await provider.refresh();

      expect(provider.status, ProfileStatus.error);
      expect(provider.username, 'walker');
      expect(provider.routesCompleted, 2);
    });

    test('a successful refresh after an error clears the error', () async {
      await seedAccount(firestore);
      final failing = _FailingWalkRepository(firestore);
      final provider = makeProvider(walkRepository: failing);
      await provider.refresh();
      expect(provider.status, ProfileStatus.error);

      failing.shouldFail = false;
      await provider.refresh();

      expect(provider.status, ProfileStatus.loaded);
      expect(provider.errorMessage, isNull);
    });
  });

  // Tests that the real walk and photo workflows show up after a refresh
  group('staying up to date', () {
    test('completing a walk updates the history and route count', () async {
      await seedAccount(firestore);
      final provider = makeProvider();
      await provider.refresh();
      expect(provider.routesCompleted, 0);

      final walk = await completeWalk(
        repository,
        startedAt: DateTime(2026, 11, 1, 9),
      );
      await provider.refresh();

      expect(provider.routesCompleted, 1);
      expect(ids(provider.walkedRoutes), [walk.id]);
    });

    test('uploading photos updates the photo count', () async {
      await seedAccount(firestore);
      final walk = await completeWalk(
        repository,
        startedAt: DateTime(2026, 11, 1, 9),
      );
      final photos = WalkPhotoService(
        auth: auth,
        firestore: firestore,
        storage: FakePhotoStorage(),
        walkRepository: repository,
      );
      final provider = makeProvider();
      await provider.refresh();
      expect(provider.photosUploaded, 0);

      await photos.uploadPhotos(walk.id, [
        photos.preparePhoto(jpeg()),
        photos.preparePhoto(jpeg(), stopId: 'red_1'),
      ]);
      await provider.refresh();
      expect(provider.photosUploaded, 2);

      await photos.uploadPhotos(walk.id, [photos.preparePhoto(jpeg())]);
      await provider.refresh();
      expect(provider.photosUploaded, 3);
    });

    test('route and photo counts stay consistent with each other', () async {
      await seedAccount(firestore);
      final walk = await completeWalk(
        repository,
        startedAt: DateTime(2026, 11, 1, 9),
      );
      final photos = WalkPhotoService(
        auth: auth,
        firestore: firestore,
        storage: FakePhotoStorage(),
        walkRepository: repository,
      );
      await photos.uploadPhotos(walk.id, [photos.preparePhoto(jpeg())]);
      await completeWalk(repository, startedAt: DateTime(2026, 11, 2, 9));
      final provider = makeProvider();

      await provider.refresh();

      expect(provider.routesCompleted, provider.walkedRoutes.length);
      expect(provider.routesCompleted, 2);
      expect(provider.photosUploaded, 1);
    });
  });

  // Tests that the UI is told about changes
  group('notifications', () {
    late ProfileProvider provider;
    late int notifications;
    late List<ProfileStatus> statuses;

    setUp(() async {
      await seedAccount(firestore);
      provider = makeProvider();
      notifications = 0;
      statuses = [];
      provider.addListener(() {
        notifications++;
        statuses.add(provider.status);
      });
    });

    test('refresh notifies when loading starts and when it finishes', () async {
      await provider.refresh();
      expect(notifications, 2);
      expect(statuses, [ProfileStatus.loading, ProfileStatus.loaded]);
    });

    test('refresh notifies on error', () async {
      final failing = makeProvider(
        walkRepository: _FailingWalkRepository(firestore),
      );
      final seen = <ProfileStatus>[];
      failing.addListener(() => seen.add(failing.status));

      await failing.refresh();

      expect(seen, [ProfileStatus.loading, ProfileStatus.error]);
    });

    test('refresh notifies once when signed out', () async {
      await auth.signOut();
      await provider.refresh();
      expect(statuses, [ProfileStatus.signedOut]);
    });

    test('listeners see the new count after a walk is completed', () async {
      await provider.refresh();
      int? countSeen;
      provider.addListener(() => countSeen = provider.routesCompleted);

      await completeWalk(repository, startedAt: DateTime(2026, 11, 1, 9));
      await provider.refresh();

      expect(countSeen, 1);
    });

    test('does not notify after dispose', () async {
      final pending = provider.refresh();
      provider.dispose();
      await expectLater(pending, completes);
      // Only the "loading" notification from before dispose.
      expect(notifications, 1);
    });
  });

  // Tests the automatic reload on sign-in and sign-out
  group('auth changes', () {
    test('loads by itself when signed in at startup', () async {
      await seedAccount(firestore, username: 'walker');
      final provider = ProfileProvider(
        authService: AuthService(auth: auth, firestore: firestore),
        walkRepository: repository,
      );
      addTearDown(provider.dispose);

      await pumpEventQueue();

      expect(provider.status, ProfileStatus.loaded);
      expect(provider.username, 'walker');
    });

    test('clears itself when the user signs out', () async {
      await seedAccount(firestore);
      final provider = ProfileProvider(
        authService: AuthService(auth: auth, firestore: firestore),
        walkRepository: repository,
      );
      addTearDown(provider.dispose);
      await pumpEventQueue();
      expect(provider.status, ProfileStatus.loaded);

      await auth.signOut();
      await pumpEventQueue();

      expect(provider.status, ProfileStatus.signedOut);
      expect(provider.account, isNull);
    });

    test('a stale load does not overwrite a newer one', () async {
      await seedAccount(firestore);
      final slow = _SlowWalkRepository(firestore);
      final provider = makeProvider(walkRepository: slow);

      final first = provider.refresh();
      await auth.signOut();
      await provider.refresh();
      slow.release.complete();
      await first;

      expect(provider.status, ProfileStatus.signedOut);
      expect(provider.account, isNull);
    });
  });
}

// WalkRepository whose completed-walks read fails, like Firestore offline
// with nothing cached.
class _FailingWalkRepository extends WalkRepository {
  _FailingWalkRepository(FirebaseFirestore firestore)
    : super(firestore: firestore);

  bool shouldFail = true;

  @override
  Future<List<WalkedRoute>> fetchCompletedWalks(String userId) {
    if (shouldFail) {
      return Future.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
    }
    return super.fetchCompletedWalks(userId);
  }
}

// WalkRepository whose completed-walks read waits until [release] completes.
class _SlowWalkRepository extends WalkRepository {
  _SlowWalkRepository(FirebaseFirestore firestore)
    : super(firestore: firestore);

  final Completer<void> release = Completer<void>();

  @override
  Future<List<WalkedRoute>> fetchCompletedWalks(String userId) async {
    await release.future;
    return super.fetchCompletedWalks(userId);
  }
}
