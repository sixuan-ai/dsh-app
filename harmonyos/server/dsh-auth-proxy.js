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

const LISTEN_HOST = process.env.LISTEN_HOST || '127.0.0.1';
const LISTEN_PORT = parseInt(process.env.LISTEN_PORT || '3081', 10);
const UPSTREAM_HOST = process.env.UPSTREAM_HOST || '127.0.0.1';
const UPSTREAM_PORT = parseInt(process.env.UPSTREAM_PORT || '3080', 10);
const AUTH_USER = process.env.AUTH_USER || '';
const AUTH_PASSWORD = process.env.AUTH_PASSWORD || '';
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
    if (safeEq(user, AUTH_USER) && safeEq(pass, AUTH_PASSWORD)) return true;
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
    if (!(safeEq(user, AUTH_USER) && safeEq(pass, AUTH_PASSWORD))) {
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
  const upstream = http.request(
    {
      host: UPSTREAM_HOST,
      port: UPSTREAM_PORT,
      method: req.method,
      path: req.url,
      headers: req.headers,
    },
    (ures) => {
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
  const upstream = net.connect(UPSTREAM_PORT, UPSTREAM_HOST, () => {
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (const [k, v] of Object.entries(req.headers)) {
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
