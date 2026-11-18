---
kind: external_dependency
name: Google Play Distribution
slug: google-play
category: external_dependency
category_hints:
    - vendor_identity
scope:
    - '**'
source_files:
    - android/key.properties
    - android/lidapay-upload.jks
    - android/upload_cert.pem
    - android/gradle.properties
    - pubspec.yaml
---

### Identity
Google Play is the sole distribution channel referenced by this repo; the README documents building `app-release.aab` and uploading it via Play Console.

### Role in this repo
- Release signing uses the upload keystore configured in `android/key.properties` (`storeFile=../lidapay-upload.jks`, alias `lidapay-upload`). The matching public certificate is committed as `android/upload_cert.pem` so CI can verify the bundle before upload.
- Store listing assets live in `android/app/src/main/play_store_512.png` and static legal pages under `web/` must be published at stable HTTPS URLs before Play submission.

### Durable integration notes
- Enroll in Play App Signing and confirm the registered upload certificate matches the release keystore before production rollout.
- On 8 GB machines Gradle needs `-Xmx3G -XX:MaxMetaspaceSize=1G` plus `kotlin.daemon.jvmargs=-Xmx2G` in `gradle.properties`; the default `-Xmx8G` OOM-kills the daemon mid-build.