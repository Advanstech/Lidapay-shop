#!/usr/bin/env node
/**
 * Provision the Melcom Ghana → East Legon fulfillment branch and assign the
 * test product to it, so checkout can resolve a pickupAddress snapshot.
 *
 * Checkout now requires shippingAddress.latitude/longitude AND a resolvable
 * pickup: a product with fulfillmentBranchId uses that branch's pin; a
 * partnerId product falls back to the partner's single active branch; a
 * product with neither falls back to the legacy COURIER_PICKUP_* env point,
 * which is not configured on the deployed API — so orders cannot be created
 * until a branch exists and the product points at it.
 *
 * Idempotent: reuses an existing shop/branch/product assignment when found.
 *
 * Usage: node setup-fulfillment.mjs
 * Config: .env (see .env.example) — needs MONGODB_URI, JWT_SECRET, ADMIN_ID,
 *         PRODUCT_ID, API_BASE.
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
const ADMIN_ID = need('ADMIN_ID');
const PRODUCT_ID = need('PRODUCT_ID');

const SHOP_NAME = process.env.SHOP_NAME || 'Melcom Ghana';
const BRANCH_NAME = process.env.BRANCH_NAME || 'East Legon Branch';
// Pickup pin from docs/SHOP_API_MOBILE_HANDOFF.md (Google Maps listing).
const BRANCH = {
  partnerName: 'Melcom Ghana',
  addressLine1: 'JRQQ+V32, Near Sel Filling Station, Mensah Wood Ave',
  city: 'Accra',
  region: 'Greater Accra',
  country: 'Ghana',
  latitude: 5.6413169,
  longitude: -0.164472,
  active: true,
};

const client = new MongoClient(MONGO);
await client.connect();
const admin = await client.db().collection('users').findOne({
  _id: new ObjectId(ADMIN_ID),
});
if (!admin) throw new Error(`admin ${ADMIN_ID} not found`);
await client.close();

const adminToken = jwt.sign(
  {
    username: admin.username || admin.phoneNumber,
    email: admin.email,
    sub: String(admin._id),
    roles: admin.roles,
  },
  JWT_SECRET,
  { expiresIn: '2h' },
);

const api = async (method, path, body) => {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${adminToken}`,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, body: json };
};

const rows = (r) => {
  const b = r.body;
  if (Array.isArray(b)) return b;
  if (b && Array.isArray(b.shops)) return b.shops;
  if (b && Array.isArray(b.branches)) return b.branches;
  return [];
};

// 1. Shop — reuse by name or create.
let shopsRes = await api('GET', '/api/v1/shop/admin/shops');
let shop = rows(shopsRes).find(
  (s) => (s.name || '').toLowerCase() === SHOP_NAME.toLowerCase(),
);
if (!shop) {
  const created = await api('POST', '/api/v1/shop/admin/shops', {
    name: SHOP_NAME,
    website: 'https://melcom.com',
    city: 'Accra',
    region: 'Greater Accra',
    country: 'Ghana',
  });
  if (created.status >= 400) {
    console.error('create shop failed:', created.status, JSON.stringify(created.body).slice(0, 400));
    process.exit(1);
  }
  shop = created.body?.shop || created.body;
  console.log(`created shop ${SHOP_NAME}: ${shop?._id}`);
} else {
  console.log(`reusing shop ${SHOP_NAME}: ${shop._id}`);
}
const shopId = shop._id || shop.id;

// 2. Branch — reuse any branch on this shop or create East Legon.
let branchesRes = await api('GET', '/api/v1/shop/admin/branches');
let branch = rows(branchesRes).find(
  (b) => String(b.shopId?._id || b.shopId || '') === String(shopId),
);
if (!branch) {
  const created = await api('POST', '/api/v1/shop/admin/branches', {
    shopId,
    name: BRANCH_NAME,
    ...BRANCH,
  });
  if (created.status >= 400) {
    console.error('create branch failed:', created.status, JSON.stringify(created.body).slice(0, 400));
    process.exit(1);
  }
  branch = created.body?.branch || created.body;
  console.log(`created branch ${BRANCH_NAME}: ${branch?._id}`);
} else {
  console.log(`reusing branch ${branch.name || BRANCH_NAME}: ${branch._id}`);
}
const branchId = branch._id || branch.id;

// 3. Assign the test product to the branch.
// Product writes live under /products/:id guarded by @Roles('admin'),
// not under /admin/*.
const productRes = await api('GET', `/api/v1/shop/products/${PRODUCT_ID}`);
const product = productRes.body?.product || productRes.body;
if (!product?._id) {
  console.error('product lookup failed:', productRes.status, JSON.stringify(productRes.body).slice(0, 300));
  process.exit(1);
}
if (String(product.fulfillmentBranchId || '') === String(branchId)) {
  console.log(`product ${product.name} already assigned to ${branchId}`);
} else {
  const upd = await api('PUT', `/api/v1/shop/products/${PRODUCT_ID}`, {
    fulfillmentBranchId: branchId,
  });
  if (upd.status >= 400) {
    console.error('product update failed:', upd.status, JSON.stringify(upd.body).slice(0, 400));
    process.exit(1);
  }
  console.log(`assigned product ${product.name} (${PRODUCT_ID}) → branch ${branchId}`);
}

console.log('\nDone. Checkout can now resolve pickup', branchId);
