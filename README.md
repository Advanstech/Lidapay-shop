# LidaPay

LidaPay is a Flutter mobile app.

## Build for Google Play

Install the project's Flutter dependencies and validate the app:

```sh
flutter pub get
flutter analyze
flutter test
```

Create the signed Android App Bundle for Play:

```sh
flutter build appbundle --release
```

The bundle is written to `build/app/outputs/bundle/release/app-release.aab`.
Release signing uses `android/key.properties` and the upload keystore configured
there. Keep both files private and backed up; do not upload them to source
control. Before each new Play release, increment the build number in
`pubspec.yaml` (the number after `+`).

## Before submitting in Play Console

- Complete the store listing, including descriptions, screenshots, support
  contact details, and the 512 × 512 store graphic at
  `android/app/src/main/play_store_512.png`.
- Publish the static pages in `web/` at stable public HTTPS URLs. The Play
  Console privacy-policy URL must point to `privacy-policy.html`; provide the
  `account-deletion.html` URL in the account deletion declaration. Also link
  the terms, payments/refunds, and verification pages from the store listing
  or website as appropriate. The account deletion page and in-app action
  initiate a support request; support must complete deletion of related
  records because the documented user-delete API does not cascade them.
- Complete the Play Console Data safety and account-deletion declarations
  based on actual backend, payment-provider, and SDK data practices.
- Complete any applicable financial-features declarations and provide
  reviewer access instructions or test credentials for sign-in-protected
  functionality.
- Enroll in Play App Signing, confirm the registered upload certificate matches
  the release keystore, and test the bundle on an internal track before
  production.
