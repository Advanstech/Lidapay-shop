---
kind: external_dependency
name: Lida Value Wallet
slug: lida-value
category: external_dependency
category_hints:
    - framework_behavior
scope:
    - '**'
source_files:
    - lib/features/lida_value/providers.dart
    - lib/features/services/screens/airtime_screen.dart
    - lib/features/services/screens/service_transaction_screen.dart
---

### Identity
Lida Value is the in-app wallet feature (balance, send, top-up) that can fund airtime/data purchases.

### Role in this repo
- Two funding modes exist: `ServiceFunding.lidaValueSend` (a menu action debited directly from the Lida Value wallet — no payment session) and `ServiceFunding.lidaValueUse` (a purchase paid from the wallet balance, with a shortfall path to Advansis Pay).
- SEND is a Lida Value menu function: it debits the Lida Value wallet and then delivers the recipient's airtime/data through the domestic/Reloadly route with `isSelfTopup: false`. It never touches mobile money or a card.
- The wallet balance is read from the backend; the UI offers a "Pay another way" switch when the balance is below the amount.

### Durable integration notes