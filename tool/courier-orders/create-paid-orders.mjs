#!/usr/bin/env node
/**
 * Seed N paid shop orders into the courier partner "available jobs" queue.
 *
 * For each order the script:
 *   1. Clears the test customer's cart and adds PRODUCT_ID x1.
 *   2. Checks out via POST /api/v1/shop/checkout (paymentMethod: momo).
 *   3. Marks payment success via the admin endpoint so the order becomes
 *      status=paid / paymentStatus=success — exactly what the courier
 *      partner's `state=available` filter requires.
 *
 * Orders are clearly marked as TEST orders in the shipping address so nobody
 * dispatches a real driver. They contain no real payment.
 *
 * Usage:
 *   node create-paid-orders.mjs [count]        # default 1
 *
 * Config comes from .env (see .env.example) or the process environment.
 * Requires: mongodb, jsonwebtoken  (npm install in this directory)
 */
import { MongoClient, ObjectId } from 'mongodb';
import jwt from 'jsonwebtoken';
import { readFileSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const envPath = join(here, '.env');
if (existsSync(envPath)) {
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const i = trimmed.indexOf('=');
    if (i === -1) continue;
    const key = trimmed.slice(0, i).trim();
    const val = trimmed.slice(i + 1).trim();
    if (key && !(key in process.env)) process.env[key] = val;
  }
}

const need = (name) => {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env var: ${name} (see .env.example)`);
    process.exit(1);
  }
  return v;
};

const MONGO = need('MONGODB_URI');
const JWT_SECRET = need('JWT_SECRET');
const API = (process.env.API_BASE || 'https://api.advansistechnologies.com').replace(/\/$/, '');
const CUSTOMER_ID = need('CUSTOMER_ID');
const ADMIN_ID = need('ADMIN_ID');
const PRODUCT_ID = need('PRODUCT_ID');
const COUNT = Math.max(1, parseInt(process.argv[2] || '1', 10) || 1);

const client = new MongoClient(MONGO);
await client.connect();
const users = client.db().collection('users');

const [customer, admin] = await Promise.all([
  users.findOne({ _id: new ObjectId(CUSTOMER_ID) }),
  users.findOne({ _id: new ObjectId(ADMIN_ID) }),
]);
if (!customer) throw new Error(`customer ${CUSTOMER_ID} not found`);
if (!admin) throw new Error(`admin ${ADMIN_ID} not found`);
if (!(admin.roles || []).includes('admin')) {
  console.warn(`warning: ${ADMIN_ID} roles=${JSON.stringify(admin.roles)} — admin payment update may 403`);
}

const mint = (u) =>
  jwt.sign(
    {
      username: u.username || u.phoneNumber,
      email: u.email,
      sub: String(u._id),
      roles: u.roles,
    },
    JWT_SECRET,
    { expiresIn: '2h' },
  );

const customerToken = mint(customer);
const adminToken = mint(admin);

const api = async (method, path, { token, body } = {}) => {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, body: json };
};

const results = [];
for (let n = 1; n <= COUNT; n++) {
  // Fresh cart each iteration so orders don't accumulate items.
  await api('DELETE', '/api/v1/shop/cart/clear', { token: customerToken });
  const add = await api('POST', '/api/v1/shop/cart/add', {
    token: customerToken,
    body: { productId: PRODUCT_ID, quantity: 1 },
  });
  if (add.status >= 400) {
    console.error(`cart/add failed: HTTP ${add.status}`, JSON.stringify(add.body));
    continue;
  }

  const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '');
  const checkout = await api('POST', '/api/v1/shop/checkout', {
    token: customerToken,
    body: {
      shippingAddress: {
        fullName: 'Courier Integration Test',
        phone: '0241120481',
        email: 'courier-test@lidapay.local',
        addressLine1: '12 Osu Avenue, Ringway Estates',
        addressLine2: `TEST ORDER ${stamp} - courier API integration, do not dispatch`,
        city: 'Accra',
        region: 'Greater Accra',
        postalCode: 'GA-001',
        country: 'Ghana',
        // Required by the current checkout contract — the backend computes
        // deliveryDistance from this pin to the branch pickup coordinates.
        latitude: 5.6037,
        longitude: -0.187,
        deliveryInstructions: 'TEST ORDER for courier partner API integration',
      },
      paymentMethod: 'momo',
    },
  });

  const order = checkout.body;
  if (checkout.status >= 400 || !order?._id) {
    console.error(`checkout ${n} failed: HTTP ${checkout.status}`, JSON.stringify(order).slice(0, 500));
    continue;
  }

  const pay = await api('PUT', `/api/v1/shop/admin/orders/${order._id}/payment`, {
    token: adminToken,
    body: {
      paymentStatus: 'success',
      paymentReference: `COURIER-TEST-${stamp}`,
      transactionId: `TEST-${Date.now()}`,
    },
  });
  if (pay.status >= 400) {
    console.error(`payment update for ${order.orderNumber} failed: HTTP ${pay.status}`, JSON.stringify(pay.body).slice(0, 500));
    continue;
  }

  results.push({ orderNumber: order.orderNumber, id: order._id });
  console.log(`[${n}/${COUNT}] ${order.orderNumber}  _id=${order._id}`);
}

console.log('\n========================================');
console.log(`Created ${results.length}/${COUNT} paid test order(s):`);
for (const r of results) console.log(`  ${r.orderNumber}  ${r.id}`);
console.log('========================================');

await client.close();
