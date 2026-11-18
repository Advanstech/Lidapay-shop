---
kind: external_dependency
name: Firebase Cloud Messaging & Core
slug: firebase
category: external_dependency
category_hints:
    - vendor_identity
scope:
    - '**'
source_files:
    - pubspec.yaml
    - android/google-services.json
    - ios/Podfile
---

### Identity
Firebase (core + messaging) is the push-notification provider for both Android and iOS.

### Role in this repo
- Declared via `firebase_core` and `firebase_messaging` in `pubspec.yaml`; Android config lives in `android/google-services.json`; iOS pods include `FirebaseCore`, `FirebaseMessaging` (and related transitives).
- Web builds intentionally skip push — the service worker registration fails on web but is non-fatal.

### Durable integration notes
- Push is not available on the web target; do not treat a web-side FCM registration failure as a crash.