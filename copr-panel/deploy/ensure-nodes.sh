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
HY2_OBFS="${HY2_OBFS:-yes}"              # salamander 混淆,抗主动探测/DPI 识别 QUIC
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-}"   # 留空=沿用节点上已有的;都没有则自动生成
HY2_UP_MBPS="${HY2_UP_MBPS:-}"           # 两个都填 = 启用 Brutal 固定速率
HY2_DOWN_MBPS="${HY2_DOWN_MBPS:-}"

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
       REALITY_TAG REALITY_PORT REALITY_DEST TLS_CERT TLS_KEY WANT_REALITY \
       HY2_OBFS HY2_OBFS_PASSWORD HY2_UP_MBPS HY2_DOWN_MBPS

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

# ── Hysteria2 的期望参数(创建与校正共用同一份定义)────────────────────────
BRUTAL = bool(E["HY2_UP_MBPS"] and E["HY2_DOWN_MBPS"])
OBFS_ON = E["HY2_OBFS"].lower() not in ("no", "0", "false")

def hy2_tuning(existing_opts=None):
    """返回 hy2 入站里与线路质量相关的字段。existing_opts 用于沿用已有的 obfs 密码。"""
    out = {
        # Brutal 由客户端声明带宽驱动,服务端必须【不要】忽略客户端带宽,否则退回 BBR
        "ignore_client_bandwidth": not BRUTAL,
    }
    if OBFS_ON:
        pw = E["HY2_OBFS_PASSWORD"]
        if not pw and existing_opts:
            pw = ((existing_opts.get("obfs") or {}).get("password")) or ""
        if not pw:
            pw = secrets.token_urlsafe(16)
            print(f"[!] 生成 obfs 密码(请存进 config.env 的 HY2_OBFS_PASSWORD):{pw}")
        out["obfs"] = {"type": "salamander", "password": pw}
    return out

def reconcile_hy2():
    """节点已存在时,把 obfs / 拥塞控制校正到期望值 —— 只改这几项,其余原样保留。"""
    cur = existing.get(E["HY2_TAG"])
    if not cur:
        return
    want = hy2_tuning(cur)
    drift = {k: v for k, v in want.items() if cur.get(k) != v}
    if not OBFS_ON and "obfs" in cur:
        drift["obfs"] = None
    if not drift:
        print(f"[skip] 入站 {E['HY2_TAG']} 的混淆/拥塞控制已是期望值")
        return
    new = dict(cur)
    for k, v in drift.items():
        if v is None:
            new.pop(k, None)
        else:
            new[k] = v
    res = save("inbounds", "edit", new)
    if res.get("success") is not True:
        die(f"校正入站 {E['HY2_TAG']} 失败: {res.get('msg')}")
    print(f"[OK] 入站 {E['HY2_TAG']} 已校正:{', '.join(drift)}")

def hy2():
    tls_id = ensure_tls(f"{E['DOMAIN']}-le", {
        "enabled": True, "server_name": E["DOMAIN"], "alpn": ["h3"],
        "certificate_path": E["TLS_CERT"], "key_path": E["TLS_KEY"],
    }, {"enabled": True, "server_name": E["DOMAIN"], "insecure": False, "alpn": ["h3"]})
    return {"id": 0, "type": "hysteria2", "tag": E["HY2_TAG"], "listen": "::",
            "listen_port": int(E["HY2_PORT"]), "tls_id": tls_id,
            "addrs": [{"server": E["DOMAIN"], "server_port": int(E["HY2_PORT"])}],
            "out_json": {}, **hy2_tuning()}

ensure_inbound(E["HY2_TAG"], hy2)
reconcile_hy2()
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
