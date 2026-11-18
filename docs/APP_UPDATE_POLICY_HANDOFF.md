# Backend Handoff — App-Version Policy & In-App Update Gate

Audience: backend team (NestJS/MongoDB). Written alongside mobile release
**1.1.3+34**, which ships an in-app update gate.

The gate asks the backend which build is current and which builds are still
supported, then prompts or blocks the user accordingly. **Until this endpoint
exists the gate does nothing** — it fails open by design, so this work can be
scheduled whenever convenient and needs no coordinated app release.

Mobile implementation (for reference when questions come up):

| Concern | File |
|---|---|
| Policy parsing + decision rules | `lib/core/update/app_update_models.dart` |
| HTTP call, timeout, fail-open | `lib/core/update/app_update_repository.dart` |
| Play Core flows + store fallback | `lib/core/update/play_update_service.dart` |
| Throttle, snooze, download state | `lib/core/update/providers.dart` |
| Prompt / blocking UI | `lib/core/update/widgets/app_update_gate.dart` |
| Route constant | `lib/core/network/api_endpoints.dart` (`appVersionPolicy`) |

---

## 1. The endpoint

```
GET /api/v1/app/version
```

- **Public / unauthenticated.** It must work before sign-in: the gate runs at
  app start, including on the login screen.
- Query parameters the app sends:

| Param | Example | Source |
|---|---|---|
| `platform` | `ANDROID` | device identity (`ANDROID` \| `IOS` \| `WEB`) |
| `version` | `1.1.3` | `versionName` |
| `build` | `34` | Android `versionCode` |

- Return **HTTP 200** with a JSON object. `404`, `5xx`, malformed bodies and
  timeouts are all tolerated silently — the app keeps working normally.
- Performance budget: the app allows **6 s** and then gives up. Target
  p95 < 500 ms; serve from config/cache, not a per-request database query.
- Traffic: roughly one call per app launch, plus at most one per 6 hours while
  the app stays open (the client throttles re-checks).
- The route path can be overridden at build time with
  `--dart-define=APP_UPDATE_POLICY_PATH=/your/path` if you prefer a different
  location; tell mobile before release if you choose another path.

---

## 2. Response body

Recommended flat shape:

```json
{
  "minimumBuild": 34,
  "latestBuild": 36,
  "latestVersion": "1.1.4",
  "storeUrl": "https://play.google.com/store/apps/details?id=com.advansistechnologies.lidapay",
  "message": "Faster top-ups, new rewards and smoother checkout."
}
```

| Field | Type | Meaning |
|---|---|---|
| `minimumBuild` | int | Builds **below** this are hard-blocked with a non-dismissible screen. Omit to never block. |
| `latestBuild` | int | Newest build in **production**. Anything below it gets an optional "Update" card. |
| `latestVersion` | string | Display name of the newest build (`1.1.4`). Informational. |
| `storeUrl` | string | Must be `https://play.google.com/...` (or `apps.apple.com`). Any other host is rejected and the app uses the default listing above. |
| `message` | string | Customer-facing copy in the prompt. Keep it **≤ 180 characters**. |

### Accepted variants

All of the following parse identically — pick whichever matches your
conventions:

```json
{ "data": { "minimumBuild": 34, "latestBuild": 36 } }
```

```json
{ "data": { "minimum_build": "34", "latest_version_code": 36,
            "play_store_url": "https://play.google.com/...",
            "release_notes": "New rewards" } }
```

```json
{ "android": { "minimumBuild": 34, "latestBuild": 36 },
  "ios":     { "minimumBuild": 1,  "latestBuild": 999 } }
```

`platforms.android` works the same as a top-level `android` node. Numeric
strings (`"34"`) are coerced. Unknown extra fields are ignored.

### Field aliases

| Canonical | Also accepted |
|---|---|
| `minimumBuild` | `minimum_build`, `minBuild`, `min_build`, `minimumVersionCode`, `minimum_version_code`, `minSupportedBuild`, `minimumSupportedBuild` |
| `minimumVersion` | `minimum_version`, `minVersion`, `min_version`, `minSupportedVersion` |
| `latestBuild` | `latest_build`, `latestVersionCode`, `latest_version_code`, `versionCode`, `version_code`, `buildNumber`, `build_number`, `build` |
| `latestVersion` | `latest_version`, `versionName`, `version_name`, `version` |
| `storeUrl` | `store_url`, `playStoreUrl`, `play_store_url`, `updateUrl`, `update_url`, `url` |
| `message` | `updateMessage`, `update_message`, `notes`, `releaseNotes`, `release_notes` |

---

## 3. Exact decision rules

Evaluated against the install's `build` (`versionCode`):

1. `build < minimumBuild` → **blocking screen**. The user cannot dismiss it or
   use the app until they update.
2. otherwise `build < latestBuild` → **optional card**. "Later" snoozes the
   prompt for 3 days, keyed to the target build.
3. otherwise → nothing is shown.

Precedence details:

- If `latestBuild` is present, version **names are ignored entirely**. Publish
  builds, not just names.
- If neither build field is sent, the app compares `version` against
  `minimumVersion` / `latestVersion` (numeric segment comparison, so
  `1.1.10` > `1.1.9`; `+build` and `-beta` suffixes are ignored).
- An install that cannot read its own build number is **never** gated.
- **Android only today.** iOS and web values are accepted but ignored by this
  client; the Play in-app update flow does not exist on those platforms.

---

## 4. Safety rules — hard requirements

1. **Never set `minimumBuild` above the build actually live in production.**
   During a staged rollout most users cannot update yet; blocking them locks
   out paying customers. Raise `minimumBuild` only after the target build
   reaches 100 % rollout.
2. `minimumBuild ≤ latestBuild`, always.
3. Values must be changeable **without an app release** (config service, env
   var, or admin setting). That is the point of the feature: a security fix can
   force an update within minutes.
4. Emergency rollback = lower `minimumBuild` immediately. The app caches the
   first successful response for the running session, so a change reaches an
   already-open app on next launch (or within 6 hours). If you need instant
   enforcement, do it at the API layer, not through this endpoint.
5. `message` is rendered verbatim to customers — no secrets, internal URLs,
   stack traces or integrator jargon.

---

## 5. Version reference

Android `versionCode` → `versionName` for this app
(`com.advansistechnologies.lidapay`):

| versionCode | versionName | Status |
|---|---|---|
| 32 | 1.1.1 | previous line |
| 33 | 1.1.2 | previous release |
| **34** | **1.1.3** | current release being uploaded |

Suggested initial values once 1.1.3 is at 100 % rollout:

```json
{ "minimumBuild": 33, "latestBuild": 34, "latestVersion": "1.1.3" }
```

That nudges 1.1.2 users and blocks nobody.

---

## 6. Adoption data you already have

Login, token refresh and device-token registration already send `appVersion`
(plus `deviceId`, `devicePlatform`) — see the `RegisterDeviceTokenDto` fields
and `lib/core/device/device_identity.dart`. Use that distribution to decide
when raising `minimumBuild` is safe, e.g. once fewer than ~2 % of active
devices are below the target build.

---

## 7. Acceptance checklist

- [ ] `GET /api/v1/app/version?platform=ANDROID&version=1.1.3&build=34`
      returns 200 JSON **without** an Authorization header
- [ ] `minimumBuild: 35, latestBuild: 36` → a build-34 install shows the
      blocking screen
- [ ] `minimumBuild: 30, latestBuild: 36` → build 34 shows the optional card
      with your `message`
- [ ] `minimumBuild: 30, latestBuild: 34` → build 34 shows nothing
- [ ] Empty object `{}` → nothing shown, app unaffected
- [ ] Route removed / 500 / offline → app unaffected
- [ ] `storeUrl` on a non-Play host → ignored; app opens the default listing
- [ ] Values editable without redeploying the mobile app

Verification command:

```bash
curl -s "https://api.advansistechnologies.com/api/v1/app/version?platform=ANDROID&version=1.1.3&build=34"
```

---

## 8. Notes for testing and rollout

- **In-app updates only work for builds installed from Google Play.** A
  sideloaded APK gets `ERROR_API_NOT_AVAILABLE` from Play Core and the app
  falls back to opening the store listing. That is expected, not a bug.
- To exercise the real flow: publish a build to an internal track, install it
  from the Play link, then publish a higher build to that same track.
- The gate is deliberately **fail-open**: a broken or missing endpoint
  degrades to "no prompt", never to "app unusable".
- This endpoint does not replace API-level version enforcement. If a build
  must be cut off immediately (security incident), reject its API calls
  server-side as well; the gate alone only affects the next app launch.
