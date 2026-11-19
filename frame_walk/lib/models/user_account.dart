// Represents the account information and statistics stored for a user
class UserAccount {
  final String uid;
  final String username;
  final String email;
  final int routesCompleted;
  final int photosTaken;

  const UserAccount({
    required this.uid,
    required this.username,
    required this.email,
    this.routesCompleted = 0,
    this.photosTaken = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'email': email,
      'routesCompleted': routesCompleted,
      'photosTaken': photosTaken,
    };
  }

  // Counters default to 0 so accounts created before a counter existed
  // still load.
  factory UserAccount.fromMap(String uid, Map<String, dynamic> map) {
    return UserAccount(
      uid: uid,
      username: map['username'] as String? ?? '',
      email: map['email'] as String? ?? '',
      routesCompleted: (map['routesCompleted'] as num?)?.toInt() ?? 0,
      photosTaken: (map['photosTaken'] as num?)?.toInt() ?? 0,
    );
  }
}
