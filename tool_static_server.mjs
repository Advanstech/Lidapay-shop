import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('./build/web/', import.meta.url));
const mime = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.bin': 'application/octet-stream',
  '.symbols': 'text/plain', '.map': 'application/json',
};

http.createServer(async (req, res) => {
  const headers = { 'Cache-Control': 'no-store' };
  try {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p === '/') p = '/index.html';
    const file = join(root, normalize(p).replace(/^[/\\]+/, ''));
    const data = await readFile(file);
    res.writeHead(200, { ...headers, 'Content-Type': mime[extname(file).toLowerCase()] ?? 'application/octet-stream' });
    res.end(data);
  } catch {
    const data = await readFile(join(root, 'index.html'));
    res.writeHead(200, { ...headers, 'Content-Type': 'text/html' });
    res.end(data);
  }
}).listen(4173, '127.0.0.1', () => console.log('ready on http://127.0.0.1:4173'));
