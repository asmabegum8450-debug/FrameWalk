import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/user_account.dart';
import '../../models/walked_route.dart';
import '../services/auth_service.dart';
import '../services/walk_repository.dart';

enum ProfileStatus {
  // Nothing loaded yet.
  initial,
  loading,
  loaded,

  // Nobody is signed in, so there is no profile to show.
  signedOut,

  // Loading failed. See [ProfileProvider.errorMessage].
  error,
}

// Single source of truth for the Account page: the signed-in user's account,
// their completed walks, and their statistics.
//
// It only coordinates. AuthService reads the account and WalkRepository reads
// the walks. The statistics are the counters on the account document, which
// WalkRepository.completeWalk and WalkPhotoService.saveChanges update in the
// same write as the walk or photos, so they never disagree with the data.
//
// Call [refresh] after anything that changes that data (finishing a walk,
// saving photos). It also reloads by itself whenever the user signs in or out.
class ProfileProvider extends ChangeNotifier {
  /// Creates a ProfileProvider.
  /// Params:
  ///  authService, walkRepository - default to the real Firebase-backed ones;
  ///  unit tests pass their own built on fakes
  ///  listenToAuthChanges - true to reload on sign-in and sign-out. Tests can
  ///  turn it off and call refresh themselves
  ProfileProvider({
    AuthService? authService,
    WalkRepository? walkRepository,
    bool listenToAuthChanges = true,
  }) : _authService = authService ?? AuthService(),
       _walkRepository = walkRepository ?? WalkRepository() {
    if (listenToAuthChanges) {
      _authSub = _authService.authStateChanges.listen(
        (_) => refresh(),
        onError: (Object _) {},
      );
    }
  }

  final AuthService _authService;
  final WalkRepository _walkRepository;
  StreamSubscription<Object?>? _authSub;

  ProfileStatus _status = ProfileStatus.initial;
  String? _errorMessage;
  UserAccount? _account;
  List<WalkedRoute> _walkedRoutes = const [];

  // Increases with every refresh, so a slow earlier load can't overwrite the
  // result of a newer one (for example, after switching accounts).
  int _loadCount = 0;
  bool _disposed = false;

  ProfileStatus get status => _status;
  bool get isLoading => _status == ProfileStatus.loading;
  String? get errorMessage => _errorMessage;

  // Null until loaded, and when signed out.
  UserAccount? get account => _account;
  String? get username => _account?.username;
  String? get email => _account?.email;

  // Completed walks, newest first.
  List<WalkedRoute> get walkedRoutes => List.unmodifiable(_walkedRoutes);

  int get routesCompleted => _account?.routesCompleted ?? 0;
  int get photosUploaded => _account?.photosTaken ?? 0;

  // Reloads the account and walks for whoever is signed in now. Never throws;
  // failures are reported through [status] and [errorMessage]. If a reload
  // fails, the last loaded data for the same user is kept so the page can
  // still show it.
  Future<void> refresh() async {
    final load = ++_loadCount;
    final uid = _authService.currentUserId;
    if (uid == null) {
      _clearData();
      _errorMessage = null;
      _setStatus(ProfileStatus.signedOut);
      return;
    }

    // Another user's data must never show, even briefly.
    if (_account != null && _account!.uid != uid) _clearData();
    _errorMessage = null;
    _setStatus(ProfileStatus.loading);

    final UserAccount? account;
    final List<WalkedRoute> walks;
    try {
      (account, walks) = await (
        _authService.fetchAccount(uid),
        _walkRepository.fetchCompletedWalks(uid),
      ).wait;
    } catch (error) {
      if (load != _loadCount) return;
      _errorMessage = "Couldn't load your profile. Check your connection.";
      _setStatus(ProfileStatus.error);
      return;
    }
    if (load != _loadCount) return;

    if (account == null) {
      _clearData();
      _errorMessage = "We couldn't find your account information.";
      _setStatus(ProfileStatus.error);
      return;
    }
    _account = account;
    _walkedRoutes = walks;
    _setStatus(ProfileStatus.loaded);
  }

  void _clearData() {
    _account = null;
    _walkedRoutes = const [];
  }

  void _setStatus(ProfileStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    super.dispose();
  }
}
