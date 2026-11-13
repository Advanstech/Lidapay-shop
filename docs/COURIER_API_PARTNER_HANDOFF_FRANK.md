# Frank's Courier Integration — API Setup, Postman & Live Verification Guide

**For:** Frank and the courier engineering team  
**From:** Advansis Technologies / LidaPay  
**Date:** 5 November 2026  
**API base URL:** `https://api.advansistechnologies.com`  
**Courier API prefix:** `/api/v1/courier`  
**Currency:** GHS

---

## 1. Quick Overview: How the Integration Works in 4 Steps

The integration between **Frank's Courier System** and **LidaPay** is two-way and follows 4 simple steps:

1. **Poll for Available Jobs (`GET /api/v1/courier/jobs?state=available`)**  
   Every ~30 seconds, Frank's server asks LidaPay for newly paid, unassigned orders.
2. **Accept a Job (`POST /api/v1/courier/jobs/{orderNumber}/accept`)**  
   When Frank's system books an order internally, it calls LidaPay with its `bookingReference` and `trackingNumber` to claim the order atomically so no other courier can take it.
3. **Send Status Updates (`POST /api/v1/courier/jobs/{orderNumber}/events`)**  
   As the parcel moves, Frank's server posts status milestones in order:
   - `picked_up` *(required first — marks the order as `shipped` in LidaPay)*
   - `out_for_delivery`
   - `delivered` *(or `delivery_exception` / `failed_delivery` if there is an issue)*
4. **Stream Live Driver GPS (`POST /api/v1/courier/jobs/{orderNumber}/location`)**  
   While the order is `shipped` (after `picked_up` and before `delivered`), Frank's system sends the driver's `latitude` and `longitude` every 5–10 seconds. The LidaPay mobile app reads these coordinates from LidaPay to move the driver pin on the customer's Google Map.

### Who does what

| Advansis Technologies / LidaPay API team | Frank's engineering team |
|---|---|
| Deploy the courier API to sandbox and production. | Build a courier client (and test in Postman/cURL) that polls available jobs and processes orders assigned to Frank. |
| Generate a distinct partner ID/secret pair for each environment, configure it on the matching API deployment, and securely share it with Frank. | Store the shared credentials in Frank's server-side secret manager; never put the secret in a mobile app, browser, logs, or source control. |
| Provide Frank the API base URL and a paid test order for end-to-end testing. | Sign every request using the shared secret, send the required HTTP headers, and keep the server clock synchronized. |
| Verify LidaPay receives accepted jobs, status events, and GPS updates; ensure customer tracking can read them. | Accept each job after booking it internally; report `picked_up` before `out_for_delivery`, send status updates, and send driver GPS during active deliveries. |
| Rotate temporary test secrets and provision permanent credentials out-of-band after sign-off. | Complete tests, report issues, and switch to permanent production credentials once both teams approve go-live. |

> **Note on Google Maps:** Google Maps does not locate the driver by itself. Frank's driver app captures the phone's GPS coordinates and sends them to LidaPay's `/location` endpoint. The LidaPay customer app then polls LidaPay (`GET /api/v1/shop/orders/{order._id}/tracking`) using its own Google Maps key to render the driver marker.

---

## 2. Understanding the Headers: Required on EVERY Request (Not Just Polling!)

> **CRITICAL RULE — Stateless Per-Request Signing:**  
> The 4 authentication headers (`X-Partner-Id`, `X-Timestamp`, `X-Event-Id`, `X-Signature`) are **required on EVERY SINGLE request** to `/api/v1/courier/*` — **not** only on the initial poll request!  
> - There is **no session cookie** or login token returned after polling.  
> - Every call — whether **polling jobs (`GET`)**, **accepting a job (`POST /accept`)**, **sending status events (`POST /events`)**, or **streaming driver GPS (`POST /location`)** — must include all 4 headers with a **fresh `X-Timestamp`**, a **new `X-Event-Id`**, and a **freshly calculated `X-Signature`** matching that specific request's method, URL path, and JSON body.

### Which Endpoints Require the Headers? (All of Them)

| Endpoint | HTTP Method | Requires `X-Partner-Id`, `X-Timestamp`, `X-Event-Id`, `X-Signature`? | Requires `Content-Type: application/json`? | What is hashed in Line 5 of the Signature? |
|---|---|---|---|---|
| `/api/v1/courier/jobs?state=available` | `GET` | **YES (Required)** | No | Empty body `""` (`e3b0c44298fc1c14...`) |
| `/api/v1/courier/jobs?state=assigned` | `GET` | **YES (Required)** | No | Empty body `""` (`e3b0c44298fc1c14...`) |
| `/api/v1/courier/jobs/{orderNumber}/accept` | `POST` | **YES (Required)** | **YES** | SHA-256 of the `/accept` raw JSON body |
| `/api/v1/courier/jobs/{orderNumber}/events` | `POST` | **YES (Required)** | **YES** | SHA-256 of the `/events` raw JSON body |
| `/api/v1/courier/jobs/{orderNumber}/location` | `POST` | **YES (Required)** | **YES** | SHA-256 of the `/location` raw JSON body |

### Where do they go?
All four authentication values go in the **HTTP Request Headers** (the **Headers** tab in Postman, or `-H` in `curl`).
- Do **not** put them in the URL query string.
- Do **not** put them inside the JSON request body.
- Do **not** use `Authorization: Bearer ...` on courier endpoints.

### The 5 Headers Explained

| Header Name | Where in Postman / cURL? | Fixed or Dynamic? | What Value Goes Here? | Example (Partner ID Masked) |
|---|---|---|---|---|
| `X-Partner-Id` | **Headers** tab (or `-H "X-Partner-Id: ..."`) | **Fixed** per environment | Your provisioned Partner ID shared out-of-band by Advansis (masked in this document as `frank-****`) | `frank-****` |
| `X-Timestamp` | Auto-set by **Pre-request Script** into **Headers** | **Dynamic** (changes every request) | Current Unix time in **seconds** (10 digits, **not** milliseconds). Must be within 5 minutes (300s) of server time. | `1793879551` |
| `X-Event-Id` | Auto-set by **Pre-request Script** into **Headers** | **Dynamic** (unique per request) | A unique ID (8–120 chars: letters, numbers, `.`, `_`, `:`, `-`). Only reuse the same ID if retrying a timed-out request. | `frank-poll-test-0001` |
| `X-Signature` | Auto-set by **Pre-request Script** into **Headers** | **Dynamic** (calculated per request) | 64-character hex `HMAC-SHA256` signature proving the request came from Frank and wasn't tampered with. | `ef3c0d076812f431...` |
| `Content-Type` | **Headers** tab (automatic when Postman Body is `raw` -> `JSON`) | Only on `POST` requests | Tells the server you are sending JSON. Not needed for `GET`. | `application/json` |

### Why can't I just copy-paste a static `X-Signature` into Postman's Headers tab?
Because `X-Signature` is mathematically tied to:
1. The current `X-Timestamp` (which expires after **5 minutes**),
2. The `X-Event-Id`,
3. The HTTP method (`GET` or `POST`),
4. The URL path + query string (e.g., `/api/v1/courier/jobs?state=available`), and
5. The exact raw JSON body.

If you change a single character in the JSON body—or wait more than 5 minutes—the signature changes. **In Postman, you solve this once by pasting a short Pre-request Script (see Section 3 below) so Postman calculates and attaches all 4 headers automatically every time you click Send.**

### How `X-Signature` is Calculated Step-by-Step

1. **Hash the raw body** with SHA-256 (lowercase hex):
   - For `GET` requests, the body is empty `""`, whose SHA-256 is always:  
     `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
   - For `POST` requests, compute the lowercase hex SHA-256 of the exact raw JSON string being sent.
2. **Join 5 lines with `\n`** (newline between each line, no trailing newline at the end):
   ```text
   <X-Timestamp>
   <X-Event-Id>
   <HTTP_METHOD_UPPERCASE>
   <path-and-query-starting-with-/api/v1/courier>
   <lowercase-sha256-hex-of-raw-body>
   ```
   *(Note: `X-Partner-Id` is sent as a header and verified by the server, while the 5 lines above are what get signed by `HMAC-SHA256`.)*
3. **Compute HMAC-SHA256** of that 5-line string using your 64-character hex `COURIER_PARTNER_SECRET` **decoded from hex into 32 raw bytes**, and output the result as a 64-character hex string.

### Partner Credentials & Environment Setup

The LidaPay backend reads `COURIER_PARTNER_ID` and `COURIER_PARTNER_SECRET` on each environment:

```text
COURIER_PARTNER_ID=frank-****
COURIER_PARTNER_SECRET=<64 hexadecimal characters: 32 random bytes>
COURIER_CARRIER_NAME=Frank Courier
```

- **Credential handling:** No reusable partner secret is included in this
  document. Advansis must provide the current partner ID and secret out-of-band.
  A temporary test secret was previously embedded here; if it was configured
  on any environment, rotate it before sharing credentials or enabling traffic.
- **Masked Partner ID (`frank-****`):**  
  Throughout this document, the partner ID is shown masked as `frank-****`. Replace `frank-****` in Postman or `curl` with the exact unmasked `COURIER_PARTNER_ID` shared with you by Advansis.

---

## 3. Connect Immediately with Postman (2-Minute Setup)

Follow these 2 setup steps once in Postman. After that, you can click **Send** on any courier endpoint and Postman will sign and attach all headers automatically.

### Step A: Create a Postman Collection & Set 4 Variables

1. Open Postman and click **New -> Collection**. Name it **`LidaPay Courier API`**.
2. Click on the **`LidaPay Courier API`** collection folder, open the **Variables** tab, and add these 4 variables:

| Variable | Initial Value / Current Value | Notes |
|---|---|---|
| `baseUrl` | `https://api.advansistechnologies.com` | Live API base URL (or `http://localhost:1124` for local dev) |
| `partnerId` | `frank-****` | **Replace `frank-****`** with the unmasked Partner ID shared by Advansis |
| `partnerSecret` | Set locally from the secure channel | Do not export or share a collection containing this value |
| `orderNumber` | `LPS261105000001` | Replace with an `orderNumber` returned from `GET /jobs?state=available` |

3. Click **Save** (`Ctrl+S` / `Cmd+S`) on the Variables tab.

### Step B: Paste the Auto-Signing Pre-request Script into the Collection

1. Still on the **`LidaPay Courier API`** collection folder, click the **Scripts** tab -> **Pre-request** (or **Pre-request Script** tab in older Postman versions).
2. Paste the following JavaScript code and click **Save**:

```javascript
// Postman Collection Pre-request Script — Auto-generates all 4 Courier Headers
const partnerId = (pm.collectionVariables.get("partnerId") || pm.environment.get("partnerId") || "").trim();
const secretHex = (pm.collectionVariables.get("partnerSecret") || pm.environment.get("partnerSecret") || "").trim();

if (!partnerId || partnerId.includes("*") || !/^[a-fA-F0-9]{64}$/.test(secretHex)) {
    throw new Error("Set your unmasked partnerId and 64-character hex partnerSecret in Postman Collection Variables first.");
}

// 1. Provide {{nowIso}} for request bodies that need an ISO-8601 timestamp
pm.collectionVariables.set("nowIso", new Date().toISOString());

// 2. Generate 10-digit Unix timestamp in seconds and a unique X-Event-Id
const timestamp = Math.floor(Date.now() / 1000).toString();
const randomSuffix = Math.random().toString(16).substring(2, 10) + Math.random().toString(16).substring(2, 6);
const retryEventId = pm.collectionVariables.get("retryEventId") || pm.environment.get("retryEventId");
const eventId = retryEventId || `frank-pm-${timestamp}-${randomSuffix}`;

// 3. Resolve path + query string (including any {{orderNumber}} variables)
const rawPathWithQuery = pm.variables.replaceIn(pm.request.url.getPathWithQuery());
const pathWithQuery = rawPathWithQuery.startsWith("/") ? rawPathWithQuery : `/${rawPathWithQuery}`;

// 4. Resolve exact raw body bytes (empty string for GET)
const method = pm.request.method.toUpperCase();
const rawBody = method === "GET"
    ? ""
    : pm.variables.replaceIn(pm.request.body && pm.request.body.raw ? pm.request.body.raw : "");

// Update the request body with resolved variables so the exact signed bytes are sent
if (method !== "GET" && pm.request.body && pm.request.body.raw) {
    pm.request.body.update(rawBody);
}

// 5. Compute SHA-256 of body and HMAC-SHA256 signature using decoded hex key
const bodyHash = CryptoJS.SHA256(rawBody).toString(CryptoJS.enc.Hex);
const canonical = [timestamp, eventId, method, pathWithQuery, bodyHash].join("\n");
const secretBytes = CryptoJS.enc.Hex.parse(secretHex);
const signature = CryptoJS.HmacSHA256(canonical, secretBytes).toString(CryptoJS.enc.Hex);

// 6. Attach the 4 required headers to the outgoing request automatically
pm.request.headers.upsert({ key: "X-Partner-Id", value: partnerId });
pm.request.headers.upsert({ key: "X-Timestamp", value: timestamp });
pm.request.headers.upsert({ key: "X-Event-Id", value: eventId });
pm.request.headers.upsert({ key: "X-Signature", value: signature });

console.log("Signed Canonical Request:\n" + canonical);
console.log("X-Signature:", signature);
```

> **How it works:** Because this script is saved on the Collection folder, **every request inside the Collection inherits it automatically**. You do **not** need to manually type `X-Partner-Id`, `X-Timestamp`, `X-Event-Id`, or `X-Signature` in the Headers tab.
>
> The script generates a fresh event ID by default. Set `retryEventId` to the original event ID only when retrying that exact timed-out status-event request, then clear it immediately.

---

## 4. API Request and Response Walkthrough

The requests below document the contract. Fixed timestamps, signatures, IDs,
and order data are historical examples; do not reuse them. The current local
isolated HTTP end-to-end test exercises poll, accept, pickup, driver location,
delivery, retry deduplication, and invalid authentication using in-memory test
data. It does **not** certify the current production deployment. A live
sandbox walkthrough requires credentials provisioned out-of-band and an
isolated paid test order.

> **Production verification gate (12 November 2026):** Signed polls to the
> documented API returned `200` for both `available` and `assigned`. The
> sampled live jobs did not include `pickupAddress`, customer destination
> latitude/longitude, or `deliveryDistance`, so they do not meet the
> branch-level job contract described below and must not be dispatched using
> this handoff. Deploy/verify the branch-level backend and create a dedicated
> paid test order with a configured shop branch and customer map pin before
> completing live sign-off. Do not accept an existing customer order as a test.

You can test these either in **Postman** (using the Pre-request Script above) or directly in your **terminal with `curl`**.

---

### Quick Terminal Test (Copy & Paste into Terminal)

To test a configured environment, load `COURIER_PARTNER_ID` and
`COURIER_PARTNER_SECRET` securely, then run this block:

```bash
export COURIER_API_BASE="https://api.advansistechnologies.com"
export COURIER_PARTNER_ID="frank-****" # <-- replace with your unmasked Partner ID
# Load COURIER_PARTNER_SECRET from your local secret manager; never paste it into this file.

TS="$(date +%s)"
EVENT_ID="frank-poll-test-0001"
PATH_QUERY="/api/v1/courier/jobs?state=available"
BODY_HASH="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

CANONICAL="$(printf '%s\n%s\nGET\n%s\n%s' "$TS" "$EVENT_ID" "$PATH_QUERY" "$BODY_HASH")"
SIG="$(printf '%s' "$CANONICAL" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$COURIER_PARTNER_SECRET" | awk '{print $NF}')"

curl -i "$COURIER_API_BASE$PATH_QUERY" \
  -H "X-Partner-Id: $COURIER_PARTNER_ID" \
  -H "X-Timestamp: $TS" \
  -H "X-Event-Id: $EVENT_ID" \
  -H "X-Signature: $SIG"
```

---

### Step 1: Poll Available Delivery Jobs (`GET`)

Frank's system polls this endpoint (e.g., every 30 seconds) to fetch up to 100 paid, unassigned orders.

#### In Postman:
- **Method:** `GET`
- **URL:** `{{baseUrl}}/api/v1/courier/jobs?state=available`
- **Body tab:** `none`
- **Historical header example (expired; generate current values with the script):**

| Header Key | Header Value |
|---|---|
| `X-Partner-Id` | `frank-****` *(unmasked ID sent in live test)* |
| `X-Timestamp` | `1793879551` |
| `X-Event-Id` | `frank-poll-test-0001` |
| `X-Signature` | `ef3c0d076812f4317366e249c1a99ae4628ae694e9a4c882fd05ffae2b82cc84` |

*(Exact 5-line canonical string that produced `ef3c0d076812f431...` with secret `78128ce1...`):*
```text
1793879551
frank-poll-test-0001
GET
/api/v1/courier/jobs?state=available
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

#### Historical response example (`HTTP/2 200`; not a current deployment check):
```http
HTTP/2 200 
content-type: application/json; charset=utf-8

{"jobs":[]}
```

When paid, unassigned orders are waiting in the queue, `"jobs"` contains:
```json
{
  "jobs": [
    {
      "_id": "66f000000000000000000001",
      "orderNumber": "LPS261105000001",
      "status": "paid",
      "currency": "GHS",
      "total": 158.58,
      "deliveryFee": 0,
      "pickupAddress": {
        "branchId": "66f000000000000000000010",
        "branchName": "East Legon Branch",
        "partnerName": "Melcom Ghana",
        "contactName": "Branch contact (when configured)",
        "phone": "Branch phone (when configured)",
        "email": "Branch email (when configured)",
        "addressLine1": "JRRQ+V32, Near Sel Filling Station, Mensah Wood Ave",
        "city": "Accra",
        "region": "Greater Accra",
        "country": "Ghana",
        "latitude": 5.6413169,
        "longitude": -0.164472
      },
      "shippingAddress": {
        "fullName": "Kofi Mensah",
        "phone": "0241120481",
        "addressLine1": "12 Osu Avenue",
        "addressLine2": "Flat 4B",
        "city": "Accra",
        "region": "Greater Accra",
        "postalCode": "GA-001",
        "country": "Ghana",
        "deliveryInstructions": "Call first",
        "latitude": 5.555,
        "longitude": -0.205
      },
      "deliveryDistance": {
        "km": 8.6,
        "durationMinutes": 24,
        "computedAt": "2026-11-05T11:50:00.000Z",
        "source": "server"
      },
      "items": [
        {
          "productId": "665e1a2b3c4d5e6f7a8b9c0d",
          "name": "Example product",
          "sku": "18339",
          "description": "Melcom catalog description with the key identifying details, such as model, size, colour, or pack quantity.",
          "price": 69.29,
          "quantity": 2,
          "images": []
        }
      ]
    }
  ]
}
```

The Melcom pickup values are provisional, transcribed from the supplied
Google Maps screenshot; the coordinate may be the map camera center rather
than the exact entrance. Do not treat this sample as a live job until the
branch has been persisted and a dedicated post-deployment test order is polled.
- **What to do next:** Copy `orderNumber` (e.g. `LPS261105000001`) into your Postman `orderNumber` variable for Steps 2–6.
- **Note on fields:** `sku` is the Melcom product code to help identify the goods (may be absent on older items; do not invent one). `description` is the catalog snapshot description.
- **Delivery pricing fields:** `pickupAddress` identifies the partner shop branch fulfilling this order (for example, Melcom East Legon), not the LidaPay/Advansis office; `shippingAddress` is the customer's destination, with required `latitude`/`longitude`. LidaPay resolves the branch from the products in the order. `deliveryDistance.km` is the server-calculated driving distance from that branch to the destination, with `durationMinutes` when available; `source` is `server`. These private pickup details are included only in the authenticated courier job response, not customer-facing order or product responses. Each order is fulfilled by one branch; mixed-branch carts are rejected at checkout and must be submitted as separate orders.
- **Quote response limitation:** Frank can use these fields to calculate its delivery price, but the current API has no endpoint for posting a quote back to LidaPay and does not update `deliveryFee` from a Frank quote. Existing accept, event, and location endpoints are unchanged. Any quote returned to the customer must use an already-agreed channel; automatically showing or charging that quote requires a separately agreed API change.

---

### Step 1b: List Currently Assigned Jobs (`GET`)

At any time, Frank's system can query all active (non-delivered, non-cancelled) orders assigned to Frank:

- **Method:** `GET`
- **URL:** `{{baseUrl}}/api/v1/courier/jobs?state=assigned`
- **Historical header example (expired; generate current values with the script):**
  - `X-Partner-Id: frank-****`
  - `X-Timestamp: 1793879584`
  - `X-Event-Id: frank-poll-assigned-0001`
  - `X-Signature: 83123d6d0dadbbe6af2247155e27227ca9326f0296ea95871001a00585263853`
- **Historical response example (`HTTP/2 200`; not a current deployment check):**
  ```json
  {"jobs":[]}
  ```

---

### Step 2: Accept a Delivery Job (`POST`)

Once Frank's system creates an internal booking for a paid order, call `/accept` to claim it atomically.

#### In Postman:
- **Method:** `POST`
- **URL:** `{{baseUrl}}/api/v1/courier/jobs/{{orderNumber}}/accept`
- **Body tab:** Select **`raw`** and choose **`JSON`** from the dropdown:
```json
{"bookingReference":"FRANK-TEST-BOOKING-001","trackingNumber":"FRANK-TEST-TRACK-001"}
```
*(Note: `bookingReference` is required; `trackingNumber` and `estimatedDeliveryDate` are optional.)*

- **Historical header example (expired; generate current values with the script):**

| Header Key | Header Value |
|---|---|
| `Content-Type` | `application/json` |
| `X-Partner-Id` | `frank-****` |
| `X-Timestamp` | `1793879683` |
| `X-Event-Id` | `frank-accept-test-0001` |
| `X-Signature` | `8bae8a40887a41041b8df6f62f85a352317b3a7474e1d217262f2002f2c2014e` |

*(Exact 5-line canonical string that produced `8bae8a40887a4104...` — note line 5 is the SHA-256 of the raw JSON body above):*
```text
1793879683
frank-accept-test-0001
POST
/api/v1/courier/jobs/LPS261105000001/accept
498b5a01abc9f5829de30468ec5a2bb49e302a135a0c248751e210fe259a1751
```

#### Historical response example:
- A previous smoke test used a placeholder order number (`LPS261105000001`) that did not exist in the DB; signature authentication passed and the service returned:
  ```json
  {"statusCode":404,"timestamp":"2026-11-05T11:55:07.377Z","path":"/api/v1/courier/jobs/LPS261105000001/accept","method":"POST","message":"Order not found"}
  ```
- When called with an available `orderNumber` from Step 1, it returns (`201 Created`):
  ```json
  {
    "accepted": true,
    "orderNumber": "LPS261105000001",
    "bookingReference": "FRANK-TEST-BOOKING-001"
  }
  ```

---

### Step 3: Report Parcel Picked Up (`POST`)

**Important:** You **must** send `status: "picked_up"` before sending `out_for_delivery`, `delivered`, or driver GPS coordinates. Reporting `picked_up` moves the LidaPay order status to `shipped`.

#### In Postman:
- **Method:** `POST`
- **URL:** `{{baseUrl}}/api/v1/courier/jobs/{{orderNumber}}/events`
- **Body tab (`raw` -> `JSON`):**
```json
{"status":"picked_up","occurredAt":"2026-11-05T12:00:00.000Z","message":"Parcel picked up from Melcom warehouse","location":"Spintex Road, Accra","trackingNumber":"FRANK-TEST-TRACK-001"}
```
*(Tip: When testing live in Postman with the Pre-request Script from Section 3, you can write `"occurredAt":"{{nowIso}}"` so Postman fills in the current ISO timestamp automatically!)*

- **Headers tab:** auto-populated with fresh values by the Pre-request Script.

| Header Key | Header Value |
|---|---|
| `Content-Type` | `application/json` |
| `X-Partner-Id` | `frank-****` |
| `X-Timestamp` | `1793879740` |
| `X-Event-Id` | `frank-event-test-0001` |
| `X-Signature` | `7f168548d8998e5b48282702caee71d348f220863e7b054c5cc0d51472d921d3` |

*(Canonical string for that signature:)*
```text
1793879740
frank-event-test-0001
POST
/api/v1/courier/jobs/LPS261105000001/events
327d50f4e252bbbd7cbf76f080cd6b7a8bce2292dfe560ecde9107c98a494809
```

#### Expected Response:
```json
{
  "accepted": true,
  "orderNumber": "LPS261105000001",
  "eventId": "frank-event-test-0001",
  "status": "picked_up"
}
```

---

### Step 4: Report Out for Delivery (`POST`)

Supported status values for `/events` are:
`packed`, `picked_up`, `out_for_delivery`, `delivered`, `delivery_exception`, `failed_delivery`

#### In Postman:
- **Method:** `POST`
- **URL:** `{{baseUrl}}/api/v1/courier/jobs/{{orderNumber}}/events`
- **Body tab (`raw` -> `JSON`):**
```json
{"status":"out_for_delivery","occurredAt":"2026-11-05T12:15:00.000Z","message":"Driver is on the way to the recipient","location":"Osu, Accra","trackingNumber":"FRANK-TEST-TRACK-001","estimatedDeliveryDate":"2026-11-05T14:00:00.000Z"}
```

- **Headers tab:** auto-populated with fresh values by the Pre-request Script.

| Header Key | Header Value |
|---|---|
| `Content-Type` | `application/json` |
| `X-Partner-Id` | `frank-****` |
| `X-Timestamp` | `1793879800` |
| `X-Event-Id` | `frank-event-test-0002` |
| `X-Signature` | `5254d4ce1cb2d03b730d79a7e7805aa87a7cfb4ad4fb852baced8b63cec1f46c` |

#### Expected Response:
```json
{
  "accepted": true,
  "orderNumber": "LPS261105000001",
  "eventId": "frank-event-test-0002",
  "status": "out_for_delivery"
}
```

---

### Step 5: Send Live Driver GPS Coordinates (`POST`)

While the order is in `shipped` status (after `picked_up` and before `delivered`), send the driver's coordinates every 5–10 seconds.

#### In Postman:
- **Method:** `POST`
- **URL:** `{{baseUrl}}/api/v1/courier/jobs/{{orderNumber}}/location`
- **Body tab (`raw` -> `JSON`):**
```json
{"latitude":5.6037,"longitude":-0.187,"recordedAt":"2026-11-05T12:15:05.000Z"}
```
*(Latitude must be `-90` to `90`; longitude `-180` to `180`; `recordedAt` is an ISO-8601 timestamp not more than 1 minute in the future.)*

- **Headers tab:** auto-populated with fresh values by the Pre-request Script.

| Header Key | Header Value |
|---|---|
| `Content-Type` | `application/json` |
| `X-Partner-Id` | `frank-****` |
| `X-Timestamp` | `1793879820` |
| `X-Event-Id` | `frank-gps-test-0001` |
| `X-Signature` | `a4c9fff7de668a66e3fa5e93b6699079bf69deb35f4e8fa76e379afb19aafb75` |

#### Expected Response:
```json
{
  "accepted": true,
  "orderNumber": "LPS261105000001",
  "recordedAt": "2026-11-05T12:15:05.000Z"
}
```
*(If an older GPS point arrives out of order, the API responds `201` with `{"accepted": true, "stale": true, "orderNumber": "..."}` and keeps the newer location.)*

---

### Step 6: Mark Order as Delivered (`POST`)

> **Warning for testing:** Once an order is marked `delivered`, it is **closed** to any further GPS or event updates. Only send `delivered` when you are ready to finish testing that order.

#### In Postman:
- **Method:** `POST`
- **URL:** `{{baseUrl}}/api/v1/courier/jobs/{{orderNumber}}/events`
- **Body tab (`raw` -> `JSON`):**
```json
{"status":"delivered","occurredAt":"{{nowIso}}","message":"Delivered to recipient Kofi Mensah","location":"12 Osu Avenue, Accra"}
```

*(Do not include proof-of-delivery photos or sensitive personal data in `message`.)*

---

## 5. Troubleshooting Common HTTP Status Codes

| Status Code | What It Means | How to Fix It |
|---|---|---|
| **`401 Unauthorized`** | Invalid partner authentication | Check that:<br>1. `X-Partner-Id` is your exact unmasked Partner ID (not `frank-****`).<br>2. `X-Timestamp` is 10-digit Unix **seconds** (not 13-digit milliseconds) and your clock is within 5 minutes of server time.<br>3. The secret was **hex-decoded** (`Buffer.from(secret, 'hex')` / `CryptoJS.enc.Hex.parse(secret)`) before computing HMAC-SHA256.<br>4. The path signed starts with `/api/v1/courier` and includes any `?state=...` query string.<br>5. The JSON body signed is byte-for-byte identical to the body sent. |
| **`404 Not Found`** | Order not found or not assigned to Frank | Signature authentication **succeeded**, but the `orderNumber` does not exist or has not been claimed via `/accept` yet. Make sure you use `orderNumber` (`LPS...`) in the URL, not the Mongo `_id`. |
| **`409 Conflict`** | Order state violation | Common causes:<br>- You sent `out_for_delivery`, `delivered`, or `/location` **before** sending `status: "picked_up"`.<br>- The order was already accepted by another booking or is already `delivered`/`cancelled`. |
| **`400 Bad Request`** | Validation error in JSON body | Check that `occurredAt` / `recordedAt` is a valid ISO-8601 timestamp and is not in the future (>60s ahead of server time). |
| **`503 Service Unavailable`** | Server credentials not configured | Advansis needs to set `COURIER_PARTNER_ID` and a 64-hex `COURIER_PARTNER_SECRET` on that API environment. |

---

## 6. Ready-to-Use Code Examples (Node.js & Bash/cURL)

### Option A: Node.js / TypeScript Helper

Drop this function into Frank's Node.js backend to make signed requests to LidaPay:

```javascript
const crypto = require('crypto');

const COURIER_API_BASE = process.env.COURIER_API_BASE || 'https://api.advansistechnologies.com';
const COURIER_PARTNER_ID = process.env.COURIER_PARTNER_ID; // Replace with your unmasked Partner ID
const COURIER_PARTNER_SECRET = process.env.COURIER_PARTNER_SECRET; // 64-char hex secret

async function callLidaPayCourierApi(method, pathWithQuery, payload = null, customEventId = null) {
  const upperMethod = method.toUpperCase();
  const rawBody = upperMethod === 'GET' || !payload ? '' : JSON.stringify(payload);
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const eventId = customEventId || `frank-${timestamp}-${crypto.randomBytes(6).toString('hex')}`;

  const bodyHash = crypto.createHash('sha256').update(rawBody).digest('hex');
  const canonical = [timestamp, eventId, upperMethod, pathWithQuery, bodyHash].join('\n');
  const signature = crypto
    .createHmac('sha256', Buffer.from(COURIER_PARTNER_SECRET, 'hex'))
    .update(canonical)
    .digest('hex');

  const headers = {
    'X-Partner-Id': COURIER_PARTNER_ID,
    'X-Timestamp': timestamp,
    'X-Event-Id': eventId,
    'X-Signature': signature,
    ...(upperMethod !== 'GET' ? { 'Content-Type': 'application/json' } : {}),
  };

  const response = await fetch(`${COURIER_API_BASE}${pathWithQuery}`, {
    method: upperMethod,
    headers,
    body: upperMethod === 'GET' ? undefined : rawBody,
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`LidaPay API ${response.status}: ${JSON.stringify(data)}`);
  }
  return data;
}

// Examples:
// 1. Poll available jobs:
// await callLidaPayCourierApi('GET', '/api/v1/courier/jobs?state=available');
//
// 2. Accept a job:
// await callLidaPayCourierApi('POST', '/api/v1/courier/jobs/LPS261105000001/accept', {
//   bookingReference: 'FRANK-BOOKING-001',
//   trackingNumber: 'FRANK-TRACK-001',
// });
```

### Option B: Bash / cURL Helper for Terminal Testing

If you prefer testing all endpoints from a terminal instead of Postman:

```bash
export COURIER_API_BASE="https://api.advansistechnologies.com"
export COURIER_PARTNER_ID="frank-****" # <-- replace with your unmasked Partner ID
# Load COURIER_PARTNER_SECRET from your local secret manager; never paste it into this file.

courier_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local event_id="${4:-frank-test-$(openssl rand -hex 8)}"
  local timestamp body_hash canonical signature

  timestamp="$(date +%s)"
  body_hash="$(printf '%s' "$body" | openssl dgst -sha256 | awk '{print $NF}')"
  canonical="$(printf '%s\n%s\n%s\n%s\n%s' \
    "$timestamp" "$event_id" "$method" "$path" "$body_hash")"
  signature="$(printf '%s' "$canonical" | \
    openssl dgst -sha256 -mac HMAC \
      -macopt hexkey:"$COURIER_PARTNER_SECRET" | awk '{print $NF}')"

  printf 'X-Timestamp: %s | X-Event-Id: %s\n' "$timestamp" "$event_id"
  printf 'X-Signature: %s\n' "$signature"

  local headers=(
    -H "X-Partner-Id: $COURIER_PARTNER_ID"
    -H "X-Timestamp: $timestamp"
    -H "X-Event-Id: $event_id"
    -H "X-Signature: $signature"
  )

  if [[ "$method" == "GET" ]]; then
    curl --fail-with-body -i "${headers[@]}" "$COURIER_API_BASE$path"
  else
    curl --fail-with-body -i "${headers[@]}" \
      -H "Content-Type: application/json" \
      --data-binary "$body" \
      "$COURIER_API_BASE$path"
  fi
}

# 1. Poll available jobs
courier_request GET '/api/v1/courier/jobs?state=available'

# 2. Poll assigned jobs
courier_request GET '/api/v1/courier/jobs?state=assigned'

# 3. Accept a job (replace LPS261105000001 with an orderNumber from Step 1)
courier_request POST \
  '/api/v1/courier/jobs/LPS261105000001/accept' \
  '{"bookingReference":"FRANK-TEST-BOOKING-001","trackingNumber":"FRANK-TEST-TRACK-001"}'

# 4. Report pickup first (changes order status to shipped)
courier_request POST \
  '/api/v1/courier/jobs/LPS261105000001/events' \
  "{\"status\":\"picked_up\",\"occurredAt\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"message\":\"Parcel picked up\",\"trackingNumber\":\"FRANK-TEST-TRACK-001\"}"

# 5. Report out for delivery
courier_request POST \
  '/api/v1/courier/jobs/LPS261105000001/events' \
  "{\"status\":\"out_for_delivery\",\"occurredAt\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"message\":\"Driver is on the way\",\"trackingNumber\":\"FRANK-TEST-TRACK-001\"}"

# 6. Send GPS location
courier_request POST \
  '/api/v1/courier/jobs/LPS261105000001/location' \
  "{\"latitude\":5.6037,\"longitude\":-0.187,\"recordedAt\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
```

### How Retries Work (Idempotency)
If a network timeout happens while sending a status event, retry the **exact same JSON body** using the **same `X-Event-Id`**, with a fresh `X-Timestamp` and freshly calculated `X-Signature`. LidaPay deduplicates status events by `X-Event-Id` and responds `201` with `"duplicate": true` instead of creating a duplicate timeline entry.

---

## 7. How the LidaPay Mobile App Uses This Data

Frank's system **only** calls `/api/v1/courier/...` endpoints. The LidaPay mobile app never calls Frank's servers directly and never holds courier credentials. Instead, when the customer opens the **Track Order** screen, the mobile app calls:

```http
GET /api/v1/shop/orders/{order._id}/tracking
Authorization: Bearer <customer-access-token>
```
*(Uses the order's Mongo `_id`, not `orderNumber`.)*

Response returned to the customer's app:
```json
{
  "_id": "66f000000000000000000001",
  "orderNumber": "LPS261105000001",
  "status": "shipped",
  "carrier": "Frank Courier",
  "trackingNumber": "FRANK-TRACK-0001",
  "estimatedDeliveryDate": "2026-11-05T14:00:00.000Z",
  "deliveredAt": null,
  "lastDriverLocation": {
    "latitude": 5.6037,
    "longitude": -0.187,
    "recordedAt": "2026-11-05T12:15:05.000Z"
  },
  "deliveryUpdates": [
    {
      "status": "courier_accepted",
      "message": "Courier accepted the delivery job",
      "timestamp": "2026-11-05T11:45:00.000Z"
    },
    {
      "status": "picked_up",
      "message": "Parcel picked up from Melcom warehouse",
      "location": "Spintex Road, Accra",
      "timestamp": "2026-11-05T12:00:00.000Z"
    },
    {
      "status": "out_for_delivery",
      "message": "Driver is on the way to the recipient",
      "location": "Osu, Accra",
      "timestamp": "2026-11-05T12:15:00.000Z"
    }
  ]
}
```

### What the LidaPay Mobile App Does on the Tracking Screen
1. **Live Driver Pin on Google Maps (`lastDriverLocation`):** Uses LidaPay's restricted Google Maps SDK key to display and move the driver marker at `latitude`/`longitude` while `status === "shipped"`, along with a *"Last updated X seconds ago"* badge from `recordedAt`.
2. **Polls Every 5–10 Seconds While Open:** Refreshes `GET /api/v1/shop/orders/{order._id}/tracking` every 5–10 seconds while the customer is actively viewing the screen, and stops polling immediately when the screen closes or the order reaches `delivered`/`cancelled`.
3. **Renders the Delivery Timeline (`deliveryUpdates`):** Displays the step-by-step history (`courier_accepted` → `packed` → `picked_up` → `out_for_delivery` → `delivered`, or `delivery_exception`/`failed_delivery`) with `message`, `location`, and `timestamp`.
4. **Shows Carrier & ETA Header:** Displays `carrier`, `trackingNumber`, and `estimatedDeliveryDate` (or `deliveredAt`).

### Existing Routes That Are NOT for Frank's System
- `POST /api/v1/shop/checkout` — Customer checkout route, not a courier endpoint.
- `GET /api/v1/shop/orders/{id}/tracking` — Customer-only read endpoint.
- `PUT /api/v1/shop/admin/orders/{id}/delivery` — Internal LidaPay admin route; Frank must not call it.
- `GET /api/v1/shop/orders/number/{orderNumber}` — Customer/public lookup; do not use to fetch courier jobs.

---

## 8. Go-Live Checklist

Before switching to permanent production credentials, both teams should confirm:

1. Temporary test secret (`78128ce1...`) is rotated and replaced with a unique permanent 64-hex `COURIER_PARTNER_SECRET` shared securely out-of-band.
2. Signed job polling (`available` & `assigned`), job acceptance, status events (`picked_up` -> `out_for_delivery` -> `delivered`), idempotent retries, and live GPS updates have been verified end-to-end.
3. Service coverage, pickup procedures, delivery pricing, SLA, exception statuses, support contacts, and proof-of-delivery procedures are agreed.
4. Frank's driver app captures and transmits GPS coordinates every 5–10 seconds only during active (`shipped`) deliveries.
5. The LidaPay mobile app polls the customer tracking route using its restricted Google Maps key to move the driver marker.

**Contact:** Advansis Technologies / LidaPay  
**Website:** `https://advansistechnologies.com`  
**Interactive Swagger Docs:** `https://api.advansistechnologies.com/api-doc`
