# Backend Handoff — Notification Triggers & Security Alerts

Audience: backend team (NestJS/MongoDB). Written after auditing why the
mobile notification feed shows only "Security alert — Your profile has been
updated successfully" records and no transaction notifications.

No mobile app release is needed for any item in this document — the app
already parses every field described below.

---

## 1. The bug: every user-document write fires "profile updated"

`GET /api/v1/notifications` returns delivery-dispatch records, and the feed
is dominated by `channel: Email` rows titled **"Your profile has been
updated successfully"** — for users who never edited their profile.

**Root cause:** the "profile updated" security alert appears to fire on
*any* mutation of the user document, including device-metadata writes that
are part of normal authentication.

### Writes the mobile app legitimately makes

| Endpoint | Fields written | When |
|---|---|---|
| `POST /api/v1/users/login` | `deviceToken`, `devicePlatform`, `deviceId`, `appVersion`, `locale` | every password login |
| `POST /api/v1/auth/login/verify-otp` | same 5 fields | every OTP login |
| `POST /api/v1/users/register` | same 5 fields | signup |
| `POST /api/v1/notifications/device-token` | `token`, `platform`, `provider: FCM`, `deviceId`, `appVersion`, `locale` | every login, cold-start token restore, and every FCM token refresh |
| `PUT /api/v1/users/profile/update` | `firstName`, `lastName`, `email`, `phoneNumber`, `street`, `city`, `region`, `country`, `digitalAddress`, `latitude`, `longitude` | only real edits |

All five device fields are in the documented login/register DTOs, and the
device-token endpoint is the documented FCM path — the app cannot avoid
these writes without breaking push targeting.

### Required fix

1. **Scope the "profile updated" alert to real profile fields only.** Fire
   when `firstName`, `lastName`, `email`, `phoneNumber`, address fields,
   or `password` actually *change value* — not on writes limited to
   `deviceToken`, `deviceId`, `devicePlatform`, `appVersion`, `locale`,
   `fcmTokens`, `pushTokens`, `lastSeen`, or similar metadata.

   Implementation options (either works):
   - Diff the updated fields inside the profile-update service instead of
     triggering on a document-level save/update hook.
   - Whitelist: only the explicit `PUT /users/profile/update` handler
     (and admin profile edits) may emit the alert.

2. **New-device detection stays valuable — emit it as its own event.** A
   previously-unseen `deviceId` signing in IS a legitimate security event.
   Emit `eventType: security.new_device` for *new* devices only, and
   nothing for token refreshes on a known device.

   Suggested email: "A new device signed in to your LidaPay account —
   {platform}, {appVersion}. If this wasn't you, reset your password."

---

## 2. The feed has no transaction categories — emit event records

Today only security emails produce notification records. The app renders
rich cards for transaction events but the backend never creates them.

### Events that should create notification records

| Trigger | Suggested `eventType` | `kind` | Deep-link data |
|---|---|---|---|
| Airtime/data top-up delivered | `topup_delivered` | `airtime` / `data` | `topupOrderId`, `amount`, `currency`, `serviceType`, `recipientPhone` |
| Top-up delivery failed | `topup_failed` | `airtime` / `data` | same + `errorMessage` |
| Recipient decision pending | `recipient_topup_decision` | `decision` | `decisionId`, `topupOrderId`, `senderName`, `amount`, `currency`, `serviceType`, `expiresAt` |
| Recipient decision resolved | `recipient_topup_resolved` | `resolved` | `decisionId`, `topupOrderId`, `selectedChoice`, `finalDisposition` |
| Wallet/Lida Value credit or debit | `wallet_credit` / `wallet_debit` | `wallet` | `amount`, `currency`, `reference` |
| Shop order status change | `order_status` | `order` | `orderId` / `orderNumber`, `status` |
| Profile actually edited | `security.profile_updated` | `security` | — |
| New device signed in | `security.new_device` | `security` | `devicePlatform`, `appVersion` |
| Promotional | `promo` | `promo` | optional `route` |

### Record fields the app already parses

Create each record with as many of these as apply — the app reads them
defensively (nested `data`/`payload`/`meta` maps are also scanned):

```json
{
  "_id": "…",
  "userId": "<mongo user id, email or phone — used for scoping>",
  "type": "push | email | sms | in_app",
  "eventType": "topup_delivered",
  "subject": "Airtime delivered",
  "title": "Airtime delivered",
  "message": "GHS 5.00 airtime sent to 0244123456.",
  "status": "sent",
  "createdAt": "2026-11-18T10:00:00.000Z",
  "data": {
    "decisionId": "…",
    "topupOrderId": "…",
    "orderId": "…",
    "amount": 5.0,
    "currency": "GHS",
    "senderName": "…",
    "serviceType": "AIRTIME | DATA",
    "recipientPhone": "…",
    "selectedChoice": "DIRECT | LIDA_VALUE",
    "finalDisposition": "…",
    "expiresAt": "…"
  }
}
```

Notes on parsing behavior already in the app:
- `type` = delivery channel; `eventType` = the semantic event. Do not put
  the event name in `type`.
- `subject` or `title` wins display; `message`/`body`/`text` is the prose.
- Read state is **not** stored server-side today — fine, the app overlays
  it locally per user. The dedup window merges duplicate dispatches across
  channels.

### Hard rule: never embed raw entity JSON in `message`

The current "profile updated" emails arrive as
`"Your profile has been updated successfully. Details: {…}"` where the
tail is the serialized user document — **including password hashes,
tokens and internal fields**. The mobile app strips anything from the
first `{`/`[` onward before rendering, but this content also goes to
user inboxes unredacted. Stop appending entity dumps to notification
messages anywhere the emails/pushes are composed — this is a data leak,
not just a display bug.

---

## 3. Related open items (same area, previously flagged)

1. **Reloadly credentials** — `GET /api/v1/reloadly/country-list` and
   `POST /api/v1/reloadly/operator/autodetect` return
   `401 INVALID_CREDENTIALS` from Reloadly. Rotate the upstream key
   server-side; no app release needed. Ghana routes are unaffected.
2. **`clientReference` dedup** — the app sends a stable
   `LDP-<uuid v4>` on `POST /api/v1/airtime/topup` and
   `POST /api/v1/internet/buydata`. Confirm the backend deduplicates on
   `clientReference + userId + recipient + amount` and returns the prior
   result on re-delivery instead of calling the provider again.
3. **Transaction notification coverage for recipient-choice flow** — the
   sender should also get a record when the recipient resolves
   (`recipient_topup_resolved`), not just the recipient.

---

## 4. Acceptance checklist for the backend team

- [ ] Logging in (password and OTP) produces **zero** "profile updated"
      emails/notifications.
- [ ] FCM `device-token` registration/refresh produces **zero** alerts on
      an already-known device.
- [ ] Editing the profile produces exactly one alert, labelled
      `security.profile_updated`.
- [ ] A new `deviceId` produces one `security.new_device` alert.
- [ ] A successful airtime top-up produces a `topup_delivered` record
      with `amount`, `currency`, `serviceType`, `recipientPhone`.
- [ ] No notification `message`/`body` contains `{`/`[` — no raw entity
      JSON, no password hashes, no tokens, anywhere (email included).
