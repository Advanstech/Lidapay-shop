---
kind: external_dependency
name: Reloadly Airtime & Data Top-Up Provider
slug: reloadly
category: external_dependency
category_hints:
    - sdk_real_api
    - framework_behavior
scope:
    - '**'
source_files:
    - docs/MOBILE_APP_REBUILD_HANDOFF.md
    - api/openapi.json
    - lib/features/services/screens/airtime_screen.dart
    - lib/features/services/screens/service_transaction_screen.dart
---

### Identity
Reloadly is the external top-up provider behind the airtime and internet-data flows.

### Role in this repo
- Operator discovery and country catalogue are consumed through the documented backend routes that mint Reloadly tokens per call:
  - `POST /api/v1/reloadly/network-operators` with `{countryIsoCode, size, page, includeBundles, includeData}`
  - `GET /api/v1/reloadly/country-list`
  - `POST /api/v1/reloadly/find-country-by-code`
  - `POST /api/v1/reloadly/get-operator-by-code`
  - `POST /api/v1/reloadly/list-operators`
- The app implements a fallback chain per flow because the backend mints its token per route: airtime tries `network-operators → get-operator-by-code → list-operators`; data tries `list-operators → network-operators → get-operator-by-code`.

### Durable integration notes
- Never gate the entire wizard on operator-catalogue success — both flows degrade to phone/amount/confirm when the list is unavailable.
- For international destinations the operator comes from autodetect, not the list; only Ghana gates on its fixed Prymo list.
- The country picker must lazily resolve dial codes via `find-country-by-code`; the base `country-list` response has no calling codes.
- The operator catalogue may arrive paginated as `{content: [...]}` — callers must unwrap the content envelope.
- Stop retrying on 401/403 (provider-token failure); keep the offline catalogue cache.