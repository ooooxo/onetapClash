#!/usr/bin/env python3
"""
onetapclash 壳层 2.1 — s-ui 订阅 converter(修正版)。
2.0 的教训:rule-providers 指向 GitHub raw,国内客户端拉不到 → 全崩。
2.1 改用【内联 GEOSITE / GEOIP 规则】—— mihomo 自带 geosite/geoip 数据,零外部下载、国内直接可用
(和一直能用的 1.0 同机制,只是更模块化 + 加看视频/AI 分组)。DNS 保持简单直连。
路由/地址/users.json 与 1.0 完全一致,订阅地址不变。
"""
from flask import Flask, Response, request, jsonify
import requests, yaml, json, os
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


def build_dns():
    # 简单直连 DNS(和 1.0 一致,国内可用),不做 geosite nameserver-policy(兼容性差)
    return {
        "enable": True, "ipv6": False, "listen": "0.0.0.0:1053",
        "enhanced-mode": "fake-ip", "fake-ip-range": "198.18.0.1/16",
        "default-nameserver": ["223.5.5.5", "119.29.29.29"],
        "nameserver": ["223.5.5.5", "119.29.29.29"],
        "fake-ip-filter": ["*.lan", "+.local", "localhost", "*.localdomain"],
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
        if name in ("🎬 看视频", "🤖 AI"):
            return {"name": name, "type": "select", "proxies": ["♻️ 自动选择", "🚀 手动选择", *auto_order]}
        return {"name": name, "type": "select", "proxies": [*auto_order, "DIRECT"]}

    config = {
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
        raw = yaml.safe_load(resp.text)
        proxies = raw.get("proxies", [])
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
