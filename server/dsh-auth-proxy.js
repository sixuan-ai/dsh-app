#!/usr/bin/env node
// Auth gateway for the dsh web UI (default upstream 127.0.0.1:3080).
// Listens on loopback only — meant to be reached through frpc (tcp + encryption).
//
// Auth model:
//  - Navigational GETs without credentials get an HTML login page (POST /__auth).
//    On success a signed HttpOnly grant cookie is issued; browsers replay it on
//    fetch(), WebSocket handshakes and subresource loads — Basic-credential
//    caching quirks no longer matter.
//  - Non-navigational clients (curl, API) can use HTTP Basic as before.
//  - Host/Origin/Referer are rewritten to the upstream authority so the dsh
//    /api browser-trust fence accepts proxied requests.
const http = require('http');
const net = require('net');
const crypto = require('crypto');
const fs = require('fs');
const {execFileSync} = require('node:child_process');

const LISTEN_HOST = process.env.LISTEN_HOST || '127.0.0.1';
const LISTEN_PORT = parseInt(process.env.LISTEN_PORT || '3081', 10);
const UPSTREAM_HOST = process.env.UPSTREAM_HOST || '127.0.0.1';
const UPSTREAM_PORT = parseInt(process.env.UPSTREAM_PORT || '3080', 10);
const AUTH_USER = process.env.AUTH_USER || '';
const AUTH_PASSWORD = process.env.AUTH_PASSWORD || '';
// Optional local hashes for directory accounts explicitly bound to this computer.
const AUTH_USERS_FILE = process.env.AUTH_USERS_FILE || '';
const AUTH_COOKIE_SECRET = process.env.AUTH_COOKIE_SECRET || '';
const COOKIE_NAME = 'dshauth';
const cookieToken = AUTH_COOKIE_SECRET
  ? crypto.createHmac('sha256', AUTH_COOKIE_SECRET).update('dsh-web-auth-grant').digest('hex')
  : '';
const UPSTREAM_AUTHORITY = `${UPSTREAM_HOST}:${UPSTREAM_PORT}`;

if (!AUTH_USER || !AUTH_PASSWORD || !AUTH_COOKIE_SECRET) {
  console.error('AUTH_USER, AUTH_PASSWORD and AUTH_COOKIE_SECRET must be set');
  process.exit(1);
}

// Static app metadata with zero sensitivity; fetched by browsers without credentials.
const AUTH_EXEMPT_GET = new Set(['/manifest.webmanifest', '/favicon.ico']);

function isExempt(req) {
  const path = (req.url || '/').split('?')[0];
  return (req.method === 'GET' || req.method === 'HEAD') && AUTH_EXEMPT_GET.has(path);
}

function safeEq(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) {
    crypto.timingSafeEqual(ba, ba); // keep timing flat on length mismatch
    return false;
  }
  return crypto.timingSafeEqual(ba, bb);
}

// Keep the original internal account and cookie grants working. Additional
// accounts are enrolled by an administrator after checking computer ownership;
// authentication itself is local and does not require the public directory.
function additionalAccountMatches(user, pass) {
  if (!AUTH_USERS_FILE) return false;
  try {
    const store = JSON.parse(fs.readFileSync(AUTH_USERS_FILE, 'utf8'));
    if (store.version !== 1 || !Array.isArray(store.users) || store.users.length > 64) return false;
    for (const entry of store.users) {
      if (!entry || typeof entry.username !== 'string' || !safeEq(user, entry.username)) continue;
      if (entry.algorithm !== 'pbkdf2-sha256' || !/^[a-f0-9]{32}$/i.test(entry.salt || '') ||
          !/^[a-f0-9]{64}$/i.test(entry.digest || '') || !Number.isInteger(entry.iterations) ||
          entry.iterations < 100000 || entry.iterations > 1000000) continue;
      const actual = crypto.pbkdf2Sync(pass, Buffer.from(entry.salt, 'hex'), entry.iterations, 32, 'sha256');
      if (crypto.timingSafeEqual(actual, Buffer.from(entry.digest, 'hex'))) return true;
    }
  } catch {
    // A missing or malformed enrollment file must never open the gateway.
  }
  return false;
}

function authorized(req) {
  const m = /^Basic (.+)$/.exec(req.headers['authorization'] || '');
  if (m) {
    let decoded;
    try {
      decoded = Buffer.from(m[1], 'base64').toString('utf8');
    } catch {
      return false;
    }
    const idx = decoded.indexOf(':');
    if (idx < 0) return false;
    const user = decoded.slice(0, idx);
    const pass = decoded.slice(idx + 1);
    if ((safeEq(user, AUTH_USER) && safeEq(pass, AUTH_PASSWORD)) || additionalAccountMatches(user, pass)) return true;
  }
  for (const part of String(req.headers['cookie'] || '').split(';')) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    if (part.slice(0, eq).trim() !== COOKIE_NAME) continue;
    const v = part.slice(eq + 1).trim();
    if (v.length === cookieToken.length && crypto.timingSafeEqual(Buffer.from(v), Buffer.from(cookieToken))) {
      return true;
    }
  }
  return false;
}

function logAuth(req, verdict) {
  const hasBasic = (req.headers['authorization'] || '').startsWith('Basic ');
  const hasCookie = String(req.headers['cookie'] || '').includes(COOKIE_NAME + '=');
  console.log(`[auth] ${req.method} ${req.url} basic=${hasBasic} cookie=${hasCookie} -> ${verdict}`);
}

function grantCookie() {
  return `${COOKIE_NAME}=${cookieToken}; Path=/; Max-Age=604800; HttpOnly; SameSite=Strict`;
}

// --- dsh browser-session brokering ------------------------------------------
// Besides this proxy's own Basic gate, dsh enforces a second gate of its own:
// every /api call and WebSocket upgrade must carry a `dsh-auth-<authority>`
// cookie minted by exchanging the launch token that `dsh web` prints at
// startup. That token is random per process, so it rotates on every restart and
// a client cannot usefully pin it.
//
// The proxy runs on the same host, so it reads the current token from the dsh
// web log and keeps a fresh cookie on every authorized client's behalf. Clients
// keep using plain Basic auth and survive dsh restarts.
//
// The cookie's signing secret is persisted by dsh's credential store, so an
// obtained cookie stays valid across restarts; the periodic refresh only guards
// against its 30-day expiry and against a rotated credential store.
//
// Opt-in: DSH_TOKEN_FILE points to its startup log; DSH_TOKEN_UNIT can
// read the startup URL from a named systemd user service journal instead.
// Left unset the broker is inert and the proxy behaves exactly as before, which
// is the right default for deployments whose dsh is satisfied by Basic auth.
const TOKEN_FILE = process.env.DSH_TOKEN_FILE || '';
const TOKEN_UNIT = process.env.DSH_TOKEN_UNIT || '';
if (TOKEN_UNIT && !/^[A-Za-z0-9_.@-]+\.service$/.test(TOKEN_UNIT)) {
  throw new Error('Invalid DSH_TOKEN_UNIT');
}
const BROKER_ENABLED = TOKEN_FILE !== '' || TOKEN_UNIT !== '';
const COOKIE_CACHE = process.env.DSH_COOKIE_CACHE || `${__dirname}/dsh-session-cookie`;
const COOKIE_REFRESH_MS =
  parseInt(process.env.DSH_COOKIE_REFRESH_MS || '', 10) || 12 * 60 * 60 * 1000;
let dshCookie = '';
let dshCookieRefreshing = null;

/** Latest `token=` printed by `dsh web`, or '' when unavailable. */
function readLaunchToken() {
  try {
    const text = TOKEN_UNIT
      ? execFileSync('/usr/bin/journalctl', ['--user', '-u', TOKEN_UNIT, '-n', '200', '-o', 'cat', '--no-pager'], {encoding:'utf8', timeout:4000, maxBuffer:2*1024*1024})
      : fs.readFileSync(TOKEN_FILE, 'utf8');
    const found = text.match(/token=([A-Za-z0-9_-]+)/g);
    return found && found.length ? found[found.length - 1].slice('token='.length) : '';
  } catch {
    return '';
  }
}

function loadCachedCookie() {
  try {
    const value = fs.readFileSync(COOKIE_CACHE, 'utf8').trim();
    if (value.startsWith('dsh-auth-')) dshCookie = value;
  } catch {
    // No cache yet; the startup exchange below will mint one.
  }
}

function saveCachedCookie() {
  try {
    fs.writeFileSync(COOKIE_CACHE, dshCookie, { mode: 0o600 });
  } catch {
    // Best effort; the in-memory cookie still serves this process.
  }
}

/** Exchange the current launch token for a dsh session cookie. */
function refreshDshCookie(reason) {
  if (!BROKER_ENABLED) return Promise.resolve(false);
  if (dshCookieRefreshing) return dshCookieRefreshing;
  dshCookieRefreshing = new Promise((resolve) => {
    const token = readLaunchToken();
    if (!token) {
      console.warn(`[dsh-cookie] no launch token in ${TOKEN_FILE} (${reason})`);
      resolve(false);
      return;
    }
    const exchange = http.request(
      {
        host: UPSTREAM_HOST,
        port: UPSTREAM_PORT,
        method: 'GET',
        path: `/?token=${encodeURIComponent(token)}`,
        headers: { host: UPSTREAM_AUTHORITY },
      },
      (res) => {
        const raw = res.headers['set-cookie'] || [];
        const cookie = raw
          .map((entry) => entry.split(';')[0])
          .find((entry) => entry.startsWith('dsh-auth-'));
        res.resume();
        if (cookie) {
          dshCookie = cookie;
          saveCachedCookie();
          console.log(`[dsh-cookie] session cookie refreshed (${reason})`);
          resolve(true);
        } else {
          console.warn(
            `[dsh-cookie] exchange returned no session cookie (${reason}, status ${res.statusCode})`,
          );
          resolve(false);
        }
      },
    );
    exchange.on('error', (err) => {
      console.warn(`[dsh-cookie] exchange failed (${reason}): ${err.message}`);
      resolve(false);
    });
    exchange.end();
  }).finally(() => {
    dshCookieRefreshing = null;
  });
  return dshCookieRefreshing;
}

/**
 * Merge the brokered cookie into outgoing headers.
 * A client that already supplied its own dsh session cookie wins.
 */
function withDshCookie(headers) {
  if (!BROKER_ENABLED || !dshCookie) return headers;
  const name = dshCookie.split('=')[0];
  const existing = String(headers.cookie || '');
  if (existing.includes(`${name}=`)) return headers;
  return { ...headers, cookie: existing ? `${existing}; ${dshCookie}` : dshCookie };
}

if (BROKER_ENABLED) {
  loadCachedCookie();
  refreshDshCookie('startup');
  setInterval(() => refreshDshCookie('periodic'), COOKIE_REFRESH_MS).unref();
  console.log(`[dsh-cookie] brokering enabled (token source: ${TOKEN_UNIT || TOKEN_FILE})`);
}

// --- login page -------------------------------------------------------------
const LOGIN_STYLE = `
  :root { color-scheme: light dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         font: 15px/1.5 system-ui, "PingFang SC", "Microsoft YaHei", sans-serif; }
  .card { width: min(340px, 90vw); padding: 2rem; border-radius: 12px;
          box-shadow: 0 4px 24px rgba(0,0,0,.18); }
  h1 { font-size: 1.1rem; margin: 0 0 1.2rem; }
  input { width: 100%; box-sizing: border-box; margin: .3rem 0 .9rem; padding: .55rem .7rem;
          border: 1px solid #888; border-radius: 8px; font: inherit; background: transparent; }
  button { width: 100%; padding: .6rem; border: 0; border-radius: 8px; font: inherit;
           font-weight: 600; background: #4f6ef7; color: #fff; cursor: pointer; }
  .err { color: #d33; margin: 0 0 .8rem; }
  @media (prefers-color-scheme: dark) {
    .card { background: #1e1f24; color: #e8e8ec; }
    input { color: inherit; }
  }
`;

function loginPage(next, err) {
  const safeNext = next.replace(/[&<>"']/g, '');
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>dsh web 访问验证</title><style>${LOGIN_STYLE}</style></head><body>
<div class="card"><h1>dsh web · 密钥验证</h1>
${err ? `<p class="err">${err}</p>` : ''}
<form method="POST" action="/__auth">
<input name="user" placeholder="用户名" autocomplete="username" required>
<input name="password" type="password" placeholder="访问密钥" autocomplete="current-password" required>
<input type="hidden" name="next" value="${safeNext}">
<button type="submit">进入</button>
</form></div></body></html>`;
}

// --- brute-force throttle ---------------------------------------------------
const fails = new Map(); // addr -> { n, until }
function throttleKey(req) {
  return req.socket.remoteAddress || '?';
}
function isThrottled(req) {
  const f = fails.get(throttleKey(req));
  return !!f && f.until > Date.now();
}
function noteFail(req) {
  const key = throttleKey(req);
  const f = fails.get(key) || { n: 0, until: 0 };
  f.n += 1;
  if (f.n >= 5) {
    f.until = Date.now() + 30000; // 5 fails -> 30 s lockout
    f.n = 0;
  }
  fails.set(key, f);
}
function noteSuccess(req) {
  fails.delete(throttleKey(req));
}

function readBody(req, cb, limit = 8192) {
  const chunks = [];
  let size = 0;
  req.on('data', (c) => {
    size += c.length;
    if (size > limit) {
      req.destroy();
      return;
    }
    chunks.push(c);
  });
  req.on('end', () => cb(Buffer.concat(chunks).toString('utf8')));
}

function handleLoginPost(req, res) {
  if (isThrottled(req)) {
    res.writeHead(429, { 'Content-Type': 'text/html; charset=utf-8', 'Retry-After': '30' });
    res.end(loginPage('/', '尝试过于频繁，请 30 秒后再试'));
    return;
  }
  readBody(req, (body) => {
    const params = new URLSearchParams(body);
    const user = params.get('user') || '';
    const pass = params.get('password') || '';
    const nextRaw = params.get('next') || '/';
    const dest = nextRaw.startsWith('/') && !nextRaw.startsWith('//') ? nextRaw : '/';
    if (!((safeEq(user, AUTH_USER) && safeEq(pass, AUTH_PASSWORD)) || additionalAccountMatches(user, pass))) {
      noteFail(req);
      setTimeout(() => {
        res.writeHead(401, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
        res.end(loginPage(dest, '密钥错误，请重试'));
      }, 250);
      return;
    }
    noteSuccess(req);
    res.writeHead(302, { Location: dest, 'Set-Cookie': grantCookie(), 'Cache-Control': 'no-store' });
    res.end();
  });
}

function wantsLoginPage(req) {
  return String(req.headers['accept'] || '').includes('text/html');
}

// Present the upstream's own authority to the dsh browser-trust fence.
function fenceHeaders(req) {
  req.headers['host'] = UPSTREAM_AUTHORITY;
  if (req.headers['origin']) req.headers['origin'] = `http://${UPSTREAM_AUTHORITY}`;
  if (req.headers['referer']) req.headers['referer'] = `http://${UPSTREAM_AUTHORITY}/`;
  // HTML responses are buffered for polyfill injection; keep them identity-encoded.
  delete req.headers['accept-encoding'];
}

// crypto.randomUUID exists only in secure contexts; the page is reached over
// plain http via frp, so backfill it (RFC 4122 v4, still CSPRNG-backed).
const UUID_POLYFILL =
  '<script>if(window.crypto&&!crypto.randomUUID){crypto.randomUUID=function(){' +
  'return([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g,function(c){' +
  'return(c^crypto.getRandomValues(new Uint8Array(1))[0]&15>>c/4).toString(16)})}}' +
  '</script>';

function injectPolyfill(html) {
  const m = /<head[^>]*>/i.exec(html);
  if (m) return html.slice(0, m.index + m[0].length) + UUID_POLYFILL + html.slice(m.index + m[0].length);
  return UUID_POLYFILL + html;
}

const server = http.createServer((req, res) => {
  const path = (req.url || '/').split('?')[0];
  if (req.method === 'POST' && path === '/__auth') {
    logAuth(req, 'login-post');
    return handleLoginPost(req, res);
  }
  if (!isExempt(req) && !authorized(req)) {
    logAuth(req, wantsLoginPage(req) ? 'login-page' : '401');
    if (wantsLoginPage(req)) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(loginPage(req.url));
    } else {
      res.writeHead(401, {
        'WWW-Authenticate': 'Basic realm="dsh-web", charset="UTF-8"',
        'Content-Type': 'text/plain; charset=utf-8',
      });
      res.end('Unauthorized.\n');
    }
    return;
  }
  logAuth(req, 'pass');
  fenceHeaders(req);
  const sentCookie = withDshCookie(req.headers);
  const upstream = http.request(
    {
      host: UPSTREAM_HOST,
      port: UPSTREAM_PORT,
      method: req.method,
      path: req.url,
      headers: sentCookie,
    },
    (ures) => {
      // A 401 while we presented a session cookie means the brokered cookie is
      // no longer accepted (rotated credential store). Drop it and mint a fresh
      // one so the next request succeeds, instead of failing until the
      // periodic refresh.
      if (ures.statusCode === 401 && sentCookie.cookie && sentCookie.cookie.includes('dsh-auth-')) {
        dshCookie = '';
        console.warn('[dsh-cookie] upstream rejected the cookie; refreshing');
        void refreshDshCookie('upstream-401');
      }
      const headers = { ...ures.headers };
      // Keep refreshing the grant cookie on authorized responses.
      headers['set-cookie'] = headers['set-cookie'] ? [].concat(headers['set-cookie'], grantCookie()) : grantCookie();
      if (ures.statusCode === 200 && String(ures.headers['content-type'] || '').includes('text/html')) {
        const chunks = [];
        ures.on('data', (c) => chunks.push(c));
        ures.on('end', () => {
          const html = injectPolyfill(Buffer.concat(chunks).toString('utf8'));
          delete headers['transfer-encoding'];
          headers['content-length'] = Buffer.byteLength(html);
          res.writeHead(ures.statusCode, headers);
          res.end(html);
        });
        return;
      }
      res.writeHead(ures.statusCode, headers);
      ures.pipe(res);
    }
  );
  upstream.on('error', (err) => {
    if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(`upstream error: ${err.message}\n`);
  });
  req.pipe(upstream);
});

// WebSocket pass-through (browsers replay cookies on upgrade handshakes).
server.on('upgrade', (req, socket, head) => {
  if (!authorized(req)) {
    logAuth(req, 'ws-401');
    socket.write(
      'HTTP/1.1 401 Unauthorized\r\n' +
        'WWW-Authenticate: Basic realm="dsh-web", charset="UTF-8"\r\n' +
        'Connection: close\r\n\r\n'
    );
    socket.destroy();
    return;
  }
  fenceHeaders(req);
  logAuth(req, 'ws-pass');
  const upgradeHeaders = withDshCookie(req.headers);
  const upstream = net.connect(UPSTREAM_PORT, UPSTREAM_HOST, () => {
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (const [k, v] of Object.entries(upgradeHeaders)) {
      if (Array.isArray(v)) v.forEach((vv) => lines.push(`${k}: ${vv}`));
      else lines.push(`${k}: ${v}`);
    }
    upstream.write(lines.join('\r\n') + '\r\n\r\n');
    if (head && head.length) upstream.write(head);
    socket.pipe(upstream);
    upstream.pipe(socket);
  });
  upstream.on('error', () => socket.destroy());
  socket.on('error', () => upstream.destroy());
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(`dsh auth gateway on http://${LISTEN_HOST}:${LISTEN_PORT} -> http://${UPSTREAM_AUTHORITY}`);
});
