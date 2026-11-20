Each sub-tool has its own bootstrap:
- Static server: `node tool_static_server.mjs` (serves `build/web/` on `127.0.0.1:4173`) or `node tool/serve_web.js [root] [port]`.
- Icons: run `python3 tool/generate_icons.py` from repo root (requires PIL/Pillow and numpy).
- Courier orders: `cd tool/courier-orders && cp .env.example .env` then `node check-courier-queue.mjs [state]`.
- Livecheck: `cd tool/livecheck && npx puppeteer-core ...` per its README.