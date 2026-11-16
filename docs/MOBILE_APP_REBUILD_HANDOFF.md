# LidaPay Android Rebuild — Mobile Developer Handoff

**Audience:** Android / Flutter mobile engineers, QA, and product  
**Backend:** `https://api.advansistechnologies.com`  
**Interactive API contract:** `https://api.advansistechnologies.com/api-doc`  
**Android application ID:** `com.advansistechnologies.lidapay`

This is the implementation handoff for rebuilding the existing LidaPay app and
adding the shop module. Use the backend as the source of truth for prices,
wallet balances, payment state, fulfilment state, and provider outcomes. Do not
put provider credentials or Firebase Admin credentials in the Android app.

## 0. Start-to-finish implementation map

Build and test in this order. Each phase has an explicit “done” result so the
team knows what to implement next and what a successful API response means.

```text
App launch
  ├─ no valid session → Login with password OR email code → save session
  └─ valid session ────────────────────────────────────────┐
                                                           ↓
              Register/refresh FCM token → Load home data
                                                           ↓
       ┌──────────────────────┬───────────────────────────┐
       │ Airtime/Data         │ Lida Value                │ Shop
       │ choose country       │ load balance/history      │ browse catalog
       │ choose provider      │ USE self / SEND / etc.    │ server cart
       │ confirm recipient    │ confirm action            │ address + checkout
       └──────────┬───────────┴────────────┬───────────────┴─────┬─────────┘
                  ↓                        ↓                     ↓
           Payment or wallet debit / provider delivery       Advansis payment
                  └────────────────────────┬────────────────────┘
                                           ↓
                      Verify final state with backend API
                                           ↓
                   Receipt / wallet refresh / order tracking
```

### Milestones

| Milestone | Start with | Expected result / exit criteria |
|---|---|---|
| 1. App foundation | API client, environment config, secure session store, navigation | Public API works; errors are typed; no secrets/tokens are logged |
| 2. Auth | Password or email-code login, refresh, logout | User reaches authenticated home; expired access token refreshes once |
| 3. Account readiness | FCM permission/token registration, profile and wallet balance | Current user token is registered; home can recover state after relaunch |
| 4. Existing core services | Ghana and Reloadly airtime/data; Lida Value | Direct success, pending recipient decision, and failure each show distinct UX |
| 5. Payments | Advansis Pay and GTPay initiation, checkout return, status verification | Provider callbacks/redirects are hints; backend verification settles the receipt |
| 6. Shopping | Catalog, server cart, shipping address, checkout, payment, orders | Order is created, paid, tracked, and recoverable after app restart |
| 7. Release hardening | FCM/deep-link cold starts, device tests, accessibility, localization | Play-signed app passes acceptance checklist in §10 |

Do not start shopping payment UI before the shared session and payment
verification flow exists. Do not start provider top-up UI by hard-coding
operator lists; build the country/operator discovery calls first.

## 1. App structure and shared client requirements

Organize the client around shared services so the existing wallet/top-up
experience and the new shop use the same authentication, networking, payment,
notification, and deep-link handling:

- **Session/auth:** OTP login, access-token attachment, refresh, logout.
- **API client:** environment-based base URL, JSON, request IDs where supported,
  bounded timeouts, typed response/error parsing, and one auth-refresh retry.
- **Wallet:** Lida Value balance, history, USE, SEND, sell, convert.
- **Top-ups:** Ghana airtime/data and international Reloadly airtime/data.
- **Payments:** Advansis Pay/ExpressPay checkout and GTPay, status verification,
  receipts.
- **Shop:** catalog, categories, server cart, checkout, orders, delivery tracking.
- **Notifications:** FCM token lifecycle, push routing, decision updates.
- **Navigation:** authenticated app routes plus payment and push deep links.

Use the production API base URL above and a separately configured development
URL for local/staging builds. Never embed API/provider secrets in an APK, and
never log passwords, full access/refresh tokens, payment tokens, FCM tokens, or
payment credentials. Store session tokens using Android secure storage; clear
them on logout/account switch.

All authenticated calls use:

```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

Users can choose password login or passwordless email-code login:
- Password: `POST /api/v1/users/login` with username and password.
- Email code: `POST /api/v1/auth/login/request-otp`, then
  `POST /api/v1/auth/login/verify-otp`.
- Refresh with `POST /api/v1/auth/refresh` and `{ "refreshToken": "..." }`.

Keep the returned `user._id` as the authenticated user ID. Do not accept a
client-supplied `userId` as authorization; backend authentication owns identity.
Refresh once on an expired access token, then require re-authentication if the
refresh request fails.

### Auth flow — password or email code, restore, and logout

Offer two sign-in choices. Keep the challenge token only in memory and do not
treat it as an access token.

**Password option:** submit the user's username, email, or phone and password:

```http
POST /api/v1/users/login
Content-Type: application/json

{
  "username": "0244000000",
  "password": "<user-entered password>",
  "deviceToken": "<FCM token, if available>",
  "devicePlatform": "ANDROID",
  "deviceId": "<stable app-scoped device ID>",
  "appVersion": "<app version>",
  "locale": "en-GH"
}
```

This returns `access_token`, `refresh_token`, and `user` immediately. Save both
tokens in secure storage and continue to the authenticated home.

**Email-code option:** request a six-digit code using the existing username,
email, or phone. No password is required:

```http
POST /api/v1/auth/login/request-otp
Content-Type: application/json

{ "username": "0244000000" }
```

The `username` field accepts the account's mobile number or email address too;
for example, `{ "username": "user@example.com" }`. The verification code is
sent to the email address saved on that account.

On success, expect a challenge response:

```json
{
  "message": "Login verification code sent to your email",
  "challengeToken": "<short-lived challenge token>",
  "expiresAt": "2026-03-18T16:00:00.000Z"
}
```

**Backend smoke test (run with an authorized test account):** send the
account's mobile number or email as a JSON string. Preserve leading zeroes in
mobile numbers:

```sh
curl --include --request POST \
  'https://api.advansistechnologies.com/api/v1/auth/login/request-otp' \
  --header 'Content-Type: application/json' \
  --data '{"username":"<TEST_MOBILE_NUMBER_OR_EMAIL>"}'
```

The request is public; do not send an access token or password. A successful
request returns HTTP `200` with a `challengeToken` and `expiresAt`, and sends
the six-digit code to the email address saved on that account. The same request
works with either identifier, for example `{"username":"0244000000"}` or
`{"username":"user@example.com"}`. Use a test account whose inbox you can
check, and do not repeatedly request codes; the endpoint is rate-limited.

After retrieving the code from that inbox, verify it using the exact challenge
token from the response:

```sh
curl --include --request POST \
  'https://api.advansistechnologies.com/api/v1/auth/login/verify-otp' \
  --header 'Content-Type: application/json' \
  --data '{"challengeToken":"<CHALLENGE_TOKEN>","otpCode":"<SIX_DIGIT_CODE>"}'
```

Successful verification returns HTTP `200` with `access_token`,
`refresh_token`, and `user`. Keep these values private; redact them before
sharing logs or screenshots. An unknown identifier returns `401` with
`"Invalid login identifier"`. A `500` from either call is a backend failure,
not an OTP/challenge-token rejection; the backend team should correlate the
UTC request time with the server exception logs. A `500` on the request step
means no successful challenge response was issued to the app.

Show the six-digit code entry screen and expiry feedback. The code is emailed to
the address on the account and expires after the configured interval (10
minutes by default). Invalid identifier, throttling, unavailable email, or
expired challenge must leave the user unauthenticated with a clear retry or
support path. To request a new code, start a new request and replace the old
challenge token.

**Verify:** submit the exact challenge token and the OTP received by the user:

```http
POST /api/v1/auth/login/verify-otp
Content-Type: application/json

{
  "challengeToken": "<challengeToken from request-otp>",
  "otpCode": "<one-time code>",
  "deviceToken": "<FCM token, if available>",
  "devicePlatform": "ANDROID",
  "deviceId": "<stable app-scoped device ID>",
  "appVersion": "<app version>",
  "locale": "en-GH"
}
```

Expect HTTP `200` with `access_token`, `refresh_token`, and the full `user`
object matching `POST /api/v1/users/login`:

```json
{
  "access_token": "<jwt>",
  "refresh_token": "<jwt>",
  "user": {
    "_id": "673ba0e3f2c001e4dcee976e",
    "username": "0593998216",
    "firstName": "Kofi",
    "lastName": "Mensah",
    "email": "user@example.com",
    "phoneNumber": "0593998216",
    "roles": ["user"],
    "emailVerified": true,
    "phoneVerified": false
  }
}
```

`verify-otp` signs `access_token` and `refresh_token` with the exact same JWT
payload structure (`sub: String(user._id)`, `username`, `email`, `roles`) as
password login, so `GET /api/v1/users/profile`, `GET /api/v1/users/wallet/user`,
`GET /api/v1/users/account`, `GET /api/v1/lida-value/balance`,
`GET /api/v1/lidapoints/balance`, and `GET /api/v1/transactions/user/:userId`
behave identically across both sign-in methods. Save both tokens in secure
storage, attach the access token to authenticated requests, then register the
latest FCM token at `POST /api/v1/notifications/device-token` and load the
authenticated home data.

Note: The backend `JwtAuthGuard` rejects any token with a missing or invalid
`sub` claim (including pre-fix cached OTP tokens where `sub` was `"undefined"`)
with HTTP `401` (`"Invalid token payload"`). Any test device still holding an
older OTP session should log out (or clear local session storage) and sign in
again to obtain a fresh token.

If verification returns an invalid/expired OTP or challenge, keep the user on
the OTP screen and let them restart the login challenge; do not create a
partially authenticated session.

**Restore:** on app launch, load the secure session. If there is no token, show
login. If there is an access token, request protected home data; on an expired
access token, try refresh once:

```http
POST /api/v1/auth/refresh
Content-Type: application/json

{ "refreshToken": "<saved refresh token>" }
```

On refresh success, replace both saved tokens and retry the original request
once. On refresh failure, clear local session and route to login. Do not loop
retries or replay non-idempotent purchases automatically.

**Logout/account switch:** call
`DELETE /api/v1/notifications/device-token` while the current user's session
is still available, then clear access/refresh tokens, cached user-specific
wallet/cart/decision data, and pending private navigation state. When another
user signs in on the same device, register the device's current FCM token under
that user.

For the email-code login option, the code is sent to the email on the user's
account. The request endpoint is rate-limited; don't implement automatic rapid
retries.

### Password reset

The app starts a reset request with
`POST /api/v1/users/reset-password`, sending either `{ "email": "..." }` or
`{ "phoneNumber": "..." }`. The backend sends the reset link by email or SMS.
For phone resets, the backend sends an SMS to the account's stored phone
number through One4All. The API server must have `ONE4ALL_BASEURL`,
`ONE4ALL_APIKEY`, `ONE4ALL_APISECRET`, and the approved
`ONE4ALL_SMS_SENDER_ID` configured. These are backend settings/secrets and
must never be added to the app. A provider failure returns HTTP `502`, while
missing One4All SMS configuration returns HTTP `503`; check the backend logs.
The link opens a responsive browser form at
`https://api.advansistechnologies.com/reset-password`; the user enters and
confirms the new password there (with Show/Hide password review toggles and live
above-input password requirements that engage as the user types). The form
submits the token and new password to the backend and displays a success or
expired-link message. The reset token is carried in the URL fragment so it is
not sent in the initial page request.

After a successful reset, the completion page provides two return paths:
1. **Open LidaPay** (mobile deep link): uses `lidapay://auth/password-reset-complete`
   on iOS and upgrades to an Android Chrome intent URI
   (`intent://auth/password-reset-complete#Intent;scheme=lidapay;package=com.advansistechnologies.lidapay;S.browser_fallback_url=...;end`)
   on Android browsers, with a 1.6s visibility check that highlights the web
   fallback if the app does not open.
2. **Continue to LidaPay Web** (browser return): links to
   `PASSWORD_RESET_WEB_RETURN_URL` if configured, or
   `${APP_URL}?passwordReset=complete` (`https://advansistechnologies.com?passwordReset=complete`).

Partner responsibilities for the return flow:
- **LidaPay Mobile (Android & iOS)**: Register the `lidapay` URL scheme in
  `AndroidManifest.xml` (`VIEW` / `DEFAULT` / `BROWSABLE` `<intent-filter>` for
  package `com.advansistechnologies.lidapay`) and iOS `Info.plist`
  (`CFBundleURLTypes` -> `lidapay`), then handle the
  `lidapay://auth/password-reset-complete` route in the app router by opening
  the login screen with a password-reset success message (the deep link
  contains no password or reset token). Keep this separate from the
  payment-specific `lidapay://redirect-url` handler. (Note: the backend serves
  Android `/.well-known/assetlinks.json`, not an iOS Universal Links
  `apple-app-site-association` file, so registering `lidapay://` is required.)

  Android (`android/app/src/main/AndroidManifest.xml` inside `MainActivity`):
  ```xml
  <intent-filter>
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data
          android:scheme="lidapay"
          android:host="auth"
          android:path="/password-reset-complete" />
  </intent-filter>
  ```

  iOS (`ios/Runner/Info.plist`):
  ```xml
  <key>CFBundleURLTypes</key>
  <array>
      <dict>
          <key>CFBundleTypeRole</key>
          <string>Editor</string>
          <key>CFBundleURLName</key>
          <string>com.advansistechnologies.lidapay</string>
          <key>CFBundleURLSchemes</key>
          <array>
              <string>lidapay</string>
          </array>
      </dict>
  </array>
  ```
- **LidaPay Web**: When users arrive via **Continue to LidaPay Web** (at
  `?passwordReset=complete` on `APP_URL`, or at `PASSWORD_RESET_WEB_RETURN_URL`),
  open the web login view/modal with a password-updated confirmation message and
  optionally strip the query parameter with `history.replaceState`.

### Email verification

Registration sends an email verification link automatically. In the profile,
use `emailVerified` from `GET /api/v1/users/profile` to show whether the email is
verified. The link calls the public endpoint below; no access token is required
when the user opens it:

```http
GET /api/v1/users/verify-email/<one-time-token>
```

The link is single-use and expires after 24 hours. If it expires or the message
was not received, an authenticated user can tap **Verify** in the profile to
request a new message:

```http
POST /api/v1/users/resend-verification-email
Authorization: Bearer <access_token>
```

No email address is sent in the request body; the backend sends the message to
the signed-in account's email. The API constructs links using `API_URL` (defaults
to the production API URL), so set it to the reachable API origin in non-
production environments. Phone verification is separate and is not part of
this email flow.

## 2. Country, provider, and service selection

Use the selected recipient country (ISO-3166 alpha-2) to choose the provider:

| Recipient country | Provider / route | App behavior |
|---|---|---|
| Ghana (`GH`) | One4All / Prymo domestic integration | Ghana airtime and data routes; numeric domestic network IDs and Ghana data bundle codes |
| All other supported countries | Reloadly | Discover country/operators from the API, then pass the selected Reloadly `operatorId` |

For a normal airtime/data send to another person, use the route selected by the
recipient country and submit one purchase request with `isSelfTopup: false`.
For an eligible registered recipient, the backend can return a pending
recipient decision instead of delivering immediately. Ghana uses the domestic
routes below; all other supported destination countries use Reloadly. Do not
make a second provider purchase request after a recipient chooses DIRECT:
the decision response tells the backend to perform the selected delivery.

Do not hard-code international operator IDs. They can differ by country and
provider catalogue updates. Use the backend's Reloadly endpoints:

- `GET /api/v1/reloadly/country-list` — supported countries.
- `POST /api/v1/reloadly/find-country-by-code` with `{ "countryCode": "NG" }`.
- `POST /api/v1/reloadly/network-operators` with `{ "countryIsoCode": "NG", "size": 20, "page": 0, "includeBundles": true, "includeData": true }`.
- `GET /api/v1/reloadly-data/auto-detect?msisdn=<number>&countryCode=<ISO>` — data operator lookup by number.
- `POST /api/v1/reloadly-data/list-operators` with `{ "countryCode": "NG" }` — data-eligible operators.

For Ghana, the backend Swagger documents these domestic network codes:

| Code | Network |
|---:|---|
| 0 | Auto |
| 1 | AirtelTigo |
| 2 | Expresso |
| 3 | Glo |
| 4 | MTN |
| 5 | TiGO |
| 6 | Telecel |
| 8 | Busy |
| 9 | Surfline |

Use the exact network/data-code returned by the backend, validate phone number
and country with the user, and show amount/currency before confirmation. Do not
assume a Ghana number means a Ghana destination; the selected destination
country is authoritative.

### Ghana airtime

`POST /api/v1/airtime/topup`

```json
{
  "recipientNumber": "0244588584",
  "amount": 10,
  "network": 4,
  "isSelfTopup": false
}
```

For an eligible recipient, this normal/SEND request can return
`status: "PENDING"` with `decisionId` and `topupOrderId` when recipient choice
is enabled on the backend. Do not set `isSelfTopup: true` for SEND; that flag
is reserved for Lida Value USE to the signed-in user's own number and bypasses
recipient choice.

### Ghana data

First fetch available bundles with `POST /api/v1/internet/bundlelist` and
`{ "network": 4 }`, then purchase using
`POST /api/v1/internet/buydata`:

```json
{
  "recipientNumber": "0244588584",
  "dataCode": "DATA_10GB",
  "network": 4,
  "amount": 10,
  "currency": "GHS",
  "isSelfTopup": false
}
```

The bundle list's returned `id`/bundle code is the value to send as `dataCode`.
Do not substitute a display label. For an eligible recipient, this
normal/SEND request can return `status: "PENDING"` with `decisionId` and
`topupOrderId` when recipient choice is enabled on the backend.

### Reloadly international airtime

Discover the operator, then call `POST /api/v1/reload-airtime/recharge`:

```json
{
  "operatorId": 1,
  "amount": 1,
  "recipientNumber": "2348130678848",
  "recipientCountryCode": "NG",
  "senderNumber": "0244588584",
  "senderCountryCode": "GH",
  "currency": "USD",
  "enableRecipientChoice": true,
  "isSelfTopup": false
}
```

### Reloadly international data

Call `POST /api/v1/reloadly-data/buy-data` with a data-capable Reloadly operator:

```json
{
  "userId": "<authenticated user._id>",
  "operatorId": 1234,
  "amount": 20,
  "recipientNumber": "2348130678848",
  "recipientCountryCode": "NG",
  "senderNumber": "0244588584",
  "senderCountryCode": "GH",
  "currency": "NGN",
  "enableRecipientChoice": true,
  "isSelfTopup": false
}
```

For non-Ghana airtime/data SEND, enable recipient choice as supported by the
Reloadly request contract. If the recipient is eligible, the initiation
response can be `PENDING` with `decisionId` and `topupOrderId`. The same
recipient decision flow applies to Ghana and Reloadly; only the delivery
provider/route differs by destination country.

Provider route requests are authenticated with the customer's LidaPay session.
Backend-owned `userId`/`userName` values are derived from that session where
applicable. Ignore requests to collect or send provider API keys from the app.

## 3. Payments

### Advansis Pay / ExpressPay

Advansis Pay is the primary payment initiation route for normal airtime/data
payments and the currently documented live payment option for shop checkout.
Initiation is `POST /api/v1/advansispay/initiate-payment`; the authenticated
customer's required `userId` is the `user._id` from login.

```json
{
  "firstName": "Kofi",
  "lastName": "Mensah",
  "email": "kofi@example.com",
  "phoneNumber": "233241120481",
  "userId": "<authenticated user._id>",
  "amount": 20,
  "orderDesc": "Lidapay airtime top-up",
  "transType": "MOMO"
}
```

The response is wrapped in `data` and includes checkout information such as
`checkoutUrl`, `token`, and a transaction/order reference. Persist the token and
reference with the pending app transaction before opening the checkout.

1. Open the returned `checkoutUrl` in the payment WebView/browser flow.
2. Listen for the app return URI and show a pending/verifying screen.
3. Verify with `POST /api/v1/advansispay/query-transaction` and
   `{ "token": "<saved payment token>" }`; use its status, not the redirect
   query, to decide success/failure.
4. Poll the relevant top-up/order status until the backend reports a final
   state. A redirect can be missing or arrive before final settlement.

The API has server-side ExpressPay callbacks (`redirect-url` and `post-status`).
The Android app must not call these callback endpoints directly and must never
mark a transaction paid from a deep-link `status=COMPLETED` value alone.

### Native payment-return limitation to account for

The backend has a built-in LidaPay return fallback using `lidapay://` (commonly
`lidapay://redirect-url?...`). The initiation DTO currently validates
`returnUrl` as HTTP(S), even though some integration notes describe custom app
schemes. For the LidaPay Android app, omit `returnUrl` unless the backend team
confirms the deployed validator accepts the exact native URI. Do not rely on an
unverified custom `redirectUrl` field. Register and test the actual
`lidapay://` routes in the Android manifest, and parse both the payment
reference/token and status as untrusted hints before querying the API.

If a verified HTTPS App Link is used instead, the backend serves Android
Digital Asset Links at `/.well-known/assetlinks.json` and
`/api/v1/.well-known/assetlinks.json`. The app team must confirm package name
and signing-certificate fingerprint match the production Play Store build.

### Shop payment linkage

After `POST /api/v1/shop/checkout`, initiate payment for the returned server
`order.total` and include its `orderNumber` as `shopOrderNumber`:

```json
{
  "firstName": "Kofi",
  "lastName": "Mensah",
  "email": "kofi@example.com",
  "phoneNumber": "233241120481",
  "userId": "<authenticated user._id>",
  "amount": 158.58,
  "shopOrderNumber": "LPS260912482913",
  "orderDesc": "Lidapay shop order LPS260912482913",
  "transType": "MOMO"
}
```

The backend uses `shopOrderNumber` to reconcile final payment status to the
shop order. Never compute or trust the payable total from client cart prices.
GTBank has cleared LidaPay for production. GTPay can be enabled as an app
payment option alongside Advansis Pay once the backend authorization gap below
is closed. Use the same `shopOrderNumber` linkage with GTPay, and verify final
status through the backend before showing a paid receipt.

### GTPay / GTBank

The mobile app calls the LidaPay API, never GTBank directly. GTBank credentials,
request signing, provider URLs, and the callback endpoint are server-side only.
Use `POST /api/v1/gtpay/services` to discover available `ServiceName` values;
do not hard-code a catalogue. `GET /api/v1/gtpay/banks` (or its POST alias)
returns the current bank list for bank-transfer flows.

**Use `debitwallet` for the normal GTPay customer payment.** It requests a
debit from the customer's mobile-money number in `ServiceNumber`; the response
may remain pending while GTBank waits for the telco/operator. For a shop order,
include `shopOrderNumber` and use the exact server-returned `order.total`.
`creditwallet` is the opposite direction (credit/inflow) and is reserved for
separately supported flows such as conversion, reversals, or incoming money
transfers. `banktrf` is an external bank transfer/payout, not the usual
customer mobile-money debit. Never substitute one service for another.
Discover available services and banks from the production API.

```http
POST /api/v1/gtpay/pay
Content-Type: application/json
Authorization: Bearer <access_token>
```

```json
{
  "PartnerTransId": "20261027000123456789",
  "userId": "<authenticated user._id>",
  "userName": "<authenticated username>",
  "shopOrderNumber": "LPS260912482913",
  "ServiceDetails": {
    "ServiceName": "debitwallet",
    "ServiceNumber": "0241120481",
    "SecondaryServiceNumber": "",
    "Amount": "158.58",
    "Remarks": "LidaPay shop order LPS260912482913",
    "PaidBy": "Kofi Mensah",
    "PayeeName": "LidaPay"
  }
}
```

`ServiceDetails` requires `ServiceName`, `ServiceNumber`, `Amount` (numeric
string, preserving exact decimal precision), `Remarks`, and `PaidBy`.
`PartnerTransId` is optional (numeric string, maximum 20 characters); if the
caller supplies it, generate it once per payment attempt and persist it. The
backend generates it if omitted. `userId`, `userName`, `shopOrderNumber`,
`CallbackURL`, `PayeeName`, `SecondaryServiceNumber`, and service-specific
fields are optional in the deployed DTO; identity must still come from the
authenticated session, not a client-provided ID. Do not send `SecureHash`; the
backend signs the provider request.

The endpoint returns an envelope `{ "status", "message", "data" }`; the
provider state is `data.Status`, not the HTTP status. A successful HTTP 200 can
still contain `data.Status: "PENDING"`. Persist `data.PartnerTransId` before
showing a verifying state. GTBank may still be waiting for the relevant
mobile-money operator/telco to confirm the debit; that downstream response can
arrive later, after the initial pay request has returned. Therefore, `PENDING`
is not a payment failure or success, and the app must keep checking rather
than deciding from the initial response.

Call `POST /api/v1/gtpay/status` with
`{ "PartnerTransId": "<saved ID>" }` to retrieve the latest provider result.
While `data.Status` is `PENDING`, continue status checks with a measured
backoff while the app is active, and resume checking when the app returns to
the foreground. Stop only when status is `COMPLETED` or `FAILED`; use that
final server-reconciled status to settle the receipt and refresh the wallet or
shop order. Do not retry the payment as a new transaction while the telco
response is outstanding. On `504 PAYMENT_STATUS_UNKNOWN` or a client timeout,
query status with the same ID before considering any retry. The callback at
`POST /api/v1/gtpay/callback` is for GTBank-to-backend delivery; the app must
not call it or treat a callback/redirect as payment confirmation.

For a non-shop customer debit, omit `shopOrderNumber` and set an accurate
payment `Remarks` value. For a credit/inflow use case, only call
`ServiceName: "creditwallet"` as part of its explicitly supported product flow;
for a bank payout, use `ServiceName: "banktrf"` with the current bank list and
beneficiary details. These are distinct operations with different ledger and
confirmation paths.

The production screenshots show a `creditwallet` request returning HTTP 200
with `data.Status: "PENDING"` and a later `/status` response of
`COMPLETED`. This confirms that creditwallet request and status flow, not
debitwallet production behavior. Test `debitwallet` separately with an
approved, controlled customer mobile-money account before enabling customer
debits. The current GTPay contract does not expose a fee-quote endpoint; if the
final debit including fees must be confirmed before submission, add a backend
quote/confirmation step rather than guessing fees in the app.

**Production API authorization caveat:** the live Swagger snapshot checked on
2026-10-27 lists GTPay operations without bearer security, and the GTPay
controller does not currently declare a JWT guard. Do not interpret that as
permission to expose an unauthenticated payment route to the app or browser.
Before release, require backend authentication/partner authorization and derive
the transaction owner from the verified session. Until then, web consumers
must call through their own trusted server and the backend team must close the
authorization gap; never put GTBank credentials in a browser or APK.

## 4. Lida Value wallet

All these endpoints use the authenticated user's wallet; attach the bearer token
and do not send a wallet/user ID as the authority:

| Function | Method and route | Call details |
|---|---|---|
| Balance | `GET /api/v1/lida-value/balance` | Returns `totalValueUnits`, `airtimeValueUnits`, `dataValueUnits` |
| History | `GET /api/v1/lida-value/history?page=1&limit=20` | Paginated ledger/history; render server data and pagination |
| USE (buy for self) | `POST /api/v1/lida-value/use` | `{ "amount": 10, "destination": "0244588584", "metadata": { "network": 4, "productType": "AIRTIME" } }` |
| SEND (transfer wallet value) | `POST /api/v1/lida-value/send` | `{ "amount": 25, "destination": "recipient identifier", "metadata": { "recipientName": "Ama" } }` |
| Sell | `POST /api/v1/lida-value/sell` | `{ "amount": 50, "destination": "account-or-phone", "metadata": { "destinationType": "mobile_money" } }` |
| Convert | `POST /api/v1/lida-value/convert` | `{ "amount": 10, "destination": "momo:+233241234567" }`; use the backend-defined destination format |
| Eligibility | `GET /api/v1/lida-value/eligibility` | Check before displaying/starting eligibility-gated wallet actions |

### USE versus SEND is not interchangeable

- **USE** is self-only: call `/lida-value/use`, pass the user's own number and
  `metadata.productType` (`AIRTIME` or `DATA`) plus the Ghana `network`.
  Backend debits Lida Value and directly purchases the service; no recipient
  decision or decision push should be expected. Do not follow this call with a
  second airtime/data request.
- **SEND from the Lida Value screen** is recipient-facing: use the supported
  send flow, and when the app is sending airtime/data on behalf of the wallet,
  follow the current documented sender/recipient decision flow. The network
  top-up endpoints accept `isSelfTopup: false` for SEND and `true` for
  self-USE. Never pass `true` when sending to another person.
- **Wallet value transfer** (`/lida-value/send`) and **airtime/data send**
  are distinct actions. Confirm intended UX with product before mapping one to
  the other.
- Sell and convert can move value to an external destination. Show destination,
  amount/rate/fees returned by the API and a final confirmation; do not invent
  rates or treat a successful request as settled payout without checking its
  response/history.

Insufficient-balance, invalid destination, provider failure, and pending
decision responses must be shown explicitly. Refresh balance and history after
each final wallet operation.

## 5. Recipient choice — sender and recipient experiences

Normal SEND requests to an eligible registered recipient can return `PENDING`
with a `decisionId`, `topupOrderId`, `expiresAt`, and `serviceType`. Unregistered
recipients are delivered directly. The backend owns eligibility and decision
creation during the supported top-up request; the app should not create a
second decision for the same purchase.

The recipient decision is the choice point for the initial airtime/data send:

| Recipient choice | Backend action | App behavior |
|---|---|---|
| `LIDA_VALUE` | Credit the recipient's Lida Value wallet | Show saved-to-wallet only after the backend confirms the final disposition |
| `DIRECT` | Deliver the selected airtime/data service using the route for the recipient's country (Ghana domestic provider or Reloadly elsewhere) | Show delivered only after the backend confirms the final disposition |

The sender makes one top-up initiation call. The recipient's response resolves
that same top-up; it is not a request for the app to call the Ghana or Reloadly
purchase endpoint again. `DIRECT` applies to airtime or data according to the
service selected at initiation.

Optional preflight:

```http
POST /api/v1/recipient/eligibility
```

```json
{
  "recipientPhone": "0244588584",
  "countryIsoCode": "GH",
  "serviceType": "AIRTIME"
}
```

When the SEND request returns pending:

1. Save its `decisionId` and `topupOrderId` to the sender's pending receipt.
2. Show “Waiting for recipient” with the backend `expiresAt`; do not report
   airtime/data delivered yet.
3. Sender polls `GET /api/v1/topups/{topupOrderId}/status` and/or
   `GET /api/v1/recipient-decisions/{decisionId}` until terminal/resolved.
4. Recipient opens the push/in-app inbox item and chooses `DIRECT` or
   `LIDA_VALUE`:

```http
POST /api/v1/recipient-decisions/{decisionId}/respond
Content-Type: application/json
X-Idempotency-Key: <stable UUID for this response attempt>

{ "choice": "DIRECT" }
```

Reuse the same idempotency key if retrying that response after a timeout.
`LIDA_VALUE` uses the same endpoint with `{ "choice": "LIDA_VALUE" }`. The app
must not separately call `/api/v1/airtime/topup`, `/api/v1/internet/buydata`,
or a Reloadly purchase route to implement either choice.

5. Poll the top-up/decision status until the backend reports the final
   disposition, then refresh both users' receipts/wallet state.

Possible outcomes include `DELIVERED_DIRECT` and `DELIVERED_LIDA_VALUE` /
`SAVED_TO_LIDA_VALUE`. Timeouts resolve by backend policy (default choice is
Lida Value in the current guide); use canonical fields such as `status`,
`selectedChoice`, `finalDisposition`, `resolvedSource`, and `resolvedAt`.
Do not assume that timeout always appears as an `EXPIRED` terminal state.
Treat duplicate taps/retries as potentially concurrent; disable the choice
buttons while a response is in flight and display the server's final decision.

### Recipient-side pending decision recovery (`GET /api/v1/recipient-decisions/pending`)

Do **not** depend exclusively on Firebase push delivery to surface a pending
choice to the recipient. Whenever a user signs in, opens the app, resumes from
the background, or opens the Notifications/Home tab, call:

```http
GET /api/v1/recipient-decisions/pending
Authorization: Bearer <access_token>
```

If `count > 0`, immediately display the pending Recipient Choice modal/sheet for
`decisions[0]` (showing `senderName`, `amount`, `currency`, `serviceType`, and
`expiresAt` countdown) so users with OS notifications muted, battery-optimized,
or offline at send time still get their choice before timeout.

### Sender flag rule (`isSelfTopup`)

- Only set `"isSelfTopup": true` when the signed-in user is explicitly executing a
  **USE** self-topup from their Lida Value dashboard to their own number.
- For every **SEND** airtime/data screen (both Ghana domestic and Reloadly
  international), send `"isSelfTopup": false` (never hardcode `true` or pass the
  string `"false"`).

## 6. FCM registration, handling, and routing

**Every phone install must be registered with an active FCM token before a user
can receive Recipient Choice push notifications.** The mobile rebuild team must
implement all four rules below:

1. **Send the FCM token in auth payloads AND call the dedicated registration endpoint:**
   - Include `deviceToken` (or `fcmToken`/`token`), `devicePlatform` (`"ANDROID"` / `"IOS"`),
     and `deviceId` in `POST /api/v1/users/login`, `POST /api/v1/users/register`,
     `POST /api/v1/auth/login/verify-otp`, and `POST /api/v1/auth/refresh`.
   - Also explicitly call `POST /api/v1/notifications/device-token` on authenticated
     app startup/session restore, on `FirebaseMessaging.instance.onTokenRefresh`,
     whenever notification permission changes to granted, and after account switch:

```http
POST /api/v1/notifications/device-token
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "token": "<FCM token>",
  "platform": "ANDROID",
  "provider": "FCM",
  "deviceId": "<persistent per-install UUID, NOT Build.DEVICE>",
  "appVersion": "<version>",
  "locale": "en_GH"
}
```

   - **Important when `await`ing FCM token on launch:** If `FirebaseMessaging.instance.getToken()`
     is still null during login (e.g., slow cold boot or Play Services init), retry
     fetching the token once the home screen initializes and immediately call
     `POST /api/v1/notifications/device-token`. The backend accepts `token`,
     `deviceToken`, `fcmToken`, or `pushToken` (and normalizes platform case),
     and defaults omitted platform safely, so never skip calling the endpoint.
2. **Generate a unique per-install UUID for `deviceId` (NEVER `Build.DEVICE`):**
   - Persist a generated UUID v4 in app storage (`SharedPreferences` /
     `flutter_secure_storage`) and pass that UUID as `deviceId`.
   - **Never** send `androidInfo.device` / `Build.DEVICE` (for example
     `emulator64_x86_64_arm64` or hardware board codenames), because multiple
     users on the same phone model share the same string.
3. **Verify registration on QA/staging builds:**
   - Call `GET /api/v1/notifications/device-token` after login/startup and confirm
     `data.total >= 1` with `isActive: true`.
4. **Deactivate only on explicit logout:**
   - On logout, deactivate the token with `DELETE /api/v1/notifications/device-token`
     using the current authenticated session. Never register a recipient token under
     the sender's account.

Handle foreground, background, and notification-open events. Recognize current
and compatibility values such as `recipient_decision`,
`recipient_topup_decision`, and `recipient_topup_resolved`, and inspect
`eventType` as well as `type`. Current decision pushes can include
`decisionId`, `topupOrderId`, `serviceType`, `amount`, `currency`,
`senderName`, `recipientPhone`, `expiresAt`, `allowedChoices`, and
`defaultChoice`. Resolved pushes can include `selectedChoice`,
`finalDisposition`, `resolvedSource`, and `resolvedAt`.

Use push data to navigate and refresh state, not as the final transaction
record. If the app is killed and a push arrives, route into the authenticated
app, fetch the decision from the API (`GET /api/v1/recipient-decisions/{decisionId}`
or `GET /api/v1/recipient-decisions/pending`), and then show the choice screen
only if the decision remains pending. Log request/response status and redacted IDs
for token registration and decision/status polling; never log the FCM token.

## 7. Deep links and Android navigation

### Advansis Pay return: exact callback and Flutter steps

When the customer finishes ExpressPay checkout and returns to the merchant, the
backend's built-in mobile fallback is:

```text
lidapay://redirect-url?orderId=<Advansis order ID>&token=<payment token>&status=<hint>&transactionId=<provider transaction ID>&timestamp=<epoch>
```

The parameter set can be incomplete on an error path. The app must have already
saved the payment `token` and `order-id` from `initiate-payment`; use those
saved values as the primary lookup keys. The incoming URI's `status` and
transaction ID are untrusted hints. Do not assume `lidapay://shop/checkout/callback`
will be emitted: current backend code builds the default `lidapay://redirect-url`
callback when no server-approved `returnUrl` was supplied.

Flutter/Android work to complete:

1. Register an Android `VIEW` intent filter on the Flutter `MainActivity` with
   `DEFAULT` and `BROWSABLE` for the payment callback (`scheme="lidapay"`,
   `host="redirect-url"`) and a separate scoped intent filter for password-reset
   completion (`scheme="lidapay"`, `host="auth"`,
   `path="/password-reset-complete"`). Keep each route explicitly scoped; do not
   add an unrestricted URL handler.
2. Use a Flutter deep-link listener (for example, `app_links`) and handle both
   the initial URI when the process is cold-started and the URI stream when the
   app is already running or resumed. Configure this once near app startup.
3. Dispatch each allowlisted route strictly by host/path: route
   `host == 'auth' && path == '/password-reset-complete'` to the Sign In screen
   with a `"Password updated"` banner (never into the payment handler), and
   route `host == 'redirect-url'` to the payment-return handler. Parse only
   allowlisted payment keys (`orderId`, `token`, `status`, `transactionId`,
   `timestamp`); never navigate directly from arbitrary host/path values.
4. Match the callback to a locally saved pending payment. If the callback's
   reference does not match a pending payment, do not query/display another
   user's or unrelated transaction. Avoid logging the `token` or full URI.
5. Immediately show a **Verifying payment** state. Call
   `POST /api/v1/advansispay/query-transaction` with the saved token. If the
   result is pending/ambiguous or the query temporarily fails, retain the
   pending payment and offer retry/status refresh; do not charge again.
6. For a shop payment, refresh the authenticated order using its saved order ID
   (`GET /api/v1/shop/orders/{id}`) and show the backend's payment/order state.
   For any other payment flow, refresh that flow's transaction/top-up state
   using its supported status endpoint. Only a final backend success may show a
   paid/delivered success receipt.
7. Mark the locally stored pending item handled only after the API-backed
   resolution has been saved. Make handling idempotent because Android may
   deliver the same URI more than once.

Android manifest intent-filter example (merge into the existing
`MainActivity`; do not replace other Flutter filters):

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="lidapay" android:host="redirect-url" />
</intent-filter>
```

Flutter listener outline (adapt it to the app's chosen routing/state
architecture):

```dart
final appLinks = AppLinks();

Future<void> startPaymentLinkHandling() async {
  final initialUri = await appLinks.getInitialLink();
  if (initialUri != null) {
    await handlePaymentReturnUri(initialUri);
  }

  appLinks.uriLinkStream.listen((uri) {
    handlePaymentReturnUri(uri);
  });
}

Future<void> handlePaymentReturnUri(Uri uri) async {
  if (uri.scheme != 'lidapay' || uri.host != 'redirect-url') return;

  final orderId = uri.queryParameters['orderId'];
  final callbackToken = uri.queryParameters['token'];
  if (orderId == null || orderId.isEmpty) {
    showPaymentPendingOrSupportState();
    return;
  }

  final pending = await pendingPayments.findByOrderId(orderId);
  if (pending == null) {
    showPaymentNotMatchedState();
    return;
  }

  showVerifyingPayment(pending);
  final result = await paymentApi.queryTransaction(
    token: pending.token,
  );
  await resolveAndRefreshLinkedPurchase(
    pending: pending,
    result: result,
    callbackTokenMatches:
        callbackToken == null || callbackToken == pending.token,
  );
}
```

The outline is illustrative: `pendingPayments`, UI methods, error handling, and
the API client must be implemented by the app. Compare the callback token, when
present, with the saved token; query using the saved token rather than trusting
the callback. If callback and saved references conflict, keep the transaction
pending and report a safe error for investigation.

Do not pass a custom `returnUrl` from Flutter unless the backend team confirms
the deployed allowlist and DTO validation accept that exact value. The current
Advansis initiation DTO documents HTTP(S)-only `returnUrl`, while the backend
generates the native `lidapay://redirect-url` fallback when it is omitted.
`redirectUrl` shown in older shop examples is not a substitute for the
server-side callback contract; send `shopOrderNumber` for order reconciliation
and use the built-in callback unless the current API contract explicitly
supports a custom URL.

### Other app links and push navigation

For every incoming URI:

1. Validate scheme, host, path, and expected query keys against an allowlist.
2. Parse it as a navigation hint; never trust `status`, `amount`, or an order
   number to prove payment.
3. Load the associated pending payment/order from app state or API.
4. Call Advansis Pay query or fetch the authenticated order/transaction status.
5. Render success only after the backend reports a final successful state;
   otherwise show pending, retry, or failure with an accessible next action.

Also implement notification deep links for recipient decisions and resolved
events. A decision link must fetch the authenticated decision first, gracefully
handle already-resolved/expired decisions, and avoid showing a stale choice UI.
Persist a pending inbound URI until login is complete, then route it once.

Do not combine auth deep-link routing, payment callback parsing, and FCM payload
parsing into one unvalidated navigation path. They have different trust
boundaries: `lidapay://auth/password-reset-complete` opens the Sign In view
with a confirmation message (and carries no credentials); payment returns must
query payment/order state; decision pushes must fetch the decision and top-up
status.

Production release checks: verify the Play signing SHA-256 fingerprint against
the backend Digital Asset Links document, verify Android `assetlinks.json`
fetches successfully without redirects, and test the installed Play-signed
build (not only debug) for app-link verification, password-reset return
(`lidapay://auth/password-reset-complete`), payment return, and cold-start
routing.

## 8. Shop catalogue, cart, checkout, and orders

The shopping backend is integrated under `/api/v1/shop`; product/category
browsing is public, while cart, checkout, and a user's orders require auth.

| Screen/action | Endpoint |
|---|---|
| Categories | `GET /api/v1/shop/categories?activeOnly=true` |
| Product list | `GET /api/v1/shop/products?page=1&limit=20&category=<id>&search=<term>` |
| Featured products | `GET /api/v1/shop/products/featured` |
| Product detail | `GET /api/v1/shop/products/{id}` |
| Cart | `GET /api/v1/shop/cart` |
| Add/update/remove/clear | `POST /cart/add`, `PUT /cart/update`, `POST /cart/remove`, `DELETE /cart/clear` under `/api/v1/shop` |
| Checkout | `POST /api/v1/shop/checkout` |
| Order history/detail | `GET /api/v1/shop/orders?page=1&limit=20`, `GET /api/v1/shop/orders/{id}` |
| Tracking | `GET /api/v1/shop/orders/{id}/tracking` |
| Cancel | `POST /api/v1/shop/orders/{id}/cancel` |

Treat returned product prices as final. `price` includes the configured
commission; when `discountPrice > 0`, that is the effective price. Do not add a
commission or recalculate discounts in the client. Keep local cart state only
for responsive UX and sync it to the server. The server cart and checkout
response are authoritative.

Checkout requires a complete shipping address (the profile does not supply one
in the current API contract) and destination map coordinates, and does not
accept a client-calculated distance or delivery fee.
Shop-specific KYC fields are not supported. `deliveryUpdates[].location` is a
tracking timeline string, not delivery coordinates. See
[SHOP_API_MOBILE_HANDOFF.md](./SHOP_API_MOBILE_HANDOFF.md) for the exact
checkout contract.

```json
{
  "shippingAddress": {
    "fullName": "Kofi Mensah",
    "phone": "0241120481",
    "addressLine1": "12 Osu Avenue",
    "addressLine2": "Flat 4B",
    "city": "Accra",
    "region": "Greater Accra",
    "country": "Ghana",
    "email": "kofi@example.com",
    "latitude": 5.555,
    "longitude": -0.205
  },
  "paymentMethod": "momo"
}
```

Checkout uses server cart/prices, validates stock, creates a pending order,
decrements stock, and clears the server cart. The app should let the customer
pin or confirm the delivery destination on the map, retain the street address,
and send destination latitude/longitude from the confirmed map pin. Both
coordinates are required for delivery checkout. A user can place the pin
manually without granting device-location permission. Do not send a pickup
location, branch ID, distance, or delivery fee from the app.

LidaPay admin configures private shop branches and assigns products to their
fulfillment branch. At checkout, the backend resolves the branch from the
server-side cart/products, saves a private pickup snapshot on the order, and
computes driving kilometers from that branch to the customer's coordinates
with the server-side Google Routes API. Frank receives the pickup, destination,
distance, and product details from the existing courier jobs poll. The pickup
branch and its coordinates are not returned by public product, order, or
tracking APIs; the app does not need them to capture the customer's address.
A map display/location SDK alone does not calculate the backend route distance.

One order must be fulfilled by one branch. If a cart contains products from
multiple branches, checkout returns `400` so the customer can place separate
orders for each branch. If a partner has only one active branch, legacy
products for that partner are automatically resolved to it; with multiple
active branches, each product needs an explicit branch assignment.

Persist its order `_id`,
`orderNumber`, `total`, and payment status before payment initiation. Initiate
payment with exactly the returned total and `shopOrderNumber`. On final payment,
refresh order detail and show its current state. The order lifecycle is
`pending → paid → processing → shipped → delivered`; cancellation/refund states
are also possible. Tracking is a backend timeline; do not fabricate courier
updates. Public order-number lookup may expose shipping details, so prefer
authenticated order detail and do not expose order numbers unnecessarily.

**Courier pricing & Order Tracking UI:** LidaPay calculates the delivery fee
at checkout from a server-side rate card (`DELIVERY_RATE_CARD` in `.env`)
based on `deliveryDistance.km`. The customer sees the final fee in
`order.total` before paying — the app does **not** send or calculate a
delivery fee. Frank reads the charged `deliveryFee` and `deliveryDistance.km`
from the courier job payload; Frank does **not** submit a quote back to LidaPay.
Customer destination GPS is optional and must only be requested when the
delivery flow requires it; keep a manual address path for users who decline.

On the **Track Order** screen, the mobile app is strictly read-only (`GET /api/v1/shop/orders/{order._id}/tracking` with the customer's `Bearer` JWT; never embed courier partner credentials in the app) and must implement four updates:

1. **Google Maps Driver Pin (`lastDriverLocation`):** Using LidaPay's restricted Google Maps SDK key, render the live driver marker at `lastDriverLocation.latitude` / `longitude` once `status === "shipped"`, along with a freshness label from `lastDriverLocation.recordedAt`.
2. **Active Screen Polling (5–10s):** Poll `GET /api/v1/shop/orders/{order._id}/tracking` every 5–10 seconds only while the tracking screen is visible and the order is active (`processing` or `shipped`). Stop polling when the screen closes, the app is backgrounded, or the order reaches `delivered`/`cancelled`.
3. **Delivery Status Timeline (`deliveryUpdates`):** Render `deliveryUpdates[]` (`courier_accepted`, `packed`, `picked_up`, `out_for_delivery`, `delivery_exception`, `failed_delivery`, `delivered`) in chronological order with `message`, optional `location`, and `timestamp`.
4. **Carrier & ETA Header:** Display `carrier`, `trackingNumber`, and `estimatedDeliveryDate` (or `deliveredAt` once completed).

See [SHOP_API_MOBILE_HANDOFF.md](./SHOP_API_MOBILE_HANDOFF.md) for field-level
catalogue, cart, checkout, payment, and tracking examples.

## 9. End-to-end flow maps — start here, finish here

These are the implementation paths the screens should follow. In every flow,
persist the backend reference before navigating away so the app can recover
after process death. A button tap or successful HTTP response that says
`PENDING` is not a completed delivery/payment.

### A. Returning user opens the app

```text
Launch
 → read secure access/refresh tokens
 → no session: show Login
 → session exists: request protected home data
      ├─ success: register/refresh FCM token → show home
      └─ access token expired: POST /auth/refresh
           ├─ success: replace both tokens → retry original GET once → show home
           └─ failure: clear session → show Login
```

**Home screen start calls:** after authentication, load the signed-in user's
profile/home data, `GET /api/v1/lida-value/balance`, and any app-required
notification/unread state. Load shop catalog only when the user enters Shop;
avoid blocking home on a slow provider catalogue. On app resume, refresh data
that may have changed while backgrounded.

**Finish when:** the home screen reflects the current account, token
registration is done for that account, and no stale account data remains.

### B. Normal airtime or data purchase

```text
Choose Airtime or Data
 → choose recipient country
 → GH: choose network (and for Data, fetch bundle list)
   Other country: fetch operators; select operator
 → enter/confirm phone, amount or bundle, show currency and total
 → user confirms once
 → call the selected top-up route
      ├─ direct provider success: show receipt and refresh relevant history
      ├─ PENDING + decisionId: save refs → sender waiting screen → flow C
      └─ error/unknown: show error or verify status before offering retry
```

Relevant start calls:

- Ghana airtime: `POST /api/v1/airtime/topup`
- Ghana data: bundle list at `POST /api/v1/internet/bundlelist`, then
  `POST /api/v1/internet/buydata`
- International airtime: country/operator discovery, then
  `POST /api/v1/reload-airtime/recharge`
- International data: country/operator discovery, then
  `POST /api/v1/reloadly-data/buy-data`

For a send to another person, set `isSelfTopup: false`. Use Ghana routes for a
Ghana recipient and Reloadly routes for other supported countries. When the
backend returns `PENDING` with decision references, follow flow C; do not
submit a second direct-credit call when the recipient later chooses `DIRECT`.
For Lida Value USE to self, use the Lida Value USE contract instead of this
normal/SEND flow.

For a result with a provider transaction reference, use the supported
transaction-status endpoint when the response is pending/ambiguous. Ghana
airtime exposes `POST /api/v1/airtime/transtatus` with
`{ "transReference": "<reference>" }`. Reloadly airtime exposes
`GET /api/v1/reload-airtime/topup-status/{transactionId}`; retain the returned
transaction ID and use it for status checks. The current mobile contract does
not identify a dedicated status route for every Reloadly data outcome, so do
not invent one: keep the provider response/reference and ask the backend team
for the deployed data-status contract if a result remains ambiguous. A timeout
is unknown, not failure: query status before submitting again.

**Important payment boundary:** the service route examples above are the
backend's airtime/data provider purchase calls. Advansis Pay initiation is a
separate payment contract. Do not invent a client-side “charge then top-up”
sequence or submit the provider purchase twice. Implement the legacy payment
ordering already used by the released app only after matching it to the
deployed Swagger/backend contract; the final receipt must show both payment
and delivery state when both apply.

### C. SEND to another person and recipient choice

```text
Sender confirms recipient/service
 → set isSelfTopup=false
 → submit one top-up request
      ├─ direct result (recipient not eligible): show final delivery result
      └─ PENDING:
           save topupOrderId + decisionId + expiresAt
           show "Waiting for recipient" receipt
           poll topup status while app is open/resumed
           recipient receives FCM → opens app → GET decision
              ├─ still PENDING: show DIRECT / LIDA_VALUE choices
              └─ already resolved/expired: show final status, no choice form
           recipient submits one choice to the decision response endpoint
              ├─ LIDA_VALUE: backend credits recipient wallet
              └─ DIRECT: backend delivers selected airtime/data via
                   Ghana domestic route or Reloadly for other countries
           sender and recipient refresh server status
           show final disposition
```

**Expected checkpoints:**

1. Initial sender response has `status: PENDING`, `decisionId`, and
   `topupOrderId` when recipient action is needed.
2. Recipient push is a notification to navigate, not the decision record.
3. Before showing choices, fetch
   `GET /api/v1/recipient-decisions/{decisionId}`.
4. Submit `DIRECT` or `LIDA_VALUE` to
   `POST /api/v1/recipient-decisions/{decisionId}/respond` with an
   `X-Idempotency-Key`, reusing that key for retries of the same response.
   The app does not initiate another provider purchase for `DIRECT`; backend
   applies the choice to the original top-up.
5. Finish only after status reports a resolved decision and final disposition.
   If the app was killed, resume using the saved IDs and fetch status again.

If the recipient does not answer, backend timeout policy resolves the request.
Render the returned default choice/final disposition; do not locally select a
choice or promise that the timeout result is `EXPIRED`.

### D. Lida Value

**USE for own airtime/data:**

```text
Open Lida Value → USE
 → GET /api/v1/lida-value/balance
 → prefill own phone; select AIRTIME or DATA
 → select Ghana network (and bundle if data)
 → confirm amount → POST /api/v1/lida-value/use once
 → show API result → GET balance + history → finish
```

Send `metadata.productType` and the correct network; destination must be the
current user's own number. Expected success is a direct operation without
`decisionId`/`PENDING`. If the API returns an error, preserve the wallet screen
and explain the failure; never retry a debit automatically after an ambiguous
timeout.

**SEND / wallet transfer:**

```text
Open Lida Value → SEND
 → collect recipient and amount
 → confirm the exact transfer type (wallet value OR airtime/data)
 → call the matching backend endpoint once
 → direct response: show result + refresh balance/history
 → recipient decision pending: continue with flow C
```

`POST /api/v1/lida-value/send` sends wallet value to another account; it is not
the airtime/data top-up endpoint. For airtime/data SEND, call the relevant
domestic/Reloadly purchase route with `isSelfTopup: false` as configured by the
released product flow. Do not silently map a wallet transfer button to airtime.

For sell/convert, show a review/confirmation of destination and server-provided
terms before submission. Finish from the API result and refreshed history;
do not present the request acknowledgement as settled payout if it is pending.

### E. Shop purchase

```text
Enter Shop
 → GET categories/products (public)
 → product detail → choose quantity → POST cart/add
 → GET cart; show server subtotal, discount, total
 → collect and validate shipping address
 → POST /api/v1/shop/checkout
      ├─ validation/stock error: remain in cart, refresh cart/product
      └─ order created: persist order id + orderNumber + total
           → POST /api/v1/advansispay/initiate-payment with exact total
              and shopOrderNumber
           → persist payment token/reference → open checkoutUrl
           → callback or app resume → query payment by token
           → GET order detail until paymentStatus is final
              ├─ success: show paid receipt → order/tracking screen
              ├─ failed: show retry/support state; don't recreate order blindly
              └─ pending/unknown: keep verifying state and poll on resume
           → GET /api/v1/shop/orders/{id}/tracking for delivery timeline
```

**Finish when:** payment is confirmed by the backend, the order reflects its
updated payment/order state, and the customer can reopen it from order history.
If checkout created an order but payment initiation failed, retain that order
reference and query order/payment state before retrying. GTPay is not the
production shop fallback until backend/product explicitly confirms it is live.

### F. Payment return or push opens a terminated app

```text
Receive URI or notification while app is cold
 → retain inbound route until session is restored
 → validate URI/payload keys
 → restore/refresh auth
 → fetch payment/decision/order from API using saved reference
 → route to the appropriate receipt/choice/tracking screen
 → discard the inbound route after handling once
```

For payment, call `POST /api/v1/advansispay/query-transaction` with the saved
token and then refresh the linked order/top-up. For recipient decisions, fetch
the decision and top-up status before showing a choice. An inbound event may be
stale, duplicated, or already resolved.

## 10. Common error and state handling

- Parse HTTP status and API error body; distinguish auth, validation, no stock,
  insufficient balance, provider failure, timeout, and network/offline cases.
- A client timeout is an unknown outcome, not proof the backend failed. Query
  by saved payment token, decision ID, top-up order ID, or shop order before
  retrying to prevent duplicate charges/delivery.
- Disable duplicate submit while a request is in flight. Use idempotency keys
  where the API contract supports them (for example `X-Idempotency-Key` on
  explicit recipient-decision creation).
- Use server amounts, currencies, and timestamps in confirmations and receipts.
- Show clear pending states for payment, top-up delivery, recipient choice, and
  shop fulfilment; each has a different status lifecycle.
- Make screens resilient to app termination and resume by re-fetching server
  state. Do not rely on in-memory navigation state for pending transactions.
- Handle empty catalogue/cart/history, expired login, unavailable provider,
  offline mode, notification denial, and deep-link cold starts.

## 11. Build sequence and acceptance tests

Recommended implementation order:

1. Shared API/auth/session and error handling.
2. Profile and wallet balance/history.
3. Ghana airtime/data and Reloadly country/operator discovery.
4. FCM token lifecycle and recipient decision handling.
5. Advansis Pay and GTPay initiation, checkout return, and server verification.
6. Shop catalogue, server cart, checkout, payment linkage, and order tracking.
7. Android deep links, accessibility, localization, analytics/redacted logs,
   and device testing.

Before release, QA should cover:

- OTP login, refresh, expired session, logout, account switch, and secure token
  cleanup.
- Hosted `/reset-password` form UX (Show/Hide toggles, above-input live
  requirements) and post-reset return (`lidapay://auth/password-reset-complete`
  opening the mobile Sign In screen, plus `?passwordReset=complete` returning to
  LidaPay Web).
- Ghana network selection and bundle discovery; Ghana airtime/data delivery.
- Reloadly country/operator lookup and airtime/data purchase for at least two
  non-Ghana destinations.
- SEND to registered recipient (testing both `0...` local and `+233` / `233` / international formats): pending receipt, recipient push, both choices, resolved push, timeout/default resolution, and in-app recovery via `GET /api/v1/recipient-decisions/pending` after app kill or with OS notifications disabled.
- FCM token registration & per-install `deviceId`: confirm `POST /api/v1/notifications/device-token` (or auth endpoints with `deviceToken`) registers an active token (`GET /api/v1/notifications/device-token` returns `total >= 1`), two users on identical phone models/emulators do NOT share `Build.DEVICE` or deactivate each other, and `onTokenRefresh` updates cleanly.
- USE from Lida Value to self: direct purchase, wallet debit, refreshed balance,
  and no recipient-choice pending state.
- Advansis Pay success, decline/failure, delayed result, cancelled checkout,
  missing redirect, and app cold start; verify all final outcomes from API.
- GTPay wallet credit and shop debit: pending-to-final status polling, provider
  callback reconciliation, timeout recovery with the same PartnerTransId,
  duplicate-submit prevention, and exact fee/total rendering.
- Shop price/discount rendering, stock changes, incomplete address, checkout,
  Advansis Pay and GTPay order linkage, payment retry, cancellation, and
  delivery tracking.
- FCM foreground/background/open handling with notification permission allowed
  and denied.
- Play-signed Android build: scheme/App Link verification, payment return, and
  recipient-decision notification routing.

## 12. Contract references and implementation caveats

- [swagger-api-documentation.md](./swagger-api-documentation.md) — backend
  endpoint reference and Shop routes.
- [SHOP_API_MOBILE_HANDOFF.md](./SHOP_API_MOBILE_HANDOFF.md) — current shopping
  payment and order handoff.
- [frontend-integration-guide.md](./frontend-integration-guide.md) — airtime,
  data, recipient-choice examples, and Reloadly discovery.
- [lida-value-use-send-backend-contract.md](./lida-value-use-send-backend-contract.md)
  — Lida Value USE/SEND behavior.
- [MOBILE_TEAM_FCM_RECIPIENT_CHOICE_HANDOFF.md](./MOBILE_TEAM_FCM_RECIPIENT_CHOICE_HANDOFF.md)
  — current FCM and decision-state requirements.
- [ADVANSISPAY_WEB_INTEGRATION.md](./ADVANSISPAY_WEB_INTEGRATION.md) — Advansis
  payment lifecycle and callback semantics.
- [GTPAY_PRODUCTION_INTEGRATION.md](./GTPAY_PRODUCTION_INTEGRATION.md) — current
  GTBank production status, app/partner request contract, and web integration
  boundary.

The API Swagger and older handoffs contain some legacy examples with different
field names/routes. In particular, use `POST /api/v1/internet/buydata` for
Ghana data (not the older `/internet/data` example), `dataCode` for the bundle
identifier, and current FCM event variants described above. If a deployed
environment's Swagger conflicts with this guide, confirm the deployed contract
with the backend team before shipping; do not silently fall back to an
unverified route or request shape.
