#!/usr/bin/env python3
"""
onetapclash 壳层 2.1 — s-ui 订阅 converter(修正版)。
2.0 的教训:rule-providers 指向 GitHub raw,国内客户端拉不到 → 全崩。
2.1 改用【内联 GEOSITE / GEOIP 规则】—— mihomo 自带 geosite/geoip 数据,零外部下载、国内直接可用
(和一直能用的 1.0 同机制,只是更模块化)。分组只留 自动选择/手动选择。DNS 保持简单直连。
路由/地址/users.json 与 1.0 完全一致,订阅地址不变。
"""
from flask import Flask, Response, request, jsonify
import requests, yaml, json, os, sys, re, base64, binascii, hmac, threading, ipaddress
from urllib.parse import urlparse, urlsplit, parse_qs, unquote, quote
from functools import wraps

app = Flask(__name__)
ADMIN_SECRET = os.environ.get("ADMIN_SECRET", "")
BASE = os.path.dirname(os.path.abspath(__file__))
USERS_FILE = os.environ.get("USERS_FILE", os.path.join(BASE, "users.json"))
RULES_FILE = os.environ.get("RULES_FILE", os.path.join(BASE, "rules.json"))
RULES_DEFAULT = os.path.join(BASE, "rules.default.json")
# s-ui 原生订阅前缀:/get/<名> 未在 users.json 时回源 SUI_SUB_BASE+<名>(面板建的会员即刻可用)
SUI_SUB_BASE = os.environ.get("SUI_SUB_BASE", "http://127.0.0.1:2096/sub/")
# 端口跳跃:服务端把 UDP <段> 全部 REDIRECT 到 hy2 真实端口(见 deploy/ensure-hopping.sh),
# 这里只负责把段告诉客户端。运营商对单个固定 UDP 端口的 QoS 是 hy2 掉速断流的主因。
HY2_HOP_PORTS = os.environ.get("HY2_HOP_PORTS", "")        # 形如 "20000-25000";空=不启用
HY2_HOP_INTERVAL = os.environ.get("HY2_HOP_INTERVAL", "30") # 秒,支持 "15-30" 随机区间
# 被重定向的 hy2 真实端口。只有这个端口的 hy2 节点才下发 ports —— 面板另建的 hy2 入站没被重定向,
# 给它们也加上跳跃段,客户端就会往别的入站上发包。空=不区分(全部 hy2 都加,旧行为)。
HY2_PORT = int(os.environ["HY2_PORT"]) if os.environ.get("HY2_PORT") else None
# Brutal 固定速率(Mbps)。设了就在订阅里下发 up/down,服务端 ignore_client_bandwidth 必须为 false。
# BBR 遇丢包会退让,在国内到海外这种高丢包链路上速度塌方;Brutal 不退让,按固定速率推。
HY2_UP_MBPS = os.environ.get("HY2_UP_MBPS", "")
HY2_DOWN_MBPS = os.environ.get("HY2_DOWN_MBPS", "")
# 只填一个或填了 "100M" 这种,会下发 mihomo 不认的带宽或悄悄退回 BBR —— 启动就拒绝,systemd 日志里能看到
if (HY2_UP_MBPS or HY2_DOWN_MBPS) and not all(re.fullmatch(r"[1-9][0-9]*", v) for v in (HY2_UP_MBPS, HY2_DOWN_MBPS)):
    sys.exit(f"HY2_UP_MBPS/HY2_DOWN_MBPS 必须同时为空(BBR)或同时为正整数 Mbps,"
             f"当前 up={HY2_UP_MBPS!r} down={HY2_DOWN_MBPS!r}")
# 服务器有公网 IPv6(域名有 AAAA)时设 yes。mihomo 全局 ipv6:false 会直接拒绝解析/拨号任何 v6 地址
# (resolver.ErrIPv6Disabled,连 v6 字面量都不行),节点只剩 v6 可达时客户端必然连不上。
CLIENT_IPV6 = os.environ.get("CLIENT_IPV6", "").lower() in ("yes", "1", "true")


# admin 写接口的 读-改-写 串行化:两个请求并发保存时,后写的会吞掉先写的改动
_lock = threading.Lock()


def _read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _write_json(path, data):
    # 同目录临时文件 + os.replace 原子替换:写到一半崩溃也不会留下半截 JSON
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)


def load_users():
    # 只有文件不存在才当空;JSON 坏了必须报错,否则下一次 admin 保存会把全部映射覆盖成 {}
    try:
        return _read_json(USERS_FILE)
    except FileNotFoundError:
        return {}


def load_rules():
    # rules.json 不存在(面板从没保存过)才用默认;解析失败要报错,不能悄悄换回默认分流
    try:
        return _read_json(RULES_FILE)
    except FileNotFoundError:
        return _read_json(RULES_DEFAULT)


# mihomo 内置出站;规则/final 只能指向这些或本配置的组。节点名因会员而异,不能写进公共规则。
BUILTIN_POLICIES = ("DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE")


def check_rules(rc):
    """校验 groups/final/模块策略/自定义规则的策略名,返回 (groups, final);不合法抛 ValueError。
    mihomo 遇到未定义的策略名会拒绝整份配置 —— 一条手滑的规则就让所有会员一起断网。"""
    groups = rc.get("groups", ["🚀 手动选择", "♻️ 自动选择"])
    if not (isinstance(groups, list) and groups and all(isinstance(g, str) and g for g in groups)):
        raise ValueError("groups 必须是非空的组名列表")
    if len(set(groups)) < len(groups) or set(groups) & set(BUILTIN_POLICIES):
        raise ValueError(f"groups 有重名,或与内置策略 {'/'.join(BUILTIN_POLICIES)} 重名")
    allowed = [*groups, *BUILTIN_POLICIES]

    def need(pol, where):
        if not isinstance(pol, str) or pol not in allowed:
            raise ValueError(f"{where}:策略 {pol!r} 不存在,可选 {' / '.join(allowed)}")

    final = rc.get("final", groups[0])
    need(final, "final")
    mods = rc.get("modules", [])
    if not (isinstance(mods, list) and all(isinstance(m, dict) for m in mods)):
        raise ValueError("modules 必须是对象列表")
    for m in mods:
        where = f"模块「{m.get('name') or m.get('id')}」"
        need(m.get("policy", final), where)
        for k in ("geosite", "geoip", "rules"):
            v = m.get(k, [])
            if not (isinstance(v, list) and all(isinstance(x, str) for x in v)):
                raise ValueError(f"{where}:{k} 必须是字符串列表")
        for r in m.get("rules", []):
            parts = [x.strip() for x in r.split(",")]
            while parts and parts[-1] in ("no-resolve", "src"):   # 策略后面的可选参数
                parts.pop()
            if len(parts) < 2:
                raise ValueError(f"{where}:规则 {r!r} 格式不对,应为 类型,内容,策略")
            need(parts[-1], f"{where} 规则 {r!r}")
    return groups, final


def require_secret(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        # compare_digest:逐字节比较耗时恒定,不给按响应时间猜密钥的机会
        got = request.headers.get("X-Admin-Secret", "")
        if not ADMIN_SECRET or not hmac.compare_digest(got.encode(), ADMIN_SECRET.encode()):
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
    # 单条链接不认识/解析失败只丢这一个节点,不连累整份订阅;但要进日志,别静默少节点
    scheme = uri.split("://", 1)[0].lower()
    fn = {
        "hysteria2": _p_hy2, "hy2": _p_hy2, "vless": _p_vless,
        "trojan": _p_trojan, "vmess": _p_vmess, "ss": _p_ss, "tuic": _p_tuic,
    }.get(scheme)
    if not fn:
        app.logger.warning("跳过不支持的协议: %s", scheme)
        return None
    try:
        p = fn(uri)
    except Exception as e:
        app.logger.warning("跳过解析失败的 %s 链接: %r", scheme, e)
        return None
    # server 为空时会下发 server: null,mihomo 直接拒绝整份配置
    if not p.get("server"):
        app.logger.warning("跳过缺 server 的 %s 节点: %s", scheme, p.get("name"))
        return None
    return p

def _p_hy2(uri):
    u = urlparse(uri); q = parse_qs(u.query)
    p = {"name": _name(u, u.hostname or "hy2"), "type": "hysteria2",
         "server": u.hostname, "port": u.port or 443,
         # hy2 URI 规范:auth 是整段 userinfo,"user:pass" 形式的 auth 就是 "user:pass";urlparse 会把它拆开
         "password": unquote(u.netloc.rpartition("@")[0]), "udp": True,
         "skip-cert-verify": q.get("insecure", ["0"])[0] in ("1", "true")}
    if q.get("sni", [None])[0]: p["sni"] = q["sni"][0]
    alpn = q.get("alpn", [None])[0]
    p["alpn"] = alpn.split(",") if alpn else ["h3"]
    # 端口跳跃:mihomo 配了 ports 就忽略 port,但仍保留 port 供不支持跳跃的客户端回退
    if HY2_HOP_PORTS and (HY2_PORT is None or p["port"] == HY2_PORT):
        p["ports"] = HY2_HOP_PORTS
        # 纯数字要发 int;"15-30" 这种随机区间才是字符串
        p["hop-interval"] = int(HY2_HOP_INTERVAL) if HY2_HOP_INTERVAL.isdigit() else HY2_HOP_INTERVAL
    # Brutal:客户端声明带宽 → 服务端启用固定速率拥塞控制(抗丢包)
    if HY2_UP_MBPS and HY2_DOWN_MBPS:
        p["up"] = f"{HY2_UP_MBPS} Mbps"
        p["down"] = f"{HY2_DOWN_MBPS} Mbps"
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
        cred, host = rest.rsplit("@", 1)
        # SIP002:userinfo 是 base64(method:pass),或明文 method:pass(密码百分号编码)。
        # base64 字母表里没有 ':',据此区分;不能先试 b64 —— b64decode 跳过非法字符,明文长度凑巧时会被解成乱码
        plain = unquote(cred)
        cred = plain if ":" in plain else _b64d(cred)
    else:
        dec = _b64d(rest); cred, host = dec.rsplit("@", 1)
    method, password = cred.split(":", 1)
    host, _, query = host.partition("?")
    # plugin(obfs/v2ray-plugin)没做转换,不带插件下发的节点必然连不上 → 抛错,由 _parse_uri 跳过并记日志
    if parse_qs(query).get("plugin", [""])[0]:
        raise ValueError("ss plugin 不支持")
    server, port = host.split("/", 1)[0].rsplit(":", 1)   # SIP002 允许 host:port/?plugin=
    return {"name": name, "type": "ss", "server": server.strip("[]"), "port": int(port),
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


# PyYAML 按 YAML 1.1 决定加不加引号,mihomo(go-yaml v3)按 YAML 1.2 读:0e123456 / 08123456 这类串
# 1.1 眼里不是数字就裸写,1.2 却读成数字 → Reality short-id(8 位随机 hex)变数字,整份配置被拒。
# 数字/+/-/. 开头的字符串一律加引号,两个版本都只能读成字符串。
class _Dumper(yaml.SafeDumper):
    pass

_Dumper.add_representer(str, lambda d, s: d.represent_scalar(
    "tag:yaml.org,2002:str", s, style="'" if s[:1] and s[0] in "0123456789+-." else None))


def build_dns(direct_domains=None):
    # 防泄漏 DNS:
    # - respect-rules=true → DNS 查询跟随代理规则走节点出口,境外域名的解析地区与出口一致(治 "DNS/代理地区冲突")
    # - 境外域名走远端 DoH(经节点),境内走国内 DNS;proxy-server-nameserver 解析节点自身域名走国内直连,避免回环
    # - fake-ip 防污染。服务器没有 IPv6 时关掉 AAAA,减少 IPv6 直连泄漏面(见 CLIENT_IPV6)
    # - direct_domains:管理域名(面板/订阅/节点)加入 fake-ip-filter,拿真实 IP,连着 VPN 也能直连打开
    fake_ip_filter = ["*.lan", "+.local", "localhost", "*.localdomain",
                      "+.pool.ntp.org", "time.*.com", "*.msftconnecttest.com"]
    for d in (direct_domains or []):
        if d:
            fake_ip_filter += [d, f"+.{d}"]
    return {
        # 只听本机:0.0.0.0 会把客户端变成局域网/公网 WiFi 上的开放 DNS 解析器
        "enable": True, "ipv6": CLIENT_IPV6, "listen": "127.0.0.1:1053",
        "enhanced-mode": "fake-ip", "fake-ip-range": "198.18.0.1/16",
        "fake-ip-filter": fake_ip_filter,
        "default-nameserver": ["223.5.5.5", "119.29.29.29"],
        "proxy-server-nameserver": ["https://223.5.5.5/dns-query"],
        "nameserver": ["https://223.5.5.5/dns-query", "https://doh.pub/dns-query"],
        "nameserver-policy": {
            "geosite:cn,private": ["223.5.5.5", "119.29.29.29"],
            "geosite:geolocation-!cn": ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"],
        },
        "respect-rules": True,
    }


def build_clash_config(proxies, userinfo, mgmt_domain=None):
    rc = load_rules()
    # 修复前存下的坏 rules.json 在这里直接 500,不下发一份会被 mihomo 整体拒绝的配置
    groups_cfg, final = check_rules(rc)

    # 节点重名(或与组名/DIRECT 重名)mihomo 会拒绝整份配置 → 追加 " 2"、" 3" 区分
    taken = set(groups_cfg) | set(BUILTIN_POLICIES)
    for p in proxies:
        base = name = str(p["name"]); n = 1
        while name in taken:
            n += 1; name = f"{base} {n}"
        p["name"] = name; taken.add(name)

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
    # 管理域名(面板/订阅/节点同域)强制直连 —— 连着 VPN 也能直接打开面板/更新订阅,不回环
    if mgmt_domain:
        rules.insert(0, f"DOMAIN-SUFFIX,{mgmt_domain},DIRECT")
    rules.append(f"MATCH,{final}")

    # 自动组优先级:UDP(HY2/TUIC 抗丢包快)> Reality TCP > 普通 TCP
    def prio(p):
        if (p.get("type") or "") in ("hysteria2", "hysteria", "tuic"):
            return 0
        if p.get("reality-opts"):
            return 1
        return 2
    auto_order = [p["name"] for p in sorted(proxies, key=prio)]

    # 默认 fallback 而不是 url-test:url-test 只比 HTTP 延迟,不看丢包 —— hy2 延迟低但
    # 丢包严重时它依然会选 hy2,用户感受就是"延迟好看但很卡",而且延迟抖动会来回横跳。
    # fallback 只在主节点【真的探测不通】时才切,主节点恒定是 auto_order[0](hy2),
    # 即"以 hy2 为准,挂了才退到 Reality"。想要选最快就把 auto_group_type 改成 url-test。
    auto_type = rc.get("auto_group_type", "fallback")

    def grp(name):
        if name == "♻️ 自动选择":
            g = {"name": name, "url": "http://www.gstatic.com/generate_204",
                 "proxies": list(auto_order), "interval": 60, "timeout": 3000,
                 "max-failed-times": 3}
            if auto_type == "url-test":
                g.update({"type": "url-test", "tolerance": 100, "interval": 180})
            else:
                g["type"] = "fallback"
            return g
        return {"name": name, "type": "select", "proxies": [*auto_order, "DIRECT"]}

    config = {
        # ipv6=false:服务器只有 IPv4 时,双栈客户端会用原生 IPv6 直连绕过代理→泄漏真实 IPv6。
        # 全局关 IPv6(+ DNS 不解析 AAAA)使客户端不产生 v6 目标,强制走 v4 代理,堵 IPv6 泄漏。
        # 服务器有 IPv6 时(CLIENT_IPV6)必须打开:v6 目标可经节点出站,不再是泄漏;
        # 而且关着的话,节点域名只有 AAAA 时客户端根本拨不出去。
        # 注:WebRTC/IPv6 泄漏的防护在客户端 TUN 模式下才完全生效(系统代理模式会被绕过)。
        "ipv6": CLIENT_IPV6,
        # allow-lan 关:没配 authentication,开着等于把 7890 免密借给同一网络里的任何人。
        # 不下发 external-controller:无 secret 的控制口本机任意进程/网页都能调;GUI 客户端会自己配。
        "mixed-port": 7890, "allow-lan": False, "mode": "rule", "log-level": "info",
        # ── 线路稳定性(mihomo 客户端侧)────────────────────────────────────
        # tcp-concurrent:对多个解析结果并发握手取最快,单条路径丢包/被阻断时不至于卡死
        # unified-delay:统一测速口径(去掉握手差异),避免因延迟抖动误判而频繁切节点
        # store-selected:记住手动选的节点,更新订阅后不被重置回默认
        "tcp-concurrent": True,
        "unified-delay": True,
        "find-process-mode": "off",
        "keep-alive-interval": 15,
        "profile": {"store-selected": True},
        "dns": build_dns([mgmt_domain] if mgmt_domain else None),
        "proxies": proxies,
        "proxy-groups": [grp(g) for g in groups_cfg],
        "rules": rules,
    }
    out = yaml.dump(config, Dumper=_Dumper, allow_unicode=True, default_flow_style=False, sort_keys=False)
    r = Response(out, content_type="text/plain; charset=utf-8")
    if userinfo:
        r.headers["Subscription-Userinfo"] = userinfo
    r.headers["Profile-Update-Interval"] = "12"
    return r


@app.route("/get/<username>")
def get_sub(username):
    users = load_users()
    entry = users.get(username)
    # 优先 users.json 的自定义映射;否则回源 s-ui 原生订阅(面板/后台建的会员即刻可用,无需手动注册)
    if isinstance(entry, dict) and entry.get("url"):
        url = entry["url"]
    else:
        # 会员名可能带空格/#/?/中文(Flask 已解码),必须重新编码成单段路径,否则打到 s-ui 别的路径上
        url = f"{SUI_SUB_BASE.rstrip('/')}/{quote(username, safe='')}"
    try:
        resp = requests.get(url, verify=False, timeout=10)
    except requests.RequestException:
        # 异常文本里有回源 URL(可能带 token),只进日志,不回给公网
        app.logger.exception("回源失败: %s", username)
        return Response("Upstream unavailable", status=502)
    if 400 <= resp.status_code < 500:
        return Response("User not found", status=404)   # s-ui 无此会员
    if not 200 <= resp.status_code < 300:
        app.logger.error("回源返回 HTTP %s: %s", resp.status_code, username)
        return Response("Upstream error", status=502)
    # 不用 resp.text:text/* 没写 charset 时 requests 按 ISO-8859-1 猜,emoji/中文节点名全乱码
    proxies = extract_proxies(resp.content.decode("utf-8", "replace"))   # 兼容 Clash YAML 与 s-ui 原生 base64 URI
    if not proxies:
        return Response("No proxies found", status=502)
    return build_clash_config(proxies, resp.headers.get("Subscription-Userinfo", ""), _mgmt_domain(request.host))


def _mgmt_domain(host):
    # 面板/订阅域名 = 请求 Host,强制直连。IPv6 字面量形如 [2a01::1]:443,不能按 ':' 切;
    # IP 访问时没有域名可加 DOMAIN-SUFFIX
    h = urlsplit("//" + (host or "")).hostname
    try:
        ipaddress.ip_address(h or "")
        return None
    except ValueError:
        return h


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
    with _lock:
        users = load_users()
        users[username] = {"url": data["url"]}
        _write_json(USERS_FILE, users)
    return jsonify({"ok": True, "user": username})


@app.route("/admin/users/<username>", methods=["DELETE"])
@require_secret
def delete_user(username):
    with _lock:
        users = load_users()
        if username not in users:
            return jsonify({"error": "User not found"}), 404
        del users[username]
        _write_json(USERS_FILE, users)
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
    try:
        check_rules(data)
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    with _lock:
        _write_json(RULES_FILE, data)
    return jsonify({"ok": True})


@app.route("/health")
def health():
    return jsonify({"ok": True, "users": len(load_users())})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=25501)
