---
kind: external_dependency
name: Advansis Pay Mobile Money & Card Payments
slug: advansis-pay
category: external_dependency
category_hints:
    - vendor_identity
scope:
    - '**'
source_files:
    - lib/features/services/widgets/lida_value_checkout_switch.dart
    - lib/features/services/screens/airtime_screen.dart
    - lib/features/services/screens/service_transaction_screen.dart
---

### Identity
Advansis Pay is the payment rail (mobile money and debit/credit card) used as the fallback funding source when the Lida Value wallet cannot cover a purchase.

### Role in this repo
- When a Lida Value-funded airtime/data run hits insufficient balance, the user may switch to the standard checkout where they are charged via mobile money or an Advansis Pay debit/credit card.
- The confirmation dialog explicitly names "mobile money or Advansis Pay debit or credit card" as the replacement charge rail.

### Durable integration notes
- The switch is reversible: from the confirm screen the user can return to Lida Value funding via "Pay from Lida Value instead", restoring the shortfall card.