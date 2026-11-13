#!/usr/bin/env node
/**
 * Stamp an estimated `deliveryDistance` onto paid shop orders that have a
 * branch pickupAddress + customer destination coords but no computed
 * distance — for courier-partner testing while the server-side Google
 * Routes API key has no billing.
 *
 * The value is honest about provenance: `source: 'estimate'`, computed with
 * haversine × a road factor (Accra ~1.35) and ~22 km/h average speed.
 * The courier jobs poll returns it as-is; the backend does NOT recompute
 * it later (only `source: 'client'` or missing values get recomputed once
 * Routes API billing is live), so these stay estimates for the life of the
 * order — fine for TEST orders that get consumed.
 *
 * Also backfills `shippingAddress.latitude/longitude` on legacy test
 * orders created before the checkout contract required them.
 *
 * Usage: node stamp-delivery-distance.mjs [--backfill-coords]
 * Config: .env — needs MONGODB_URI.
 */
import { MongoClient } from 'mongodb';
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

const MONGO = process.env.MONGODB_URI;
if (!MONGO) {
  console.error('Missing MONGODB_URI (see .env.example)');
  process.exit(1);
}

const BACKFILL = process.argv.includes('--backfill-coords');
// Accra test destination used for legacy orders that predate the pin.
const FALLBACK_DEST = { latitude: 5.6037, longitude: -0.187 };

const toRad = (d) => (d * Math.PI) / 180;
function haversineKm(a, b) {
  const R = 6371;
  const dLat = toRad(b.latitude - a.latitude);
  const dLng = toRad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.latitude)) *
      Math.cos(toRad(b.latitude)) *
      Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

const client = new MongoClient(MONGO);
await client.connect();
const orders = client.db().collection('orders');

// Orders the courier queue can see: paid/processing, successful payment,
// not yet claimed (or claimed — stamping helps assigned tests too).
const candidates = await orders
  .find({
    paymentStatus: 'success',
    status: { $in: ['paid', 'processing', 'shipped'] },
  })
  .project({
    orderNumber: 1,
    status: 1,
    courierPartnerId: 1,
    shippingAddress: 1,
    pickupAddress: 1,
    deliveryDistance: 1,
  })
  .toArray();

console.log(`${candidates.length} paid/in-flight order(s) found\n`);

for (const order of candidates) {
  const destLat = order.shippingAddress?.latitude;
  const destLng = order.shippingAddress?.longitude;

  // Legacy orders have no destination pin — offer to backfill the test pin.
  if ((destLat === undefined || destLng === undefined) && BACKFILL) {
    const res = await orders.updateOne(
      { _id: order._id },
      {
        $set: {
          'shippingAddress.latitude': FALLBACK_DEST.latitude,
          'shippingAddress.longitude': FALLBACK_DEST.longitude,
        },
      },
    );
    console.log(
      `${order.orderNumber}: backfilled destination pin ` +
        `(${FALLBACK_DEST.latitude}, ${FALLBACK_DEST.longitude})`,
    );
    order.shippingAddress = {
      ...order.shippingAddress,
      ...FALLBACK_DEST,
    };
  }

  const pickup = order.pickupAddress;
  const hasCoords =
    typeof pickup?.latitude === 'number' &&
    typeof pickup?.longitude === 'number' &&
    typeof order.shippingAddress?.latitude === 'number' &&
    typeof order.shippingAddress?.longitude === 'number';

  if (!hasCoords) {
    console.log(
      `${order.orderNumber}: SKIP — missing pickup or destination coords ` +
        `(partner=${order.courierPartnerId || 'unassigned'})`,
    );
    continue;
  }

  if (order.deliveryDistance?.km) {
    console.log(
      `${order.orderNumber}: already has deliveryDistance ` +
        `${order.deliveryDistance.km}km (source=${order.deliveryDistance.source || '?'})`,
    );
    continue;
  }

  const straight = haversineKm(pickup, order.shippingAddress);
  const km = Math.round(straight * 1.35 * 10) / 10; // road factor
  const durationMinutes = Math.max(5, Math.round((km / 22) * 60)); // ~22km/h Accra avg

  await orders.updateOne(
    { _id: order._id },
    {
      $set: {
        deliveryDistance: {
          km,
          durationMinutes,
          computedAt: new Date(),
          source: 'estimate',
        },
      },
    },
  );
  console.log(
    `${order.orderNumber}: stamped estimate ${km}km / ~${durationMinutes}min ` +
      `(haversine ${straight.toFixed(1)}km ×1.35)`,
  );
}

await client.close();
console.log('\nDone. Poll the courier queue to verify deliveryDistance.');
