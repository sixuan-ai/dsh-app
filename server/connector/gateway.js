#!/usr/bin/env node
// Opt-in TLS device gateway; legacy account proxy remains untouched.
"use strict";
const fs = require("node:fs"),
  https = require("node:https"),
  http = require("node:http"),
  net = require("node:net"),
  crypto = require("node:crypto");
const configPath = process.env.XHARNESS_CONFIG;
if (!configPath) {
  console.error("Set XHARNESS_CONFIG to a private connector configuration");
  process.exit(1);
}
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
const base = require("node:path").dirname(configPath);
function read(name, fallback) {
  try {
    return JSON.parse(fs.readFileSync(base + "/" + name, "utf8"));
  } catch {
    return fallback;
  }
}
function write(name, value) {
  const p = base + "/" + name,
    t = p + "." + crypto.randomBytes(6).toString("hex");
  const fd = fs.openSync(t, "wx", 0o600);
  try {
    fs.writeFileSync(fd, JSON.stringify(value));
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(t, p);
  const dir = fs.openSync(base, "r");
  try {
    fs.fsyncSync(dir);
  } finally {
    fs.closeSync(dir);
  }
}
function eq(a, b) {
  const x = Buffer.from(String(a)),
    y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}
function hash(password, salt) {
  return crypto
    .pbkdf2Sync(password, Buffer.from(salt, "hex"), 210000, 32, "sha256")
    .toString("hex");
}
async function mutation(fn) {
  const lock = base + "/.mutation-lock";
  const deadline = Date.now() + 5000;
  while (true) {
    try {
      fs.mkdirSync(lock, { mode: 0o700 });
      break;
    } catch (e) {
      if (e.code !== "EEXIST") throw e;
      try {
        const pid = Number(fs.readFileSync(lock + "/pid", "utf8"));
        try {
          process.kill(pid, 0);
        } catch (err) {
          if (err.code === "ESRCH") {
            fs.rmSync(lock, { recursive: true, force: true });
            continue;
          }
        }
      } catch {
        try {
          if (Date.now() - fs.statSync(lock).mtimeMs > 30000)
            fs.rmSync(lock, { recursive: true, force: true });
        } catch {}
      }
      if (Date.now() > deadline) throw Error("busy");
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }
  fs.writeFileSync(lock + "/pid", String(process.pid), { mode: 0o600 });
  try {
    return fn();
  } finally {
    fs.rmSync(lock, { recursive: true, force: true });
  }
}
const sockets = new Map(),
  attempts = new Map();
function devices() {
  const s = read("devices.json", null);
  return s && s.version === 1 && Array.isArray(s.devices) ? s.devices : [];
}
function auth(req) {
  try {
    const m = /^Basic ([A-Za-z0-9+/=]+)$/.exec(req.headers.authorization || "");
    if (!m) return null;
    const raw = Buffer.from(m[1], "base64").toString("utf8"),
      i = raw.indexOf(":");
    if (i < 0) return null;
    const user = raw.slice(0, i),
      pass = raw.slice(i + 1);
    if (
      !/^device-[a-f0-9-]{36}$/.test(user) ||
      !/^[A-Za-z0-9_-]{43}$/.test(pass)
    )
      return null;
    const d = devices().find((x) => x.id === user && !x.revoked);
    if (
      !d ||
      !/^[a-f0-9]{32}$/.test(d.salt) ||
      !/^[a-f0-9]{64}$/.test(d.digest)
    )
      return null;
    return eq(hash(pass, d.salt), d.digest) ? d.id : null;
  } catch {
    return null;
  }
}
function json(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  res.end(JSON.stringify(body));
}
async function body(req) {
  let size = 0,
    chunks = [];
  for await (const c of req) {
    size += c.length;
    if (size > 8192) throw Error("body-too-large");
    chunks.push(c);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}
const options = {
  key: fs.readFileSync(config.tlsKey),
  cert: fs.readFileSync(config.tlsCert),
  minVersion: "TLSv1.2",
};
const cert = new crypto.X509Certificate(options.cert),
  fingerprint = crypto.createHash("sha256").update(cert.raw).digest("hex");
const server = https.createServer(options, async (req, res) => {
  const url = new URL(req.url, "https://connector.invalid");
  // No server credentials, paths or launch tokens in public metadata.
  if (req.method === "GET" && url.pathname === "/connector/info")
    return json(res, 200, {
      version: 1,
      nodeId: config.nodeId,
      name: config.name,
      fingerprint,
    });
  if (req.method === "GET" && url.pathname === "/connector/enroll-proof") {
    const nonce = url.searchParams.get("nonce") || "";
    if (!/^[a-f0-9]{64}$/.test(nonce))
      return json(res, 400, { error: "invalid-nonce" });
    return json(res, 200, {
      nodeId: config.nodeId,
      proof: crypto
        .createHmac("sha256", config.enrollmentSecret)
        .update(nonce)
        .digest("hex"),
    });
  }
  if (req.method === "POST" && url.pathname === "/connector/pair") {
    const addr = req.socket.remoteAddress;
    const now = Date.now();
    const a = attempts.get(addr) || { n: 0, until: 0 };
    if (a.until > now) return json(res, 429, { error: "try-later" });
    try {
      const b = await body(req);
      return await mutation(() => {
        const pairs = read("pairings.json", { version: 1, pairings: [] });
        const p = pairs.pairings.find(
          (p) => eq(p.id, b.id) && eq(p.code, b.code),
        );
        if (!p || p.expiresAt <= now || p.used) {
          a.n++;
          if (a.n >= 5) {
            a.until = now + 30000;
            a.n = 0;
          }
          attempts.set(addr, a);
          return json(res, 403, { error: "pairing-expired-or-invalid" });
        }
        const name =
          String(b.name || "手机")
            .trim()
            .slice(0, 80) || "手机";
        const id = "device-" + crypto.randomUUID(),
          secret = crypto.randomBytes(32).toString("base64url"),
          salt = crypto.randomBytes(16).toString("hex");
        const all = devices()
          .filter((d) => !d.revoked)
          .concat(
            devices()
              .filter((d) => d.revoked)
              .slice(-64),
          );
        if (all.filter((d) => !d.revoked).length >= 64)
          return json(res, 409, { error: "device-limit" });
        // Synchronous consume+write before yielding: one request can claim a code.
        p.used = true;
        delete p.code;
        write("pairings.json", pairs);
        all.push({
          id,
          name,
          salt,
          digest: hash(secret, salt),
          createdAt: now,
          revoked: false,
        });
        write("devices.json", { version: 1, devices: all });
        attempts.delete(addr);
        return json(res, 200, {
          version: 1,
          nodeId: config.nodeId,
          name: config.name,
          username: id,
          password: secret,
          remoteUrl: read("remote.json", {}).url || null,
        });
      });
    } catch {
      return json(res, 400, { error: "invalid-pairing-request" });
    }
  }
  const id = auth(req);
  if (!id) {
    res.setHeader("WWW-Authenticate", 'Basic realm="xHarness device"');
    return json(res, 401, { error: "device-auth-required" });
  }
  // Never issue or forward reusable upstream cookies to a paired device.
  const headers = {
    ...req.headers,
    host: config.upstreamHost + ":" + config.upstreamPort,
    authorization: config.upstreamAuthorization,
  };
  delete headers.cookie;
  delete headers["proxy-authorization"];
  const up = http.request(
    {
      host: config.upstreamHost,
      port: config.upstreamPort,
      path: req.url,
      method: req.method,
      headers,
    },
    (r) => {
      const h = { ...r.headers };
      delete h["set-cookie"];
      res.writeHead(r.statusCode, h);
      r.pipe(res);
    },
  );
  up.on("error", () => {
    if (!res.headersSent) json(res, 502, { error: "dsh-unavailable" });
    else res.destroy();
  });
  req.on("aborted", () => up.destroy());
  res.on("close", () => up.destroy());
  req.pipe(up);
});
server.on("upgrade", (req, socket, head) => {
  const id = auth(req);
  if (!id) {
    socket.end(
      "HTTP/1.1 401 Unauthorized\r\nConnection: close\r\nContent-Length: 0\r\n\r\n",
    );
    return;
  }
  const up = net.connect(config.upstreamPort, config.upstreamHost);
  const set = sockets.get(id) || new Set();
  set.add(socket);
  sockets.set(id, set);
  socket.on("close", () => {
    set.delete(socket);
    up.destroy();
  });
  socket.on("error", () => up.destroy());
  up.on("error", () => socket.destroy());
  up.on("connect", () => {
    const headers = {
      ...req.headers,
      host: config.upstreamHost + ":" + config.upstreamPort,
      authorization: config.upstreamAuthorization,
    };
    delete headers.cookie;
    delete headers["proxy-authorization"];
    const lines = [
      req.method + " " + req.url + " HTTP/1.1",
      ...Object.entries(headers).map(([k, v]) => k + ": " + v),
      "",
      "",
    ];
    up.write(lines.join("\r\n"));
    if (head.length) up.write(head);
    let response = Buffer.alloc(0);
    const handshake = (chunk) => {
      response = Buffer.concat([response, chunk]);
      if (response.length > 65536) {
        socket.destroy();
        up.destroy();
        return;
      }
      const end = response.indexOf("\r\n\r\n");
      if (end < 0) return;
      up.removeListener("data", handshake);
      const h = response
        .subarray(0, end)
        .toString("latin1")
        .split("\r\n")
        .filter((line) => !/^set-cookie:/i.test(line));
      socket.write(h.join("\r\n") + "\r\n\r\n");
      if (response.length > end + 4) socket.write(response.subarray(end + 4));
      up.pipe(socket);
    };
    up.on("data", handshake);
    socket.pipe(up);
  });
});
// Revocation also terminates already-open WS channels, not only future requests.
fs.watchFile(
  base + "/devices.json",
  { interval: 250, persistent: false },
  () => {
    const allowed = new Set(
      devices()
        .filter((d) => !d.revoked)
        .map((d) => d.id),
    );
    for (const [id, set] of sockets)
      if (!allowed.has(id)) {
        for (const s of set) s.destroy();
        sockets.delete(id);
      }
  },
);
server.requestTimeout = 30000;
server.headersTimeout = 15000;
server.listen(config.port || 3082, config.listenHost || "0.0.0.0", () =>
  console.log("xHarness connector ready on " + (config.port || 3082)),
);
process.on("SIGTERM", () => {
  for (const set of sockets.values()) for (const s of set) s.destroy();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
});
