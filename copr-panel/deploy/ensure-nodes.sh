#!/usr/bin/env bash
# =============================================================================
# ensure-nodes.sh — 幂等地把「能用的节点」开好(s-ui 装完但一个入站都没有 = 会员链接必死)
#   干什么: 经 s-ui API 建 TLS 记录 + 入站(Hysteria2 / VLESS-Reality),并放行防火墙端口
#   怎么跑: sudo bash ensure-nodes.sh          (读同目录 config.env)
#   需要什么: s-ui 已在跑、管理员账号密码、域名证书(hy2 用)
#   已存在同名 tag 就跳过,可以反复跑。
# 参数集中在这里:
# =============================================================================
DOMAIN="${DOMAIN:-}"
SUI_ADDR="${SUI_ADDR:-127.0.0.1:2095}"       # s-ui 面板本机地址
SUI_BASE="${SUI_BASE:-/app/}"                # s-ui 面板路径
SUI_USER="${SUI_USER:-}"
SUI_PASS="${SUI_PASS:-}"
HY2_TAG="${HY2_TAG:-quick}"
HY2_PORT="${HY2_PORT:-443}"                  # UDP;nginx 占的是 TCP 443,不冲突
REALITY_TAG="${REALITY_TAG:-reality}"
REALITY_PORT="${REALITY_PORT:-8443}"         # TCP;443/tcp 通常被 nginx 占着
REALITY_DEST="${REALITY_DEST:-www.apple.com}"
TLS_CERT="${TLS_CERT:-}"
TLS_KEY="${TLS_KEY:-}"
WANT_REALITY="${WANT_REALITY:-yes}"

set -euo pipefail
cd "$(dirname "$0")"
. ./_common.sh
load_config_env config.env
DOMAIN="${DOMAIN:?需要 DOMAIN}"
TLS_CERT="${TLS_CERT:-/etc/letsencrypt/live/${DOMAIN}/fullchain.pem}"
TLS_KEY="${TLS_KEY:-/etc/letsencrypt/live/${DOMAIN}/privkey.pem}"
[[ -n "$SUI_USER" && -n "$SUI_PASS" ]] || { echo "需要 SUI_USER / SUI_PASS(config.env 里填)"; exit 1; }
[[ -f "$TLS_CERT" && -f "$TLS_KEY" ]] || { echo "证书不存在: $TLS_CERT / $TLS_KEY —— 先申好证书再跑"; exit 1; }

export DOMAIN SUI_ADDR SUI_BASE SUI_USER SUI_PASS HY2_TAG HY2_PORT \
       REALITY_TAG REALITY_PORT REALITY_DEST TLS_CERT TLS_KEY WANT_REALITY

python3 - <<'PY'
import json, os, subprocess, secrets, sys, urllib.parse

E = os.environ
BASE = f"http://{E['SUI_ADDR']}{E['SUI_BASE'].rstrip('/')}"
JAR  = "/tmp/.ensure-nodes.cookie"
HOST = E["DOMAIN"]          # s-ui 设了面板域名时,Host 对不上会 403

def curl(args):
    r = subprocess.run(["curl", "-s", "-b", JAR, "-c", JAR, "-H", f"Host: {HOST}"] + args,
                       capture_output=True, text=True)
    return r.stdout

def jget(path):
    return json.loads(curl([f"{BASE}{path}"]))

def save(obj, action, data):
    # ⚠️ 必须 compact:s-ui 把 inbounds 原样存成 BLOB,SQLite 见 BLOB 先按 JSONB 解析,
    # `[1, 2]`(带空格,6 字节)恰好撞上 JSONB 头部长度 → "malformed JSON";`[1,2]` 才安全。
    body = urllib.parse.urlencode({"object": obj, "action": action,
                                   "data": json.dumps(data, separators=(',', ':'))})
    return json.loads(curl(["-X", "POST", f"{BASE}/api/save", "--data", body]))

def die(m):
    print(f"[ERR] {m}", file=sys.stderr); sys.exit(1)

# ── 登录 ─────────────────────────────────────────────────────────────────────
r = json.loads(curl(["-X", "POST", f"{BASE}/api/login",
                     "--data-urlencode", f"user={E['SUI_USER']}",
                     "--data-urlencode", f"pass={E['SUI_PASS']}"]))
if r.get("success") is not True:
    die(f"s-ui 登录失败: {r.get('msg')}")
print("[OK] s-ui 登录成功")

existing = {i["tag"]: i for i in (jget("/api/inbounds").get("obj") or {}).get("inbounds") or []}
tls_by_name = {t["name"]: t["id"] for t in (jget("/api/load?lu=0").get("obj") or {}).get("tls") or []}
opened = []   # (port, proto) 供防火墙放行

def ensure_tls(name, server, client):
    if name in tls_by_name:
        return tls_by_name[name]
    res = save("tls", "new", {"id": 0, "name": name, "server": server, "client": client})
    if res.get("success") is not True:
        die(f"建 TLS {name} 失败: {res.get('msg')}")
    for t in (res.get("obj") or {}).get("tls") or []:
        tls_by_name[t["name"]] = t["id"]
    if name not in tls_by_name:
        die(f"建了 TLS {name} 但拿不到 id")
    return tls_by_name[name]

def ensure_inbound(tag, build):
    if tag in existing:
        print(f"[skip] 入站 {tag} 已存在(id={existing[tag]['id']})")
        return
    res = save("inbounds", "new", build())
    if res.get("success") is not True:
        die(f"建入站 {tag} 失败: {res.get('msg')}")
    print(f"[OK] 入站 {tag} 已创建")

# ── Hysteria2(真实证书,UDP)────────────────────────────────────────────────
def hy2():
    tls_id = ensure_tls(f"{E['DOMAIN']}-le", {
        "enabled": True, "server_name": E["DOMAIN"], "alpn": ["h3"],
        "certificate_path": E["TLS_CERT"], "key_path": E["TLS_KEY"],
    }, {"enabled": True, "server_name": E["DOMAIN"], "insecure": False, "alpn": ["h3"]})
    return {"id": 0, "type": "hysteria2", "tag": E["HY2_TAG"], "listen": "::",
            "listen_port": int(E["HY2_PORT"]), "tls_id": tls_id,
            "ignore_client_bandwidth": True,       # 不按客户端宣告限速,交给 BBR
            "addrs": [{"server": E["DOMAIN"], "server_port": int(E["HY2_PORT"])}],
            "out_json": {}}

ensure_inbound(E["HY2_TAG"], hy2)
opened.append((E["HY2_PORT"], "udp"))

# ── VLESS + Vision + Reality(TCP)───────────────────────────────────────────
if E["WANT_REALITY"].lower() not in ("no", "0", "false"):
    def reality():
        kp = jget("/api/keypairs?k=reality").get("obj") or []
        pick = lambda p: next((x.split(": ", 1)[1] for x in kp if x.startswith(p)), "")
        priv, pub = pick("PrivateKey"), pick("PublicKey")
        if not priv or not pub:
            die("拿不到 Reality 密钥对")
        sid = secrets.token_hex(4)
        dest = E["REALITY_DEST"]
        tls_id = ensure_tls(f"reality-{dest}", {
            "enabled": True, "server_name": dest,
            "reality": {"enabled": True, "handshake": {"server": dest, "server_port": 443},
                        "private_key": priv, "short_id": [sid]},
        }, {"enabled": True, "server_name": dest,
            "utls": {"enabled": True, "fingerprint": "chrome"},
            "reality": {"enabled": True, "public_key": pub, "short_id": sid}})
        # 不要带 transport:{} —— 空 transport 会让 s-ui 生成链接时报 malformed JSON
        return {"id": 0, "type": "vless", "tag": E["REALITY_TAG"], "listen": "::",
                "listen_port": int(E["REALITY_PORT"]), "tls_id": tls_id,
                "addrs": [{"server": E["DOMAIN"], "server_port": int(E["REALITY_PORT"])}],
                "out_json": {}}
    ensure_inbound(E["REALITY_TAG"], reality)
    opened.append((E["REALITY_PORT"], "tcp"))

with open("/tmp/.ensure-nodes.ports", "w") as f:
    f.write("\n".join(f"{p}/{proto}" for p, proto in opened))
PY

# ── 防火墙放行节点端口 ───────────────────────────────────────────────────────
if command -v ufw >/dev/null && [[ -f /tmp/.ensure-nodes.ports ]]; then
  # `|| [[ -n "$rule" ]]`:文件最后一行没有换行符时 read 返回非 0,少了这句会漏掉最后一条规则
  # ——曾因此漏放 Reality 的 TCP 端口,节点在防火墙后连不上。
  while read -r rule || [[ -n "$rule" ]]; do
    [[ -n "$rule" ]] && ufw allow "$rule" >/dev/null 2>&1 && echo "[OK] ufw 放行 $rule"
  done < /tmp/.ensure-nodes.ports
fi
rm -f /tmp/.ensure-nodes.ports /tmp/.ensure-nodes.cookie

# ── 自检:端口真的在监听才算成功 ─────────────────────────────────────────────
sleep 2
ss -lun | grep -q ":${HY2_PORT}\b" && echo "[OK] Hysteria2 监听 UDP ${HY2_PORT}" \
  || echo "[!] UDP ${HY2_PORT} 没监听,看 journalctl -u s-ui"
if [[ "$(printf '%s' "$WANT_REALITY" | tr 'A-Z' 'a-z')" != "no" ]]; then
  ss -lnt | grep -q ":${REALITY_PORT}\b" && echo "[OK] Reality 监听 TCP ${REALITY_PORT}" \
    || echo "[!] TCP ${REALITY_PORT} 没监听,看 journalctl -u s-ui"
fi
