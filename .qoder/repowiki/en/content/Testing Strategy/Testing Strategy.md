# Testing Strategy

<cite>
**Referenced Files in This Document**   
- [pubspec.yaml](file://pubspec.yaml)
- [mock_app.dart](file://test/helpers/mock_app.dart)
- [auth_flow_test.dart](file://test/auth_flow_test.dart)
- [payment_flow_test.dart](file://test/payment_flow_test.dart)
- [orders_screen_test.dart](file://test/orders_screen_test.dart)
- [payment_method_selector_test.dart](file://test/payment_method_selector_test.dart)
- [connectivity_service_test.dart](file://test/connectivity_service_test.dart)
- [token_store_test.dart](file://test/token_store_test.dart)
- [app_update_gate_test.dart](file://test/app_update_gate_test.dart)
- [app_update_models.dart](file://lib/core/update/app_update_models.dart)
- [app_update_repository.dart](file://lib/core/update/app_update_repository.dart)
- [providers.dart](file://lib/core/update/providers.dart)
- [play_update_service.dart](file://lib/core/update/play_update_service.dart)
- [app_update_gate.dart](file://lib/core/update/widgets/app_update_gate.dart)
</cite>

## Update Summary
**Changes Made**
- Added comprehensive documentation for the new app version gate testing infrastructure
- Updated testing strategy to include live production payload validation for backend API contract stability
- Enhanced integration testing patterns with Play Store update flow testing
- Added regression testing coverage for app version policy parsing and urgency calculations

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
This document explains the testing strategy for the LidaPay Flutter application. It covers unit testing, widget testing, integration-style flows, and end-to-end scenarios that are already present in the repository. It also documents the test helpers, mock repositories, fake services, and patterns used to isolate authentication, payment processing, routing, deep links, connectivity, token storage, and app version gate functionality.

The project uses `flutter_test` as its primary testing framework. There is no explicit usage of Mockito or Mocktail in the analyzed test files; instead, tests rely on:
- Dart classes implementing repository interfaces as fakes.
- Small custom stubs for HTTP adapters and platform channels.
- Provider overrides through Riverpod's `ProviderScope`.
- `SharedPreferences.setMockInitialValues` for deterministic local state.

**Updated** The testing infrastructure has been enhanced with live production payload validation for app version gate testing, ensuring backend API contract stability through comprehensive regression testing.

## Project Structure
The testing code lives under `test/`. The most important testing entry points are:
- `test/helpers/mock_app.dart`: a shared helper that pumps the full app with mock repositories.
- Feature-specific tests such as `auth_flow_test.dart`, `payment_flow_test.dart`, `orders_screen_test.dart`, and `payment_method_selector_test.dart`.
- Service and domain tests such as `connectivity_service_test.dart` and `token_store_test.dart`.
- **New**: `test/app_update_gate_test.dart`: comprehensive testing for app version gate functionality including live production payload validation.

```mermaid
graph TB
TestRoot["test/"] --> Helpers["helpers/mock_app.dart"]
TestRoot --> AuthFlow["auth_flow_test.dart"]
TestRoot --> PaymentFlow["payment_flow_test.dart"]
TestRoot --> OrdersScreen["orders_screen_test.dart"]
TestRoot --> PaymentMethodSelector["payment_method_selector_test.dart"]
TestRoot --> ConnectivityTest["connectivity_service_test.dart"]
TestRoot --> TokenStoreTest["token_store_test.dart"]
TestRoot --> AppUpdateGate["app_update_gate_test.dart"]
AppUpdateGate --> Models["app_update_models.dart"]
AppUpdateGate --> Repository["app_update_repository.dart"]
AppUpdateGate --> Providers["providers.dart"]
AppUpdateGate --> PlayService["play_update_service.dart"]
AppUpdateGate --> GateWidget["app_update_gate.dart"]
```

**Diagram sources**
- [mock_app.dart:1-161](file://test/helpers/mock_app.dart#L1-L161)
- [auth_flow_test.dart:1-408](file://test/auth_flow_test.dart#L1-L408)
- [payment_flow_test.dart:1-786](file://test/payment_flow_test.dart#L1-L786)
- [orders_screen_test.dart:1-106](file://test/orders_screen_test.dart#L1-L106)
- [payment_method_selector_test.dart:1-39](file://test/payment_method_selector_test.dart#L1-L39)
- [connectivity_service_test.dart:1-76](file://test/connectivity_service_test.dart#L1-L76)
- [token_store_test.dart:1-171](file://test/token_store_test.dart#L1-L171)
- [app_update_gate_test.dart:1-531](file://test/app_update_gate_test.dart#L1-L531)

**Section sources**
- [pubspec.yaml:76-82](file://pubspec.yaml#L76-L82)

## Core Components
The testing strategy centers around five core components:

1. **Shared App Pump Helper**  
   `pumpMockApp` wires the full application into a `ProviderScope` and replaces all feature repositories with mock implementations. This allows widget tests to exercise real screens without touching production APIs.

2. **Fake Repositories**  
   - `FakePaymentsRepository`: returns fixed checkout URLs, tokens, and successful query results so payment sessions can run deterministically.
   - `FakeRecipientChoiceRepository`: returns predictable recipient decisions and topup statuses.
   - **New**: `_FakeUpdateRepository`: provides deterministic app version policies for update gate testing.

3. **HTTP Stubbing**  
   `payment_flow_test.dart` defines `_StubAdapter`, which captures Dio requests and returns JSON responses. This isolates parsing and request-shape logic from the live backend.

4. **Platform and Storage Fakes**  
   Tests use `SharedPreferences.setMockInitialValues` and implement small fakes for platform abstractions such as `Connectivity`, `SecretStore`, and `PlayUpdateService`.

5. **Live Production Payload Validation**  
   **New**: Comprehensive testing of backend API contracts using actual production payloads captured from the live backend, ensuring backward compatibility and contract stability.

```mermaid
classDiagram
class FakePaymentsRepository {
+initiatePayment(...)
+queryTransaction(token)
+gtPayDebit(...)
+gtPayStatus(partnerTransId)
}
class FakeRecipientChoiceRepository {
+checkEligibility(...)
+getPendingDecisions()
+getDecision(decisionId)
+respondToDecision(...)
+getTopupStatus(topupOrderId)
}
class _FakeUpdateRepository {
+policy : AppVersionPolicy
+calls : int
+fetchPolicy(platform, appVersion, buildNumber)
}
class PaymentsRepository
class RecipientChoiceRepository
class AppUpdateRepository
FakePaymentsRepository ..|> PaymentsRepository
FakeRecipientChoiceRepository ..|> RecipientChoiceRepository
_FakeUpdateRepository ..|> AppUpdateRepository
```

**Diagram sources**
- [mock_app.dart:29-120](file://test/helpers/mock_app.dart#L29-L120)
- [app_update_gate_test.dart:27-42](file://test/app_update_gate_test.dart#L27-L42)

**Section sources**
- [mock_app.dart:26-161](file://test/helpers/mock_app.dart#L26-L161)
- [payment_flow_test.dart:20-60](file://test/payment_flow_test.dart#L20-L60)
- [connectivity_service_test.dart:6-24](file://test/connectivity_service_test.dart#L6-L24)
- [token_store_test.dart:5-15](file://test/token_store_test.dart#L5-L15)
- [app_update_gate_test.dart:27-42](file://test/app_update_gate_test.dart#L27-L42)

## Architecture Overview
The testing architecture follows a layered approach:

- **Widget layer**: Uses `flutter_test` to pump widgets, tap buttons, enter text, scroll, and assert UI state.
- **State layer**: Uses Riverpod providers with overrides to inject mocks.
- **Domain/session layer**: Exercises `PaymentSessionNotifier`, pending payment persistence, service calls, and app update controller logic.
- **Network layer**: Uses Dio adapter stubs to validate request bodies, headers, and response parsing.
- **Platform layer**: Fakes connectivity streams, secure storage, deep link behavior, and Play Store update flows.

```mermaid
sequenceDiagram
participant Test as "Flutter Test"
participant Widget as "Widget Under Test"
participant Providers as "Riverpod Providers"
participant Repo as "Fake/Mock Repository"
participant Network as "Dio Adapter Stub"
participant Platform as "Platform Fake"
Test->>Widget : pumpMockApp / pumpWidget
Widget->>Providers : read state
Providers->>Repo : call repository method
Repo-->>Providers : deterministic result
Note over Repo,Network : Network stubs used in API-level tests
Platform-->>Widget : connectivity / deep link events
Test->>Widget : interact (tap, type, scroll)
Widget-->>Test : render expected UI
```

**Diagram sources**
- [mock_app.dart:122-161](file://test/helpers/mock_app.dart#L122-L161)
- [payment_flow_test.dart:46-60](file://test/payment_flow_test.dart#L46-L60)
- [auth_flow_test.dart:22-37](file://test/auth_flow_test.dart#L22-L37)
- [connectivity_service_test.dart:6-24](file://test/connectivity_service_test.dart#L6-L24)

## Detailed Component Analysis

### Authentication Flow Testing
Authentication testing covers cold start, onboarding, login via password and OTP, registration, deep-link-based password reset confirmation, and payment return routing.

Key behaviors validated:
- Splash screen renders branding and transitions to onboarding.
- Onboarding skips to login.
- Login accepts phone/email input and switches between OTP boxes and password mode.
- API validation errors are rendered inline.
- Personal and merchant registration wizards complete successfully.
- Deep link `lidapay://auth/password-reset-complete` routes back to login with a confirmation message.
- Payment redirect deep link routes directly to the payment receipt screen without restarting at splash.

```mermaid
flowchart TD
Start(["Cold Start"]) --> Splash["Splash Screen"]
Splash --> Onboarding["Onboarding"]
Onboarding --> Login["Login Screen"]
Login --> PasswordMode{"Password Mode?"}
PasswordMode --> |Yes| EnterPassword["Enter Password"]
PasswordMode --> |No| OtpBoxes["OTP Boxes"]
EnterPassword --> Dashboard["Dashboard"]
OtpBoxes --> Dashboard
Dashboard --> PaymentReturn["Payment Return Deep Link"]
PaymentReturn --> Receipt["Service Receipt Screen"]
```

**Diagram sources**
- [auth_flow_test.dart:40-101](file://test/auth_flow_test.dart#L40-L101)
- [auth_flow_test.dart:313-405](file://test/auth_flow_test.dart#L313-L405)

**Section sources**
- [auth_flow_test.dart:40-147](file://test/auth_flow_test.dart#L40-L147)
- [auth_flow_test.dart:163-311](file://test/auth_flow_test.dart#L163-L311)
- [auth_flow_test.dart:313-405](file://test/auth_flow_test.dart#L313-L405)

### Payment Process Testing
Payment testing validates both network-layer parsing and session-layer orchestration.

#### Network Layer
- Parses wrapped API payloads with kebab-case fields.
- Sends `shopOrderNumber` and `payTransRef`, but never sends `returnUrl`.
- Sends `redirectUrl` when provided by shop flows.
- Throws on malformed checkout payloads.
- Normalizes Ghana mobile money numbers and validates them before calling GTPay.
- Parses GTPay responses using the inner `Status` field rather than the envelope status.

#### Session Layer
- Begins a payment, persists it, launches checkout, and verifies return callbacks.
- Credits Ghana airtime through the local airtime service after success.
- Ignores mismatched order IDs.
- Retries pending queries until completion.
- Clears pending state on terminal failure.
- Prevents double credit when return and recheck race.
- Credits global airtime through the Reloadly route.
- Cancels unverified initiations.
- Handles declined mobile money by keeping the transaction recoverable and issuing a fresh partner transaction ID on retry.
- Stops polling after an approval window expires and marks the payment timed out.
- Reconciles shop orders when the callback contains the shop order number.

```mermaid
flowchart TD
Begin["Begin Payment"] --> Initiate["Initiate Payment"]
Initiate --> Launch["Launch Checkout"]
Launch --> Callback{"Callback Received?"}
Callback --> |No| Poll["Poll Transaction Status"]
Poll --> Pending{"Still Pending?"}
Pending --> |Yes| Poll
Pending --> |No| Verify["Verify Outcome"]
Callback --> |Yes| Verify
Verify --> Success{"Success?"}
Success --> |Yes| Credit["Credit Service"]
Success --> |No| Fail["Mark Failed or Timed Out"]
Credit --> Complete["Completed"]
Fail --> Complete
```

**Diagram sources**
- [payment_flow_test.dart:263-364](file://test/payment_flow_test.dart#L263-L364)
- [payment_flow_test.dart:451-585](file://test/payment_flow_test.dart#L451-L585)
- [payment_flow_test.dart:587-784](file://test/payment_flow_test.dart#L587-L784)

**Section sources**
- [payment_flow_test.dart:20-60](file://test/payment_flow_test.dart#L20-L60)
- [payment_flow_test.dart:64-138](file://test/payment_flow_test.dart#L64-L138)
- [payment_flow_test.dart:229-247](file://test/payment_flow_test.dart#L229-L247)
- [payment_flow_test.dart:263-364](file://test/payment_flow_test.dart#L263-L364)
- [payment_flow_test.dart:451-585](file://test/payment_flow_test.dart#L451-L585)
- [payment_flow_test.dart:587-784](file://test/payment_flow_test.dart#L587-L784)

### App Version Gate Testing
**New Section**: The app version gate testing represents a significant enhancement to the testing infrastructure, providing comprehensive validation of backend API contracts through live production payload testing.

#### Live Production Payload Validation
The test suite includes a specific test case that validates against the actual production payload captured from the backend on 2026-11-18. This ensures that any changes to the backend API contract will be caught immediately through regression testing.

Key validation scenarios:
- **Flat camelCase payload parsing**: Validates standard API response format
- **Snake_case alias support**: Ensures backward compatibility with different naming conventions
- **Data envelope unwrapping**: Handles nested API response structures
- **Android node parsing**: Processes platform-specific configuration
- **Empty payload handling**: Gracefully handles missing or incomplete responses
- **Live production payload**: Uses actual backend response data for regression testing

#### Policy Urgency Calculation Testing
Comprehensive testing of the decision logic that determines whether updates are required, optional, or not needed:
- **Blocking builds**: Builds below minimum supported version trigger mandatory updates
- **Optional updates**: Builds between minimum and latest versions show upgrade prompts
- **Current builds**: Latest builds remain unaffected
- **Unknown builds**: Development or unknown builds never get blocked
- **Version name fallback**: Falls back to semantic version comparison when build numbers are unavailable

#### Play Store Integration Testing
Testing of Google Play Store integration including:
- **Immediate updates**: Full-screen blocking updates for critical security fixes
- **Flexible updates**: Background downloads that install on restart
- **Store listing fallback**: Opens Play Store when Play Core is unavailable
- **Installation lifecycle**: Tracks download progress and installation completion
- **Platform support detection**: Handles unsupported platforms gracefully

```mermaid
flowchart TD
BackendAPI["Backend API /api/v1/app/version"] --> PolicyParser["AppVersionPolicy Parser"]
PolicyParser --> DecisionEngine["Urgency Decision Engine"]
DecisionEngine --> BlockingCheck{"Build Below Minimum?"}
BlockingCheck --> |Yes| Required["Required Update"]
BlockingCheck --> |No| LatestCheck{"Build Older Than Latest?"}
LatestCheck --> |Yes| Optional["Optional Update"]
LatestCheck --> |No| Current["Current Build"]
Required --> PlayStore["Play Store Immediate Update"]
Optional --> Flexible["Play Store Flexible Download"]
Current --> NoAction["No Action Needed"]
```

**Diagram sources**
- [app_update_gate_test.dart:182-215](file://test/app_update_gate_test.dart#L182-L215)
- [app_update_gate_test.dart:218-272](file://test/app_update_gate_test.dart#L218-L272)
- [app_update_gate_test.dart:434-461](file://test/app_update_gate_test.dart#L434-L461)

**Section sources**
- [app_update_gate_test.dart:127-216](file://test/app_update_gate_test.dart#L127-L216)
- [app_update_gate_test.dart:218-286](file://test/app_update_gate_test.dart#L218-L286)
- [app_update_gate_test.dart:288-462](file://test/app_update_gate_test.dart#L288-L462)
- [app_update_gate_test.dart:464-529](file://test/app_update_gate_test.dart#L464-L529)

### Widget Testing Patterns
Widget tests focus on user interactions and UI state:

- **Orders Screen**: verifies order listing, tracking sheet opening, cancellation flow, empty state, and automatic opening of an initial order.
- **Payment Method Selector**: verifies that the payment method sheet opens and wraps correctly on narrow screens.
- **App Update Gate**: validates blocking covers, optional update cards, and current build behavior.

```mermaid
sequenceDiagram
participant Test as "Widget Test"
participant Screen as "OrdersScreen"
participant Repo as "MockShopRepository"
Test->>Screen : pumpWidget with mock repository
Screen->>Repo : getOrders()
Repo-->>Screen : list of orders
Test->>Screen : tap Track Order
Screen-->>Test : show delivery tracking sheet
Test->>Screen : tap Cancel Order
Screen-->>Test : show confirmation dialog
```

**Diagram sources**
- [orders_screen_test.dart:11-24](file://test/orders_screen_test.dart#L11-L24)
- [orders_screen_test.dart:26-99](file://test/orders_screen_test.dart#L26-L99)

**Section sources**
- [orders_screen_test.dart:11-106](file://test/orders_screen_test.dart#L11-L106)
- [payment_method_selector_test.dart:5-39](file://test/payment_method_selector_test.dart#L5-L39)

### Integration-Style Testing
Integration-style tests bridge multiple layers without hitting the real backend:

- **Deep Links**: A fake `AppLinks` implementation emits URIs so the app can process password reset completion and payment return deep links.
- **Connectivity**: A fake `Connectivity` implementation drives stream events and asserts online/offline transitions.
- **Token Store**: Tests verify saving, migrating legacy tokens, clearing, biometric session persistence, refresh synchronization, and graceful degradation when the secret store fails.
- **Play Store Integration**: Fake `PlayUpdateService` implementations simulate various Play Store scenarios including immediate updates, flexible downloads, and store listing fallbacks.

```mermaid
sequenceDiagram
participant Test as "Test"
participant FakeLinks as "_FakeAppLinks"
participant Handler as "PaymentDeepLinkHandler"
participant Router as "Router"
Test->>FakeLinks : emit Uri
FakeLinks->>Handler : uriLinkStream event
Handler->>Router : navigate to callback route
Router-->>Test : render expected screen
```

**Diagram sources**
- [auth_flow_test.dart:22-37](file://test/auth_flow_test.dart#L22-L37)
- [auth_flow_test.dart:313-350](file://test/auth_flow_test.dart#L313-L350)

**Section sources**
- [auth_flow_test.dart:22-37](file://test/auth_flow_test.dart#L22-L37)
- [auth_flow_test.dart:313-405](file://test/auth_flow_test.dart#L313-L405)
- [connectivity_service_test.dart:6-76](file://test/connectivity_service_test.dart#L6-L76)
- [token_store_test.dart:5-171](file://test/token_store_test.dart#L5-L171)

### Test Helpers, Mock Implementations, and Utilities
- **`pumpMockApp`**: Pumps the full app with mock repositories for auth, dashboard, history, notifications, services, shop, payments, and recipient choice. It also overrides the checkout launcher to avoid launching a browser.
- **Fake Repositories**: Provide deterministic outcomes for payment initiation, transaction queries, GTPay debit/status, recipient decisions, and app version policies.
- **HTTP Adapter Stub**: Captures Dio requests and returns controlled JSON responses for API parsing tests.
- **Platform Fakes**: Custom fakes for `AppLinks`, `Connectivity`, `SecretStore`, and `PlayUpdateService`.
- **SharedPreferences Mocking**: Used across tests to initialize deterministic local state.

**Section sources**
- [mock_app.dart:26-161](file://test/helpers/mock_app.dart#L26-L161)
- [payment_flow_test.dart:20-60](file://test/payment_flow_test.dart#L20-L60)
- [auth_flow_test.dart:22-37](file://test/auth_flow_test.dart#L22-L37)
- [connectivity_service_test.dart:6-24](file://test/connectivity_service_test.dart#L6-L24)
- [token_store_test.dart:5-15](file://test/token_store_test.dart#L5-L15)
- [app_update_gate_test.dart:27-90](file://test/app_update_gate_test.dart#L27-L90)

## Dependency Analysis
The tests depend on:
- `flutter_test` for widget and unit testing.
- Riverpod providers for dependency injection during widget tests.
- `shared_preferences` for deterministic local storage.
- Dio adapter stubs for isolated network tests.
- Feature-specific mock repositories located under `lib/features/*/data/mock_*.dart`.
- **New**: Play Store integration dependencies for update flow testing.

```mermaid
graph TB
FlutterTest["flutter_test"] --> AuthFlowTest["auth_flow_test.dart"]
FlutterTest --> PaymentFlowTest["payment_flow_test.dart"]
FlutterTest --> OrdersScreenTest["orders_screen_test.dart"]
FlutterTest --> PaymentMethodSelectorTest["payment_method_selector_test.dart"]
FlutterTest --> ConnectivityTest["connectivity_service_test.dart"]
FlutterTest --> TokenStoreTest["token_store_test.dart"]
FlutterTest --> AppUpdateGateTest["app_update_gate_test.dart"]
Riverpod["Riverpod Providers"] --> MockApp["mock_app.dart"]
SharedPreferences["SharedPreferences"] --> AllTests["All Tests"]
Dio["Dio Adapter Stub"] --> PaymentFlowTest
PlayStore["Play Store Integration"] --> AppUpdateGateTest
```

**Diagram sources**
- [pubspec.yaml:76-82](file://pubspec.yaml#L76-L82)
- [mock_app.dart:1-24](file://test/helpers/mock_app.dart#L1-L24)
- [payment_flow_test.dart:1-18](file://test/payment_flow_test.dart#L1-L18)
- [app_update_gate_test.dart:1-14](file://test/app_update_gate_test.dart#L1-L14)

**Section sources**
- [pubspec.yaml:76-82](file://pubspec.yaml#L76-L82)
- [mock_app.dart:1-24](file://test/helpers/mock_app.dart#L1-L24)

## Performance Considerations
The current test suite focuses on correctness rather than performance measurement. Recommended considerations include:

- Keep widget tests fast by avoiding real network calls and heavy animations.
- Use `pumpAndSettle` only when necessary; prefer targeted `pump` calls for faster feedback.
- Avoid long delays in tests; simulate latency through deterministic queues or zero-delay configuration where possible.
- For load testing, consider external tools against the backend API rather than Flutter widget tests.
- For mobile-specific performance, measure frame rendering and memory usage using Flutter DevTools and platform-native profiling tools.
- **New**: App version gate tests should be lightweight since they primarily test parsing logic and decision algorithms rather than heavy UI interactions.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
Common issues and how the existing tests address them:

- **Unstable UI timing**: Tests use `pumpAndSettle` and explicit durations to stabilize animations and async work.
- **Deep link routing failures**: Tests simulate deep link URIs and assert navigation to the correct screens.
- **Connectivity flakiness**: Tests drive connectivity streams explicitly and assert state changes.
- **Token storage corruption**: Tests cover failed secret store operations and ensure the app degrades gracefully.
- **Payment session races**: Tests verify that concurrent return and recheck do not cause duplicate credits.
- **Backend API contract changes**: New live production payload validation catches API contract changes immediately through regression testing.
- **Play Store integration issues**: Fake Play Store implementations allow testing of various update scenarios without requiring actual Play Store access.

**Section sources**
- [auth_flow_test.dart:40-101](file://test/auth_flow_test.dart#L40-L101)
- [auth_flow_test.dart:313-405](file://test/auth_flow_test.dart#L313-L405)
- [connectivity_service_test.dart:43-76](file://test/connectivity_service_test.dart#L43-L76)
- [token_store_test.dart:157-169](file://test/token_store_test.dart#L157-L169)
- [payment_flow_test.dart:537-551](file://test/payment_flow_test.dart#L537-L551)
- [app_update_gate_test.dart:182-215](file://test/app_update_gate_test.dart#L182-L215)

## Conclusion
LidaPay's testing strategy emphasizes deterministic isolation through fake repositories, provider overrides, and platform fakes. Authentication, payment, routing, connectivity, token storage, and app version gate functionality are covered by focused tests. While Mockito and Mocktail are not used in the analyzed tests, the repository demonstrates robust alternatives using Dart fakes and stubs.

**Enhanced** The introduction of live production payload validation for app version gate testing represents a significant advancement in testing infrastructure, ensuring backend API contract stability through comprehensive regression testing. This approach catches breaking changes to backend contracts immediately, preventing deployment of incompatible app versions.

Future enhancements should include coverage reporting, CI integration, and additional mobile-specific tests for biometrics, location, and maps.

[No sources needed since this section summarizes without analyzing specific files]

## Appendices

### Testing Best Practices Observed in the Repository
- Initialize `SharedPreferences` with mock values before running tests.
- Replace repositories with fakes or mocks via Riverpod overrides.
- Use small, focused fakes for platform abstractions.
- Assert both UI state and side effects such as service calls and persisted state.
- Handle asynchronous behavior explicitly with `pump`, `pumpAndSettle`, and `pumpEventQueue`.
- **New**: Include live production payload validation for critical backend API contracts to ensure regression testing coverage.

**Section sources**
- [mock_app.dart:122-161](file://test/helpers/mock_app.dart#L122-L161)
- [payment_flow_test.dart:229-247](file://test/payment_flow_test.dart#L229-L247)
- [connectivity_service_test.dart:33-41](file://test/connectivity_service_test.dart#L33-L41)
- [token_store_test.dart:21-44](file://test/token_store_test.dart#L21-L44)
- [app_update_gate_test.dart:182-215](file://test/app_update_gate_test.dart#L182-L215)

### Continuous Integration and Coverage Recommendations
- Add a CI step that runs `flutter test` and reports coverage.
- Enforce minimum coverage thresholds for critical domains such as payments, authentication, token storage, and app version gate functionality.
- Separate fast unit/widget tests from slower integration tests if needed.
- Cache dependencies and build artifacts to speed up CI.
- **New**: Include regression tests that validate against live production payloads to catch backend API contract changes early.

[No sources needed since this section provides general guidance]

### Backend API Contract Testing Pattern
**New Section**: The app version gate testing demonstrates a powerful pattern for backend API contract validation:

1. **Capture Production Payloads**: Store actual backend responses as test fixtures
2. **Parse and Validate**: Ensure parsers handle both expected and edge cases
3. **Regression Testing**: Run tests against production payloads to catch breaking changes
4. **Backward Compatibility**: Support multiple field naming conventions and response shapes

This pattern can be extended to other critical backend APIs to ensure contract stability across deployments.

**Section sources**
- [app_update_gate_test.dart:182-215](file://test/app_update_gate_test.dart#L182-L215)
- [app_update_models.dart:72-142](file://lib/core/update/app_update_models.dart#L72-L142)