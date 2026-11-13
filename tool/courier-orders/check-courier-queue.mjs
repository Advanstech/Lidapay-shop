#!/usr/bin/env node
/**
 * Poll the courier partner API exactly the way the partner's backend does,
 * to verify which orders are sitting in the `available` queue.
 *
 * Signs GET /api/v1/courier/jobs?state=<state> with the HMAC headers from
 * docs/COURIER_API_PARTNER_HANDOFF_FRANK.md:
 *   X-Partner-Id, X-Timestamp (unix seconds), X-Event-Id, X-Signature
 * Canonical string: timestamp\neventId\nMETHOD\npath+query\nsha256(body)
 * Signature: HMAC-SHA256(secret-hex-decoded, canonical) hex.
 *
 * Usage:
 *   node check-courier-queue.mjs [state]     # default "available"
 *
 * Config: .env (see .env.example) or process env:
 *   COURIER_PARTNER_ID, COURIER_PARTNER_SECRET, API_BASE
 */
import { createHash, createHmac, randomUUID } from 'crypto';
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

const partnerId = process.env.COURIER_PARTNER_ID;
const secret = process.env.COURIER_PARTNER_SECRET;
const API = (process.env.API_BASE || 'https://api.advansistechnologies.com').replace(/\/$/, '');
const state = process.argv[2] || 'available';

if (!partnerId || !secret) {
  console.error('Missing COURIER_PARTNER_ID / COURIER_PARTNER_SECRET (see .env.example)');
  process.exit(1);
}

const method = 'GET';
const path = `/api/v1/courier/jobs?state=${encodeURIComponent(state)}`;
const body = '';
const timestamp = Math.floor(Date.now() / 1000).toString();
const eventId = `queue-check-${timestamp}-${randomUUID().slice(0, 8)}`;
const bodyHash = createHash('sha256').update(body).digest('hex');
const canonical = [timestamp, eventId, method, path, bodyHash].join('\n');
const signature = createHmac('sha256', Buffer.from(secret, 'hex')).update(canonical).digest('hex');

const res = await fetch(`${API}${path}`, {
  headers: {
    'X-Partner-Id': partnerId,
    'X-Timestamp': timestamp,
    'X-Event-Id': eventId,
    'X-Signature': signature,
  },
});

console.log(`GET ${path}  →  HTTP ${res.status}`);
const json = await res.json().catch(() => null);

const jobs = Array.isArray(json) ? json : json?.jobs || json?.data || json;
if (res.status === 200 && Array.isArray(jobs)) {
  console.log(`\n${jobs.length} job(s) in state "${state}":`);
  for (const j of jobs) {
    console.log(`  ${j.orderNumber || j.order?.orderNumber || '?'}  _id=${j._id || j.order?._id || j.orderId || '?'}`);
  }
  if (jobs.length === 0) console.log('  (queue is empty)');
} else {
  console.log(JSON.stringify(json, null, 1).slice(0, 3000));
}
