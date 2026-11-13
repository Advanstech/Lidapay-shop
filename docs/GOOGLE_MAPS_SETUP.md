# Google Maps Setup — Courier Driver Pin

The order-tracking screen renders the courier's live GPS position on a Google
Map (`lib/features/shop/widgets/driver_location_map.dart`). It needs a Maps
SDK key in **three** places: the Android native layer, the iOS native layer,
and a Dart compile-time define that tells the widget a key exists.

If any piece is missing the tracking card degrades gracefully to a
coordinates-only view — nothing breaks, the map just doesn't render.

## 1. Create the key

Google Cloud Console → APIs & Services → Credentials → Create API key.

Enable **Maps SDK for Android** and **Maps SDK for iOS** on the project.

> **Billing is required for everything below.** All Maps Platform SKUs —
> including the mobile SDKs and the backend's Routes API — return
> `BILLING_DISABLED`/`REQUEST_DENIED` on projects without an active billing
> account. Demo/trial keys will not work. The backend additionally needs
> **Routes API** enabled on the same project for `deliveryDistance`
> computation (server-side `GOOGLE_MAPS_API_KEY` env var).

**Restrict the key before shipping** (an unrestricted key can be extracted
from the APK/IPA and abused):

- **Android:** Application restriction → Android apps → package name
  `com.advansistechnologies.lidapay` + your release SHA-1 fingerprint
  (and debug SHA-1 for dev builds: `keytool -list -v -keystore <debug.keystore>`).
- **iOS:** Application restriction → iOS apps → bundle id
  `com.advansistechnologies.lidapay` (check `PRODUCT_BUNDLE_IDENTIFIER` in
  Xcode if different).
- **API restriction:** Maps SDK for Android + Maps SDK for iOS only.

## 2. Android

Add to `android/local.properties` (gitignored, already exists on dev
machines):

```properties
GOOGLE_MAPS_API_KEY=AIza...your-key
```

Alternatives: `-PGOOGLE_MAPS_API_KEY=...` gradle flag, or export
`GOOGLE_MAPS_API_KEY` in the environment. Resolution order is
`-P` → env → `local.properties` (see `android/app/build.gradle.kts`).

## 3. iOS

```bash
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
```

Then edit `ios/Flutter/Local.xcconfig` (gitignored) and set:

```xcconfig
GOOGLE_MAPS_API_KEY = AIza...your-key
```

`AppDelegate.swift` reads it from Info.plist and calls
`GMSServices.provideAPIKey` at launch.

## 4. Dart side (required for the map widget to render)

The widget checks `AppConstants.googleMapsConfigured`, which is a
compile-time `--dart-define`. Pass the same key when running/building:

```bash
flutter run --dart-define=GOOGLE_MAPS_API_KEY=AIza...your-key
flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=AIza...your-key
flutter build ipa --dart-define=GOOGLE_MAPS_API_KEY=AIza...your-key
```

For VS Code, add to `.vscode/launch.json` args:
`"--dart-define=GOOGLE_MAPS_API_KEY=AIza...your-key"`.

## 5. Verify

1. `flutter run` with the dart-define on a device/emulator.
2. Open an order in `processing`/`shipped` state that has a
   `lastDriverLocation` (seed one via the courier `/location` endpoint —
   see `tool/courier-orders/`).
3. The tracking sheet should show the map with the driver pin and a
   "updated Xs ago" freshness label. If you see the coordinates fallback
   instead, one of the three key locations above is missing.

## CI / release builds

Store the key as a CI secret and inject it three ways:

- Android: write `GOOGLE_MAPS_API_KEY` into `android/local.properties`
  before `flutter build`, or pass `-PGOOGLE_MAPS_API_KEY`.
- iOS: generate `ios/Flutter/Local.xcconfig` from the example in a CI step.
- Dart: always pass `--dart-define=GOOGLE_MAPS_API_KEY=$GOOGLE_MAPS_API_KEY`.
