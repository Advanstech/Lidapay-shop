# Swagger API Documentation Guide
## Complete API Reference for Frontend Engineers

**Date:** 2026-03-01  
**Priority:** HIGH - Required for Implementation  
**Base URL:** `https://api.advansistechnologies.com` (Production) / `http://localhost:1124` (Development)  

---

## �️ **System & Diagnostics**

### **Verify Environment Variables**
**GET** `/system/verify-env`

#### **Auth:** Bearer token required

#### **Response:**
```json
{
  "recipientChoiceEnabled": true,
  "timeoutWorkerEnabled": true,
  "timeoutSeconds": "180",
  "nodeEnv": "production",
  "firebaseProjectId": true,
  "firebaseServiceAccountBase64": true,
  "firebaseClientEmail": true,
  "firebasePrivateKey": true,
  "googleAppCreds": false
}
```

### **System Health Check**
**GET** `/system/health`

#### **Auth:** Bearer token required

#### **Response:**
```json
{
  "status": "healthy",
  "timestamp": "2026-03-11T12:42:09.000Z",
  "environment": {
    "recipientChoiceEnabled": true,
    "timeoutWorkerEnabled": true,
    "firebaseConfigured": true
  },
  "warnings": []
}
```

## �🔐 **Authentication Endpoints**

### **User Login**
**POST** `/api/v1/users/login`

#### **Request Body:**
```json
{
  "username": "0244588584",
  "password": "digimas@14",
  "deviceToken": "f3H9CNR6RXqRwxPC-1BImM:APA91bFJvYosF3zKFGAFTPyx5GDLxjqXdjbQkUAUk3OUA9Ts_O6QedoCePh5pJMs0te2Uppm78GSQQ1JoooyPKBO_kRw5S7iHRHqerzS",
  "devicePlatform": "ANDROID",
  "deviceId": "abc123-device-id-12345",
  "appVersion": "1.2.3",
  "locale": "en-GH"
}
```

#### **Required Fields:**
- `username` (string): Phone number, email, or username
- `password` (string): User password (min 6 chars)

#### **Optional Fields (for FCM):**
- `deviceToken` (string): FCM token from Firebase
- `devicePlatform` (string): "ANDROID", "IOS", or "WEB"
- `deviceId` (string): Unique device identifier
- `appVersion` (string): App version
- `locale` (string): Device locale

#### **Response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6IjAyNDQ1ODg1ODQiLCJzdWIiOiI2NzQ5ZjEwNDhlNjI5ZTQ3ZWEwZmJlNmMiLCJpYXQiOjE3MDkyNzU0MDAsImV4cCI6MTcwOTI3OTAwMH0.signature",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6IjAyNDQ1ODg1ODQiLCJzdWIiOiI2NzQ5ZjEwNDhlNjI5ZTQ3ZWEwZmJlNmMiLCJpYXQiOjE3MDkyNzU0MDAsImV4cCI6MTcxMTg2NzQwMH0.signature",
  "user": {
    "_id": "6749f1048e629e47ea0fbe6c",
    "username": "0244588584",
    "email": "user@example.com",
    "phoneNumber": "0244588584",
    "firstName": "John",
    "lastName": "Doe",
    "country": "Ghana",
    "roles": ["user"],
    "status": "ACTIVE",
    "createdAt": "2026-03-01T10:00:00.000Z",
    "updatedAt": "2026-03-01T10:00:00.000Z"
  }
}
```

---

### **Refresh Tokens (Mobile Contract)**
**POST** `/api/v1/auth/refresh`

#### **Request Body:**
```json
{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.refresh..."
}
```

#### **Response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.new-access...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.new-refresh...",
  "user": {
    "_id": "6749f1048e629e47ea0fbe6c",
    "username": "0244588584",
    "phoneNumber": "0244588584",
    "roles": ["user"]
  }
}
```

#### **Note:**
- Legacy `POST /api/v1/users/refresh-token` is deprecated for mobile clients.

---

### **User Registration**
**POST** `/api/v1/users/register`

#### **Request Body:**
```json
{
  "firstName": "John",
  "lastName": "Doe",
  "email": "john.doe@example.com",
  "phoneNumber": "0244588584",
  "password": "securePassword123",
  "country": "Ghana",
  "roles": ["user"],
  "deviceToken": "f3H9CNR6RXqRwxPC-1BImM:APA91bFJvYosF3zKFGAFTPyx5GDLxjqXdjbQkUAUk3OUA9Ts_O6QedoCePh5pJMs0te2Uppm78GSQQ1JoooyPKBO_kRw5S7iHRHqerzS",
  "devicePlatform": "ANDROID",
  "deviceId": "abc123-device-id-12345",
  "appVersion": "1.2.3",
  "locale": "en-GH"
}
```

#### **Required Fields:**
- `firstName` (string): User first name
- `lastName` (string): User last name
- `email` (string): Valid email address
- `phoneNumber` (string): Ghana format (0xxxxxxxx)
- `password` (string): Password (min 6 chars)
- `country` (string): Full country name
- `roles` (array): User roles, typically ["user"]

#### **Optional Fields (for FCM):**
- Same as login endpoint

#### **Response:**
```json
{
  "_id": "6749f1048e629e47ea0fbe6d",
  "username": "0244588584",
  "email": "john.doe@example.com",
  "phoneNumber": "0244588584",
  "firstName": "John",
  "lastName": "Doe",
  "country": "Ghana",
  "roles": ["user"],
  "status": "ACTIVE",
  "points": 0,
  "createdAt": "2026-03-01T10:00:00.000Z",
  "updatedAt": "2026-03-01T10:00:00.000Z"
}
```

---

## 📱 **Device Token Management**

### **1. Register Device Token**
**POST** `/api/v1/notifications/device-token`

Alias routes:
- `POST /api/v1/notifications/push-token`
- `POST /api/v1/users/push-token` (legacy compatibility)

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

#### **Request Body:**
```json
{
  "token": "f3H9CNR6RXqRwxPC-1BImM:APA91bFJvYosF3zKFGAFTPyx5GDLxjqXdjbQkUAUk3OUA9Ts_O6QedoCePh5pJMs0te2Uppm78GSQQ1JoooyPKBO_kRw5S7iHRHqerzS",
  "platform": "ANDROID",
  "provider": "FCM",
  "deviceId": "abc123-device-id-12345",
  "appVersion": "1.2.3",
  "locale": "en-GH"
}
```

#### **Required Fields:**
- At least one of `token` or `deviceToken`
- At least one of `platform` or `devicePlatform`

#### **Optional Fields:**
- `provider` (string): "FCM", "APNS", or "WEB" (default: "FCM")
- `deviceId` (string): Unique device identifier
- `appVersion` (string): App version
- `locale` (string): Device locale

#### **Legacy-compatible Payload (also accepted):**
```json
{
  "deviceToken": "f3H9CNR6RXqRwxPC-1BImM:APA91b...",
  "devicePlatform": "ANDROID",
  "provider": "FCM",
  "deviceId": "abc123-device-id-12345"
}
```

#### **Response:**
```json
{
  "success": true,
  "message": "Device token registered successfully",
  "data": {
    "isActive": true,
    "userId": "6749f1048e629e47ea0fbe6c",
    "token": "f3H9CNR6RXqRwxPC-1BImM:APA91bFJvYosF3zKFGAFTPyx5GDLxjqXdjbQkUAUk3OUA9Ts_O6QedoCePh5pJMs0te2Uppm78GSQQ1JoooyPKBO_kRw5S7iHRHqerzS",
    "platform": "ANDROID",
    "registeredAt": "2026-03-01T10:00:00.000Z"
  }
}
```

---

### **2. Get Active Device Tokens**
**GET** `/api/v1/notifications/device-token`

#### **Headers:**
```
Authorization: Bearer {access_token}
```

#### **Response:**
```json
{
  "success": true,
  "message": "Active device tokens retrieved",
  "data": {
    "userId": "6749f1048e629e47ea0fbe6c",
    "tokens": [
      {
        "token": "f3H9CNR6RXqRwxPC-1BImM:APA91bFJvYosF3zKFGAFTPyx5GDLxjqXdjbQkUAUk3OUA9Ts_O6QedoCePh5pJMs0te2Uppm78GSQQ1JoooyPKBO_kRw5S7iHRHqerzS",
        "platform": "ANDROID",
        "deviceId": "abc123-device-id-12345",
        "appVersion": "1.2.3",
        "locale": "en-GH",
        "isActive": true,
        "lastSeenAt": "2026-03-01T10:00:00.000Z",
        "createdAt": "2026-03-01T09:00:00.000Z"
      }
    ],
    "total": 1
  }
}
```

---

### **3. Deactivate Device Token**
**DELETE** `/api/v1/notifications/device-token`

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

#### **Request Body:**
```json
{
  "token": "f3H9CNR6RXqRwxPC-1BImM:APA91bFJvYosF3zKFGAFTPyx5GDLxjqXdjbQkUAUk3OUA9Ts_O6QedoCePh5pJMs0te2Uppm78GSQQ1JoooyPKBO_kRw5S7iHRHqerzS"
}
```

#### **Response:**
```json
{
  "success": true,
  "message": "Device token deactivated"
}
```

---

## � **Internet Data (One4All)**

### **1. Buy Internet Data**
**POST** `/api/v1/internet/buydata`

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

#### **Request Body:**
```json
{
  "userId": "USER123",
  "userName": "Sender",
  "recipientNumber": "0244588584",
  "dataCode": "DATA_10GB",
  "network": 4,
  "amount": 10,
  "currency": "GHS",
  "saveToLidaValue": false,
  "isSelfTopup": false
}
```

#### **Required Fields:**
- `recipientNumber` (string): Recipient number
- `dataCode` (string): Data bundle code
- `network` (number): Network code (0-9)

#### **Optional Fields:**
- `userId` (string): Optional sender user id (server overrides from auth token)
- `userName` (string): Optional sender username (server overrides from auth token)
- `amount` (number): Amount in GHS (if required by bundle)
- `currency` (string): Currency code (default: GHS)
- `saveToLidaValue` (boolean): Save value to wallet instead of direct delivery
- `isSelfTopup` (boolean): `true` for USE (self), `false` for SEND (recipient choice)

#### **Response - Direct Delivery (USE or unregistered recipient):**
```json
{
  "status": "00",
  "message": "Data bundle purchase successful",
  "trxn": "LDP-123",
  "balance_after": "90.00"
}
```

#### **Response - Recipient Decision Required (SEND to registered recipient):**
```json
{
  "status": "PENDING",
  "message": "Recipient decision required",
  "topupOrderId": "LDP-1772140",
  "decisionId": "DEC-56789",
  "expiresAt": "2026-02-27T14:25:00Z",
  "serviceType": "DATA"
}
```

---

### **2. List Data Bundles**
**POST** `/api/v1/internet/bundlelist`

#### **Request Body:**
```json
{
  "network": 4
}
```

#### **Optional Fields:**
- `network` (number): Network code. Omit or use 0 for all networks.

#### **Response:**
```json
{
  "success": true,
  "bundles": [
    { "id": "DATA_5GB", "name": "5GB Bundle", "price": 5, "dataAmount": "5GB" },
    { "id": "DATA_10GB", "name": "10GB Bundle", "price": 10, "dataAmount": "10GB" }
  ]
}
```

---

## �� **Recipient Choice Endpoints**

### **1. Check Recipient Eligibility**
**POST** `/api/v1/recipient/eligibility`

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

#### **Request Body:**
```json
{
  "recipientPhone": "0244588584",
  "countryIsoCode": "GH",
  "serviceType": "AIRTIME"
}
```

#### **Required Fields:**
- `recipientPhone` (string): Phone number (supports: 0xxxxxxxx, 233xxxxxxxx, +233xxxxxxxx)
- `serviceType` (string): "AIRTIME" or "DATA"

#### **Optional Fields:**
- `countryIsoCode` (string): Country code (default: "GH")

#### **Response - Registered Recipient:**
```json
{
  "isRegistered": true,
  "recipientUserId": "6749f1048e629e47ea0fbe6c",
  "canPromptChoice": true,
  "defaultChoice": "LIDA_VALUE",
  "timeoutSeconds": 180,
  "serviceType": "AIRTIME"
}
```

#### **Response - Unregistered Recipient:**
```json
{
  "isRegistered": false,
  "recipientUserId": null,
  "canPromptChoice": false,
  "serviceType": "AIRTIME"
}
```

---

### **2. Create Recipient Decision**
**POST** `/api/v1/topups/{topupOrderId}/recipient-decision`

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
X-Idempotency-Key: unique-request-id (optional)
```

#### **Request Body:**
```json
{
  "recipientPhone": "0244588584",
  "amount": 10.0,
  "serviceType": "AIRTIME",
  "timeoutSeconds": 180
}
```

#### **Required Fields:**
- `recipientPhone` (string): Phone number
- `amount` (number): Amount being sent
- `serviceType` (string): "AIRTIME" or "DATA"

#### **Optional Fields:**
- `timeoutSeconds` (number): Timeout in seconds (default: 180)

#### **Response:**
```json
{
  "decisionId": "TXN-MM6IM2CV-B70B4DE9",
  "topupOrderId": "TXN-MM6IM1LW-718F6908",
  "recipientPhone": "0244588584",
  "recipientUserId": "6749f1048e629e47ea0fbe6c",
  "amount": 10.0,
  "serviceType": "AIRTIME",
  "status": "PENDING",
  "createdAt": "2026-03-01T10:00:00.000Z",
  "expiresAt": "2026-03-01T10:03:00.000Z"
}
```

---

### **3. Respond to Recipient Decision**
**POST** `/api/v1/recipient-decisions/{decisionId}/respond`

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

#### **Request Body:**
```json
{
  "choice": "DIRECT"
}
```

#### **Required Fields:**
- `choice` (string): "DIRECT" or "LIDA_VALUE"

#### **Response:**
```json
{
  "decisionId": "TXN-MM6IM2CV-B70B4DE9",
  "selectedChoice": "DIRECT",
  "status": "RESOLVED",
  "resolvedSource": "RECIPIENT",
  "finalDisposition": "DELIVERED_DIRECT",
  "resolvedAt": "2026-03-01T10:01:30.000Z",
  "deliveryResult": {
    "topupOrderId": "TXN-MM6IM1LW-718F6908",
    "state": "DELIVERED_DIRECT",
    "resolvedSource": "RECIPIENT"
  }
}
```

---

## AdGenie SaaS Payments (AdvansisPay)

### Initiate an AdGenie checkout

**POST** `/api/v1/advansispay/adgenie/initiate-payment`

Server-to-server only. AdGenie's backend calls this route; never call it from
browser JavaScript or Android/iOS apps.

#### Headers

| Header | Required | Description |
|---|---:|---|
| `x-api-key` | yes | Dedicated AdGenie key provisioned by the AdvansisPay API operator. Keep it in AdGenie's backend production secret store. |
| `Content-Type` | yes | `application/json` |

#### Request body

```json
{
  "firstName": "Ama",
  "lastName": "Mensah",
  "email": "ama@example.com",
  "phoneNumber": "0244123456",
  "amount": 99,
  "customerReference": "adgenie-user-84721",
  "orderDesc": "AdGenie Pro monthly subscription",
  "returnUrl": "https://app.adgenie.example/billing/return",
  "webhookUrl": "https://api.adgenie.example/webhooks/advansispay",
  "webhookSecret": "<AdGenie-generated backend secret>",
  "orderImgUrl": "https://app.adgenie.example/assets/adgenie-logo.png",
  "payTransRef": "ADG-20261027-84721"
}
```

| Property | Required | Validation / meaning |
|---|---:|---|
| `firstName` | yes | String, 2–50 characters. |
| `lastName` | yes | String, 2–50 characters. |
| `email` | yes | Valid email address. |
| `phoneNumber` | yes | 10–15 digits, optionally prefixed with `+`. |
| `amount` | yes | Number, at least 1; GHS. AdGenie's backend calculates this from its plan, not from an untrusted app value. |
| `customerReference` | yes | AdGenie-owned stable customer reference, 1–100 characters; not a LidaPay user ID. |
| `orderDesc` | no | Checkout description, up to 200 characters. |
| `returnUrl` | no | HTTPS return URL or an app link/scheme explicitly approved in the API callback allowlist. |
| `webhookUrl` | no | HTTPS endpoint for final payment notification; host must be allowlisted. |
| `webhookSecret` | no | 8–128 character secret used for the webhook HMAC. Send only from AdGenie's backend and never log or expose it in an app. |
| `orderImgUrl` | no | HTTPS image URL. |
| `payTransRef` | no | AdGenie payment reference, 1–150 characters. Use a unique value per billing attempt. |

The settlement `accountNumber` is deliberately not a request property. The
AdvansisPay operator configures `ADGENIE_ADVANSIS_ACCOUNT_NUMBER` on the API
service so a client cannot redirect funds to another account.

#### Success response — HTTP 201

```json
{
  "checkoutUrl": "https://expresspaygh.com/api/checkout.php?token=...",
  "token": "<provider-token>",
  "order-id": "ADV-M2NN2COD-11D269AA"
}
```

Persist `token` and `order-id` against AdGenie's pending billing record, then
send only the hosted `checkoutUrl` and an AdGenie payment identifier to the
client. This response means checkout was created, not that payment succeeded.

#### Error responses

Invalid input or callback URL not allowlisted — HTTP 400:

```json
{
  "statusCode": 400,
  "message": "webhookUrl host is not on the payment callback allowlist",
  "error": "Bad Request"
}
```

Missing or invalid partner key — HTTP 401:

```json
{
  "statusCode": 401,
  "message": "Invalid AdGenie API key",
  "error": "Unauthorized"
}
```

AdGenie integration not configured on the API service — HTTP 503:

```json
{
  "statusCode": 503,
  "message": "AdGenie payment integration is not configured",
  "error": "Service Unavailable"
}
```

Provider or server error — HTTP 500:

```json
{
  "statusCode": 500,
  "message": "Payment initiation failed",
  "error": "Internal Server Error"
}
```

#### Callback and payment verification

The return URL may receive `orderId`, `token`, `status`, `transactionId`, and
`timestamp`. Treat redirect parameters as untrusted; do not activate a
subscription from the redirect. Verify the final result through the signed
webhook and/or the server-side transaction query. The API's webhook payload,
signature, query example, and mobile return setup are covered in
[ADVANSISPAY_ADGENIE_PARTNER_INTEGRATION.md](./ADVANSISPAY_ADGENIE_PARTNER_INTEGRATION.md).

## 🏦 **GTBank Payment Integration (GTPay)**

### **1. List Available Services**
**GET** `/api/v1/gtpay/services`

#### **Headers:**
```
Authorization: Bearer {access_token}
```

#### **Description:**
Lists all services available on the GTBank Partner API. No query params or request body. Internally the app POSTs to GTBank `/services/query` with `ServiceName: "services"`.

#### **Request Body:**
None. Use GET with an empty body.

#### **Response:**
```json
{
  "status": 200,
  "message": "Services retrieved successfully.",
  "data": {
    "Status": "00",
    "Message": "Successful",
    "Data": {
      "services": [
        {
          "ServiceName": "creditwallet",
          "Description": "Credit GTBank Wallet",
          "Enabled": true
        },
        {
          "ServiceName": "banktrf",
          "Description": "Bank Transfer",
          "Enabled": true
        },
        {
          "ServiceName": "airtime",
          "Description": "Airtime Top-up",
          "Enabled": true
        }
      ]
    }
  }
}
```

---

### **2. Query Service / Verify Account**
**POST** `/api/v1/gtpay/query`

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

#### **Description:**
Verifies customer details on a service (e.g., bank account validation, mobile money account verification) or checks account balance when ServiceName is 'balance'.

#### **Request Body:**
```json
{
  "PartnerTransId": "2022011800004",
  "ServiceName": "creditwallet",
  "ServiceNumber": "0241120481",
  "SecondaryServiceNumber": ""
}
```

#### **Required Fields:**
- `ServiceName` (string): Service to query (e.g., 'services', 'balance', 'creditwallet', 'banktrf', 'airtime')

#### **Optional Fields:**
- `PartnerTransId` (string): Unique transaction reference (max 20 chars, auto-generated if omitted)
- `ServiceNumber` (string): Account/service identifier (bank account, mobile money number, wallet number)
- `SecondaryServiceNumber` (string): Extra verification data (e.g., bank sort code)

#### **Response:**
```json
{
  "status": 200,
  "message": "Query processed successfully.",
  "data": {
    "Status": "00",
    "Message": "Successful",
    "Data": {
      "AccountName": "JOHN DOE",
      "AccountNumber": "0241120481",
      "AccountBalance": "100.50"
    }
  }
}
```

---

### **3. Initiate Payment**
**POST** `/api/v1/gtpay/pay`

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

#### **Description:**
Initiates a payment or completes a merchant transaction on the GTBank Partner API. The endpoint returns immediately with a pending status; final status is delivered via callback.

#### **Request Body:**
```json
{
  "PartnerTransId": "2022011800011",
  "CallbackURL": "https://api.advansistechnologies.com/api/v1/gtpay/callback",
  "ServiceDetails": {
    "ServiceName": "creditwallet",
    "ServiceNumber": "0241120481",
    "SecondaryServiceNumber": "",
    "Amount": 10.50,
    "Remarks": "Lidapay wallet top-up",
    "PaymentMethod": "credit_account",
    "Payer": {
      "Name": "Kofi Owusu",
      "PhoneNumber": "0241120481",
      "Email": "kofi.owusu@example.com"
    }
  }
}
```

#### **Required Fields:**
- `ServiceDetails.ServiceName` (string): Service being paid for
- `ServiceDetails.ServiceNumber` (string): Account number/identifier
- `ServiceDetails.Amount` (number): Payment amount

#### **Optional Fields:**
- `PartnerTransId` (string): Unique transaction reference (auto-generated if omitted)
- `CallbackURL` (string): URL for async status updates (defaults to system callback URL)
- `ServiceDetails.SecondaryServiceNumber` (string): Additional service identifier
- `ServiceDetails.Remarks` (string): Transaction notes
- `ServiceDetails.PaymentMethod` (string): Payment method (e.g., 'credit_account')
- `ServiceDetails.Payer` (object): Payer information (Name, PhoneNumber, Email)

#### **Response:**
```json
{
  "status": 200,
  "message": "Payment initiated successfully.",
  "data": {
    "Status": "02",
    "Message": "Transaction pending",
    "GTBTransId": "10462602201180001",
    "PartnerTransId": "2022011800011"
  }
}
```

#### **Callback Payload (sent to CallbackURL when payment completes):**
```json
{
  "SecureHash": "6ec91f1f96d0869e0fcef11e4f44337084bc0c43f2deadd35cbb433dcc",
  "GTBTransId": "10462602201180001",
  "PartnerTransId": "2022011800011",
  "ProviderTransId": "",
  "Status": "COMPLETED",
  "Message": "Payment successful",
  "Data": {}
}
```

---

### **4. Query Transaction Status**
**POST** `/api/v1/gtpay/status`

#### **Headers:**
```
Authorization: Bearer {access_token}
Content-Type: application/json
```

#### **Description:**
Queries the current status of a previously initiated transaction.

#### **Request Body:**
```json
{
  "PartnerTransId": "202201140008"
}
```

#### **Required Fields:**
- `PartnerTransId` (string): The transaction reference used in the original /pay call

#### **Response:**
```json
{
  "status": 200,
  "message": "Status retrieved successfully.",
  "data": {
    "Status": "00",
    "Message": "Transaction completed",
    "GTBTransId": "10462602201180001",
    "PartnerTransId": "202201140008",
    "Amount": "10.50",
    "TransactionDate": "2026-08-13T14:30:00Z"
  }
}
```

---

### **5. List Supported Banks**
**GET** `/api/v1/gtpay/banks`

#### **Headers:**
```
Authorization: Bearer {access_token}
```

#### **Description:**
Retrieves a list of banks supported for bank transfer services. No query params or request body. Internally the app POSTs to GTBank `/services/query` with `ServiceName: "banks"`.

#### **Request Body:**
None. Use GET with an empty body.

#### **Response:**
```json
{
  "status": 200,
  "message": "Banks retrieved successfully.",
  "data": {
    "Status": "00",
    "Message": "Successful",
    "Data": {
      "banks": [
        {
          "BankCode": "030100",
          "BankName": "GTBank Ghana",
          "SortCode": "030100"
        },
        {
          "BankCode": "040101",
          "BankName": "Ecobank Ghana",
          "SortCode": "040101"
        }
      ]
    }
  }
}
```

---

### **6. Receive Async Callback (Internal)**
**POST** `/api/v1/gtpay/callback`

#### **Description:**
Internal endpoint for receiving async transaction status updates from GTBank. This endpoint is called by GTBank, not by client applications.

**Security:** All callbacks are verified using HMAC-SHA256 SecureHash before processing. Invalid or missing hash results in 400 Bad Request.

#### **Request Body (sent by GTBank):**
```json
{
  "SecureHash": "6ec91f1f96d0869e0fcef11e4f44337084bc0c43f2deadd35cbb433dcc",
  "GTBTransId": "10462602201180001",
  "PartnerTransId": "2022011800011",
  "ProviderTransId": "",
  "Status": "COMPLETED",
  "Message": "Payment successful",
  "Data": {}
}
```

#### **Response:**
```json
{
  "success": true,
  "partnerTransId": "2022011800011",
  "gtbTransId": "10462602201180001",
  "status": "COMPLETED",
  "message": "Payment successful"
}
```

---

### **GTBank Payment Integration Notes:**

#### **Transaction Flow:**
1. **Discover Services**: Call `/gtpay/services` to get available payment services
2. **Verify Account**: Call `/gtpay/query` to validate recipient account details
3. **Initiate Payment**: Call `/gtpay/pay` with payment details
4. **Monitor Status**: Either wait for callback or poll `/gtpay/status`
5. **Handle Callback**: Backend receives async update from GTBank at `/gtpay/callback`

#### **Status Codes:**
- `00` - Successful
- `02` - Transaction pending
- `03` - Transaction failed
- `99` - Unknown error

#### **Security:**
- All requests use Basic Auth with GT_USERNAME and GT_PASSWORD
- Payment requests include HMAC-SHA256 SecureHash for integrity
- Callbacks are verified using SecureHash before processing

#### **Error Handling:**
```json
{
  "statusCode": 400,
  "message": "PAYMENT_INITIATION_FAILED: Insufficient funds",
  "error": "Bad Request",
  "code": "PAYMENT_INITIATION_FAILED",
  "details": {
    "PartnerTransId": "2022011800011"
  }
}
```

#### **Common Error Codes:**
- `SERVICES_QUERY_FAILED` - Failed to retrieve service list
- `CUSTOMER_QUERY_FAILED` - Account verification failed
- `PAYMENT_INITIATION_FAILED` - Payment request failed
- `STATUS_QUERY_FAILED` - Status check failed
- `BANKS_QUERY_FAILED` - Bank list retrieval failed

---

## �️ **Shop — E-Commerce Module**

Base path: `/api/v1/shop`. Live interactive docs: `/api-doc` (Shop tag).

### **Authentication**
- **Public endpoints** (browse only): product/category listing, product details, order lookup by number — no token needed.
- **Customer endpoints** (cart, checkout, orders): `Authorization: Bearer {access_token}` from `/api/v1/auth/access-token`.
- **Admin endpoints** (`/admin/*`): Bearer token. (Role check recommended before production use.)

---

### **1. Browse Categories**
**GET** `/api/v1/shop/categories`

Optional query: `?activeOnly=true`

#### **Response:**
```json
[
  { "_id": "665e1a2b...", "name": "Electronics", "description": "Gadgets", "active": true, "sortOrder": 0 }
]
```

---

### **2. Browse Products**
**GET** `/api/v1/shop/products`

Query params (all optional):

| Param | Example | Notes |
|---|---|---|
| `page` | `1` | default 1 |
| `limit` | `20` | default 20, max 100 |
| `category` | `665e1a2b...` | Category ObjectId |
| `search` | `samsung` | full-text on name/description/brand |
| `featured` | `true` | featured only |
| `sortBy` | `price` | default `createdAt` |
| `sortOrder` | `asc`/`desc` | default desc |

#### **Response:**
```json
{
  "products": [
    {
      "_id": "665f0a...",
      "name": "Samsung Galaxy A05",
      "price": 850,
      "discountPrice": 790,
      "stock": 50,
      "images": ["https://cdn..."],
      "featured": false,
      "category": { "_id": "665e1a...", "name": "Electronics" }
    }
  ],
  "total": 120,
  "page": 1,
  "totalPages": 6
}
```

**Featured shortcut:** `GET /api/v1/shop/products/featured`

**Product detail:** `GET /api/v1/shop/products/{id}`

---

### **3. Cart (auth required)**

**Get cart with summary:**
```
GET /api/v1/shop/cart
```
```json
{
  "items": [ { "productId": "665f0a...", "name": "Samsung Galaxy A05", "price": 850, "discountPrice": 790, "quantity": 2, "image": ["https://cdn..."] } ],
  "itemCount": 2,
  "subtotal": 1700,
  "discount": 120,
  "total": 1580
}
```

**Add to cart:**
```
POST /api/v1/shop/cart/add
```
```json
{ "productId": "665f0a...", "quantity": 2 }
```

**Update quantity:**
```
PUT /api/v1/shop/cart/update
```
```json
{ "productId": "665f0a...", "quantity": 3 }
```

**Remove item:**
```
POST /api/v1/shop/cart/remove
```
```json
{ "productId": "665f0a..." }
```

**Clear cart:** `DELETE /api/v1/shop/cart/clear`

---

### **4. Checkout (auth required)**
```
POST /api/v1/shop/checkout
```

```json
{
  "shippingAddress": {
    "fullName": "Kofi Mensah",
    "phone": "0241120481",
    "email": "kofi@example.com",
    "addressLine1": "12 Osu Avenue, Ringway Estates",
    "city": "Accra",
    "region": "Greater Accra",
    "country": "Ghana",
    "deliveryInstructions": "Call before delivery"
  },
  "paymentMethod": "momo"
}
```

#### **Response (order created, status `pending`, paymentStatus `pending`):**
```json
{
  "orderNumber": "LPS260907123456",
  "items": [ { "productId": "665f0a...", "name": "Samsung Galaxy A05", "sku": "SAM-A05-128", "description": "Budget smartphone with 6.7-inch display", "price": 790, "quantity": 2 } ],
  "subtotal": 1700,
  "discount": 120,
  "deliveryFee": 0,
  "total": 1580,
  "status": "pending",
  "paymentStatus": "pending"
}
```

**Flow for the mobile app:**
1. `POST /shop/checkout` → returns order (stock decremented, cart cleared)
2. Initiate payment using the existing payment integration (AdvansisPay/ExpressPay, PaySwitch, or GTBank) with the order total and `orderNumber` as reference
3. On payment success, backend marks paymentStatus `success` and order advances to `paid`

The server controls the fee using `DELIVERY_FEE_GHS` (default `0` GHS); any
client-supplied delivery fee is ignored.

---

### **5. Orders (auth required)**

**My orders:** `GET /api/v1/shop/orders?page=1&limit=20`

**Order detail:** `GET /api/v1/shop/orders/{id}` (own orders only)

**Track by order number (public):** `GET /api/v1/shop/orders/number/{orderNumber}`

**Cancel order:**
```
POST /api/v1/shop/orders/{id}/cancel
```
```json
{ "reason": "Changed my mind" }
```
Allowed while `pending` or `processing` (shipped/delivered cannot be cancelled). Stock is restored automatically.

**Delivery tracking & live driver GPS (polled by the mobile app):**
```
GET /api/v1/shop/orders/{id}/tracking
```
*(Use the order's Mongo `_id`, not `orderNumber`. Authenticated with the customer's `Authorization: Bearer <accessToken>`.)*

```json
{
  "_id": "66f000000000000000000001",
  "orderNumber": "LPS261105000001",
  "status": "shipped",
  "trackingNumber": "FRANK-TRACK-0001",
  "carrier": "Frank Courier",
  "estimatedDeliveryDate": "2026-11-05T14:00:00.000Z",
  "deliveredAt": null,
  "shippingAddress": {
    "fullName": "Kofi Mensah",
    "phone": "0241120481",
    "addressLine1": "12 Osu Avenue, Ringway Estates",
    "city": "Accra",
    "region": "Greater Accra",
    "country": "Ghana"
  },
  "lastDriverLocation": {
    "latitude": 5.6037,
    "longitude": -0.187,
    "recordedAt": "2026-11-05T12:15:05.000Z"
  },
  "deliveryUpdates": [
    { "status": "order_placed", "message": "Order placed", "timestamp": "2026-11-05T11:30:00.000Z" },
    { "status": "courier_accepted", "message": "Courier accepted the delivery job", "timestamp": "2026-11-05T11:45:00.000Z" },
    { "status": "picked_up", "message": "Parcel picked up from Melcom warehouse", "location": "Spintex Road, Accra", "timestamp": "2026-11-05T12:00:00.000Z" },
    { "status": "out_for_delivery", "message": "Driver is on the way to the recipient", "location": "Osu, Accra", "timestamp": "2026-11-05T12:15:00.000Z" }
  ]
}
```

**Mobile App Order Tracking Screen Responsibilities:**
1. **Google Maps Driver Pin (`lastDriverLocation`):** Render the rider marker at `lastDriverLocation.latitude` / `longitude` when `status === "shipped"` using LidaPay's restricted Google Maps SDK key, plus a freshness indicator from `recordedAt`.
2. **Active Polling (every 5–10s):** Poll `GET /api/v1/shop/orders/{id}/tracking` every 5–10 seconds while the tracking screen is visible and the order is `processing` or `shipped`. Stop polling immediately when the screen closes, the app is backgrounded, or `status` reaches `delivered`/`cancelled`.
3. **Delivery Timeline (`deliveryUpdates`):** Render `deliveryUpdates[]` (`order_placed`, `courier_accepted`, `packed`, `picked_up`, `out_for_delivery`, `delivery_exception`, `failed_delivery`, `delivered`) in chronological order.
4. **Carrier & ETA Header:** Show `carrier`, `trackingNumber`, and `estimatedDeliveryDate` (or `deliveredAt`).

---

### **6. Admin / Fulfilment (auth required)**

**All orders:** `GET /api/v1/shop/admin/orders?status=pending&paymentStatus=success&page=1`

**Update order status:**
```
PUT /api/v1/shop/admin/orders/{id}/status
```
```json
{ "status": "processing", "note": "Preparing items" }
```

Valid transitions: `pending → paid | cancelled`, `paid → processing | cancelled | refunded`, `processing → shipped | cancelled`, `shipped → delivered`.

**Update payment status:**
```
PUT /api/v1/shop/admin/orders/{id}/payment
```
```json
{ "paymentStatus": "success", "paymentReference": "EXP-123456", "transactionId": "TRX-789012" }
```
Setting `success` auto-advances the order from `pending` to `paid`.

**Update delivery tracking:**
```
PUT /api/v1/shop/admin/orders/{id}/delivery
```
```json
{
  "status": "out_for_delivery",
  "message": "Package handed to rider",
  "location": "Accra Central Hub",
  "trackingNumber": "GHP-TRACK-001",
  "carrier": "Ghana Post",
  "estimatedDeliveryDate": "2026-09-10T10:00:00Z"
}
```
Setting status `delivered` also marks the order `delivered`.

---

### **7. Product & Category Management (auth required — admin/partner)**

**Create product:**
```
POST /api/v1/shop/products
```
```json
{
  "name": "Samsung Galaxy A05",
  "description": "Budget smartphone, 6.7\" display",
  "category": "665e1a2b3c4d5e6f7a8b9c0d",
  "images": ["https://cdn.lidapay.com/prod/a05-1.jpg"],
  "price": 850,
  "discountPrice": 790,
  "stock": 50,
  "sku": "SAM-A05-128",
  "brand": "Samsung",
  "attributes": { "color": "Black", "storage": "128GB" },
  "featured": false,
  "partnerId": "665e1a2b...",
  "partnerName": "Melcom Shopping Centre"
}
```

**Update product:** `PUT /api/v1/shop/products/{id}` (any subset of fields)

**Delete product:** `DELETE /api/v1/shop/products/{id}`

**Create category:**
```
POST /api/v1/shop/categories
```
```json
{ "name": "Groceries", "description": "Fresh food and pantry items", "image": "https://cdn...", "sortOrder": 1 }
```

**Update category:** `PUT /api/v1/shop/categories/{id}`
**Delete category:** `DELETE /api/v1/shop/categories/{id}` (fails if products still reference it)

---

### **Shop Integration Notes:**

#### **Order Lifecycle:**
`pending → paid → processing → shipped → delivered` (with `cancelled`/`refunded` exits at allowed points)

#### **Stock Rules:**
- Stock checked and decremented at checkout
- Stock restored on cancellation
- Cart add/update validates live stock

#### **Data Privacy:**
- `GET /orders` and `GET /orders/{id}` are scoped to the authenticated user's own orders
- Public tracking via order number only (`GET /orders/number/{orderNumber}`)

---

## 🚚 Courier Partner API (HMAC-signed on EVERY Request)

**Base path:** `/api/v1/courier`  
**Authentication:** Stateless HMAC-SHA256 request signing on **every single request**. These routes do **not** use a user JWT or Swagger's **Authorize** button. Advansis provisions a partner ID (shown masked below as `frank-****`) and a 64-character hexadecimal secret (32 random bytes) separately for each environment.

> **CRITICAL RULE — Stateless Per-Request Signing:**  
> The 4 authentication headers (`X-Partner-Id`, `X-Timestamp`, `X-Event-Id`, `X-Signature`) are **required on EVERY SINGLE request** to `/api/v1/courier/*` — **not** only on the initial poll request!  
> - There is **no session cookie** or token returned after polling.  
> - Every call — whether **polling jobs (`GET /jobs`)**, **accepting a job (`POST /accept`)**, **sending status events (`POST /events`)**, or **streaming driver GPS (`POST /location`)** — must include all 4 headers with a **fresh `X-Timestamp`**, a **new `X-Event-Id`**, and a **freshly calculated `X-Signature`** matching that specific request's HTTP method, URL path+query, and raw JSON body.

### Responsibilities

| Advansis Technologies / LidaPay | Frank's engineering team |
|---|---|
| Deploy the courier routes, configure a distinct sandbox/production credential pair, and securely share each pair with Frank. | Implement signed polling, job acceptance, delivery events, and driver-location requests using the shared environment-specific credentials. |
| Provide the base URL and a paid test order; rotate temporary test secrets and provision permanent production credentials out-of-band. | Keep credentials in server-side secret storage, test end-to-end in Postman/cURL, and switch to permanent production credentials after go-live approval. |

### Required headers on every request

| Header | Fixed or Dynamic? | Value |
|---|---|---|
| `X-Partner-Id` | **Fixed** per environment | Partner ID provisioned by LidaPay (masked in this document as `frank-****`) |
| `X-Timestamp` | **Dynamic** (every request) | Current Unix timestamp in **seconds**, exactly 10 digits (not milliseconds); must be within 300 seconds of API server time |
| `X-Event-Id` | **Dynamic** (unique per request) | Unique ID, 8–120 characters (`A-Za-z0-9._:-`); reuse the exact same ID only when retrying a timed-out delivery status event |
| `X-Signature` | **Dynamic** (calculated per request) | 64-character hex `HMAC-SHA256` signature described below |
| `Content-Type` | Required on `POST` requests | `application/json` for requests with a JSON body (`POST /accept`, `POST /events`, `POST /location`) |

### Which Endpoints Require the Headers? (All of Them)

| Endpoint | HTTP Method | Requires `X-Partner-Id`, `X-Timestamp`, `X-Event-Id`, `X-Signature`? | Requires `Content-Type: application/json`? | What is hashed in Line 5 of the Signature? |
|---|---|---|---|---|
| `/api/v1/courier/jobs?state=available` | `GET` | **YES (Required)** | No | Empty body `""` (`e3b0c44298fc1c14...`) |
| `/api/v1/courier/jobs?state=assigned` | `GET` | **YES (Required)** | No | Empty body `""` (`e3b0c44298fc1c14...`) |
| `/api/v1/courier/jobs/{orderNumber}/accept` | `POST` | **YES (Required)** | **YES** | SHA-256 of the `/accept` raw JSON body |
| `/api/v1/courier/jobs/{orderNumber}/events` | `POST` | **YES (Required)** | **YES** | SHA-256 of the `/events` raw JSON body |
| `/api/v1/courier/jobs/{orderNumber}/location` | `POST` | **YES (Required)** | **YES** | SHA-256 of the `/location` raw JSON body |

Build the canonical string from the exact request being sent. Join these five
lines with `\n`, with no trailing newline:

```text
X-Timestamp
X-Event-Id
HTTP_METHOD_IN_UPPERCASE
request-path-and-query
lowercase-hex-SHA256-of-exact-raw-body
```

For GET requests, the raw body is empty; its SHA-256 is
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
Decode the provisioned 64-character secret from hex to 32 raw bytes, then compute:

```text
X-Signature = lowercase_hex(HMAC-SHA256(secret_bytes, canonical_string))
```

### Postman Auto-Signing Pre-request Script

To test in Postman without manually computing timestamps or signatures, set `baseUrl`, `partnerId` (replace `frank-****` with your unmasked ID), `partnerSecret`, and `orderNumber` in your Postman Collection **Variables** tab, and paste this script into the Collection's **Scripts -> Pre-request** tab:

```javascript
const partnerId = (pm.collectionVariables.get("partnerId") || pm.environment.get("partnerId") || "").trim();
const secretHex = (pm.collectionVariables.get("partnerSecret") || pm.environment.get("partnerSecret") || "").trim();

if (!partnerId || partnerId.includes("*") || !/^[a-fA-F0-9]{64}$/.test(secretHex)) {
    throw new Error("Set your unmasked partnerId and 64-character hex partnerSecret in Postman Collection Variables first.");
}

pm.collectionVariables.set("nowIso", new Date().toISOString());

const timestamp = Math.floor(Date.now() / 1000).toString();
const randomSuffix = Math.random().toString(16).substring(2, 10) + Math.random().toString(16).substring(2, 6);
const eventId = pm.request.headers.get("X-Event-Id") || `frank-pm-${timestamp}-${randomSuffix}`;

const rawPathWithQuery = pm.variables.replaceIn(pm.request.url.getPathWithQuery());
const pathWithQuery = rawPathWithQuery.startsWith("/") ? rawPathWithQuery : `/${rawPathWithQuery}`;

const method = pm.request.method.toUpperCase();
const rawBody = method === "GET"
    ? ""
    : pm.variables.replaceIn(pm.request.body && pm.request.body.raw ? pm.request.body.raw : "");

if (method !== "GET" && pm.request.body && pm.request.body.raw) {
    pm.request.body.update(rawBody);
}

const bodyHash = CryptoJS.SHA256(rawBody).toString(CryptoJS.enc.Hex);
const canonical = [timestamp, eventId, method, pathWithQuery, bodyHash].join("\n");
const secretBytes = CryptoJS.enc.Hex.parse(secretHex);
const signature = CryptoJS.HmacSHA256(canonical, secretBytes).toString(CryptoJS.enc.Hex);

pm.request.headers.upsert({ key: "X-Partner-Id", value: partnerId });
pm.request.headers.upsert({ key: "X-Timestamp", value: timestamp });
pm.request.headers.upsert({ key: "X-Event-Id", value: eventId });
pm.request.headers.upsert({ key: "X-Signature", value: signature });
```

### Practical signed GET example (Bash / cURL)

Replace `frank-****` with your unmasked Partner ID:

```bash
export COURIER_API_BASE='https://api.advansistechnologies.com'
export COURIER_PARTNER_ID='frank-****' # <-- replace with your unmasked Partner ID
export COURIER_PARTNER_SECRET='78128ce10d1e47cb6d767d0552f39336b98ec9a730a8e858d7f53e55b3a81f09' # temporary test secret

method='GET'
path='/api/v1/courier/jobs?state=available'
body=''
timestamp="$(date +%s)"                         # Unix seconds, 10 digits
event_id='frank-poll-test-0001'                 # use a new ID for each request
body_hash="$(printf '%s' "$body" | openssl dgst -sha256 | awk '{print $NF}')"
canonical="$(printf '%s\n%s\n%s\n%s\n%s' \
  "$timestamp" "$event_id" "$method" "$path" "$body_hash")"
signature="$(printf '%s' "$canonical" | \
  openssl dgst -sha256 -mac HMAC \
    -macopt hexkey:"$COURIER_PARTNER_SECRET" | awk '{print $NF}')"

curl --fail-with-body -i "$COURIER_API_BASE$path" \
  -H "X-Partner-Id: $COURIER_PARTNER_ID" \
  -H "X-Timestamp: $timestamp" \
  -H "X-Event-Id: $event_id" \
  -H "X-Signature: $signature"
```

### Live-Verified Header Values (`https://api.advansistechnologies.com`)

Verified against the live API using the temporary test secret `78128ce10d1e47cb6d767d0552f39336b98ec9a730a8e858d7f53e55b3a81f09` (which will be rotated before production go-live) and masked partner ID `frank-****`:

```text
GET /api/v1/courier/jobs?state=available
X-Partner-Id: frank-****
X-Timestamp: 1793879551
X-Event-Id: frank-poll-test-0001
X-Signature: ef3c0d076812f4317366e249c1a99ae4628ae694e9a4c882fd05ffae2b82cc84
```

Live response:
```http
HTTP/2 200
{"jobs":[]}
```

### Courier routes

| Method and path | Purpose |
|---|---|
| `GET /api/v1/courier/jobs?state=available` | List up to 100 paid, unassigned delivery jobs (includes `shippingAddress` and item `name`, `sku`, `description`, `price`, `quantity`) |
| `GET /api/v1/courier/jobs?state=assigned` | List active jobs assigned to this partner |
| `POST /api/v1/courier/jobs/{orderNumber}/accept` | Atomically claim a paid job |
| `POST /api/v1/courier/jobs/{orderNumber}/events` | Record delivery status (`packed`, `picked_up`, `out_for_delivery`, `delivered`, `delivery_exception`, `failed_delivery`) |
| `POST /api/v1/courier/jobs/{orderNumber}/location` | Update the driver's latest GPS point (`latitude`, `longitude`, `recordedAt`) |

`orderNumber` is the LidaPay `LPS…` reference from the courier jobs list.

**Accept a job** (`bookingReference` required; the other fields are optional):

```json
{
  "bookingReference": "FRANK-TEST-BOOKING-001",
  "trackingNumber": "FRANK-TEST-TRACK-001",
  "estimatedDeliveryDate": "2026-11-05T14:00:00.000Z"
}
```

**Post a delivery event** (all dates are ISO-8601; `X-Timestamp` remains a
separate Unix-seconds authentication header):

```json
{
  "status": "picked_up",
  "occurredAt": "2026-11-05T12:00:00.000Z",
  "message": "Parcel picked up from Melcom warehouse",
  "location": "Spintex Road, Accra",
  "trackingNumber": "FRANK-TEST-TRACK-001"
}
```

Supported `status` values: `packed`, `picked_up`, `out_for_delivery`,
`delivered`, `delivery_exception`, `failed_delivery`. Report `picked_up`
before `out_for_delivery`, `delivered`, or `/location`. A repeated delivery event using the
same `X-Event-Id` is acknowledged as a duplicate.

**Post a driver location:**

```json
{
  "latitude": 5.6037,
  "longitude": -0.187,
  "recordedAt": "2026-11-05T12:15:05.000Z"
}
```

Coordinates must be within latitude `[-90, 90]` and longitude `[-180, 180]`.
Locations are accepted only after pickup (`status === "shipped"`) and before the delivery is closed.
Older location points are acknowledged with `"stale": true`.

### Common courier responses

- `401`: authentication failed. Check unmasked partner ID, 10-digit seconds timestamp,
  five-minute clock window, event ID, method/path/query, raw body bytes, and
  hex-decoded HMAC secret.
- `404`: order not found or not assigned to this partner.
- `409`: job already claimed/closed, or `out_for_delivery`/`delivered`/`location` sent before `picked_up`.
- `503`: courier partner credentials are not configured on this API deployment.

For full step-by-step Postman sample tests, Node.js/Bash helpers, and how the LidaPay mobile app polls `GET /api/v1/shop/orders/{id}/tracking` to render `lastDriverLocation` on Google Maps and `deliveryUpdates` in the timeline, see:
- [COURIER_API_PARTNER_HANDOFF_FRANK.md](./COURIER_API_PARTNER_HANDOFF_FRANK.md)
- [SHOP_API_MOBILE_HANDOFF.md](./SHOP_API_MOBILE_HANDOFF.md)

---

## �📊 **Error Responses**

### **Standard Error Format:**
```json
{
  "statusCode": 400,
  "message": "Error description",
  "error": "Bad Request"
}
```

### **Common Error Codes:**
- `400` - Bad Request (invalid parameters)
- `401` - Unauthorized (missing/invalid token)
- `404` - Not Found (resource doesn't exist)
- `500` - Internal Server Error

---

## 🔧 **Testing with Swagger**

### **1. Access Swagger UI:**
- Development: `http://localhost:1124/api-doc`
- Production: `https://api.advansistechnologies.com/api-doc`

### **2. Authentication:**
1. First call `/api/v1/users/login` to get token
2. Click "Authorize" button in Swagger
3. Enter `Bearer {access_token}` in the value field
4. Click "Authorize" to apply to all endpoints

### **3. Testing FCM Integration:**
1. Login with device token fields
2. Verify token registration with GET `/api/v1/notifications/device-token`
3. Check recipient eligibility
4. Create recipient decision
5. Monitor push notifications on device

### **4. Testing GTBank Payment Integration:**
1. List services: `GET /api/v1/gtpay/services`
2. Query balance: `POST /api/v1/gtpay/query` with `ServiceName: 'balance'`
3. Verify account: `POST /api/v1/gtpay/query` with account details
4. Initiate payment: `POST /api/v1/gtpay/pay` with service details
5. Check status: `POST /api/v1/gtpay/status` with PartnerTransId
6. List banks: `GET /api/v1/gtpay/banks`

---

## 📱 **Flutter Implementation Tips**

### **1. HTTP Client Setup:**
```dart
class ApiClient {
  static const String baseUrl = 'https://api.advansistechnologies.com';
  static String? _authToken;
  
  static void setAuthToken(String token) {
    _authToken = token;
  }
  
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };
}
```

### **2. Login with FCM:**
```dart
Future<Map<String, dynamic>> login({
  required String username,
  required String password,
  String? deviceToken,
}) async {
  final response = await http.post(
    Uri.parse('${ApiClient.baseUrl}/api/v1/users/login'),
    headers: ApiClient.headers,
    body: jsonEncode({
      'username': username,
      'password': password,
      if (deviceToken != null) 'deviceToken': deviceToken,
      'devicePlatform': Platform.isIOS ? 'IOS' : 'ANDROID',
      // Add other device info...
    }),
  );
  
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    ApiClient.setAuthToken(data['access_token']);
    return data;
  } else {
    throw Exception('Login failed: ${response.body}');
  }
}
```

### **3. Device Token Registration:**
```dart
Future<bool> registerDeviceToken(String token) async {
  final response = await http.post(
    Uri.parse('${ApiClient.baseUrl}/api/v1/notifications/device-token'),
    headers: ApiClient.headers,
    body: jsonEncode({
      'token': token,
      'platform': Platform.isIOS ? 'IOS' : 'ANDROID',
      'deviceId': await DeviceInfo.getDeviceId(),
      'appVersion': await PackageInfo.getVersion(),
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
    }),
  );
  
  return response.statusCode == 200;
}
```

### **4. GTBank Payment Flow:**
```dart
// Step 1: List available services
Future<List<dynamic>> listGTBankServices() async {
  final response = await http.get(
    Uri.parse('${ApiClient.baseUrl}/api/v1/gtpay/services'),
    headers: ApiClient.headers,
  );
  
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return data['data']['Data']['services'];
  }
  throw Exception('Failed to load services');
}

// Step 2: Verify account before payment
Future<Map<String, dynamic>> verifyAccount({
  required String serviceName,
  required String serviceNumber,
}) async {
  final response = await http.post(
    Uri.parse('${ApiClient.baseUrl}/api/v1/gtpay/query'),
    headers: ApiClient.headers,
    body: jsonEncode({
      'ServiceName': serviceName,
      'ServiceNumber': serviceNumber,
    }),
  );
  
  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  }
  throw Exception('Account verification failed');
}

// Step 3: Initiate payment
Future<Map<String, dynamic>> initiatePayment({
  required String serviceName,
  required String serviceNumber,
  required double amount,
  String? remarks,
}) async {
  final response = await http.post(
    Uri.parse('${ApiClient.baseUrl}/api/v1/gtpay/pay'),
    headers: ApiClient.headers,
    body: jsonEncode({
      'ServiceDetails': {
        'ServiceName': serviceName,
        'ServiceNumber': serviceNumber,
        'Amount': amount,
        'Remarks': remarks ?? 'Payment from Lidapay',
      },
    }),
  );
  
  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  }
  throw Exception('Payment initiation failed');
}

// Step 4: Check payment status
Future<Map<String, dynamic>> checkPaymentStatus(String partnerTransId) async {
  final response = await http.post(
    Uri.parse('${ApiClient.baseUrl}/api/v1/gtpay/status'),
    headers: ApiClient.headers,
    body: jsonEncode({
      'PartnerTransId': partnerTransId,
    }),
  );
  
  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  }
  throw Exception('Status check failed');
}
```

---

## 🚀 **Production Checklist**

### **General:**
- [ ] Test all endpoints with Swagger UI
- [ ] Verify error handling
- [ ] Monitor backend logs

### **FCM Integration:**
- [ ] Verify FCM token registration works
- [ ] Test recipient eligibility check
- [ ] Test complete recipient decision flow
- [ ] Test with real device tokens
- [ ] Monitor backend logs for push dispatch
- [ ] Validate timeout behavior

### **GTBank Payment Integration:**
- [ ] Test service listing endpoint
- [ ] Verify account query/verification works
- [ ] Test payment initiation flow
- [ ] Verify callback URL is correctly configured
- [ ] Test transaction status polling
- [ ] Validate SecureHash generation and verification
- [ ] Test with GTBank test credentials
- [ ] Verify bank list retrieval
- [ ] Test error handling for failed payments
- [ ] Monitor GTBank callback logs

---

**Need help? Check the Flutter integration guide or contact the backend team.**
