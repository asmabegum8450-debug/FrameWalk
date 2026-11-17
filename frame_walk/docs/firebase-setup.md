# Firebase Setup

Login and account data use one Firebase project shared by the whole team: Firebase Auth for email and password sign-in, and Cloud Firestore for account data. Unlike the Maps key, **teammates don't need their own setup**. The config is committed, so `flutter pub get` and `flutter run` are enough.

**Committed config:** these files contain a Firebase API key starting with `AIza`. That's expected, because this key identifies the project rather than granting access. Access to data is controlled by `frame_walk/firestore.rules`. These are the only files allowed to contain `AIza`:

- `frame_walk/lib/firebase_options.dart`
- `frame_walk/android/app/google-services.json`
- `frame_walk/ios/Runner/GoogleService-Info.plist`

**Firestore collections:**

| Collection | Document ID | Contents |
| --- | --- | --- |
| `users` | Firebase Auth user ID | Username, email, statistics, and created date. Readable only by that user. |
| `usernames` | Lowercase username | The owner's user ID. Keeps usernames unique. |
| `users/{uid}/walks` | Generated walk ID | One walk of a route: route ID and title, status (`active` or `completed`), start and completion times, a copy of the route's stops (ID, name, coordinates, prompt, time reached), distance walked. Cancelled walks are deleted. |
| `users/{uid}/walks/{walkId}/locationPoints` | `p000000`, `p000001`, ... | GPS history for a walk: latitude, longitude, accuracy, and time recorded. |

Passwords are handled by Firebase Auth and are never stored in Firestore.

**If you change `firestore.rules`,** deploy them. This requires the [Firebase CLI](https://firebase.google.com/docs/cli) and access to the project:

```bash
cd frame_walk
firebase deploy --only firestore:rules
```

**If an app ID changes or a platform is added,** regenerate the config with the [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup) by running `flutterfire configure` from `frame_walk`, then commit the result.

**Running the auth tests** (they use fakes, so they don't touch the real project):

```bash
cd frame_walk
flutter test test/backend/services/auth_service_test.dart test/frontend/auth_flow_test.dart
```