# API Documentation

<cite>
**Referenced Files in This Document**   
- [ENDPOINTS.md](file://api/ENDPOINTS.md)
- [swagger-api-documentation.md](file://docs/swagger-api-documentation.md)
- [APP_UPDATE_POLICY_HANDOFF.md](file://docs/APP_UPDATE_POLICY_HANDOFF.md)
- [app_constants.dart](file://lib/core/constants/app_constants.dart)
- [api_endpoints.dart](file://lib/core/network/api_endpoints.dart)
- [api_client.dart](file://lib/core/network/api_client.dart)
- [token_store.dart](file://lib/core/network/token_store.dart)
- [app_update_models.dart](file://lib/core/update/app_update_models.dart)
- [app_update_repository.dart](file://lib/core/update/app_update_repository.dart)
</cite>

## Update Summary
**Changes Made**   
- Added new App Version Policy endpoint section documenting `/api/v1/app/version`
- Updated Core Components section to include app version policy functionality
- Enhanced Architecture Overview with app update gate workflow
- Added comprehensive documentation for flexible field naming conventions
- Included fail-open design principles and security considerations

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [Dependency Analysis](#dependency-analysis)
7. [Performance Considerations](#performance-considerations)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Conclusion](#conclusion)
10. [Appendices](#appendices)

## Introduction
This document describes the LidaPay backend REST API as consumed by the mobile application. It consolidates the endpoint map, Swagger-style reference documentation, and Flutter client implementation details into a single guide for engineers integrating or maintaining the mobile app against the backend.

The backend base URL is `https://api.advansistechnologies.com`. The mobile app uses versioned routes under `/api/v1`, with additional system endpoints such as `/system/health` and `/system/verify-env`. Authentication is primarily Bearer JWT, with partner-specific HMAC signing for the courier integration.

**Updated** Added support for app version policy management through the new `/api/v1/app/version` endpoint, enabling dynamic app update control with flexible field naming conventions.

## Project Structure
The repository contains:
- Backend endpoint definitions and Swagger documentation under `api/` and `docs/`.
- Flutter client code under `lib/`, including constants, route path constants, HTTP client, token storage, device identity helpers, and app update management.
- Android and iOS platform configurations are present but not directly relevant to this API contract.

```mermaid
graph TB
subgraph "Mobile App"
A["Flutter App"]
B["ApiClient<br/>Dio + interceptors"]
C["TokenStore<br/>Secure session storage"]
D["ApiEndpoints<br/>Route constants"]
E["AppConstants<br/>Base URL, timeouts"]
F["AppUpdateRepository<br/>Version policy fetcher"]
G["AppVersionPolicy<br/>Flexible field parser"]
end
subgraph "Backend"
H["REST API<br/>/api/v1/*"]
I["System Endpoints<br/>/system/*"]
J["App Version Policy<br/>/api/v1/app/version"]
end
A --> B
B --> C
B --> D
B --> E
B --> F
F --> G
B --> H
B --> I
B --> J
```

**Diagram sources**
- [app_constants.dart:1-65](file://lib/core/constants/app_constants.dart#L1-L65)
- [api_endpoints.dart:1-155](file://lib/core/network/api_endpoints.dart#L1-L155)
- [api_client.dart:1-276](file://lib/core/network/api_client.dart#L1-L276)
- [token_store.dart:1-238](file://lib/core/network/token_store.dart#L1-L238)
- [app_update_repository.dart:1-84](file://lib/core/update/app_update_repository.dart#L1-L84)
- [app_update_models.dart:1-246](file://lib/core/update/app_update_models.dart#L1-L246)

**Section sources**
- [ENDPOINTS.md:1-195](file://api/ENDPOINTS.md#L1-L195)
- [swagger-api-documentation.md:1-800](file://docs/swagger-api-documentation.md#L1-L800)
- [APP_UPDATE_POLICY_HANDOFF.md:1-217](file://docs/APP_UPDATE_POLICY_HANDOFF.md#L1-L217)
- [app_constants.dart:1-65](file://lib/core/constants/app_constants.dart#L1-L65)

## Core Components
- Base URL and environment configuration:
  - Production base URL: `https://api.advansistechnologies.com`.
  - Build-time overrides supported via `API_BASE_URL`.
  - Default timeouts: connect/send 15 seconds, receive 30 seconds.
- Route constants:
  - Centralized route paths for authentication, users, transactions, Lida Value/Lidapoints, airtime/data, Reloadly, AdvansisPay, GTBank, shop, notifications, recipient decisions, and app version policy.
- HTTP client:
  - Dio-based client that injects `Authorization: Bearer <accessToken>` and `X-Request-Id`.
  - Transparent refresh on 401 using `/api/v1/auth/refresh`.
  - Sensitive payload redaction in debug logs.
- Token store:
  - Secure persistence of access and refresh tokens.
  - Biometric session support with migration from legacy plaintext storage.
  - Stream signaling when session is cleared.
- App version policy management:
  - Flexible field parsing supporting camelCase, snake_case, and various naming conventions.
  - Fail-open design ensuring app functionality even when endpoint is unavailable.
  - Support for per-platform policies (Android/iOS/Web).

**Section sources**
- [app_constants.dart:1-65](file://lib/core/constants/app_constants.dart#L1-L65)
- [api_endpoints.dart:1-155](file://lib/core/network/api_endpoints.dart#L1-L155)
- [api_client.dart:1-276](file://lib/core/network/api_client.dart#L1-L276)
- [token_store.dart:1-238](file://lib/core/network/token_store.dart#L1-L238)
- [app_update_repository.dart:1-84](file://lib/core/update/app_update_repository.dart#L1-L84)
- [app_update_models.dart:1-246](file://lib/core/update/app_update_models.dart#L1-L246)

## Architecture Overview
The mobile app communicates with the backend through a centralized HTTP client. Authentication is handled by storing JWTs securely and refreshing them automatically when needed. Device push tokens are registered for FCM. Payment flows may involve multiple integrations (AdvansisPay, GTBank, Reloadly), while the shop module provides e-commerce capabilities. The app version policy system enables dynamic update control with flexible field naming conventions.

```mermaid
sequenceDiagram
participant App as "Flutter App"
participant Client as "ApiClient"
participant Store as "TokenStore"
participant Repo as "AppUpdateRepository"
participant Server as "Backend /api/v1/*"
App->>Client : GET /api/v1/app/version
Client->>Repo : fetchPolicy(platform, version, build)
Repo->>Server : GET /api/v1/app/version?platform=ANDROID&version=1.1.3&build=34
Server-->>Repo : {minimumBuild, latestBuild, latestVersion}
Repo-->>Client : AppVersionPolicy
Client-->>App : Policy parsed with flexible fields
App->>Client : POST /api/v1/users/login
Client->>Server : Login request
Server-->>Client : {access_token, refresh_token, user}
Client->>Store : saveSession(accessToken, refreshToken)
App->>Client : GET protected resource
Client->>Server : Request with Authorization header
Server-->>Client : 401 Unauthorized
Client->>Store : read refreshToken
Client->>Server : POST /api/v1/auth/refresh
Server-->>Client : New tokens
Client->>Store : saveSession(new tokens)
Client->>Server : Retry original request
Server-->>Client : Success response
```

**Diagram sources**
- [api_client.dart:13-84](file://lib/core/network/api_client.dart#L13-L84)
- [api_client.dart:204-265](file://lib/core/network/api_client.dart#L204-L265)
- [token_store.dart:148-175](file://lib/core/network/token_store.dart#L148-L175)
- [app_update_repository.dart:30-84](file://lib/core/update/app_update_repository.dart#L30-L84)

## Detailed Component Analysis

### App Version Policy Management
**New** The app version policy endpoint enables dynamic control over app updates with flexible field naming conventions.

- **Endpoint**: `GET /api/v1/app/version`
- **Authentication**: Public/unauthenticated - works before sign-in
- **Query Parameters**:
  - `platform`: Device platform (`ANDROID`, `IOS`, `WEB`)
  - `version`: Current app version name (e.g., `1.1.3`)
  - `build`: Current build number (e.g., `34`)

- **Response Format**: JSON object with flexible field naming support
- **Behavior**: Fail-open design - returns empty policy if endpoint unavailable

#### Response Fields and Aliases
The endpoint supports extensive field aliasing for different backend naming conventions:

| Canonical Field | Also Accepted | Type | Description |
|---|---|---|---|
| `minimumBuild` | `minimum_build`, `minBuild`, `min_build`, `minimumVersionCode`, `minimum_version_code`, `minSupportedBuild`, `minimumSupportedBuild` | int | Builds below this are hard-blocked |
| `minimumVersion` | `minimum_version`, `minVersion`, `min_version`, `minSupportedVersion` | string | Minimum version name for fallback comparison |
| `latestBuild` | `latest_build`, `latestVersionCode`, `latest_version_code`, `versionCode`, `version_code`, `buildNumber`, `build_number`, `build` | int | Newest published build |
| `latestVersion` | `latest_version`, `versionName`, `version_name`, `version` | string | Display name of newest build |
| `storeUrl` | `store_url`, `playStoreUrl`, `play_store_url`, `updateUrl`, `update_url`, `url` | string | Store listing URL (must be Play Store or App Store) |
| `message` | `updateMessage`, `update_message`, `notes`, `releaseNotes`, `release_notes` | string | Customer-facing copy (≤180 characters) |

#### Supported Response Shapes
The endpoint accepts multiple JSON structures:

```json
// Flat format (recommended)
{
  "minimumBuild": 34,
  "latestBuild": 36,
  "latestVersion": "1.1.4",
  "storeUrl": "https://play.google.com/store/apps/details?id=com.advansistechnologies.lidapay",
  "message": "Faster top-ups, new rewards and smoother checkout."
}
```

```json
// Enveloped format
{
  "data": {
    "minimumBuild": 34,
    "latestBuild": 36
  }
}
```

```json
// Per-platform format
{
  "android": { "minimumBuild": 34, "latestBuild": 36 },
  "ios": { "minimumBuild": 1, "latestBuild": 999 }
}
```

```json
// Nested platforms format
{
  "platforms": {
    "android": { "minimumBuild": 34, "latestBuild": 36 },
    "ios": { "minimumBuild": 1, "latestBuild": 999 }
  }
}
```

#### Decision Logic
The app evaluates the policy to determine update urgency:

1. **Blocking Update** (`minimumBuild` exceeded): Non-dismissible screen requiring immediate update
2. **Optional Update** (`latestBuild` available): Optional prompt with "Later" option (3-day snooze)
3. **No Action**: Current build is sufficient

```mermaid
flowchart TD
Start(["App Launch"]) --> FetchPolicy["GET /api/v1/app/version"]
FetchPolicy --> ParsePolicy["Parse flexible field names"]
ParsePolicy --> CheckBuild{"Current build < minimumBuild?"}
CheckBuild --> |Yes| Blocking["Show blocking update screen"]
CheckBuild --> |No| CheckLatest{"Current build < latestBuild?"}
CheckLatest --> |Yes| Optional["Show optional update prompt"]
CheckLatest --> |No| NoAction["No action required"]
Blocking --> UpdateRequired["User must update"]
Optional --> UserChoice{"User chooses 'Later'?"}
UserChoice --> |Yes| Snooze["Snooze for 3 days"]
UserChoice --> |No| StartUpdate["Start update process"]
Snooze --> Continue["Continue using app"]
StartUpdate --> UpdateRequired
NoAction --> Continue
```

**Diagram sources**
- [app_update_models.dart:144-183](file://lib/core/update/app_update_models.dart#L144-L183)
- [app_update_repository.dart:30-84](file://lib/core/update/app_update_repository.dart#L30-L84)

**Section sources**
- [APP_UPDATE_POLICY_HANDOFF.md:24-107](file://docs/APP_UPDATE_POLICY_HANDOFF.md#L24-L107)
- [app_update_models.dart:16-142](file://lib/core/update/app_update_models.dart#L16-L142)
- [app_update_repository.dart:30-84](file://lib/core/update/app_update_repository.dart#L30-L84)
- [api_endpoints.dart:146-153](file://lib/core/network/api_endpoints.dart#L146-L153)

### Authentication and Session Management
- User login:
  - Endpoint: `POST /api/v1/users/login`
  - Accepts username/password and optional device metadata for FCM registration.
  - Returns access and refresh tokens along with user profile data.
- Refresh tokens:
  - Endpoint: `POST /api/v1/auth/refresh`
  - Mobile-compatible refresh flow; legacy `/api/v1/users/refresh-token` is deprecated for mobile clients.
- OTP-based login:
  - Two-step flow: request OTP after validating credentials, then verify OTP to obtain tokens.
  - Endpoints: `POST /api/v1/auth/login/request-otp`, `POST /api/v1/auth/login/verify-otp`.
- Registration:
  - Endpoint: `POST /api/v1/users/register`
  - Creates a new user and optionally registers device token.
- Profile and account:
  - Get/update profile: `GET /api/v1/users/profile`, `PUT /api/v1/users/profile/update`.
  - Get account: `GET /api/v1/users/account`.
- Password management:
  - Change password: `PUT /api/v1/users/change-password`
  - Confirm change: `POST /api/v1/users/confirm-password-change`
  - Reset password: `POST /api/v1/users/reset-password`, `POST /api/v1/users/confirm-reset-password`
- Email and phone verification:
  - Verify email: `GET /api/v1/users/verify-email/{token}`
  - Resend verification: `POST /api/v1/users/resend-verification-email`
  - Verify phone: `POST /api/v1/users/verify-phone`
  - Resend phone code: `POST /api/v1/users/resend-phone-verification-code`
- Merchant authentication:
  - Register/login: `POST /api/v1/merchants/register`, `POST /api/v1/merchants/login`
  - Manage merchant: CRUD endpoints under `/api/v1/merchants/*`

```mermaid
flowchart TD
Start(["Login Flow"]) --> Validate["Validate username/password"]
Validate --> OtpFlow{"OTP required?"}
OtpFlow --> |Yes| RequestOtp["POST /auth/login/request-otp"]
RequestOtp --> VerifyOtp["POST /auth/login/verify-otp"]
VerifyOtp --> Tokens["Receive access_token + refresh_token"]
OtpFlow --> |No| Tokens
Tokens --> SaveTokens["Save tokens securely"]
SaveTokens --> Done(["Authenticated"])
```

**Diagram sources**
- [swagger-api-documentation.md:51-183](file://docs/swagger-api-documentation.md#L51-L183)
- [ENDPOINTS.md:6-15](file://api/ENDPOINTS.md#L6-L15)

**Section sources**
- [swagger-api-documentation.md:51-183](file://docs/swagger-api-documentation.md#L51-L183)
- [ENDPOINTS.md:6-39](file://api/ENDPOINTS.md#L6-L39)
- [api_client.dart:204-265](file://lib/core/network/api_client.dart#L204-L265)
- [token_store.dart:148-175](file://lib/core/network/token_store.dart#L148-L175)

### Device Push Notifications
- Register device token:
  - Endpoint: `POST /api/v1/notifications/device-token`
  - Aliases: `POST /api/v1/notifications/push-token`, `POST /api/v1/users/push-token`
  - Accepts token/platform/provider/deviceId/appVersion/locale.
- List active tokens:
  - Endpoint: `GET /api/v1/notifications/device-token`
- Deactivate token:
  - Endpoint: `DELETE /api/v1/notifications/device-token`
- Metrics:
  - Endpoint: `GET /api/v1/notifications/device-token/metrics`

```mermaid
sequenceDiagram
participant App as "Flutter App"
participant Client as "ApiClient"
participant Server as "Backend"
App->>Client : POST /notifications/device-token
Client->>Server : Register FCM token
Server-->>Client : success + device token record
App->>Client : GET /notifications/device-token
Client->>Server : Fetch active tokens
Server-->>Client : Active tokens list
App->>Client : DELETE /notifications/device-token
Client->>Server : Deactivate token
Server-->>Client : Acknowledgement
```

**Diagram sources**
- [swagger-api-documentation.md:185-307](file://docs/swagger-api-documentation.md#L185-L307)
- [ENDPOINTS.md:72-81](file://api/ENDPOINTS.md#L72-L81)

**Section sources**
- [swagger-api-documentation.md:185-307](file://docs/swagger-api-documentation.md#L185-L307)
- [ENDPOINTS.md:72-81](file://api/ENDPOINTS.md#L72-L81)

### Internet Data and Airtime Top-up
- Buy internet data:
  - Endpoint: `POST /api/v1/internet/buydata`
  - Supports direct delivery or recipient decision flow depending on recipient registration status.
- List data bundles:
  - Endpoint: `POST /api/v1/internet/bundlelist`
- Airtime top-up:
  - Endpoints: `POST /api/v1/airtime/topup`, `POST /api/v1/airtime/transtatus`
- Reloadly integration:
  - Phone lookup, country list, operators, FX rates, buy data.

```mermaid
flowchart TD
Start(["Buy Data"]) --> Eligibility["Check recipient eligibility"]
Eligibility --> Registered{"Recipient registered?"}
Registered --> |No| DirectDelivery["Direct delivery"]
Registered --> |Yes| Decision["Create recipient decision"]
Decision --> Respond["Recipient responds DIRECT or LIDA_VALUE"]
Respond --> Delivery["Finalize delivery"]
DirectDelivery --> Delivery
Delivery --> End(["Complete"])
```

**Diagram sources**
- [swagger-api-documentation.md:309-395](file://docs/swagger-api-documentation.md#L309-L395)
- [swagger-api-documentation.md:398-530](file://docs/swagger-api-documentation.md#L398-L530)
- [ENDPOINTS.md:94-100](file://api/ENDPOINTS.md#L94-L100)

**Section sources**
- [swagger-api-documentation.md:309-395](file://docs/swagger-api-documentation.md#L309-L395)
- [swagger-api-documentation.md:398-530](file://docs/swagger-api-documentation.md#L398-L530)
- [ENDPOINTS.md:94-100](file://api/ENDPOINTS.md#L94-L100)

### Recipient Choice and Decision Workflow
- Check eligibility:
  - Endpoint: `POST /api/v1/recipient/eligibility`
- Create decision:
  - Endpoint: `POST /api/v1/topups/{topupOrderId}/recipient-decision`
- Respond to decision:
  - Endpoint: `POST /api/v1/recipient-decisions/{decisionId}/respond`
- Status queries:
  - Endpoints: `GET /api/v1/transaction-status/decision/{decisionId}`, `GET /api/v1/transaction-status/transaction/{transactionRef}`

```mermaid
sequenceDiagram
participant App as "Flutter App"
participant Server as "Backend"
App->>Server : POST /recipient/eligibility
Server-->>App : Eligibility result
App->>Server : POST /topups/{orderId}/recipient-decision
Server-->>App : Decision created (PENDING)
App->>Server : POST /recipient-decisions/{decisionId}/respond
Server-->>App : Decision resolved (DIRECT or LIDA_VALUE)
```

**Diagram sources**
- [swagger-api-documentation.md:398-530](file://docs/swagger-api-documentation.md#L398-L530)
- [ENDPOINTS.md:8-9](file://api/ENDPOINTS.md#L8-L9)

**Section sources**
- [swagger-api-documentation.md:398-530](file://docs/swagger-api-documentation.md#L398-L530)
- [ENDPOINTS.md:8-9](file://api/ENDPOINTS.md#L8-L9)

### Payments: AdvansisPay and GTBank
- AdvansisPay:
  - Initiate payment: `POST /api/v1/advansispay/initiate-payment`
  - Query transaction: `POST /api/v1/advansispay/query-transaction`
  - Callback handling: `GET /api/v1/advansispay/redirect-url`
  - Additional endpoints include debit wallet, post status, and Constant Capital funding.
- GTBank (GTPay):
  - Services: `GET /api/v1/gtpay/services`
  - Query/verify: `POST /api/v1/gtpay/query`
  - Pay: `POST /api/v1/gtpay/pay`
  - Status: `POST /api/v1/gtpay/status`
  - Banks: `GET /api/v1/gtpay/banks`
  - Callback: `POST /api/v1/gtpay/callback`

```mermaid
sequenceDiagram
participant App as "Flutter App"
participant Server as "Backend"
participant Provider as "Payment Provider"
App->>Server : POST /advansispay/initiate-payment
Server->>Provider : Initiate checkout
Provider-->>Server : Checkout URL + token
Server-->>App : Redirect URL
Provider->>Server : POST /advansispay/post-status
Server-->>App : Payment success notification
```

**Diagram sources**
- [swagger-api-documentation.md:532-650](file://docs/swagger-api-documentation.md#L532-L650)
- [swagger-api-documentation.md:651-980](file://docs/swagger-api-documentation.md#L651-L980)
- [ENDPOINTS.md:139-158](file://api/ENDPOINTS.md#L139-L158)

**Section sources**
- [swagger-api-documentation.md:532-650](file://docs/swagger-api-documentation.md#L532-L650)
- [swagger-api-documentation.md:651-980](file://docs/swagger-api-documentation.md#L651-L980)
- [ENDPOINTS.md:139-158](file://api/ENDPOINTS.md#L139-L158)

### Shop and E-commerce Module
- Categories:
  - List: `GET /api/v1/shop/categories`
  - Admin create/update/delete: `POST/PUT/DELETE /api/v1/shop/categories/{id}`
- Products:
  - Browse: `GET /api/v1/shop/products`
  - Featured: `GET /api/v1/shop/products/featured`
  - Detail: `GET /api/v1/shop/products/{id}`
  - Admin create/update/delete: `POST/PUT/DELETE /api/v1/shop/products/{id}`
- Cart:
  - Get/add/update/remove/clear: endpoints under `/api/v1/shop/cart/*`
- Checkout:
  - Endpoint: `POST /api/v1/shop/checkout`
  - Returns order with pending payment status.
- Orders:
  - My orders: `GET /api/v1/shop/orders`
  - Order detail: `GET /api/v1/shop/orders/{id}`
  - Public tracking: `GET /api/v1/shop/orders/number/{orderNumber}`
  - Cancel: `POST /api/v1/shop/orders/{id}/cancel`
  - Tracking: `GET /api/v1/shop/orders/{id}/tracking`
- Admin operations:
  - List all orders: `GET /api/v1/shop/admin/orders`
  - Update status/payment/delivery: `PUT /api/v1/shop/admin/orders/{id}/{status,payment,delivery}`

```mermaid
flowchart TD
Start(["Shop Flow"]) --> Browse["Browse categories/products"]
Browse --> AddToCart["Add items to cart"]
AddToCart --> Checkout["POST /shop/checkout"]
Checkout --> Payment["Initiate payment (AdvansisPay/GTBank)"]
Payment --> OrderCreated["Order created (pending)"]
OrderCreated --> Track["Poll /orders/{id}/tracking"]
Track --> Delivered["Delivered/Closed"]
```

**Diagram sources**
- [swagger-api-documentation.md:982-1296](file://docs/swagger-api-documentation.md#L982-L1296)
- [ENDPOINTS.md:159-185](file://api/ENDPOINTS.md#L159-L185)

**Section sources**
- [swagger-api-documentation.md:982-1296](file://docs/swagger-api-documentation.md#L982-L1296)
- [ENDPOINTS.md:159-185](file://api/ENDPOINTS.md#L159-L185)

### Courier Partner API
- Authentication:
  - Stateless HMAC-SHA256 per request using headers: `X-Partner-Id`, `X-Timestamp`, `X-Event-Id`, `X-Signature`.
- Endpoints:
  - Jobs: `GET /api/v1/courier/jobs?state=available|assigned`
  - Accept job: `POST /api/v1/courier/jobs/{orderNumber}/accept`
  - Events: `POST /api/v1/courier/jobs/{orderNumber}/events`
  - Location: `POST /api/v1/courier/jobs/{orderNumber}/location`

```mermaid
sequenceDiagram
participant Courier as "Courier Partner"
participant Server as "Backend"
Courier->>Server : GET /courier/jobs?state=available (signed)
Server-->>Courier : Available jobs
Courier->>Server : POST /courier/jobs/{orderNumber}/accept (signed)
Server-->>Courier : Job accepted
Courier->>Server : POST /courier/jobs/{orderNumber}/events (signed)
Server-->>Courier : Event acknowledged
Courier->>Server : POST /courier/jobs/{orderNumber}/location (signed)
Server-->>Courier : Location updated
```

**Diagram sources**
- [swagger-api-documentation.md:1298-1507](file://docs/swagger-api-documentation.md#L1298-L1507)

**Section sources**
- [swagger-api-documentation.md:1298-1507](file://docs/swagger-api-documentation.md#L1298-L1507)

### System and Diagnostics
- Verify environment variables:
  - Endpoint: `GET /system/verify-env`
- Health check:
  - Endpoint: `GET /system/health`

**Section sources**
- [swagger-api-documentation.md:10-50](file://docs/swagger-api-documentation.md#L10-L50)
- [ENDPOINTS.md:193-195](file://api/ENDPOINTS.md#L193-L195)

## Dependency Analysis
The Flutter client depends on:
- `AppConstants` for base URL and timeouts.
- `ApiEndpoints` for route path constants.
- `TokenStore` for secure session persistence.
- `Dio` for HTTP requests and interceptors.
- `AppUpdateRepository` for app version policy fetching.
- `AppVersionPolicy` for flexible field parsing and decision logic.

```mermaid
graph LR
Constants["AppConstants"] --> Client["ApiClient"]
Endpoints["ApiEndpoints"] --> Client
Store["TokenStore"] --> Client
Repo["AppUpdateRepository"] --> Client
Policy["AppVersionPolicy"] --> Repo
Client --> Server["Backend /api/v1/*"]
Repo --> PolicyEndpoint["/api/v1/app/version"]
```

**Diagram sources**
- [app_constants.dart:1-65](file://lib/core/constants/app_constants.dart#L1-L65)
- [api_endpoints.dart:1-155](file://lib/core/network/api_endpoints.dart#L1-L155)
- [api_client.dart:1-276](file://lib/core/network/api_client.dart#L1-L276)
- [token_store.dart:1-238](file://lib/core/network/token_store.dart#L1-L238)
- [app_update_repository.dart:1-84](file://lib/core/update/app_update_repository.dart#L1-L84)
- [app_update_models.dart:1-246](file://lib/core/update/app_update_models.dart#L1-L246)

**Section sources**
- [app_constants.dart:1-65](file://lib/core/constants/app_constants.dart#L1-L65)
- [api_endpoints.dart:1-155](file://lib/core/network/api_endpoints.dart#L1-L155)
- [api_client.dart:1-276](file://lib/core/network/api_client.dart#L1-L276)
- [token_store.dart:1-238](file://lib/core/network/token_store.dart#L1-L238)
- [app_update_repository.dart:1-84](file://lib/core/update/app_update_repository.dart#L1-L84)
- [app_update_models.dart:1-246](file://lib/core/update/app_update_models.dart#L1-L246)

## Performance Considerations
- Timeouts:
  - Connect/send timeout: 15 seconds.
  - Receive timeout: 30 seconds.
  - App version policy timeout: 6 seconds (shorter for faster startup).
- Retries:
  - Automatic retry on 401 after successful token refresh.
  - Single-flight refresh prevents concurrent refresh storms.
  - App version policy caching within app session.
- Debug logging:
  - Sensitive fields are redacted in debug logs.
- External providers:
  - Longer timeouts accommodate provider round-trips (Reloadly/Prymo).
- App version policy:
  - Fail-open design ensures app startup is never blocked.
  - Throttled re-checks every 6 hours while app stays open.
  - Config/cache serving recommended for p95 < 500ms.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
Common issues and resolutions:
- 401 Unauthorized:
  - Ensure valid access token; if missing, refresh using `/api/v1/auth/refresh`.
  - Clear biometric session if refresh fails repeatedly.
- Invalid device token:
  - Re-register device token via `/api/v1/notifications/device-token`.
- Network errors:
  - Check connectivity and backend health via `/system/health`.
- Payment failures:
  - Verify callback URLs and HMAC signatures for partner integrations.
  - Use Swagger UI to test endpoints interactively.
- App version policy issues:
  - Endpoint returns empty policy `{}` when unavailable - this is expected fail-open behavior.
  - Verify query parameters: `platform`, `version`, `build`.
  - Check field naming conventions match supported aliases.
  - Test with curl: `curl -s "https://api.advansistechnologies.com/api/v1/app/version?platform=ANDROID&version=1.1.3&build=34"`

**Section sources**
- [api_client.dart:50-84](file://lib/core/network/api_client.dart#L50-L84)
- [api_client.dart:204-265](file://lib/core/network/api_client.dart#L204-L265)
- [swagger-api-documentation.md:1510-1556](file://docs/swagger-api-documentation.md#L1510-L1556)
- [APP_UPDATE_POLICY_HANDOFF.md:197-201](file://docs/APP_UPDATE_POLICY_HANDOFF.md#L197-L201)

## Conclusion
The LidaPay backend exposes a comprehensive set of REST APIs covering authentication, user management, payments, shop/e-commerce, notifications, courier partner integrations, and app version policy management. The Flutter client centralizes HTTP communication, token management, device identity, and app update control, providing a robust foundation for mobile integration. Engineers should follow the documented authentication flows, validate inputs, handle errors gracefully, use the provided endpoints and examples for reliable integration, and leverage the flexible field naming conventions for app version policy responses.

**Updated** The addition of the app version policy endpoint enables dynamic app update control with extensive flexibility in field naming conventions, supporting various backend service patterns while maintaining fail-safe operation.

[No sources needed since this section summarizes without analyzing specific files]

## Appendices

### API Versioning and Base URL
- Base URL: `https://api.advansistechnologies.com`
- Versioning: All primary endpoints are under `/api/v1`.
- Environment override: `API_BASE_URL` can be set at build time.
- App version policy path override: `APP_UPDATE_POLICY_PATH` can be set at build time.

**Section sources**
- [app_constants.dart:1-12](file://lib/core/constants/app_constants.dart#L1-L12)
- [ENDPOINTS.md:1-5](file://api/ENDPOINTS.md#L1-L5)
- [api_endpoints.dart:146-153](file://lib/core/network/api_endpoints.dart#L146-L153)

### Error Handling Strategy
- Standard error format includes `statusCode`, `message`, and `error`.
- Common codes: 400, 401, 404, 500.
- Partner integrations may return additional structured errors.
- App version policy: Fail-open design treats any error as no policy enforcement.

**Section sources**
- [swagger-api-documentation.md:1510-1527](file://docs/swagger-api-documentation.md#L1510-L1527)
- [app_update_repository.dart:30-84](file://lib/core/update/app_update_repository.dart#L30-L84)

### Client Implementation Guidelines
- Use `ApiClient` for all backend calls.
- Inject `TokenStore` for session management.
- Register device tokens for FCM.
- Handle 401 responses by relying on automatic refresh logic.
- Implement app version policy checking with fail-open behavior.
- Support flexible field naming in app version policy responses.

**Section sources**
- [api_client.dart:13-84](file://lib/core/network/api_client.dart#L13-L84)
- [token_store.dart:148-175](file://lib/core/network/token_store.dart#L148-L175)
- [app_update_repository.dart:1-84](file://lib/core/update/app_update_repository.dart#L1-L84)
- [app_update_models.dart:64-142](file://lib/core/update/app_update_models.dart#L64-L142)

### App Version Policy Security Considerations
- **Fail-open design**: App version policy endpoint failures never block app functionality.
- **Field validation**: Store URLs must be from approved domains (Play Store, App Store).
- **Rate limiting**: One call per app launch plus one per 6 hours while app is open.
- **Emergency rollback**: Lower `minimumBuild` immediately for security incidents.
- **Configuration management**: Values must be editable without app redeployment.

**Section sources**
- [APP_UPDATE_POLICY_HANDOFF.md:133-149](file://docs/APP_UPDATE_POLICY_HANDOFF.md#L133-L149)
- [app_update_models.dart:16-21](file://lib/core/update/app_update_models.dart#L16-L21)