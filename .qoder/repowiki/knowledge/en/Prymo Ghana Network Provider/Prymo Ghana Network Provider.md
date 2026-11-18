---
kind: external_dependency
name: Prymo Ghana Network Provider
slug: prymo
category: external_dependency
category_hints:
    - client_constraint
scope:
    - '**'
source_files:
    - lib/features/services/screens/airtime_screen.dart
    - lib/features/services/screens/service_transaction_screen.dart
---

### Identity
Prymo is the fixed-network operator used for Ghana airtime/data purchases.

### Role in this repo
- Ghana is treated specially: instead of querying Reloadly's global catalogue, the app pins Prymo's known network code (stored as `_ghanaAutoNetworkId`) so the submit payload is never null.
- The Network step lists Prymo options directly for Ghana; for other countries it falls back to the Reloadly catalogue.

### Durable integration notes
- Do not remove or null out `_ghanaAutoNetworkId` — it is required by the submit path even when the user defers to Auto Detect.