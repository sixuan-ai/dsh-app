"use strict";
const $ = (id) => document.getElementById(id);
async function api(path, data) {
  const r = await fetch(
    path,
    data
      ? {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(data),
        }
      : {},
  );
  const b = await r.json();
  if (!r.ok) throw Error(b.error || "操作失败");
  return b;
}
function work(fn) {
  return async (e) => {
    e?.preventDefault();
    $("message").textContent = "处理中…";
    try {
      await fn(e);
      $("message").textContent = "已完成";
    } catch (e) {
      $("message").textContent = e.message;
    }
  };
}
async function refresh() {
  const s = await api("/status");
  const local =
    s.checks.authenticatedBridgeHttpStatus === 200 &&
    s.checks.tlsIdentity === true;
  const running = Object.values(s.services).every((v) => v === "active");
  $("health").textContent =
    (running && local
      ? "电脑连接器正常，DSH 已就绪。"
      : "电脑连接尚未就绪，请展开诊断检查服务状态。") +
    (s.remoteConfigured
      ? s.checks.remoteIdentity
        ? " 公网通路已验证。"
        : " 公网暂时不可达，局域网仍可单独使用。"
      : " 尚未配置公网，可先在同一网络配对使用。");
  $("status").textContent = JSON.stringify(
    { 服务: s.services, 检查: s.checks, 公网已注册: s.remoteConfigured },
    null,
    2,
  );
  const selected = $("host").value;
  $("host").replaceChildren(...s.lanAddresses.map((ip) => new Option(ip, ip)));
  if (s.lanAddresses.includes(selected)) $("host").value = selected;
  $("devices").replaceChildren(
    ...s.devices.map((d) => {
      const row = document.createElement("p");
      row.textContent =
        d.name +
        " · " +
        new Date(d.createdAt).toLocaleString() +
        " · " +
        d.id.slice(-8) +
        " · " +
        (d.revoked ? "已撤销" : "已授权") +
        " ";
      if (!d.revoked) {
        const btn = document.createElement("button");
        btn.textContent = "撤销";
        btn.onclick = work(async () => {
          await api("/revoke", { id: d.id });
          await refresh();
        });
        row.append(btn);
      }
      return row;
    }),
  );
}
$("refresh").onclick = work(refresh);
$("pair").onclick = work(async () => {
  const d = await api("/pair", { host: $("host").value });
  $("link").value = d.link;
  $("qr").src = "/qr.svg?t=" + Date.now();
  $("expiry").textContent =
    "有效至 " + new Date(d.expiresAt).toLocaleTimeString();
  $("pairing").hidden = false;
});
$("remote").onsubmit = work(async (e) => {
  const form = e.target;
  const values = Object.fromEntries(new FormData(form));
  try {
    await api("/remote", values);
    form.password.value = "";
    await refresh();
  } finally {
    form.password.value = "";
  }
});
work(refresh)();
