// Live-API verification: drives the release build in a headless browser
// against the real backend. Negative path — invalid credentials prove the
// full round trip (CORS, base URL, request-otp, NestJS error parsing, UI).
import puppeteer from 'puppeteer-core';

const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const BASE = 'http://127.0.0.1:8903/';
const OUT = 'E:/QODER/lidapay-app/tool_screens/live_verify';
const VIEW = { width: 430, height: 932 };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function allNodes(page) {
  return page.evaluate(() => {
    const out = [];
    const walk = (node) => {
      for (const n of node.querySelectorAll('*')) walk(n);
    };
    const root = document.querySelector('flt-semantics');
    if (!root) return out;
    const visit = (el) => {
      for (const child of el.children) visit(child);
      const role = el.getAttribute('role');
      const tag = el.tagName.toLowerCase();
      if (!role && !tag.startsWith('flt-') && tag !== 'input') return;
      const r = el.getBoundingClientRect();
      if (r.width < 2 || r.height < 2) return;
      let label = '';
      if (tag === 'input') {
        label = el.getAttribute('data-semantics-role') || el.getAttribute('aria-label') || '';
        out.push({
          label,
          role: el.getAttribute('data-semantics-role') || 'input',
          tag,
          x: r.x + r.width / 2,
          y: r.y + r.height / 2,
          w: Math.round(r.width),
          h: Math.round(r.height),
        });
        return;
      }
      const own = el.getAttribute('aria-label') ?? '';
      const directSpan = el.tagName === 'FLT-SEMANTICS' ? (el.textContent || '').trim() : '';
      const text = own || directSpan;
      label = text.replace(/\s+/g, ' ').trim();
      if (label || role === 'button') {
        out.push({ label, role: role || '', tag, x: r.x + r.width / 2, y: r.y + r.height / 2, w: Math.round(r.width), h: Math.round(r.height) });
      }
    };
    visit(root);
    return out;
  });
}

async function findNode(page, text, opts = {}, timeout = 9000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const nodes = await allNodes(page);
    const hit = nodes.find(
      (n) =>
        (n.label.toLowerCase().includes(text.toLowerCase()) ||
          (opts.role && n.role === opts.role && n.label.toLowerCase().includes(text.toLowerCase()))) &&
        n.w > 10,
    );
    if (hit) return hit;
    await sleep(250);
  }
  throw new Error('[timeout] text not found: ' + text);
}

async function findField(page, index, timeout = 9000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const fields = (await allNodes(page)).filter((n) => n.tag === 'input');
    if (fields.length > index) return fields[index];
    await sleep(250);
  }
  throw new Error('[timeout] field not found');
}

async function findWideButton(page, timeout = 8000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const pool = (await allNodes(page)).filter((n) => n.role === 'button' && n.w > 300);
    if (pool.length) {
      pool.sort((a, b) => b.w - a.w || b.y - a.y);
      return pool[0];
    }
    await sleep(250);
  }
  throw new Error('[timeout] no full-width button');
}

async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 20000 });
  await page.evaluate(() => {
    const placeholder = document.querySelector('flt-semantics-placeholder');
    if (placeholder) placeholder.click();
  });
  await sleep(600);
  await page.evaluate(() => {
    const style = document.createElement('style');
    style.textContent = 'flt-semantics, flt-semantics input { pointer-events: none !important; }';
    document.head.appendChild(style);
  });
}

async function tap(page, x, y) {
  await page.mouse.click(x, y);
  await sleep(400);
}

async function type(page, field, text) {
  await tap(page, field.x, field.y);
  await page.keyboard.type(text, { delay: 20 });
  await sleep(300);
}

async function run(theme) {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: ['--no-sandbox', '--enable-unsafe-swiftshader'],
    defaultViewport: { ...VIEW, deviceScaleFactor: 2 },
  });
  const page = await browser.newPage();
  const apiCalls = [];
  page.on('response', async (res) => {
    if (res.url().includes('advansistechnologies.com')) {
      let body = '';
      try {
        body = (await res.text()).slice(0, 220);
      } catch {}
      apiCalls.push({ url: res.url(), status: res.status(), body });
    }
  });

  await page.evaluateOnNewDocument((mode) => {
    localStorage.setItem('flutter.onboarding_seen_v1', 'true');
    localStorage.setItem('flutter.theme_mode', JSON.stringify(mode));
  }, theme);

  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await enableSemantics(page);
  await findNode(page, 'Welcome back', {}, 25000);
  console.log(`[${theme}] login screen rendered`);

  // Step 1: username.
  const usernameField = await findField(page, 0);
  await type(page, usernameField, 'qa.noaccount@example.com');
  const continueBtn = await findWideButton(page);
  await tap(page, continueBtn.x, continueBtn.y);
  await findNode(page, 'Enter Password');
  console.log(`[${theme}] password step reached`);

  // Step 2: password + submit → live request-otp call.
  const passwordField = await findField(page, 0);
  await type(page, passwordField, 'NotARealPassword123');
  const signInBtn = await findWideButton(page);
  await tap(page, signInBtn.x, signInBtn.y);

  // Expect the live 401 rendered inline.
  const error = await findNode(page, 'Incorrect', {}, 20000).catch(() => null);
  const genericError =
    error ??
    (await findNode(page, 'password', {}, 6000).catch(() => null)) ??
    (await findNode(page, 'Invalid', {}, 3000).catch(() => null));
  console.log(`[${theme}] inline error:`, genericError ? genericError.label.slice(0, 90) : 'NOT FOUND');

  await sleep(800);
  await page.screenshot({ path: `${OUT}/1_live_login_error_${theme}.png` });

  console.log(`[${theme}] live API calls:`);
  for (const c of apiCalls) console.log('   ', c.status, c.url.replace('https://api.advansistechnologies.com', ''), '→', c.body);

  await browser.close();
  return { errorFound: !!error, apiCalls };
}

fs: {
  const { mkdirSync } = await import('node:fs');
  mkdirSync(OUT, { recursive: true });
}

const results = {};
for (const theme of ['light', 'dark']) {
  results[theme] = await run(theme);
}
const ok = Object.values(results).every((r) => r.errorFound && r.apiCalls.length > 0);
console.log(ok ? 'LIVE WIRING VERIFIED (negative path, both themes)' : 'VERIFICATION INCOMPLETE');
process.exit(ok ? 0 : 1);
