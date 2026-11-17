# iOS Setup

iOS builds need a Mac with Xcode (from the App Store) and CocoaPods (`brew install cocoapods`). Check them with `flutter doctor`. Firebase is already set up for iOS (`ios/Runner/GoogleService-Info.plist` and `lib/firebase_options.dart`), so only Google Maps needs per-developer setup.

| What | Value / location |
| --- | --- |
| iOS bundle ID | `com.username.framewalk`, using your own username (Xcode: Runner > Signing & Capabilities). It differs from the Android ID because iOS doesn't allow `_` in bundle IDs. |
| Where your iOS Maps key goes | `MAPS_API_KEY=...` in `frame_walk/ios/Flutter/Secrets.xcconfig`, which is not committed (ignored by `frame_walk/ios/.gitignore`) |
| How the key reaches the app | `Debug.xcconfig`/`Release.xcconfig` include `Secrets.xcconfig` > `Info.plist` (`GMSApiKey`) > `AppDelegate.swift` calls `GMSServices.provideAPIKey` |

## Google Maps key for iOS

Your Android key can't be reused: it's restricted to Android apps and the Maps SDK for Android. Make a second key in the **same** Google Cloud project (billing is already set up there).

1. In **APIs & Services > Library**, enable **Maps SDK for iOS**.
2. In **APIs & Services > Credentials**, click **+ Create credentials > API key**.
3. Restrict it: under **Application restrictions** choose **iOS apps** and add `com.jltrinh.frameWalk`; under **API restrictions** choose **Maps SDK for iOS** only. Click **Save**.
4. Create `frame_walk/ios/Flutter/Secrets.xcconfig` containing one line, with no quotes:

   ```properties
   MAPS_API_KEY=AIzaYourOwnIosKeyGoesHere
   ```

5. Confirm Git ignores it (from `frame_walk`): `git check-ignore -v ios/Flutter/Secrets.xcconfig` should print the rule. If it prints nothing, **stop** and ask the team.

Without `Secrets.xcconfig` the app still builds and runs, but maps are blank, the same as Android without a key. The Xcode console shows `MAPS_API_KEY is not set`.

## Running on iOS

From `frame_walk`:

```bash
open -a Simulator
flutter run -d ios
```

- **Simulator:** no Apple account is needed. To fake a location, use the Simulator menu **Features > Location > Custom Location** (for example Red Square, `47.6559, -122.3078`). To simulate walking, run the app from Xcode (`open ios/Runner.xcworkspace`) and use **Debug > Simulate Location** with a GPX file.
- **Physical iPhone:** In Xcode under **Runner > Signing & Capabilities**, click **Add Account** and login to your apple account. Make sure to select the team once you've logged in. Change the bundle identifier to be `com.username.framewalk`, using your own username and save all your changes. Plug in your phone and make sure to turn on **Developer Mode** on the phone (**Settings > Privacy & Security > Developer Mode**). From there, you can use `flutter run` as normal.

## iOS differences

- **Location is foreground only**, as on Android. No background mode is set. iOS doesn't let apps open the device-wide Location Services switch, so if it's off the app explains where to turn it on (**Settings > Privacy & Security > Location Services**).
- **Automatic GPS pausing is off** (`pauseLocationUpdatesAutomatically: false` in `location_source.dart`). iOS doesn't resume paused updates on its own, and walkers often stand still at photo stops.
- The Map tab has no zoom buttons on iOS, because the iOS Maps SDK has none. Pinch to zoom instead.
- On iOS, Firebase keeps the login in the Keychain, so a user may still be logged in after deleting and reinstalling the app.