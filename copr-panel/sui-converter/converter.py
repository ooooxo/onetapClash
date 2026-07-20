#!/usr/bin/env python3
"""
onetapclash 壳层 2.1 — s-ui 订阅 converter(修正版)。
2.0 的教训:rule-providers 指向 GitHub raw,国内客户端拉不到 → 全崩。
2.1 改用【内联 GEOSITE / GEOIP 规则】—— mihomo 自带 geosite/geoip 数据,零外部下载、国内直接可用
(和一直能用的 1.0 同机制,只是更模块化)。分组只留 自动选择/手动选择。DNS 保持简单直连。
路由/地址/users.json 与 1.0 完全一致,订阅地址不变。
"""
from flask import Flask, Response, request, jsonify
import requests, yaml, json, os, base64, binascii
from urllib.parse import urlparse, parse_qs, unquote
from functools import wraps

app = Flask(__name__)
ADMIN_SECRET = os.environ.get("ADMIN_SECRET", "")
BASE = os.path.dirname(os.path.abspath(__file__))
USERS_FILE = os.environ.get("USERS_FILE", os.path.join(BASE, "users.json"))
RULES_FILE = os.environ.get("RULES_FILE", os.path.join(BASE, "rules.json"))
RULES_DEFAULT = os.path.join(BASE, "rules.default.json")


def load_users():
    try:
        with open(USERS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_users(users):
    with open(USERS_FILE, "w") as f:
        json.dump(users, f, ensure_ascii=False, indent=2)


def load_rules():
    for p in (RULES_FILE, RULES_DEFAULT):
        try:
            with open(p) as f:
                return json.load(f)
        except Exception:
            continue
    return {"modules": [], "groups": ["🚀 手动选择"], "final": "🚀 手动选择"}


def require_secret(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not ADMIN_SECRET or request.headers.get("X-Admin-Secret") != ADMIN_SECRET:
            return jsonify({"error": "Unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated


# ── s-ui 原生订阅解析(base64 的 URI 列表 → Clash proxies)─────────────────────
# s-ui 订阅永远返回 base64 编码的 分享链接列表(hysteria2:// / vless:// ...),不是 Clash。
# converter 自己解析,零依赖 s-ui 的订阅格式设置。
def _b64d(s):
    s = s.strip().replace("-", "+").replace("_", "/")
    try:
        return base64.b64decode(s + "=" * (-len(s) % 4)).decode("utf-8", "ignore")
    except (binascii.Error, ValueError):
        return ""

def extract_proxies(text):
    # 1) 上游本就是 Clash YAML(兼容旧 users.json)
    try:
        raw = yaml.safe_load(text)
        if isinstance(raw, dict) and raw.get("proxies"):
            return raw["proxies"]
    except Exception:
        pass
    # 2) s-ui 原生:整体 base64 → 逐行 URI
    body = text
    if "://" not in body:
        dec = _b64d(text)
        if "://" in dec:
            body = dec
    out = []
    for line in body.splitlines():
        line = line.strip()
        if "://" not in line:
            continue
        p = _parse_uri(line)
        if p:
            out.append(p)
    return out

def _name(u, default):
    return unquote(u.fragment) if u.fragment else default

def _parse_uri(uri):
    scheme = uri.split("://", 1)[0].lower()
    try:
        return {
            "hysteria2": _p_hy2, "hy2": _p_hy2, "vless": _p_vless,
            "trojan": _p_trojan, "vmess": _p_vmess, "ss": _p_ss, "tuic": _p_tuic,
        }.get(scheme, lambda _u: None)(uri)
    except Exception:
        return None

def _p_hy2(uri):
    u = urlparse(uri); q = parse_qs(u.query)
    p = {"name": _name(u, u.hostname or "hy2"), "type": "hysteria2",
         "server": u.hostname, "port": u.port or 443,
         "password": unquote(u.username or ""), "udp": True,
         "skip-cert-verify": q.get("insecure", ["0"])[0] in ("1", "true")}
    if q.get("sni", [None])[0]: p["sni"] = q["sni"][0]
    alpn = q.get("alpn", [None])[0]
    p["alpn"] = alpn.split(",") if alpn else ["h3"]
    if q.get("obfs", [None])[0] in ("salamander",):
        p["obfs"] = "salamander"
        if q.get("obfs-password", [None])[0]: p["obfs-password"] = q["obfs-password"][0]
    return p

def _tls_common(p, q, default_sni=None):
    sec = q.get("security", ["none"])[0]
    if sec in ("tls", "reality", "xtls"):
        p["tls"] = True
        sni = q.get("sni", [q.get("host", [default_sni])[0]])[0]
        if sni: p["servername"] = sni
        if q.get("fp", [None])[0]: p["client-fingerprint"] = q["fp"][0]
        if q.get("insecure", ["0"])[0] in ("1", "true"): p["skip-cert-verify"] = True
        if sec == "reality":
            ro = {}
            if q.get("pbk", [None])[0]: ro["public-key"] = q["pbk"][0]
            if q.get("sid", [None])[0]: ro["short-id"] = q["sid"][0]
            if ro: p["reality-opts"] = ro
    return p

def _net_common(p, q):
    net = q.get("type", ["tcp"])[0]
    p["network"] = net
    if net == "ws":
        opts = {"path": q.get("path", ["/"])[0]}
        if q.get("host", [None])[0]: opts["headers"] = {"Host": q["host"][0]}
        p["ws-opts"] = opts
    elif net == "grpc" and q.get("serviceName", [None])[0]:
        p["grpc-opts"] = {"grpc-service-name": q["serviceName"][0]}
    return p

def _p_vless(uri):
    u = urlparse(uri); q = parse_qs(u.query)
    p = {"name": _name(u, u.hostname or "vless"), "type": "vless",
         "server": u.hostname, "port": u.port or 443, "uuid": u.username, "udp": True}
    if q.get("flow", [None])[0]: p["flow"] = q["flow"][0]
    return _tls_common(_net_common(p, q), q)

def _p_trojan(uri):
    u = urlparse(uri); q = parse_qs(u.query)
    p = {"name": _name(u, u.hostname or "trojan"), "type": "trojan",
         "server": u.hostname, "port": u.port or 443,
         "password": unquote(u.username or ""), "udp": True}
    p["tls"] = True
    sni = q.get("sni", [q.get("host", [None])[0]])[0]
    if sni: p["sni"] = sni
    if q.get("insecure", ["0"])[0] in ("1", "true"): p["skip-cert-verify"] = True
    return _net_common(p, q)

def _p_vmess(uri):
    j = json.loads(_b64d(uri.split("://", 1)[1]) or "{}")
    p = {"name": j.get("ps") or j.get("add", "vmess"), "type": "vmess",
         "server": j.get("add"), "port": int(j.get("port", 443)),
         "uuid": j.get("id"), "alterId": int(j.get("aid", 0)),
         "cipher": j.get("scy", "auto"), "udp": True,
         "network": j.get("net", "tcp")}
    if str(j.get("tls", "")).lower() in ("tls", "1", "true"):
        p["tls"] = True
        if j.get("sni") or j.get("host"): p["servername"] = j.get("sni") or j.get("host")
    if j.get("net") == "ws":
        opts = {"path": j.get("path", "/")}
        if j.get("host"): opts["headers"] = {"Host": j["host"]}
        p["ws-opts"] = opts
    return p

def _p_ss(uri):
    rest = uri.split("://", 1)[1]
    frag, name = "", "ss"
    if "#" in rest:
        rest, frag = rest.split("#", 1); name = unquote(frag)
    if "@" in rest:
        cred, host = rest.split("@", 1); cred = _b64d(cred) or cred
    else:
        dec = _b64d(rest); cred, host = dec.split("@", 1)
    method, password = cred.split(":", 1)
    host = host.split("?", 1)[0]
    server, port = host.rsplit(":", 1)
    return {"name": name, "type": "ss", "server": server, "port": int(port),
            "cipher": method, "password": password, "udp": True}

def _p_tuic(uri):
    u = urlparse(uri); q = parse_qs(u.query)
    p = {"name": _name(u, u.hostname or "tuic"), "type": "tuic",
         "server": u.hostname, "port": u.port or 443, "udp": True,
         "uuid": u.username, "password": unquote(u.password or "")}
    if q.get("sni", [None])[0]: p["sni"] = q["sni"][0]
    if q.get("alpn", [None])[0]: p["alpn"] = q["alpn"][0].split(",")
    if q.get("allow_insecure", ["0"])[0] in ("1", "true"): p["skip-cert-verify"] = True
    return p


def build_dns():
    # 防泄漏 DNS:
    # - respect-rules=true → DNS 查询跟随代理规则走节点出口,境外域名的解析地区与出口一致(治 "DNS/代理地区冲突")
    # - 境外域名走远端 DoH(经节点),境内走国内 DNS;proxy-server-nameserver 解析节点自身域名走国内直连,避免回环
    # - fake-ip 防污染。ipv6 关闭,减少 IPv6 直连泄漏面
    return {
        "enable": True, "ipv6": False, "listen": "0.0.0.0:1053",
        "enhanced-mode": "fake-ip", "fake-ip-range": "198.18.0.1/16",
        "fake-ip-filter": ["*.lan", "+.local", "localhost", "*.localdomain",
                           "+.pool.ntp.org", "time.*.com", "*.msftconnecttest.com"],
        "default-nameserver": ["223.5.5.5", "119.29.29.29"],
        "proxy-server-nameserver": ["https://223.5.5.5/dns-query"],
        "nameserver": ["https://223.5.5.5/dns-query", "https://doh.pub/dns-query"],
        "nameserver-policy": {
            "geosite:cn,private": ["223.5.5.5", "119.29.29.29"],
            "geosite:geolocation-!cn": ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"],
        },
        "respect-rules": True,
    }


def build_clash_config(proxies, userinfo):
    rc = load_rules()
    proxy_names = [p["name"] for p in proxies]
    groups_cfg = rc.get("groups", ["🚀 手动选择", "♻️ 自动选择"])
    final = rc.get("final", groups_cfg[0] if groups_cfg else "🚀 手动选择")

    # 内联 GEOSITE/GEOIP + 自定义规则(无 rule-providers)
    rules = []
    for mod in rc.get("modules", []):
        if not mod.get("enabled", True):
            continue
        policy = mod.get("policy", final)
        for gs in mod.get("geosite", []):
            rules.append(f"GEOSITE,{gs},{policy}")
        for gi in mod.get("geoip", []):
            rules.append(f"GEOIP,{gi},{policy},no-resolve")
        for r in mod.get("rules", []):
            rules.append(r)
    rules.append(f"MATCH,{final}")

    # 自动组优先级:UDP(HY2/TUIC 抗丢包快)> Reality TCP > 普通 TCP
    def prio(p):
        if (p.get("type") or "") in ("hysteria2", "hysteria", "tuic"):
            return 0
        if p.get("reality-opts"):
            return 1
        return 2
    auto_order = [p["name"] for p in sorted(proxies, key=prio)]

    def grp(name):
        # 自动选择 = url-test 选最快:HY2 置顶为初始默认(UDP 延迟通常也最低,平时稳定在它),
        # tolerance 粘滞——其他节点快出 100ms 以上才切,防止临界节点活/死横跳导致连接反复重置
        if name == "♻️ 自动选择":
            return {"name": name, "type": "url-test", "url": "http://www.gstatic.com/generate_204",
                    "interval": 180, "tolerance": 100, "proxies": list(auto_order)}
        return {"name": name, "type": "select", "proxies": [*auto_order, "DIRECT"]}

    config = {
        # ipv6=false:服务器只有 IPv4 时,双栈客户端会用原生 IPv6 直连绕过代理→泄漏真实 IPv6。
        # 全局关 IPv6(+ DNS 不解析 AAAA)使客户端不产生 v6 目标,强制走 v4 代理,堵 IPv6 泄漏。
        # 注:WebRTC/IPv6 泄漏的防护在客户端 TUN 模式下才完全生效(系统代理模式会被绕过)。
        "ipv6": False,
        "mixed-port": 7890, "allow-lan": True, "mode": "rule", "log-level": "info",
        "external-controller": "127.0.0.1:9090",
        "dns": build_dns(),
        "proxies": proxies,
        "proxy-groups": [grp(g) for g in groups_cfg],
        "rules": rules,
    }
    out = yaml.dump(config, allow_unicode=True, default_flow_style=False, sort_keys=False)
    r = Response(out, content_type="text/plain; charset=utf-8")
    if userinfo:
        r.headers["Subscription-Userinfo"] = userinfo
    r.headers["Profile-Update-Interval"] = "12"
    return r


@app.route("/get/<username>")
def get_sub(username):
    users = load_users()
    if username not in users:
        return Response("User not found", status=404)
    try:
        resp = requests.get(users[username]["url"], verify=False, timeout=10)
        proxies = extract_proxies(resp.text)   # 兼容 Clash YAML 与 s-ui 原生 base64 URI
        if not proxies:
            return Response("No proxies found", status=502)
        return build_clash_config(proxies, resp.headers.get("Subscription-Userinfo", ""))
    except Exception as e:
        return Response(f"Error: {e}", status=500)


@app.route("/admin/users", methods=["GET"])
@require_secret
def list_users():
    return jsonify(load_users())


@app.route("/admin/users/<username>", methods=["POST"])
@require_secret
def add_user(username):
    data = request.get_json(silent=True)
    if not data or "url" not in data:
        return jsonify({"error": "Missing url"}), 400
    users = load_users()
    users[username] = {"url": data["url"]}
    save_users(users)
    return jsonify({"ok": True, "user": username})


@app.route("/admin/users/<username>", methods=["DELETE"])
@require_secret
def delete_user(username):
    users = load_users()
    if username not in users:
        return jsonify({"error": "User not found"}), 404
    del users[username]
    save_users(users)
    return jsonify({"ok": True, "deleted": username})


@app.route("/admin/rules", methods=["GET"])
@require_secret
def get_rules():
    return jsonify(load_rules())


@app.route("/admin/rules", methods=["POST"])
@require_secret
def set_rules():
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or "modules" not in data:
        return jsonify({"error": "Invalid rules"}), 400
    with open(RULES_FILE, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    return jsonify({"ok": True})


@app.route("/health")
def health():
    return jsonify({"ok": True, "users": len(load_users())})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=25501)
