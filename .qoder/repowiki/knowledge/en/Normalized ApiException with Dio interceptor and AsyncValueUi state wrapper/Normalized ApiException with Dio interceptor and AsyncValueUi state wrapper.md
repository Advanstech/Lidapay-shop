---
kind: error_handling
name: Normalized ApiException with Dio interceptor and AsyncValueUi state wrapper
category: error_handling
scope:
    - '**'
source_files:
    - lib/core/network/api_exception.dart
    - lib/core/network/api_client.dart
    - lib/core/state/async_value_ui.dart
    - lib/features/auth/data/mock_auth_repository.dart
---

## Approach

The LidaPay Flutter app centralizes network error handling around a single normalized exception type, `ApiException`, created from Dio errors inside a centralized `ApiClient`. UI layers consume a small sealed-state wrapper (`AsyncValueUi`) that models loading / data / error uniformly. There are no custom HTTP status-code enums or sentinel-error constants — business failures are represented by user-facing message strings carried on `ApiException`.

## Key files

- `lib/core/network/api_exception.dart` — the sole application-level exception class.
- `lib/core/network/api_client.dart` — Dio client, token-refresh interceptor, request logging/redaction, and the single place where `DioException` is converted into `ApiException`.
- `lib/core/state/async_value_ui.dart` — sealed `AsyncValueUi<T>` hierarchy (`LoadingUi`, `DataUi`, `ErrorUi`).
- `lib/features/auth/data/mock_auth_repository.dart` — demonstrates repositories throwing `ApiException` directly (used for tests).

## Architecture and conventions

### 1. One normalized exception

`ApiException implements Exception` carries four fields:

- `message` — the user-facing string.
- `code` — backend error code (from NestJS `data['error']`).
- `statusCode` — raw HTTP status.
- `outcomeUnknown` — true when there was no server response (timeout / dropped connection), so callers must not blindly retry non-idempotent operations.

`ApiException.fromDio(DioException)` is the only factory: it reads the NestJS default body shape `{ statusCode, message, error }`, joins list messages, and then runs `_friendly` to translate opaque backend messages into actionable UI text. Examples of translation:

- 5xx with `"internal server error"` → `"The service is temporarily unavailable. Please try again shortly."`
- Message containing `"invalid login identifier"` → account-not-found guidance.
- 401 `"unauthorized"` → generic credential hint.
- Messages mentioning `access token` → temporary-unavailable hint (avoids leaking provider internals).

For transport-level failures (`connectionTimeout`, `receiveTimeout`, `sendTimeout`, `connectionError`) a `_fallbackFor` switch returns friendly strings; everything else falls back to `"Something went wrong. Please try again."`.

### 2. Single conversion point in `ApiClient`

All public methods (`get`, `post`, `put`, `delete`, plus their `*Raw` variants) delegate to `_request` / `_requestRaw`, which wrap the call in `try { ... } on DioException catch (e) { throw ApiException.fromDio(e); }`. Callers never see Dio types.

The constructor installs a single `InterceptorsWrapper` that:

- Adds `Authorization: Bearer <token>` from `TokenStore`.
- Injects an `X-Request-Id` UUID per request.
- Redacts sensitive keys (`password`, `token`, `refreshtoken`, `accesstoken`, `authorization`, `secret`, `otp`, `pin`) in debug logs via `_redact`.
- On 401 with an existing bearer header, performs a **single-flight** refresh: concurrent requests share one `_refreshAccessToken()` future; after refresh, GET/HEAD/OPTIONS are retried once with the new token, other methods are re-thrown as-is.
- If refresh fails because the refresh token itself is rejected (400/401/403), `tokenStore.clear(clearBiometric: true)` is called; transient failures (timeouts, offline, 5xx) keep tokens alive so the next request can retry.

### 3. UI state model

`AsyncValueUi<T>` is a sealed class with three subclasses:

- `LoadingUi<T>` — no payload.
- `DataUi<T>` — holds the parsed value.
- `ErrorUi<T>` — holds a `String message` and optional `VoidCallback? onRetry`.

This is the contract every API-bound screen uses to render loading spinners, data, or error screens with a retry action. It replaces ad-hoc `isLoading` / `errorMessage` pairs across features.

### 4. Repository boundary

Repositories are expected to either:

- Throw `ApiException` (as `mock_auth_repository.dart` does, with user-facing messages like `"Enter the 6-digit code we sent to your phone."` or `"This reset link is invalid or has expired."`).
- Or return domain values wrapped in `AsyncValueUi`.

This keeps UI code free of Dio / HTTP details.

### 5. Non-network errors

Other core services (`location_service.dart`, `push_notification_service.dart`, `device_identity.dart`, `deep_links.dart`) use plain `try/catch` blocks and swallow or log exceptions locally rather than propagating them through `ApiException`. This is intentional: these are platform-channel / native-service failures that do not map cleanly to HTTP semantics.

## Conventions and constraints

- **Network errors surface as `ApiException`**: all Dio calls go through `ApiClient._requestRaw`, which converts `DioException` to `ApiException` — callers cannot accidentally leak Dio types.
- **Backend messages are sanitized before reaching the UI**: `_friendly` in `ApiException` translates 5xx, auth, and access-token messages into customer-safe text; internal stack fragments and provider details are deliberately hidden.
- **Non-idempotent writes must not be auto-retried on unknown outcome**: `outcomeUnknown` is set whenever `e.response == null`; consumers should treat such cases as potentially applied on the server.
- **Token refresh is single-flight and idempotent**: concurrent 401s share one `_refreshing` Future; only GET/HEAD/OPTIONS are retried after a successful refresh.
- **UI renders via `AsyncValueUi`**: the sealed hierarchy is the documented contract for "every API-bound screen handles loading / error / data consistently" (per the file's doc comment).
- **Mock repositories throw `ApiException` directly**: test doubles follow the same contract as real repositories, enabling feature-layer tests to assert on user-facing error messages without wiring Dio.