# courier-orders

Ops scripts for the Frank courier integration test loop.

## Setup

```bash
cd tool/courier-orders
npm install
cp .env.example .env   # then fill in values — .env is gitignored
```

`.env` needs `MONGODB_URI`, `JWT_SECRET`, `CUSTOMER_ID`, `ADMIN_ID`,
`PRODUCT_ID` for order creation, and `COURIER_PARTNER_ID` /
`COURIER_PARTNER_SECRET` for the queue check. The current working sandbox
pair is documented in `docs/COURIER_API_PARTNER_HANDOFF_FRANK.md`.

> Note: the API's effective JWT secret is the hardcoded fallback in
> `lidapay-prod/src/constants.ts`, which takes precedence over `.env`'s
> `JWT_SECRET`. If tokens start returning 401, re-sync `JWT_SECRET` in this
> `.env` from that file.

## Scripts

### `check-courier-queue.mjs [state]`

Signs a request exactly like the partner backend and lists jobs.

```bash
node check-courier-queue.mjs available   # paid, unassigned orders
node check-courier-queue.mjs assigned    # orders Frank has accepted
```

### `setup-fulfillment.mjs`

One-time provisioning: creates the **Melcom Ghana** shop and **East Legon
Branch** fulfillment branch (pickup pin from the handoff doc) via the admin
API and assigns `PRODUCT_ID` to it with `fulfillmentBranchId`. Checkout now
**requires** a resolvable pickup — without a branch (and without the legacy
`COURIER_PICKUP_*` env fallback on the server) every checkout 400s. Idempotent;
safe to re-run.

### `create-paid-orders.mjs [count]`

Seeds `count` paid test orders (default 1) into the `available` queue.
Each order is checkout (with delivery-pin coordinates) → admin
`paymentStatus=success`, marked "TEST ORDER" in the shipping address.
No real payment is taken. Orders created this way carry the branch
`pickupAddress` snapshot and destination coords, so Frank's job poll can
compute `deliveryDistance`.

```bash
node create-paid-orders.mjs 3
```

### `stamp-delivery-distance.mjs [--backfill-coords]`

Stamps `deliveryDistance { km, durationMinutes, source: 'estimate' }` onto
paid orders that have pickup + destination coords but no computed distance —
for courier testing while the server-side Google Routes key has no billing.
Values are haversine × 1.35 road factor at ~22 km/h; `source: 'estimate'`
marks them as non-Routes. `--backfill-coords` also fills the destination pin
on orders created before the checkout contract required it. Orders missing a
`pickupAddress` snapshot (pre-branch-provisioning) need it backfilled
separately — see the script's header comment.

Typical loop while Frank tests: he accepts/burns an order through
`delivered`, `available` goes empty → run `create-paid-orders.mjs` again,
then `stamp-delivery-distance.mjs` if Routes billing still isn't live.
