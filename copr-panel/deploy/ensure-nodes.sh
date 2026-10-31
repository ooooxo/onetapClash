#!/usr/bin/env bash
# =============================================================================
# ensure-nodes.sh — 幂等地把「能用的节点」开好(s-ui 装完但一个入站都没有 = 会员链接必死)
#   干什么: 经 s-ui API 建 TLS 记录 + 入站(Hysteria2 / VLESS-Reality),并放行防火墙端口
#   怎么跑: sudo bash ensure-nodes.sh          (读同目录 config.env)
#   需要什么: s-ui 已在跑、管理员账号密码、域名证书(hy2 用)
#   已存在同名 tag 不重建;但已有的 hy2 节点会被校正(TLS 换 LE 证书、obfs/拥塞控制对齐配置),
#   已有的 Reality 节点会被校正握手目标(密钥不变),s-ui 路由补上拦 BT / 拦私网目标两条规则、
#   DNS 为空时补 local + prefer_go(不让 sing-box 按 resolv.conf 注释误走 systemd-resolved),
#   不走订阅、手工导入分享链接的客户端需要重新导入。可以反复跑。
#   单独跑时需要 SUI_PASS(环境变量传入,别写进 config.env):SUI_PASS=xxx sudo -E bash ensure-nodes.sh
# 参数集中在这里:
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
. ./_common.sh
# 必须先读 config.env 再写默认值:load_config_env 不覆盖已有值,
# 反过来的话默认值先占位,单独跑脚本时 config.env 整个被无视。
load_config_env config.env
DOMAIN="${DOMAIN:-}"
SUI_ADDR="${SUI_ADDR:-127.0.0.1:${SUI_PORT:-2095}}"   # s-ui 面板本机地址
SUI_BASE="${SUI_BASE:-/app/}"                # s-ui 面板路径
SUI_USER="${SUI_USER:-}"
SUI_PASS="${SUI_PASS:-}"
HY2_TAG="${HY2_TAG:-quick}"
HY2_PORT="${HY2_PORT:-443}"                  # UDP;nginx 占的是 TCP 443,不冲突
REALITY_TAG="${REALITY_TAG:-reality}"
REALITY_PORT="${REALITY_PORT:-8443}"         # TCP;443/tcp 通常被 nginx 占着
REALITY_DEST="${REALITY_DEST:-}"             # 留空 = 偷自己:握手转给本机 nginx 的 $DOMAIN;填域名 = 借别人的站
TLS_PORT="${TLS_PORT:-443}"                  # 偷自己时握手目标 = 127.0.0.1:TLS_PORT(nginx)
TLS_CERT="${TLS_CERT:-}"
TLS_KEY="${TLS_KEY:-}"
WANT_REALITY="${WANT_REALITY:-yes}"
HY2_OBFS="${HY2_OBFS:-yes}"              # salamander 混淆,抗主动探测/DPI 识别 QUIC
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-}"   # 留空=沿用节点上已有的;都没有则自动生成
HY2_UP_MBPS="${HY2_UP_MBPS:-}"           # 两个都填 = 启用 Brutal 固定速率
HY2_DOWN_MBPS="${HY2_DOWN_MBPS:-}"

DOMAIN="${DOMAIN:?需要 DOMAIN}"
TLS_CERT="${TLS_CERT:-/etc/letsencrypt/live/${DOMAIN}/fullchain.pem}"
TLS_KEY="${TLS_KEY:-/etc/letsencrypt/live/${DOMAIN}/privkey.pem}"
[[ -n "$SUI_USER" && -n "$SUI_PASS" ]] || { echo "需要 SUI_USER / SUI_PASS(config.env 里填)"; exit 1; }
[[ -f "$TLS_CERT" && -f "$TLS_KEY" ]] || { echo "证书不存在: $TLS_CERT / $TLS_KEY —— 先申好证书再跑"; exit 1; }

# 登录 cookie = 管理员会话,不能放在全局可读的固定 /tmp 路径;脚本中途失败也要清掉
umask 077
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export WORK
export DOMAIN SUI_ADDR SUI_BASE SUI_USER SUI_PASS HY2_TAG HY2_PORT \
       REALITY_TAG REALITY_PORT REALITY_DEST TLS_PORT TLS_CERT TLS_KEY WANT_REALITY \
       HY2_OBFS HY2_OBFS_PASSWORD HY2_UP_MBPS HY2_DOWN_MBPS

python3 - <<'PY'
import json, os, subprocess, secrets, sys, urllib.parse

E = os.environ
BASE = f"http://{E['SUI_ADDR']}{E['SUI_BASE'].rstrip('/')}"
JAR  = f"{E['WORK']}/cookie"
HOST = E["DOMAIN"]          # s-ui 设了面板域名时,Host 对不上会 403

def curl(args):
    # s-ui ≥1.6 的 CSRF 检查:POST 不带 Origin/Referer 时必须有 X-Requested-With,否则一律 403
    r = subprocess.run(["curl", "-s", "-b", JAR, "-c", JAR, "-H", f"Host: {HOST}",
                        "-H", "X-Requested-With: XMLHttpRequest"] + args,
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

# /api/inbounds 只给摘要(id/tag/端口/tls_id…),没有 obfs、addrs、out_json;校正前必须按 id 取完整记录,
# 否则拿摘要去比对永远"有差异",拿摘要去保存会冲掉面板上改过的其他选项
existing = {i["tag"]: i for i in (jget("/api/inbounds").get("obj") or {}).get("inbounds") or []}

def full_inbound(tag):
    got = (jget(f"/api/inbounds?id={existing[tag]['id']}").get("obj") or {}).get("inbounds") or []
    if len(got) != 1:
        die(f"取入站 {tag} 完整记录失败")
    return got[0]
tls_all = (jget("/api/load?lu=0").get("obj") or {}).get("tls") or []
tls_by_name = {t["name"]: t["id"] for t in tls_all}
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

def le_tls():
    return ensure_tls(f"{E['DOMAIN']}-le", {
        "enabled": True, "server_name": E["DOMAIN"], "alpn": ["h3"],
        "certificate_path": E["TLS_CERT"], "key_path": E["TLS_KEY"],
    }, {"enabled": True, "server_name": E["DOMAIN"], "insecure": False, "alpn": ["h3"]})

def reconcile_hy2():
    """节点已存在时,把 TLS / obfs / 拥塞控制校正到期望值 —— 只改这几项,其余原样保留。
    TLS:老部署的 hy2 常是自签证书 + 冒充别人的 SNI + 客户端 insecure,这是明显的特征;
    统一换成本域名的 LE 证书(s-ui 会按新 TLS 重建 out_json,分享链接随之更新)。"""
    if E["HY2_TAG"] not in existing:
        return
    cur = full_inbound(E["HY2_TAG"])
    want = {"tls_id": le_tls(), **hy2_tuning(cur)}
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
    return {"id": 0, "type": "hysteria2", "tag": E["HY2_TAG"], "listen": "::",
            "listen_port": int(E["HY2_PORT"]), "tls_id": le_tls(),
            "addrs": [{"server": E["DOMAIN"], "server_port": int(E["HY2_PORT"])}],
            "out_json": {}, **hy2_tuning()}

ensure_inbound(E["HY2_TAG"], hy2)
reconcile_hy2()
opened.append((E["HY2_PORT"], "udp"))

# ── VLESS + Vision + Reality(TCP)───────────────────────────────────────────
if E["WANT_REALITY"].lower() not in ("no", "0", "false"):
    # 握手目标。偷自己(默认):SNI = 本域名,握手转给本机 nginx —— 探测者看到的是本域名的真证书和真站点,
    # SNI 解析出的 IP 就是本机,不会出现"SNI 是 CDN 大站、IP 却是小 VPS"的错位。
    if E["REALITY_DEST"]:
        SNI, HS = E["REALITY_DEST"], {"server": E["REALITY_DEST"], "server_port": 443}
    else:
        SNI, HS = E["DOMAIN"], {"server": "127.0.0.1", "server_port": int(E["TLS_PORT"])}

    def reality_tls(priv, pub, sid):
        return ensure_tls(f"reality-{SNI}", {
            "enabled": True, "server_name": SNI,
            "reality": {"enabled": True, "handshake": HS, "private_key": priv, "short_id": [sid]},
        }, {"enabled": True, "server_name": SNI,
            "utls": {"enabled": True, "fingerprint": "chrome"},
            "reality": {"enabled": True, "public_key": pub, "short_id": sid}})

    def reality():
        kp = jget("/api/keypairs?k=reality").get("obj") or []
        pick = lambda p: next((x.split(": ", 1)[1] for x in kp if x.startswith(p)), "")
        priv, pub = pick("PrivateKey"), pick("PublicKey")
        if not priv or not pub:
            die("拿不到 Reality 密钥对")
        # 不要带 transport:{} —— 空 transport 会让 s-ui 生成链接时报 malformed JSON
        return {"id": 0, "type": "vless", "tag": E["REALITY_TAG"], "listen": "::",
                "listen_port": int(E["REALITY_PORT"]), "tls_id": reality_tls(priv, pub, secrets.token_hex(4)),
                "addrs": [{"server": E["DOMAIN"], "server_port": int(E["REALITY_PORT"])}],
                "out_json": {}}

    def reconcile_reality():
        """已有节点的握手目标与期望不一致 → 复制原 TLS 记录(密钥、short_id 原样)只改握手目标/SNI,
        存成新记录再切 tls_id。不原地改旧记录:换 tls_id 与 hy2 校正同一条路,s-ui 会重建分享链接。"""
        if E["REALITY_TAG"] not in existing:
            return
        cur = full_inbound(E["REALITY_TAG"])
        old = next((t for t in tls_all if t["id"] == cur.get("tls_id")), None)
        if old is None:
            die(f"入站 {E['REALITY_TAG']} 的 TLS 记录(id={cur.get('tls_id')})不存在")
        if old["server"].get("server_name") == SNI and old["server"]["reality"].get("handshake") == HS:
            print(f"[skip] 入站 {E['REALITY_TAG']} 的握手目标已是 {SNI}")
            return
        server = json.loads(json.dumps(old["server"]))
        client = json.loads(json.dumps(old["client"]))
        server["server_name"], server["reality"]["handshake"] = SNI, HS
        client["server_name"] = SNI
        new = dict(cur, tls_id=ensure_tls(f"reality-{SNI}", server, client))
        res = save("inbounds", "edit", new)
        if res.get("success") is not True:
            die(f"校正入站 {E['REALITY_TAG']} 失败: {res.get('msg')}")
        print(f"[OK] 入站 {E['REALITY_TAG']} 握手目标 {old['server'].get('server_name')} → {SNI}")

    ensure_inbound(E["REALITY_TAG"], reality)
    reconcile_reality()
    opened.append((E["REALITY_PORT"], "tcp"))

# ── 服务端路由加固 ───────────────────────────────────────────────────────────
# BT 流量招投诉、也是 IP 被标记的常见诱因;私网目标 = 会员能经代理摸到本机 127.0.0.1 上的
# s-ui 面板 / converter 等内部服务。插在开头的 sniff / hijack-dns 之后:协议要先嗅探出来才能匹配,
# 且发往私网 DNS(如 192.168.1.1:53)的查询应先被劫持应答,不能被私网规则直接拒掉。
HARDEN_RULES = [{"protocol": ["bittorrent"], "action": "reject"},
                {"ip_is_private": True, "action": "reject"}]
cfg = (jget("/api/load?lu=0").get("obj") or {}).get("config")
if not isinstance(cfg, dict):
    die("取不到 s-ui 的 sing-box 基础配置")
rules = cfg.setdefault("route", {}).setdefault("rules", [])
missing = [r for r in HARDEN_RULES if r not in rules]
changed = []
if missing:
    if not any(r.get("action") == "sniff" for r in rules):
        rules.insert(0, {"action": "sniff"})
    at = 0
    while at < len(rules) and rules[at].get("action") in ("sniff", "hijack-dns"):
        at += 1
    rules[at:at] = missing
    changed.append(f"路由加固 {len(missing)} 条(拦 BT、拦私网目标)")

# DNS 不写 = sing-box 用默认 local;1.13 起它见 /etc/resolv.conf 开头注释提到 systemd-resolved
# 就改走 DBus 问 resolved。有的镜像留着这句注释而 resolved 没开 → 所有域名解析失败,节点连得上
# 却什么都打不开(vpn-am 2026-10-27)。prefer_go = 只按 resolv.conf 里的 nameserver 自己查。
# 只有一个 DNS 服务器时 sing-box 默认用它解析出站域名,不用再设 default_domain_resolver。
servers = cfg.setdefault("dns", {}).setdefault("servers", [])
if not servers:
    servers.append({"type": "local", "tag": "local", "prefer_go": True})
    changed.append("DNS 改为 local + prefer_go")

if changed:
    res = save("config", "set", cfg)
    if res.get("success") is not True:
        die(f"写入 s-ui 基础配置失败: {res.get('msg')}")
    print(f"[OK] s-ui 基础配置:{';'.join(changed)}")
else:
    print("[skip] 路由加固规则与 DNS 均已就位")

with open(f"{E['WORK']}/ports", "w") as f:
    f.write("\n".join(f"{p}/{proto}" for p, proto in opened))
PY

# ── 防火墙放行节点端口 ───────────────────────────────────────────────────────
if command -v ufw >/dev/null && [[ -f "$WORK/ports" ]]; then
  # `|| [[ -n "$rule" ]]`:文件最后一行没有换行符时 read 返回非 0,少了这句会漏掉最后一条规则
  # ——曾因此漏放 Reality 的 TCP 端口,节点在防火墙后连不上。
  while read -r rule || [[ -n "$rule" ]]; do
    [[ -n "$rule" ]] && ufw allow "$rule" >/dev/null 2>&1 && echo "[OK] ufw 放行 $rule"
  done < "$WORK/ports"
fi

# ── 自检:端口真的在监听才算成功 ─────────────────────────────────────────────
sleep 2
ss -lun | grep ":${HY2_PORT}\b" >/dev/null && echo "[OK] Hysteria2 监听 UDP ${HY2_PORT}" \
  || echo "[!] UDP ${HY2_PORT} 没监听,看 journalctl -u s-ui"
# 与上面 Python 建节点、bootstrap 放行端口的判定一致(no/0/false 都算关)
if [[ ! "$(printf '%s' "$WANT_REALITY" | tr 'A-Z' 'a-z')" =~ ^(no|0|false)$ ]]; then
  ss -lnt | grep ":${REALITY_PORT}\b" >/dev/null && echo "[OK] Reality 监听 TCP ${REALITY_PORT}" \
    || echo "[!] TCP ${REALITY_PORT} 没监听,看 journalctl -u s-ui"
fi
