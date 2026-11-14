# LidaPay Shop API — Mobile App Handoff

API contract for the shop & checkout flow in the Flutter app. Interactive Swagger UI
is available at `https://api.advansistechnologies.com/api-doc` (tag: **Shop**); a
self-contained export is also generated at `dist/swagger.html` / `dist/swagger.json`
via `npm run swagger:html`.

**Base URL:** `https://api.advansistechnologies.com`
**Shop base path:** `/api/v1/shop`
**Auth:** `Authorization: Bearer <accessToken>` on all cart/checkout/order endpoints.
Product and category browsing is public.

### Getting a token

Users can sign in with a password via `POST /api/v1/users/login`, or choose
passwordless email-code login via `POST /api/v1/auth/login/request-otp` →
`POST /api/v1/auth/login/verify-otp`. Either flow returns `access_token`,
`refresh_token` and the `user` object. Refresh via
`POST /api/v1/auth/refresh`. Wherever a `userId` is required below, use
`user._id` from the login response (the same value the JWT carries as `sub`).

---

## 1. Pricing contract (important)

Prices are **final, server-computed** — do not add commission or re-apply discounts
in the app.

| Field | Meaning |
|---|---|
| `price` | Base partner price **+ 10% commission** already applied. This is the "original"/list price. |
| `discountPrice` | Promo price (commission also applied). `0` or absent = not discounted. |
| **Effective price** | `discountPrice > 0 ? discountPrice : price` — always display and pay this. |

Images: use `imageUrl` (string) or `images[0]` — already a public CDN URL.

```jsonc
// Product object (abridged)
{
  "_id": "665e1a2b3c4d5e6f7a8b9c0d",
  "name": "Long Mountain Ruby Cabernet 75cl",
  "price": 76.99,          // includes 10% commission
  "discountPrice": 69.29,  // final price if > 0
  "stock": 100,
  "sku": "18339",
  "brand": "Long Mountain",
  "imageUrl": "https://.../products/18339.webp",
  "images": ["https://.../products/18339.webp"],
  "attributes": { "size": "75cl", "type": "Ruby Cabernet" },
  "category": { "_id": "...", "name": "Alcohol" },
  "active": true,
  "featured": false
}
```

### Product names and metadata contract

Use the API field names exactly as returned. Product display names are always in
`name`; product specifications/metadata are in `attributes`. The API does not
return `productName`, `title`, or a `metadata` alias. Do not derive the display
name from `brand` or another field.

```json
{
  "_id": "665e1a2b3c4d5e6f7a8b9c0d",
  "name": "Samsung Galaxy A05",
  "description": "Budget smartphone with 6.7-inch display",
  "category": { "_id": "665e1a2b3c4d5e6f7a8b9c0e", "name": "Electronics" },
  "images": ["https://cdn.lidapay.com/prod/a05-1.jpg"],
  "imageUrl": "https://cdn.lidapay.com/prod/a05-main.jpg",
  "price": 850,
  "discountPrice": 790,
  "stock": 50,
  "sku": "SAM-A05-128",
  "brand": "Samsung",
  "attributes": { "color": "Black", "storage": "128GB", "ram": "4GB" },
  "weight": 0.3,
  "active": true,
  "featured": false,
  "rating": 4.5,
  "reviewCount": 12,
  "salesCount": 25,
  "createdAt": "2026-09-01T12:00:00.000Z",
  "updatedAt": "2026-09-02T12:00:00.000Z"
}
```

- `attributes` is a key/value object; keys vary by product type and can be
  absent or empty. Model it as an optional string-to-string map, not a fixed
  set of fields.
- Product list and featured-list responses use the envelope
  `{ "products": [...], "total": number, "page": number, "totalPages": number }`.
  Each product's `category` is populated with `_id` and `name`.
- Product detail also populates `category`; it may include `description` and
  `image` in addition to `_id` and `name`.
- `imageUrl` is an optional single URL and `images` is an array of URLs. If
  `imageUrl` is empty or absent, use the first non-empty value in `images`.
- Cart and order line items are snapshots, not full catalog products. They use
  `name` for the line-item name, include `sku` when the product has one, and do
  `description` when the product has one, and do not include `attributes`; fetch
  the product detail endpoint when the UI needs product specifications. Keep
  SKU as a string and show it on order item/detail views to help identify goods
  for delivery. Both SKU and description may be absent on older/incomplete
  catalog products.

---

## 2. Catalog endpoints (public)

| Method | Endpoint | Notes |
|---|---|---|
| GET | `/api/v1/shop/categories?activeOnly=true` | List categories |
| GET | `/api/v1/shop/categories/{id}` | Category detail |
| GET | `/api/v1/shop/products` | Paginated list — params: `page` (default 1), `limit` (default 20, max 100), `category` (category ObjectId), `search` (name/description/brand), `featured=true`, `sortBy`, `sortOrder` (`asc`/`desc`) |
| GET | `/api/v1/shop/products/featured` | Featured products (limit 20) |
| GET | `/api/v1/shop/products/{id}` | Product detail |

```jsonc
// GET /products response
{ "products": [ /* Product[] */ ], "total": 11163, "page": 1, "totalPages": 559 }
```

---

## 3. Cart endpoints (auth required)

> The **server cart is the source of truth at checkout.** The app may keep a local
> cart for snappy UX, but must sync it to the backend before checkout
> (`cart/add` per item, or `cart/update` to reconcile).

Cart line items contain `productId`, `name`, optional `sku`, `price`, `image`
(an array of image URLs), `quantity`, and `discountPrice`. The `GET /cart` response also contains
summary fields at the top level and the raw cart under `cart`; catalog-only
fields such as `attributes` are not copied into cart items.

| Method | Endpoint | Body |
|---|---|---|
| GET | `/api/v1/shop/cart` | — returns `{ items, itemCount, subtotal, discount, total, cart }` with **live prices** |
| POST | `/api/v1/shop/cart/add` | `{ "productId": "<ObjectId>", "quantity": 2 }` |
| PUT | `/api/v1/shop/cart/update` | `{ "productId": "<ObjectId>", "quantity": 3 }` |
| POST | `/api/v1/shop/cart/remove` | `{ "productId": "<ObjectId>" }` |
| DELETE | `/api/v1/shop/cart/clear` | — |

Errors: `400` on insufficient stock / inactive product, `404` when product or cart item missing.

---

## 4. Checkout (auth required)

**`POST /api/v1/shop/checkout`** — creates an order from the server cart.

```jsonc
// Request — shippingAddress is required in practice; other fields are optional
{
  "shippingAddress": {
    "fullName": "Kofi Mensah", "phone": "0241120481",
    "addressLine1": "12 Osu Avenue", "city": "Accra",
    "region": "Greater Accra", "country": "Ghana",
    "email": "kofi@example.com",          // optional
    "addressLine2": "Flat 4B",            // optional
    "postalCode": "GA-001",               // optional
    "deliveryInstructions": "Call first", // optional
    "latitude": 5.555,                    // required delivery pin
    "longitude": -0.205                   // required with latitude
  },
  "paymentMethod": "momo",   // momo | card | wallet (default "momo")
  "redirectUrl": "lidapay://shop/checkout/callback"
}
// shippingAddress is effectively REQUIRED — user profiles have no address
// fields, so the profile fallback returns 400 "Shipping address incomplete".
```

### Courier address, location, and KYC boundary

The checkout contract accepts the `shippingAddress` fields shown above, plus
customer destination coordinates:

- `shippingAddress.latitude` / `shippingAddress.longitude` — required delivery
  drop-off coordinates in decimal degrees (latitude `-90` to `90`, longitude
  `-180` to `180`). Send both coordinates. Capture them when the customer
  pins/confirms their delivery destination on the map. This does not require
  device location permission if the user places the pin manually.
The pickup origin must be the actual partner shop branch fulfilling this
order, not the LidaPay/Advansis office. Shops and branches are persisted as
separate backend records. LidaPay admin first creates a shop at
`/api/v1/shop/admin/shops`; MongoDB generates and returns its `_id`. The admin
then creates each branch at `/api/v1/shop/admin/branches`, passing that
`shopId` and the verified pickup address and map pin. Optional shop contact
details (email, phone, website, and address) and an optional existing partner
User ID can be stored on the shop. Branch-level contact name, email, and phone
are also supported; branch contact details are included in Frank's private
pickup snapshot, not customer-facing responses.
If a partner User ID is not yet available, products must be explicitly assigned
to a branch using the private `fulfillmentBranchId` field. Branch IDs, names,
and pickup addresses are not returned by public product endpoints or customer
order responses. The mobile app only sends the customer's destination address
and coordinates; the backend resolves pickup branch from the server-side
products in the cart and computes driving distance using its server-side
Google Routes API key when Frank polls jobs.

Each checkout must contain products fulfilled by one branch. If the cart spans
branches, the API returns `400`; the customer must check out those groups
separately so each courier job has one clear pickup point. A single active
branch for a partner is inferred for older product records. If that partner
has multiple active branches, the product must be explicitly assigned to one.

### Admin shop and branch setup (private)

Create the parent shop first. These endpoints require an admin JWT and are not
for customer app use:

```http
POST /api/v1/shop/admin/shops
```

```json
{
  "name": "Melcom Ghana",
  "website": "https://melcom.com",
  "city": "Accra",
  "region": "Greater Accra",
  "country": "Ghana"
}
```

The shop ID is generated by MongoDB and does not need to be supplied by the
caller. No unverified contact details are included.

The response contains the generated shop `_id`. Use it as `shopId` to create
the East Legon branch:

```http
POST /api/v1/shop/admin/branches
```

```jsonc
{
  "shopId": "<shop _id from the create-shop response>",
  "name": "East Legon Branch",
  "partnerName": "Melcom Ghana",
  "addressLine1": "JRRQ+V32, Near Sel Filling Station, Mensah Wood Ave",
  "city": "Accra",
  "region": "Greater Accra",
  "country": "Ghana",
  "latitude": 5.6413169,
  "longitude": -0.164472,
  "active": true
}
```

The address and map pin above are transcribed from the supplied Google Maps
screenshot as initial values. The coordinates may be the map camera center
rather than the exact pickup entrance; the listing also showed "Temporarily
closed." The create example sets the branch active at the user's direction for
testing. Confirm operational status and refine the entrance pin before
fulfilling real customer orders.

Create the second initial location using the same parent `shopId`:

```json
{
  "shopId": "<same generated Melcom Ghana shop _id>",
  "name": "Shiashie Branch",
  "partnerName": "Melcom Ghana",
  "addressLine1": "Shiashie, Boundary Rd, Accra",
  "addressLine2": "Opposite Gethsemane Memorial Garden",
  "city": "Accra",
  "region": "Greater Accra",
  "country": "Ghana",
  "latitude": 5.6274853,
  "longitude": -0.1758338,
  "active": true
}
```

The Shiashie coordinates are a provisional geocode for Shiashie on Boundary
Road, not a confirmed Melcom entrance. Verify the exact pickup point before
using this branch for live customer deliveries.

Manage shops with `GET /api/v1/shop/admin/shops`,
`PUT /api/v1/shop/admin/shops/{id}`, and
`DELETE /api/v1/shop/admin/shops/{id}`. Shops with branches cannot be deleted;
deactivate them instead. Manage branches with `GET /api/v1/shop/admin/branches`,
`PUT /api/v1/shop/admin/branches/{id}`, and
`DELETE /api/v1/shop/admin/branches/{id}`. A branch referenced by products or
orders cannot be deleted; deactivate it instead. Set a product's
`fulfillmentBranchId` to the branch `_id` when creating/updating that product.
The shop, branch, and `fulfillmentBranchId` are operational metadata and are
kept out of public catalog responses.

Only request location permission when the delivery flow requires it, and keep
a manual address path for customers who decline. The backend-calculated
`deliveryDistance` is a **distance, not a price** — do not send a client-calculated delivery fee. The
current courier API has no endpoint for Frank to submit a quote back to LidaPay,
so `DELIVERY_FEE_GHS` remains the checkout fee (default GHS 0) until a separate
quote-return contract is agreed and implemented.

`deliveryUpdates[].location` is a human-readable tracking timeline value; it is
not the customer's or driver's GPS coordinates. Driver GPS is sent separately
by the authenticated courier integration and appears as `lastDriverLocation`
on the customer tracking response.

```jsonc
// Response — the created Order
{
  "_id": "66f...",
  "orderNumber": "LPS260912482913",
  "items": [{ "productId": "...", "name": "...", "sku": "18339", "description": "Product description", "price": 69.29, "quantity": 2, "images": [] }],
  "subtotal": 153.98, "discount": 15.40, "deliveryFee": 0,
  "total": 138.58, "currency": "GHS",
  "status": "pending", "paymentStatus": "pending",
  "paymentMethod": "momo",
  "deliveryUpdates": [{ "status": "order_placed", "message": "...", "timestamp": "..." }]
}
```

Server-side guarantees: prices re-verified against DB (client prices are ignored),
stock validated & decremented, cart cleared. `400` if cart is empty or stock insufficient.
The order item's `sku` is copied from the server's product catalog, not accepted
from the checkout request. The app should display it for item identification
and preserve it as a string (SKUs can contain letters or leading zeroes).
The optional order-item `description` is likewise copied from the catalog by
the server. Display it where it helps the customer identify the ordered item.

---

## 5. Payment (initiated by the app)

After checkout, initiate payment for `order.total` through either provider:

The app offers two payment options at checkout — **Advansis Pay (ExpressPay)** and
**Mobile Money (GTPay)**. Both carry the same `shopOrderNumber` linkage so the
backend marks the order paid/failed automatically when payment completes.

### Option A — Advansis Pay / ExpressPay (LIVE — primary): `POST /api/v1/advansispay/initiate-payment`

```jsonc
{
  "firstName": "Kofi", "lastName": "Mensah",
  "email": "kofi@example.com",
  "phoneNumber": "233241120481",
  "userId": "<user ObjectId>",
  "amount": 158.58,
  "shopOrderNumber": "LPS260912482913",      // ← links payment to the order
  "orderDesc": "Lidapay shop order LPS260912482913",
  "transType": "MOMO"
}
// → { data: { checkoutUrl, token, "order-id": "ADV-..." } }
// Open checkoutUrl; use the supported LidaPay return flow and verify via API.
```

Confirm via `POST /api/v1/advansispay/query-transaction` with `{ "token": "..." }`.
On final outcome — from the post-URL callback, the redirect callback, or your
`query-transaction` poll — the backend marks the order `paymentStatus:
success`/`failed` and advances `status` to `paid`. This is the same integration
that already serves airtime payments in production; shop linkage activates only
when `shopOrderNumber` (or an `LPS…` token in `payTransRef`/`orderDesc`) is
present.

> **Web / e-commerce clients:** pass `returnUrl` (browser redirect target) and
> optionally `webhookUrl` + `webhookSecret` (signed server-to-server
> notification) at initiation — the mobile `lidapay://` deep link only applies
> when `returnUrl` is absent. See `ADVANSISPAY_WEB_INTEGRATION.md`.

### Option B — Mobile Money / GTPay (GTBank): `POST /api/v1/gtpay/pay`

**Primary GTPay action — debit the customer's mobile-money wallet.**
`debitwallet` is the expected service for a customer paying for an order:
GTBank requests a debit from the customer's mobile-money number in
`ServiceNumber`, then the final response may arrive later from the telco.
GTBank has cleared LidaPay for production. GTPay may be offered as a shop
payment option using the production `debitwallet` service returned by service
discovery, once the backend authorization gap described
in [GTPAY_PRODUCTION_INTEGRATION.md](./GTPAY_PRODUCTION_INTEGRATION.md) is
closed. The app must still confirm completion by checking the status endpoint;
initiation is asynchronous and is not proof of payment.

```jsonc
{
  "userId": "<user ObjectId>",
  "userName": "kowusu",
  "shopOrderNumber": "LPS260912482913",      // ← links payment to the order
  "ServiceDetails": {
    "ServiceName": "debitwallet",            // GTBank customer-payment service for this shop flow
    "ServiceNumber": "0241120481",           // the momo number to debit (customer-selected)
    "SecondaryServiceNumber": "",
    "Amount": "158.58",                      // string, exact order total
    "Remarks": "Lidapay shop order LPS260912482913",
    "PaidBy": "Kofi Mensah",
    "PayeeName": "Lidapay"
  }
}
// → { data: { PartnerTransId, GTBTransId, Status: "PENDING", Data: { Network, TotalAmount } } }
```

`PartnerTransId` is optional and may be generated by the backend; persist the
returned `data.PartnerTransId` and use it with
`POST /api/v1/gtpay/status` and `{ "PartnerTransId": "..." }` to check the
result (`COMPLETED` / `PENDING` / `FAILED`). `PENDING` means GTBank may still
be waiting for the customer's mobile-money operator/telco to return its
response; that response can arrive after the initial pay request. Keep the
order in a pending/verifying state and continue querying `/status` with the
same `PartnerTransId` (use a measured backoff and resume checks when the app
returns to the foreground). Only the final server-reconciled status decides
whether the order is paid or failed. If the request times out or returns
`PAYMENT_STATUS_UNKNOWN`, check status before any retry; do not start a second
payment while the telco response is outstanding. Do NOT use `creditwallet` for this checkout: it is the opposite money direction
(credit/inflow) and is reserved for separately supported wallet credit flows.
`banktrf` is for a bank transfer/payout and is not the customer's normal
mobile-money payment method.

> **Always pass the shop `orderNumber`** — via `shopOrderNumber` on either
> provider (or an `LPS…` token in `payTransRef`/`orderDesc` on ExpressPay) — so
> the payment reconciles to the order.

---

## 6. Orders & tracking (auth required unless noted)

| Method | Endpoint | Notes |
|---|---|---|
| GET | `/api/v1/shop/orders?page=1&limit=20` | Current user's order history → `{ orders: Order[], total, page, totalPages }` |

| GET | `/api/v1/shop/orders/{id}` | Order detail (own orders only) |
| GET | `/api/v1/shop/orders/number/{orderNumber}` | **Public** lookup by order number — returns the full order incl. shipping address; treat `orderNumber` as a shareable tracking ID, don't expose it where it shouldn't be |
| GET | `/api/v1/shop/orders/{id}/tracking` | Tracking: `orderNumber`, `status`, `trackingNumber`, `carrier`, `estimatedDeliveryDate`, `deliveredAt`, `deliveryUpdates[]`, `lastDriverLocation`, `shippingAddress` |
| POST | `/api/v1/shop/orders/{id}/cancel` | `{ "reason": "..." }` — only pending/processing orders; restores stock |

### Status values

- **`status`**: `pending` → `paid` → `processing` → `shipped` → `delivered` (also `cancelled`, `refunded`)
- **`paymentStatus`**: `pending` | `success` | `failed` | `refunded`
- **`deliveryUpdates[].status`**: `order_placed`, `payment_confirmed`,
  `payment_failed`, `courier_accepted`, courier events (`packed`, `picked_up`,
  `out_for_delivery`, `delivered`, `delivery_exception`, `failed_delivery`),
  and raw order-status values (`paid`, `processing`, `shipped`, `cancelled`,
  `refunded`) pushed by fulfilment/admin updates — render as a timeline.

### Live driver map & Order Tracking screen updates (Mobile App Responsibilities)

The mobile app is **read-only** for courier tracking: it never calls `/api/v1/courier/*` or includes courier partner credentials. Instead, when the customer opens the **Track Order** screen, the app calls:

```http
GET /api/v1/shop/orders/{order._id}/tracking
Authorization: Bearer <customer-access-token>
```
*(Use the order's Mongo `_id`, not `orderNumber`.)*

Example response:
```json
{
  "_id": "66f000000000000000000001",
  "orderNumber": "LPS261104123456",
  "status": "shipped",
  "carrier": "Frank Courier",
  "trackingNumber": "FRANK-TRACK-0001",
  "estimatedDeliveryDate": "2026-11-04T12:00:00.000Z",
  "deliveredAt": null,
  "shippingAddress": {
    "fullName": "Kofi Mensah",
    "phone": "0241120481",
    "addressLine1": "12 Osu Avenue",
    "city": "Accra",
    "region": "Greater Accra",
    "country": "Ghana"
  },
  "lastDriverLocation": {
    "latitude": 5.6037,
    "longitude": -0.187,
    "recordedAt": "2026-11-04T10:15:05.000Z"
  },
  "deliveryUpdates": [
    {
      "status": "courier_accepted",
      "message": "Courier accepted the delivery job",
      "timestamp": "2026-11-04T09:45:00.000Z"
    },
    {
      "status": "picked_up",
      "message": "Parcel picked up from Melcom warehouse",
      "location": "Spintex Road, Accra",
      "timestamp": "2026-11-04T10:00:00.000Z"
    },
    {
      "status": "out_for_delivery",
      "message": "Driver is on the way to the recipient",
      "location": "Osu, Accra",
      "timestamp": "2026-11-04T10:15:00.000Z"
    }
  ]
}
```

#### What the Mobile App Needs to Implement on the Tracking Screen:

1. **Render the Live Driver Pin on Google Maps (`lastDriverLocation`)**
   - Configure the Google Maps SDK for Android/iOS using LidaPay's own restricted Google Maps API key (never embed courier partner credentials in the app).
   - When `status === "shipped"` and `lastDriverLocation` is present (`latitude`, `longitude`), display the map with a driver/rider marker at those coordinates.
   - Show a staleness/timestamp indicator (e.g., *"Updated X seconds ago"*) derived from `lastDriverLocation.recordedAt`, and handle missing or stale coordinates gracefully before pickup.

2. **Poll Every 5–10 Seconds While the Tracking Screen is Active**
   - While the order `status` is `"processing"` or `"shipped"` **and** the tracking screen is visible in the foreground, poll `GET /api/v1/shop/orders/{order._id}/tracking` every **5–10 seconds**.
   - Update/animate the Google Maps marker whenever `lastDriverLocation` changes.
   - **Stop polling** immediately when the customer leaves the screen, backgrounds the app, or when `status` reaches `"delivered"` or `"cancelled"`.

3. **Display the Delivery Status Timeline (`deliveryUpdates`)**
   - Render `deliveryUpdates` as a step-by-step timeline showing `status`, `message`, optional `location`, and `timestamp`:
     - `order_placed` / `payment_confirmed` → *"Order Confirmed"*
     - `courier_accepted` → *"Courier Assigned"*
     - `packed` → *"Order Packed"*
     - `picked_up` → *"Picked Up by Courier"*
     - `out_for_delivery` → *"Out for Delivery"*
     - `delivery_exception` / `failed_delivery` → *"Delivery Attempt Issue"* (show warning state)
     - `delivered` → *"Delivered"*

4. **Display Carrier & ETA Summary Header**
   - Show `carrier` (e.g., `"Frank Courier"`), `trackingNumber` (e.g., `"FRANK-TRACK-0001"`), and `estimatedDeliveryDate` (or `deliveredAt` once completed) at the top of the tracking card.

### Recommended app flow

```
Browse products → sync cart → POST /checkout (get orderNumber + total)
→ initiate payment (GTPay or ExpressPay, amount = order.total)
→ poll payment status endpoint → poll GET /orders/{id} until status=paid
→ tracking screen reads GET /orders/{id}/tracking
```

---

## 7. Known caveats

- Payment → order reconciliation is automatic on **both** providers when
  `shopOrderNumber` is sent: on `COMPLETED` the order becomes
  `paymentStatus: success` / `status: paid`; on `FAILED`/`DECLINED` it becomes
  `paymentStatus: failed` (order stays `pending`, so payment can be retried).
  GTBank has cleared GTPay for production. The API initiation response may be
  `PENDING`; only the final server-reconciled status is a receipt state.
- The server applies `DELIVERY_FEE_GHS`, which defaults to 0; a calculated-fee
  endpoint is not exposed and the mobile client must not set the fee.
- Admin endpoints (`/admin/orders/*`, product/category writes) exist in Swagger but
  are not for app use.
