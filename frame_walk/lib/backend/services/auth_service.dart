import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/user_account.dart';

// An authentication error with a message that is safe to show to the user.
class AuthFailure implements Exception {
  final String message;

  const AuthFailure(this.message);

  @override
  String toString() => 'AuthFailure: $message';
}

// Handles creating accounts, logging in, and logging out.
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  // Emits the signed-in user, or null when nobody is signed in.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // The signed-in user's ID, or null when nobody is signed in.
  String? get currentUserId => _auth.currentUser?.uid;

  // The account saved by createAccount, or null if [uid] has no account
  // document. Firestore errors are passed on to the caller.
  Future<UserAccount?> fetchAccount(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data();
    return data == null ? null : UserAccount.fromMap(doc.id, data);
  }

  Future<void> createAccount({
    required String email,
    required String username,
    required String password,
  }) async {
    final User user;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      user = credential.user!;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_messageForAuthError(error));
    }

    // Firestore can only be used once signed in, so the username check has to
    // come after creating the user. Any failure here must remove that user, or
    // their email would stay taken by an account with no data.
    final account = UserAccount(
      uid: user.uid,
      username: username.trim(),
      email: email.trim(),
    );
    final bool isSaved;
    try {
      isSaved = await _saveNewAccount(account);
    } on FirebaseException {
      await _discardUser(user);
      throw const AuthFailure(
        "We couldn't finish creating your account. Please try again.",
      );
    }
    if (!isSaved) {
      await _discardUser(user);
      throw const AuthFailure('That username is already taken.');
    }
  }

  Future<void> logIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_messageForAuthError(error));
    }
  }

  Future<void> logOut() => _auth.signOut();

  // Reserves the username and writes the account together, so two people can't
  // claim the same name. Returns false if the username is already taken.
  Future<bool> _saveNewAccount(UserAccount account) {
    final usernameDoc = _firestore
        .collection('usernames')
        .doc(account.username.toLowerCase());
    final accountDoc = _firestore.collection('users').doc(account.uid);

    return _firestore.runTransaction<bool>((transaction) async {
      final existingUsername = await transaction.get(usernameDoc);
      if (existingUsername.exists) {
        return false;
      }
      transaction.set(usernameDoc, {'uid': account.uid});
      transaction.set(accountDoc, {
        ...account.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  Future<void> _discardUser(User user) async {
    try {
      await user.delete();
    } on FirebaseAuthException {
      await _auth.signOut();
    }
  }

  String _messageForAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'Please enter a valid email.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      // Firebase may report any of these for a failed login. They share one
      // message so the app doesn't reveal which emails have accounts.
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Please check your internet connection and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
