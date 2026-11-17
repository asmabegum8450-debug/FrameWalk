# GPS Tracking

Pressing **Start Walk** on a route opens the active-walk screen, which records where the user walks and tells them when they approach (within 75 m) or reach (within 25 m) each stop.

| Piece | File |
| --- | --- |
| Device location (the only code that uses `geolocator`) | `lib/backend/services/location_source.dart` |
| Stop proximity and route progress | `lib/backend/services/route_progress_tracker.dart` |
| Firestore storage | `lib/backend/services/walk_repository.dart` |
| Starts/stops tracking, handles permission and signal problems | `lib/backend/services/walk_tracking_service.dart` |
| Screen | `lib/frontend/screens/active_walk_page.dart` |

**Routes vs. Walked-Routes:** predefined routes are not stored with walks. A walk refers to its route by `routeId` and keeps its own copy of the stops. Only walks with `status: completed` are Walked-Routes.

**Foreground only.** Location is recorded only while FrameWalk is open on screen. When the app goes to the background or the screen locks, tracking pauses and resumes when the user returns. The gap shows up in the location history timestamps. Background tracking would need, at minimum, a location foreground service (`FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_LOCATION` permissions, `POST_NOTIFICATIONS` on Android 13+, and a `foregroundNotificationConfig` in `AndroidSettings`) on Android, and the `location` background mode on iOS. None of these are set up.

**Battery:** high accuracy with a 10 m distance filter (a 5 s minimum interval on Android), so no readings arrive while standing still. Points are saved to Firestore in batches of 10, or every 30 seconds.

**Permissions:** the app asks for "while using the app" location when a walk starts. If permission is denied, location services are off, or only approximate location is allowed, the screen explains why and links to the right settings. If the GPS signal drops mid-walk, the walk keeps going and a banner shows the problem.

**Testing on an emulator:** open the emulator's **Extended controls (⋯) > Location** and set a point near a stop (for example Red Square, `47.6559, -122.3078`), or play back a route.