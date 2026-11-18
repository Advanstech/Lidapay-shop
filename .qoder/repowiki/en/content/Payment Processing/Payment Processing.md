# Payment Processing

<cite>
**Referenced Files in This Document**
- [providers.dart](file://lib/features/payments/providers.dart)
- [payment_models.dart](file://lib/features/payments/data/payment_models.dart)
- [pending_payment.dart](file://lib/features/payments/data/pending_payment.dart)
- [pending_payment_store.dart](file://lib/features/payments/data/pending_payment_store.dart)
- [remote_payments_repository.dart](file://lib/features/payments/data/remote_payments_repository.dart)
- [payments_repository.dart](file://lib/features/payments/data/payments_repository.dart)
- [payment_method_selector.dart](file://lib/features/payments/widgets/payment_method_selector.dart)
- [payment_awaiting_panel.dart](file://lib/features/payments/widgets/payment_awaiting_panel.dart)
- [payment_return_screen.dart](file://lib/features/payments/screens/payment_return_screen.dart)
- [deep_links.dart](file://lib/core/deep_links.dart)
- [app_constants.dart](file://lib/core/constants/app_constants.dart)
- [api_endpoints.md](file://api/ENDPOINTS.md)
</cite>

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

## Introduction
This document explains the payment processing system used by the application for service purchases and shop orders. It covers:

- Payment method selection between Mobile Money and card payments.
- Mobile Money integration through GTPay debitwallet.
- Card payment processing through ExpressPay via Advansis Pay.
- Transaction status monitoring, polling, and reconciliation.
- Payment history and receipt handling after successful delivery.
- Pending payment persistence and transaction state management.
- Error handling, retry logic, and user notification patterns.
- Security considerations and compliance implications.

The implementation is centered around a single payment session that coordinates initiation, verification, crediting, and completion while keeping sensitive data out of normal app storage.

## Project Structure
Payment functionality lives under `lib/features/payments` with supporting core utilities and API endpoints documented separately.

```mermaid
graph TB
subgraph "Payments Feature"
Providers["Payment Session<br/>providers.dart"]
Models["Models<br/>payment_models.dart"]
PendingModel["Pending Payment<br/>pending_payment.dart"]
Store["Pending Payment Store<br/>pending_payment_store.dart"]
Repo["Remote Payments Repository<br/>remote_payments_repository.dart"]
RepoInterface["Repository Interface<br/>payments_repository.dart"]
MethodSelector["Method Selector UI<br/>payment_method_selector.dart"]
AwaitingPanel["Awaiting Panel UI<br/>payment_awaiting_panel.dart"]
ReturnScreen["Return Screen<br/>payment_return_screen.dart"]
end
subgraph "Core"
DeepLinks["Deep Link Handler<br/>deep_links.dart"]
Constants["App Constants<br/>app_constants.dart"]
end
subgraph "API"
Endpoints["Backend Endpoints<br/>api/ENDPOINTS.md"]
end
Providers --> Repo
Providers --> Store
Providers --> Models
Providers --> PendingModel
Repo --> RepoInterface
ReturnScreen --> Providers
MethodSelector --> Providers
AwaitingPanel --> Providers
DeepLinks --> ReturnScreen
Providers --> Constants
Repo --> Endpoints
```

**Diagram sources**
- [providers.dart:120-178](file://lib/features/payments/providers.dart#L120-L178)
- [payment_models.dart:5-49](file://lib/features/payments/data/payment_models.dart#L5-L49)
- [pending_payment.dart:16-87](file://lib/features/payments/data/pending_payment.dart#L16-L87)
- [pending_payment_store.dart:8-26](file://lib/features/payments/data/pending_payment_store.dart#L8-L26)
- [remote_payments_repository.dart:7-11](file://lib/features/payments/data/remote_payments_repository.dart#L7-L11)
- [payments_repository.dart:3-45](file://lib/features/payments/data/payments_repository.dart#L3-L45)
- [payment_method_selector.dart:21-46](file://lib/features/payments/widgets/payment_method_selector.dart#L21-L46)
- [payment_awaiting_panel.dart:9-30](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L9-L30)
- [payment_return_screen.dart:22-25](file://lib/features/payments/screens/payment_return_screen.dart#L22-L25)
- [deep_links.dart:8-11](file://lib/core/deep_links.dart#L8-L11)
- [app_constants.dart:23-46](file://lib/core/constants/app_constants.dart#L23-L46)
- [api_endpoints.md:153-192](file://api/ENDPOINTS.md#L153-L192)

**Section sources**
- [providers.dart:120-178](file://lib/features/payments/providers.dart#L120-L178)
- [payment_models.dart:5-49](file://lib/features/payments/data/payment_models.dart#L5-L49)
- [pending_payment.dart:16-87](file://lib/features/payments/data/pending_payment.dart#L16-L87)
- [pending_payment_store.dart:8-26](file://lib/features/payments/data/pending_payment_store.dart#L8-L26)
- [remote_payments_repository.dart:7-11](file://lib/features/payments/data/remote_payments_repository.dart#L7-L11)
- [payments_repository.dart:3-45](file://lib/features/payments/data/payments_repository.dart#L3-L45)
- [payment_method_selector.dart:21-46](file://lib/features/payments/widgets/payment_method_selector.dart#L21-L46)
- [payment_awaiting_panel.dart:9-30](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L9-L30)
- [payment_return_screen.dart:22-25](file://lib/features/payments/screens/payment_return_screen.dart#L22-L25)
- [deep_links.dart:8-11](file://lib/core/deep_links.dart#L8-L11)
- [app_constants.dart:23-46](file://lib/core/constants/app_constants.dart#L23-L46)
- [api_endpoints.md:153-192](file://api/ENDPOINTS.md#L153-L192)

## Core Components
- Payment session orchestrator: manages phases, initiation, verification, crediting, retries, and cancellation.
- Payment models: parse gateway responses and classify outcomes as success, failed, or pending.
- Pending payment model: represents an in-flight purchase with kind-specific delivery parameters.
- Pending payment store: persists the purchase record and encrypts sensitive fields.
- Remote payments repository: calls backend endpoints for Advansis Pay and GTPay.
- Repository interface: defines the contract for payment operations.
- UI components: method selector, awaiting panel, and return screen.
- Deep link handler: routes payment return URIs into the app.
- App constants: checkout host allowlist and shop redirect URL.

Key responsibilities:
- Selection: decide between Mobile Money and card.
- Initiation: create checkout or MoMo prompt.
- Verification: poll provider status until success, failure, or timeout.
- Crediting: deliver the service or mark the shop order paid.
- Persistence: survive process death and resume safely.
- User feedback: guide users through approval, recheck, retry, and cancellation.

**Section sources**
- [providers.dart:43-85](file://lib/features/payments/providers.dart#L43-L85)
- [payment_models.dart:51-163](file://lib/features/payments/data/payment_models.dart#L51-L163)
- [pending_payment.dart:16-87](file://lib/features/payments/data/pending_payment.dart#L16-L87)
- [pending_payment_store.dart:8-26](file://lib/features/payments/data/pending_payment_store.dart#L8-L26)
- [remote_payments_repository.dart:12-109](file://lib/features/payments/data/remote_payments_repository.dart#L12-L109)
- [payments_repository.dart:3-45](file://lib/features/payments/data/payments_repository.dart#L3-L45)
- [payment_method_selector.dart:21-46](file://lib/features/payments/widgets/payment_method_selector.dart#L21-L46)
- [payment_awaiting_panel.dart:9-30](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L9-L30)
- [payment_return_screen.dart:22-25](file://lib/features/payments/screens/payment_return_screen.dart#L22-L25)
- [deep_links.dart:8-11](file://lib/core/deep_links.dart#L8-L11)
- [app_constants.dart:23-46](file://lib/core/constants/app_constants.dart#L23-L46)

## Architecture Overview
The payment flow has two main rails:

- Card rail: initiate Advansis Pay checkout, open hosted page, verify via token query, then credit or complete.
- Mobile Money rail: call GTPay debitwallet, poll status using PartnerTransId, then credit or complete.

Both rails converge on a single verification-and-credit path to avoid duplicate delivery.

```mermaid
sequenceDiagram
participant User as "User"
participant UI as "Payment UI"
participant Session as "PaymentSessionNotifier"
participant Store as "PendingPaymentStore"
participant Repo as "RemotePaymentsRepository"
participant Backend as "Backend API"
participant Gateway as "ExpressPay / GTPay"
User->>UI : Select payment method
UI->>Session : beginPayment(draft, method, momoNumber?)
alt Card
Session->>Repo : initiatePayment(...)
Repo->>Backend : POST advansispay/initiate-payment
Backend-->>Repo : checkoutUrl, token, orderId
Repo-->>Session : PaymentInitiation
Session->>Store : save(pending with token)
Session->>Gateway : launchUrl(checkoutUrl)
Session->>Session : phase = awaitingCallback
else Mobile Money
Session->>Store : save(pending with partnerTransId)
Session->>Repo : gtPayDebit(partnerTransId, momoNumber, amount)
Repo->>Backend : POST gtpay/pay (debitwallet)
Backend-->>Repo : GtPayResult
Repo-->>Session : outcome
alt success
Session->>Session : _credit(pending)
else pending or unknown
Session->>Session : _verifyThenCredit(pending)
end
end
Note over Session,Gateway : Deep link or manual recheck triggers verification
Session->>Repo : queryTransaction(token) or gtPayStatus(partnerTransId)
Repo->>Backend : POST advansispay/query-transaction or gtpay/status
Backend-->>Repo : outcome
Repo-->>Session : outcome
alt success
Session->>Session : _credit(pending)
else failed or timeout
Session->>Session : awaitingCallback with providerStatus/message
end
```

**Diagram sources**
- [providers.dart:182-277](file://lib/features/payments/providers.dart#L182-L277)
- [providers.dart:283-367](file://lib/features/payments/providers.dart#L283-L367)
- [providers.dart:474-572](file://lib/features/payments/providers.dart#L474-L572)
- [providers.dart:578-665](file://lib/features/payments/providers.dart#L578-L665)
- [remote_payments_repository.dart:12-109](file://lib/features/payments/data/remote_payments_repository.dart#L12-L109)
- [payment_return_screen.dart:54-66](file://lib/features/payments/screens/payment_return_screen.dart#L54-L66)
- [deep_links.dart:64-72](file://lib/core/deep_links.dart#L64-L72)
- [api_endpoints.md:153-192](file://api/ENDPOINTS.md#L153-L192)

## Detailed Component Analysis

### Payment Method Selection
The payment sheet lets users choose between Mobile Money and Debit/Credit Card. For Mobile Money, it supports default registered wallets and custom wallet entry with network detection. For cards, it directs users to the ExpressPay hosted checkout.

Important behaviors:
- Mobile Money shows MTN, Telecel Cash, and AirtelTigo options.
- Default wallet can be selected or replaced by a custom number.
- Card option indicates 3-D Secure verification happens on ExpressPay.
- The sheet returns a structured choice including method, optional MoMo number, and network label.

```mermaid
flowchart TD
Start(["Open Payment Sheet"]) --> ShowOptions["Show Mobile Money and Card options"]
ShowOptions --> Choice{"User selects"}
Choice --> |Mobile Money| ValidateMomo["Validate 10-digit Ghana MoMo number"]
Choice --> |Card| LaunchCard["Launch ExpressPay checkout"]
ValidateMomo --> Ready{"Valid?"}
Ready --> |Yes| ConfirmMomo["Confirm MoMo payment"]
Ready --> |No| ShowError["Show validation error"]
ConfirmMomo --> ReturnChoice["Return PaymentChoice"]
LaunchCard --> ReturnChoice
ShowError --> ShowOptions
```

**Diagram sources**
- [payment_method_selector.dart:21-46](file://lib/features/payments/widgets/payment_method_selector.dart#L21-L46)
- [payment_method_selector.dart:48-94](file://lib/features/payments/widgets/payment_method_selector.dart#L48-L94)
- [payment_method_selector.dart:177-190](file://lib/features/payments/widgets/payment_method_selector.dart#L177-L190)
- [payment_method_selector.dart:452-538](file://lib/features/payments/widgets/payment_method_selector.dart#L452-L538)

**Section sources**
- [payment_method_selector.dart:21-46](file://lib/features/payments/widgets/payment_method_selector.dart#L21-L46)
- [payment_method_selector.dart:48-94](file://lib/features/payments/widgets/payment_method_selector.dart#L48-L94)
- [payment_method_selector.dart:177-190](file://lib/features/payments/widgets/payment_method_selector.dart#L177-L190)
- [payment_method_selector.dart:452-538](file://lib/features/payments/widgets/payment_method_selector.dart#L452-L538)

### Mobile Money Integration (GTPay)
Mobile Money uses GTPay’s debitwallet service. The flow generates a unique PartnerTransId before calling pay, persists it, and reconciles any timeout or partial response through status polling.

Key points:
- Phone numbers are normalized to local 10-digit format.
- debitwallet request includes service details, amount, remarks, and payer identity.
- Outcome may be immediate success, pending, or failed; pending paths trigger verification.
- Status polling uses a bounded attempt count and delay, with special handling for timeouts.
- Retries send a fresh prompt with a new PartnerTransId only after a network-reported failure.

```mermaid
sequenceDiagram
participant Session as "PaymentSessionNotifier"
participant Store as "PendingPaymentStore"
participant Repo as "RemotePaymentsRepository"
participant Backend as "Backend API"
participant Telco as "Telco Network"
Session->>Store : save(pending with partnerTransId)
Session->>Repo : gtPayDebit(partnerTransId, momoNumber, amount)
Repo->>Backend : POST gtpay/pay
Backend->>Telco : debitwallet authorization
Telco-->>Backend : authorization result
Backend-->>Repo : GtPayResult
Repo-->>Session : outcome
alt success
Session->>Session : _credit(pending)
else pending or transient error
Session->>Repo : gtPayStatus(partnerTransId)
Repo->>Backend : POST gtpay/status
Backend-->>Repo : GtPayResult
Repo-->>Session : outcome
alt success
Session->>Session : _credit(pending)
else failed or timeout
Session->>Session : awaitingCallback(providerStatus, message)
end
end
```

**Diagram sources**
- [providers.dart:283-367](file://lib/features/payments/providers.dart#L283-L367)
- [providers.dart:578-665](file://lib/features/payments/providers.dart#L578-L665)
- [remote_payments_repository.dart:64-109](file://lib/features/payments/data/remote_payments_repository.dart#L64-L109)
- [api_endpoints.md:185-192](file://api/ENDPOINTS.md#L185-L192)

**Section sources**
- [providers.dart:283-367](file://lib/features/payments/providers.dart#L283-L367)
- [providers.dart:578-665](file://lib/features/payments/providers.dart#L578-L665)
- [remote_payments_repository.dart:64-109](file://lib/features/payments/data/remote_payments_repository.dart#L64-L109)
- [api_endpoints.md:185-192](file://api/ENDPOINTS.md#L185-L192)

### Card Payment Processing (Advansis Pay / ExpressPay)
Card payments use Advansis Pay to obtain a hosted checkout URL. The app opens the URL externally, stores the token, and verifies the transaction later.

Key points:
- Initiation returns checkoutUrl, token, and orderId.
- Checkout URL is validated against allowed hosts.
- Deep link returns carry hints but verification uses the saved token.
- Query endpoint classifies ambiguous provider statuses into success, failed, or pending.
- Successful verification leads to crediting or marking the shop order paid.

```mermaid
sequenceDiagram
participant UI as "Payment UI"
participant Session as "PaymentSessionNotifier"
participant Store as "PendingPaymentStore"
participant Repo as "RemotePaymentsRepository"
participant Backend as "Backend API"
participant Gateway as "ExpressPay"
UI->>Session : beginPayment(method=card)
Session->>Repo : initiatePayment(...)
Repo->>Backend : POST advansispay/initiate-payment
Backend-->>Repo : PaymentInitiation
Repo-->>Session : checkoutUrl, token, orderId
Session->>Store : save(pending with token)
Session->>Gateway : launchUrl(checkoutUrl)
Session->>Session : phase = awaitingCallback
Note over Session,Gateway : Deep link or manual recheck
Session->>Repo : queryTransaction(token)
Repo->>Backend : POST advansispay/query-transaction
Backend-->>Repo : PaymentQueryResult
Repo-->>Session : outcome
alt success
Session->>Session : _credit(pending)
else failed
Session->>Session : failed(message)
else pending
Session->>Session : awaitingCallback(message)
end
```

**Diagram sources**
- [providers.dart:182-277](file://lib/features/payments/providers.dart#L182-L277)
- [providers.dart:501-572](file://lib/features/payments/providers.dart#L501-L572)
- [remote_payments_repository.dart:12-62](file://lib/features/payments/data/remote_payments_repository.dart#L12-L62)
- [payment_models.dart:57-150](file://lib/features/payments/data/payment_models.dart#L57-L150)
- [api_endpoints.md:153-157](file://api/ENDPOINTS.md#L153-L157)

**Section sources**
- [providers.dart:182-277](file://lib/features/payments/providers.dart#L182-L277)
- [providers.dart:501-572](file://lib/features/payments/providers.dart#L501-L572)
- [remote_payments_repository.dart:12-62](file://lib/features/payments/data/remote_payments_repository.dart#L12-L62)
- [payment_models.dart:57-150](file://lib/features/payments/data/payment_models.dart#L57-L150)
- [api_endpoints.md:153-157](file://api/ENDPOINTS.md#L153-L157)

### Transaction Status Monitoring and Polling
Verification is centralized and idempotent per purchase reference. It prevents duplicate credits when deep links or app resumption occur multiple times.

Monitoring characteristics:
- Single-flight verification future per pending reference.
- Generation counter invalidates stale polls when the user cancels, resets, or retries.
- Card polling uses fixed attempts and delay.
- Mobile Money polling respects an approval window anchored to creation time.
- Timeouts and transient errors are treated cautiously to avoid false failures.

```mermaid
flowchart TD
Enter(["Start verification for pending"]) --> CheckRail{"Rail type?"}
CheckRail --> |Card| CardPoll["Loop queryAttempts times"]
CheckRail --> |Mobile Money| MomoPoll["Loop gtPayPollAttempts times"]
CardPoll --> QueryToken["queryTransaction(token)"]
QueryToken --> Outcome{"Outcome?"}
Outcome --> |success| Credit["Credit or complete"]
Outcome --> |failed| Fail["Set failed state"]
Outcome --> |pending| NextAttempt["Delay and repeat"]
MomoPoll --> QueryStatus["gtPayStatus(partnerTransId)"]
QueryStatus --> Outcome2{"Outcome?"}
Outcome2 --> |success| Credit
Outcome2 --> |failed| AwaitFail["Awaiting callback with providerStatus"]
Outcome2 --> |pending| NextAttempt2["Delay and repeat"]
NextAttempt --> CheckGen{"Generation changed?"}
CheckGen --> |Yes| Abort["Abandon stale verification"]
CheckGen --> |No| Continue["Continue loop"]
```

**Diagram sources**
- [providers.dart:474-572](file://lib/features/payments/providers.dart#L474-L572)
- [providers.dart:578-665](file://lib/features/payments/providers.dart#L578-L665)

**Section sources**
- [providers.dart:474-572](file://lib/features/payments/providers.dart#L474-L572)
- [providers.dart:578-665](file://lib/features/payments/providers.dart#L578-L665)

### Payment History Tracking and Receipt Handling
After successful delivery, the return screen refreshes relevant feeds and displays receipts or shop order success.

History-related behavior:
- On completion, history analytics, recent transactions, wallet summary, points, Lida Value, and orders are invalidated to reload from backend.
- Service purchases show a service receipt screen.
- Shop orders show checkout success and optionally fetch the latest order by ID or order number.
- Pending topups route to a dedicated pending topup screen.

```mermaid
sequenceDiagram
participant Return as "PaymentReturnScreen"
participant Session as "PaymentSessionNotifier"
participant Feeds as "History & Order Feeds"
participant Shop as "Shop Repository"
Session-->>Return : phase = completed
Return->>Feeds : invalidate(history, analytics, recent, wallet, points, lidaValue, orders)
alt service receipt available
Return->>Return : show ServiceReceiptScreen
else shop order
Return->>Shop : getOrder(orderId) or getOrderByNumber(orderNumber)
Shop-->>Return : ShopOrder
Return->>Return : show CheckoutSuccessScreen
end
```

**Diagram sources**
- [payment_return_screen.dart:68-77](file://lib/features/payments/screens/payment_return_screen.dart#L68-L77)
- [payment_return_screen.dart:120-150](file://lib/features/payments/screens/payment_return_screen.dart#L120-L150)
- [payment_return_screen.dart:157-204](file://lib/features/payments/screens/payment_return_screen.dart#L157-L204)

**Section sources**
- [payment_return_screen.dart:68-77](file://lib/features/payments/screens/payment_return_screen.dart#L68-L77)
- [payment_return_screen.dart:120-150](file://lib/features/payments/screens/payment_return_screen.dart#L120-L150)
- [payment_return_screen.dart:157-204](file://lib/features/payments/screens/payment_return_screen.dart#L157-L204)

### Pending Payment Store and Data Security
The pending payment store persists the in-flight purchase across process death and separates sensitive fields from general storage.

Security design:
- Sensitive fields such as the payment token and MoMo number are stored in a secret store backed by platform keystore/keychain.
- The rest of the pending record is stored in shared preferences.
- Hydration loads secrets at startup so load can serve tokens synchronously.
- Legacy plaintext fields are migrated to encrypted storage when possible.
- Clear removes both persistent and secret fields.

```mermaid
classDiagram
class PendingPaymentStore {
+hydrate() void
+save(payment) Future~void~
+load() PendingPayment?
+clear() Future~void~
}
class PendingPayment {
+kind
+reference
+clientReference
+payAmount
+payCurrency
+deliverAmount
+deliverCurrency
+orderDesc
+params
+createdAt
+token
+advansisOrderId
+checkoutUrl
+method
+partnerTransId
+momoNumber
}
class SecretStore {
<<interface>>
+read(key) Future~String?~
+write(key, value) Future~void~
+delete(key) Future~void~
}
PendingPaymentStore --> PendingPayment : "persists"
PendingPaymentStore --> SecretStore : "encrypts token/momo"
```

**Diagram sources**
- [pending_payment_store.dart:8-26](file://lib/features/payments/data/pending_payment_store.dart#L8-L26)
- [pending_payment_store.dart:31-63](file://lib/features/payments/data/pending_payment_store.dart#L31-L63)
- [pending_payment_store.dart:65-121](file://lib/features/payments/data/pending_payment_store.dart#L65-L121)
- [pending_payment.dart:24-87](file://lib/features/payments/data/pending_payment.dart#L24-L87)

**Section sources**
- [pending_payment_store.dart:8-26](file://lib/features/payments/data/pending_payment_store.dart#L8-L26)
- [pending_payment_store.dart:31-63](file://lib/features/payments/data/pending_payment_store.dart#L31-L63)
- [pending_payment_store.dart:65-121](file://lib/features/payments/data/pending_payment_store.dart#L65-L121)
- [pending_payment.dart:24-87](file://lib/features/payments/data/pending_payment.dart#L24-L87)

### Transaction State Management
The payment session tracks phases from idle through initiating, awaiting callback, verifying, crediting, completed, and failed.

State transitions:
- beginPayment sets initiating and saves pending.
- Card flow moves to awaitingCallback after launching checkout.
- Mobile Money flow may move directly to success or to verifying/awaitingCallback depending on outcome.
- _verifyThenCredit centralizes polling and avoids duplicate work.
- _credit delivers services or marks shop orders paid and clears pending state.
- cancelPending clears persisted pending and resets session.

```mermaid
stateDiagram-v2
[*] --> Idle
Idle --> Initiating : "beginPayment"
Initiating --> AwaitingCallback : "checkout opened"
Initiating --> Failed : "initiation error"
AwaitingCallback --> Verifying : "recheck / handleReturn"
Verifying --> Crediting : "outcome = success"
Verifying --> AwaitingCallback : "outcome = pending or timeout"
Verifying --> Failed : "outcome = failed"
Crediting --> Completed : "delivery confirmed"
AwaitingCallback --> Failed : "cancel / explicit failure"
Completed --> [*]
Failed --> [*]
```

**Diagram sources**
- [providers.dart:43-85](file://lib/features/payments/providers.dart#L43-L85)
- [providers.dart:182-277](file://lib/features/payments/providers.dart#L182-L277)
- [providers.dart:372-468](file://lib/features/payments/providers.dart#L372-L468)
- [providers.dart:700-769](file://lib/features/payments/providers.dart#L700-L769)

**Section sources**
- [providers.dart:43-85](file://lib/features/payments/providers.dart#L43-L85)
- [providers.dart:182-277](file://lib/features/payments/providers.dart#L182-L277)
- [providers.dart:372-468](file://lib/features/payments/providers.dart#L372-L468)
- [providers.dart:700-769](file://lib/features/payments/providers.dart#L700-L769)

### Payment Failure Scenarios, Retry Logic, and User Notifications
Failure handling distinguishes provider-reported failures from transient network issues.

Patterns:
- Card query failures during polling are treated as unknown unless explicitly failed.
- Mobile Money status polling stops on timeout and leaves the user in awaitingCallback with provider status.
- When the network reports failure, users can check status again or send a new prompt.
- New prompts generate a fresh PartnerTransId to avoid double debits.
- Cancellation is only safe for unverified initiations; once verified, local cancellation does not reverse provider charges.
- UI panels provide clear guidance for checking approvals, dialing USSD menus, and choosing next actions.

```mermaid
flowchart TD
Start(["Provider reports failure or timeout"]) --> Type{"Type?"}
Type --> |Card query error| Unknown["Treat as pending if not explicit failure"]
Type --> |Mobile Money FAILED| NotConfirmed["Awaiting callback with providerStatus"]
Type --> |Mobile Money timeout| TimedOut["Awaiting callback TIMED_OUT"]
Unknown --> PollAgain["Allow recheck"]
NotConfirmed --> Options{"User action"}
TimedOut --> Options
Options --> |Check status| Recheck["Recheck status"]
Options --> |Send new prompt| Retry["retryMobileMoney(new PartnerTransId)"]
Options --> |Cancel| Cancel["cancelPending()"]
```

**Diagram sources**
- [providers.dart:325-367](file://lib/features/payments/providers.dart#L325-L367)
- [providers.dart:527-572](file://lib/features/payments/providers.dart#L527-L572)
- [providers.dart:602-665](file://lib/features/payments/providers.dart#L602-L665)
- [providers.dart:670-695](file://lib/features/payments/providers.dart#L670-L695)
- [payment_awaiting_panel.dart:82-103](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L82-L103)
- [payment_awaiting_panel.dart:232-421](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L232-L421)

**Section sources**
- [providers.dart:325-367](file://lib/features/payments/providers.dart#L325-L367)
- [providers.dart:527-572](file://lib/features/payments/providers.dart#L527-L572)
- [providers.dart:602-665](file://lib/features/payments/providers.dart#L602-L665)
- [providers.dart:670-695](file://lib/features/payments/providers.dart#L670-L695)
- [payment_awaiting_panel.dart:82-103](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L82-L103)
- [payment_awaiting_panel.dart:232-421](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L232-L421)

### Deep Link and Return Handling
Payment returns are routed through deep links into the return screen, which delegates verification to the payment session.

Behavior:
- Deep link handler recognizes payment return URIs.
- Return screen passes hint params to handleReturn.
- handleReturn validates orderId against saved values and ignores mismatches.
- Cancelled returns without token clear pending and show failure.
- Otherwise, verification proceeds and results are displayed.

```mermaid
sequenceDiagram
participant Browser as "Browser / Gateway"
participant DeepLink as "Deep Link Handler"
participant Return as "PaymentReturnScreen"
participant Session as "PaymentSessionNotifier"
Browser-->>DeepLink : lidapay : //payments/callback?...
DeepLink-->>Return : navigate to payment callback route
Return->>Session : handleReturn(status, orderId, token)
alt cancelled without token
Session->>Session : clear pending, set failed
else mismatched orderId
Session->>Session : keep awaitingCallback
else valid
Session->>Session : _verifyThenCredit(pending)
end
```

**Diagram sources**
- [deep_links.dart:64-72](file://lib/core/deep_links.dart#L64-L72)
- [payment_return_screen.dart:54-66](file://lib/features/payments/screens/payment_return_screen.dart#L54-L66)
- [providers.dart:372-421](file://lib/features/payments/providers.dart#L372-L421)

**Section sources**
- [deep_links.dart:64-72](file://lib/core/deep_links.dart#L64-L72)
- [payment_return_screen.dart:54-66](file://lib/features/payments/screens/payment_return_screen.dart#L54-L66)
- [providers.dart:372-421](file://lib/features/payments/providers.dart#L372-L421)

## Dependency Analysis
The payment subsystem depends on repositories, UI providers, deep linking, constants, and backend endpoints.

```mermaid
graph LR
Provider["PaymentSessionNotifier"] --> Repo["RemotePaymentsRepository"]
Provider --> Store["PendingPaymentStore"]
Provider --> Models["Payment Models"]
Provider --> Pending["PendingPayment Model"]
Repo --> Endpoint["Backend Endpoints"]
Return["PaymentReturnScreen"] --> Provider
Method["PaymentMethodSelector"] --> Provider
Awaiting["PaymentAwaitingPanel"] --> Provider
Deep["Deep Link Handler"] --> Return
Const["AppConstants"] --> Provider
```

**Diagram sources**
- [providers.dart:120-178](file://lib/features/payments/providers.dart#L120-L178)
- [remote_payments_repository.dart:12-109](file://lib/features/payments/data/remote_payments_repository.dart#L12-L109)
- [payment_models.dart:5-49](file://lib/features/payments/data/payment_models.dart#L5-L49)
- [pending_payment.dart:16-87](file://lib/features/payments/data/pending_payment.dart#L16-L87)
- [payment_return_screen.dart:22-25](file://lib/features/payments/screens/payment_return_screen.dart#L22-L25)
- [payment_method_selector.dart:21-46](file://lib/features/payments/widgets/payment_method_selector.dart#L21-L46)
- [payment_awaiting_panel.dart:9-30](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L9-L30)
- [deep_links.dart:64-72](file://lib/core/deep_links.dart#L64-L72)
- [app_constants.dart:23-46](file://lib/core/constants/app_constants.dart#L23-L46)

**Section sources**
- [providers.dart:120-178](file://lib/features/payments/providers.dart#L120-L178)
- [remote_payments_repository.dart:12-109](file://lib/features/payments/data/remote_payments_repository.dart#L12-L109)
- [payment_models.dart:5-49](file://lib/features/payments/data/payment_models.dart#L5-L49)
- [pending_payment.dart:16-87](file://lib/features/payments/data/pending_payment.dart#L16-L87)
- [payment_return_screen.dart:22-25](file://lib/features/payments/screens/payment_return_screen.dart#L22-L25)
- [payment_method_selector.dart:21-46](file://lib/features/payments/widgets/payment_method_selector.dart#L21-L46)
- [payment_awaiting_panel.dart:9-30](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L9-L30)
- [deep_links.dart:64-72](file://lib/core/deep_links.dart#L64-L72)
- [app_constants.dart:23-46](file://lib/core/constants/app_constants.dart#L23-L46)

## Performance Considerations
- Polling limits prevent excessive network calls:
  - Card verification uses a fixed number of attempts with delays.
  - Mobile Money polling respects an expiration window anchored to creation time.
- Single-flight verification avoids duplicate queries when deep links or resume events occur.
- Timeout handling for mobile money status queries prevents long hangs.
- UI remains responsive by separating busy states from user-waiting states.

Recommendations:
- Keep polling attempts conservative to balance responsiveness and reliability.
- Prefer server-side callbacks where possible to reduce client polling.
- Monitor backend latency and adjust timeouts accordingly.
- Avoid unnecessary re-fetches by relying on feed invalidation only on completion.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
Common issues and resolutions:

- No pending payment found on return:
  - Indicates no active purchase or cleared state; show generic failure and guide user to history or support.
- Checkout URL invalid or not launchable:
  - Validate URLs against allowed hosts and show a friendly error.
- Deep link orderId mismatch:
  - Ignore mismatched hints and continue verification using saved token or PartnerTransId.
- Mobile Money prompt expired:
  - Set provider status to timed out; guide user to check approvals and offer check status or cancellation.
- Network timeout during status polling:
  - Stop polling and let user manually check status; do not declare failure prematurely.
- Delivery failure after payment confirmation:
  - Keep pending record so user can retry crediting without paying again.

Operational tips:
- Use the awaiting panel to expose actionable steps: reopen checkout, check status, send new prompt, cancel.
- Log provider status and messages for diagnostics without exposing sensitive tokens.
- Ensure secret store hydration succeeds; otherwise degrade gracefully and ask user to recheck.

**Section sources**
- [providers.dart:235-277](file://lib/features/payments/providers.dart#L235-L277)
- [providers.dart:372-421](file://lib/features/payments/providers.dart#L372-L421)
- [providers.dart:602-665](file://lib/features/payments/providers.dart#L602-L665)
- [providers.dart:730-753](file://lib/features/payments/providers.dart#L730-L753)
- [payment_awaiting_panel.dart:82-103](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L82-L103)
- [payment_awaiting_panel.dart:232-421](file://lib/features/payments/widgets/payment_awaiting_panel.dart#L232-L421)

## Conclusion
The payment processing system provides a robust, secure, and user-friendly flow for both Mobile Money and card payments. It centralizes verification, protects sensitive data, handles asynchronous provider behavior, and offers clear user guidance throughout the process. By combining careful state management, bounded polling, and resilient error handling, the system minimizes double charges and maximizes recovery from transient failures.

For production hardening:
- Pin checkout allowed hosts at build time.
- Monitor backend health and provider SLAs.
- Extend observability around provider status and polling outcomes.
- Continuously validate deep link routing and return semantics.
- Review security posture regularly, especially secret store usage and token handling.

[No sources needed since this section summarizes without analyzing specific files]