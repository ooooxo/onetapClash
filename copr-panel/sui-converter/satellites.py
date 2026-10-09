"""
附属节点(satellite):别的服务器上的 onetapclash,会员只在本机(主节点)管,自动镜像过去。
  - 订阅合并:/get/<名> 在本机节点之后追加各附属节点 /get/<名> 里的节点,按 label 加前缀区分
  - 会员镜像:本机 s-ui 的会员按名字同步到附属节点(增/删/启停/到期),附属节点自己生成凭证
配置在 SATELLITES_FILE(面板「设置 → 附属节点」写入),含 s-ui 管理员密码,文件权限 600。
配额:附属节点 volume 恒为 0;它上面跑的流量每轮同步加回主节点会员的 up/down,于是主节点 s-ui
自己的超额/到期/周期重置、面板流量、订阅里的已用量都把附属节点算在内。主节点停用会员 → 同步过去附属节点也停。
回写流量靠 s-ui 的 editbulk 接受 up/down,只有 ≤1.5 行;≥1.6 起服务端不让改,回写后会核对,不生效就报错。
"""
import copy, json, os, secrets, threading, time, urllib.parse, uuid
import requests

SATELLITES_FILE = os.environ.get("SATELLITES_FILE", "")
# 本机 s-ui API:同步时读会员列表。Host 必须是面板域名,否则 s-ui 设了域名时回 403
SUI_API = os.environ.get("SUI_API", "http://127.0.0.1:2095/app/api")
SUI_HOST = os.environ.get("SUI_HOST", "")
SYNC_INTERVAL = int(os.environ.get("SATELLITE_SYNC_INTERVAL", "120"))   # 秒
FETCH_TIMEOUT = 6   # 拉附属节点订阅的超时;附属节点挂了不能拖垮主订阅
MIRROR_DESC = "镜像自主节点,别在这里改"
# 各附属节点每个会员上次看到的 up/down,算增量用。丢了只会少算(重新以当前值为起点),不会多算
TRAFFIC_FILE = os.path.splitext(SATELLITES_FILE)[0] + ".traffic.json" if SATELLITES_FILE else ""

_lock = threading.Lock()          # 配置文件 读-改-写 与 同步 串行
_status = {}                      # url → {"ok", "at", "msg"};只在内存,面板展示用


def load():
    if not SATELLITES_FILE:
        return {"local": {}, "satellites": []}
    try:
        with open(SATELLITES_FILE, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {"local": {}, "satellites": []}


def _write(data):
    # 含管理员密码:临时文件先 600 再替换,任何时刻都不出现可读的副本
    tmp = f"{SATELLITES_FILE}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, SATELLITES_FILE)


def public_view():
    """给面板看的版本:密码只告诉有没有,不回传。"""
    d = load()
    loc = d.get("local") or {}
    return {
        "local": {"label": loc.get("label", ""), "user": loc.get("user", ""), "has_pass": bool(loc.get("pass"))},
        "satellites": [{"label": s["label"], "url": s["url"], "user": s["user"], "has_pass": bool(s.get("pass")),
                        "status": _status.get(s["url"])} for s in d.get("satellites", [])],
        "interval": SYNC_INTERVAL,
    }


def save(new):
    """面板提交的配置;pass 留空 = 沿用已存的(按 url 对应)。不合法抛 ValueError。"""
    if not SATELLITES_FILE:
        raise ValueError("converter 没配 SATELLITES_FILE,重跑 bootstrap.sh --update")
    with _lock:
        old = load()
        oldpass = {s["url"]: s.get("pass", "") for s in old.get("satellites", [])}
        loc_in = new.get("local") or {}
        loc = {"label": str(loc_in.get("label", "")).strip(), "user": str(loc_in.get("user", "")).strip(),
               "pass": loc_in.get("pass") or (old.get("local") or {}).get("pass", "")}
        sats, seen = [], set()
        for s in new.get("satellites") or []:
            url = str(s.get("url", "")).strip().rstrip("/")
            label = str(s.get("label", "")).strip()
            user = str(s.get("user", "")).strip()
            pw = s.get("pass") or oldpass.get(url, "")
            if not url.startswith("https://") or "/" in url[len("https://"):]:
                raise ValueError(f"地址要写成 https://域名(不带路径),当前 {url!r}")
            if url in seen:
                raise ValueError(f"{url} 重复")
            if not (label and user and pw):
                raise ValueError(f"{url}:前缀、账号、密码都要填")
            seen.add(url)
            sats.append({"label": label, "url": url, "user": user, "pass": pw})
        if sats and not (loc["user"] and loc["pass"]):
            raise ValueError("有附属节点时必须填本机 s-ui 账号密码(同步要读会员列表)")
        _write({"local": loc, "satellites": sats})


# ── 订阅合并 ────────────────────────────────────────────────────────────────
def prefix(proxies, label):
    if label:
        for p in proxies:
            p["name"] = f"{label} {p['name']}"
    return proxies


def fetch_proxies(username, extract, log):
    """各附属节点上同名会员的节点(已加前缀)。单个附属节点失败只记日志,不影响其他。"""
    out = []
    for s in load().get("satellites", []):
        url = f"{s['url']}/get/{urllib.parse.quote(username, safe='')}"
        try:
            r = requests.get(url, timeout=FETCH_TIMEOUT)   # 真证书,校验开着:响应里是会员凭证
        except requests.RequestException as e:
            log.error("附属节点 %s 订阅拉取失败: %r", s["url"], e)
            continue
        if r.status_code != 200:
            # 404 = 还没同步到 / 已停用;都不该带它的节点
            log.warning("附属节点 %s 返回 HTTP %s: %s", s["url"], r.status_code, username)
            continue
        out += prefix(extract(r.content.decode("utf-8", "replace")), s["label"])
    return out


# ── 会员镜像 ────────────────────────────────────────────────────────────────
class _Sui:
    """s-ui cookie 会话。附属节点走它面板的 HTTPS 同源反代 /panel/api。"""
    def __init__(self, api, user, pw, host=None):
        self.api, self.s = api, requests.Session()
        if host:
            self.s.headers["Host"] = host
        self.s.headers["X-Requested-With"] = "XMLHttpRequest"   # 过期时回 JSON 而不是 307
        r = self.s.post(f"{api}/login", data={"user": user, "pass": pw}, timeout=10).json()
        if r.get("success") is not True:
            raise RuntimeError(f"登录 {api} 失败: {r.get('msg')}")

    def get(self, path):
        r = self.s.get(f"{self.api}{path}", timeout=10).json()
        if r.get("success") is not True:
            raise RuntimeError(f"{path}: {r.get('msg')}")
        return r.get("obj") or {}

    def save(self, action, data):
        # 必须紧凑 JSON:s-ui 把 inbounds 当 BLOB 存,`[1, 2]` 会被 SQLite 误当 JSONB → malformed JSON
        body = {"object": "clients", "action": action, "data": json.dumps(data, separators=(",", ":"))}
        r = self.s.post(f"{self.api}/save", data=body, timeout=10).json()
        if r.get("success") is not True:
            raise RuntimeError(f"save {action}: {r.get('msg')}")


def _rb64(n):
    a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    return "".join(a[b & 63] for b in secrets.token_bytes(n))


def _new_client(name, enable, expiry, inbounds):
    # 与面板 web/src/lib/suiClient.ts buildClient 同结构;凭证本机生成,不必与主节点一致
    u1, u2, mp = str(uuid.uuid4()), str(uuid.uuid4()), _rb64(10)
    config = {
        "mixed": {"username": name, "password": mp}, "socks": {"username": name, "password": mp},
        "http": {"username": name, "password": mp}, "shadowsocks": {"name": name, "password": _rb64(32)},
        "shadowsocks16": {"name": name, "password": _rb64(16)}, "shadowtls": {"name": name, "password": _rb64(32)},
        "vmess": {"name": name, "uuid": u1, "alterId": 0}, "vless": {"name": name, "uuid": u1, "flow": "xtls-rprx-vision"},
        "anytls": {"name": name, "password": mp}, "trojan": {"name": name, "password": mp},
        "naive": {"username": name, "password": mp}, "hysteria": {"name": name, "auth_str": mp},
        "tuic": {"name": name, "uuid": u2, "password": mp}, "hysteria2": {"name": name, "password": mp},
    }
    return {"enable": enable, "name": name, "config": config, "inbounds": inbounds, "links": [],
            "volume": 0, "expiry": expiry, "up": 0, "down": 0, "desc": MIRROR_DESC, "group": "",
            "delayStart": False, "autoReset": False, "resetDays": 0}


def _sync_one(parent, s):
    sat = _Sui(f"{s['url']}/panel/api", s["user"], s["pass"])
    o = sat.get("/load?lu=0")
    ids = sorted(i["id"] for i in o.get("inbounds") or [])
    if not ids:
        raise RuntimeError("附属节点上没有入站,先在那台跑 bootstrap.sh")
    have = {c["name"]: c for c in o.get("clients") or []}
    n_new = n_edit = n_del = 0
    for name, p in parent.items():
        want = {"enable": bool(p["enable"]), "expiry": p.get("expiry") or 0, "inbounds": ids, "volume": 0}
        c = have.get(name)
        if c is None:
            sat.save("new", _new_client(name, want["enable"], want["expiry"], ids)); n_new += 1
            continue
        if {"enable": bool(c["enable"]), "expiry": c.get("expiry") or 0,
                "inbounds": sorted(c.get("inbounds") or []), "volume": c.get("volume") or 0} == want:
            continue
        # 列表里没有 config,直接 edit 会清空凭证 → 先取整条记录再改
        full = (sat.get(f"/clients?id={c['id']}").get("clients") or [None])[0]
        if not full:
            raise RuntimeError(f"读不到附属节点会员 {name}")
        full.update(want)
        sat.save("edit", full); n_edit += 1
    for name, c in have.items():
        if name not in parent:
            sat.save("del", c["id"]); n_del += 1
    # 本轮新建的会员计数从 0 开始
    usage = {n: (have[n]["up"], have[n]["down"]) if n in have else (0, 0) for n in parent}
    return f"{len(parent)} 人;新增 {n_new} 改 {n_edit} 删 {n_del}", usage


def _deltas(state, url, usage):
    """本轮附属节点各会员新增的流量;state[url] 换成本轮读数。第一次见到的会员以当前值为起点。"""
    old, out = state.get(url, {}), {}
    for name, (u, d) in usage.items():
        if name in old:
            ou, od = old[name]
            du, dd = (u - ou if u >= ou else u), (d - od if d >= od else d)   # 计数被清零过 → 全算新增
            if du or dd:
                out[name] = (du, dd)
    state[url] = {n: list(v) for n, v in usage.items()}
    return out


def _writeback(me, total):
    """把附属节点流量加到本机会员 up/down。editbulk 不带 config:s-ui 从库里补,不触发入站重载。"""
    cur = {c["name"]: c for c in me.get("/load?lu=0").get("clients") or []}
    batch, want = [], {}
    for name, (du, dd) in total.items():
        c = cur.get(name)
        if not c:
            continue                        # 本机刚删掉的会员
        c = {k: v for k, v in c.items() if k not in ("config", "links")}
        c["up"] += du; c["down"] += dd
        batch.append(c); want[name] = c["up"] + c["down"]
    if not batch:
        return
    me.save("editbulk", batch)
    after = {c["name"]: c for c in me.get("/load?lu=0").get("clients") or []}
    lost = [n for n, w in want.items() if n in after and after[n]["up"] + after[n]["down"] < w]
    if lost:
        raise RuntimeError(f"本机 s-ui 没接受流量回写({', '.join(lost)}),s-ui ≥1.6 不允许改 up/down")


def _load_traffic():
    try:
        with open(TRAFFIC_FILE, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def _write_traffic(state):
    tmp = f"{TRAFFIC_FILE}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, TRAFFIC_FILE)


def sync_all(log):
    with _lock:
        d = load()
        sats = d.get("satellites", [])
        if not sats:
            return
        loc = d.get("local") or {}
        try:
            me = _Sui(SUI_API, loc.get("user", ""), loc.get("pass", ""), SUI_HOST or None)
            parent = {c["name"]: c for c in me.get("/load?lu=0").get("clients") or []}
        except Exception as e:
            # 读不到本机会员就一个都别动:空列表会被当成「全删」
            for s in sats:
                _status[s["url"]] = {"ok": False, "at": int(time.time()), "msg": f"读本机会员失败: {e}"}
            log.error("附属节点同步:读本机会员失败: %r", e)
            return
        state = _load_traffic()
        before = copy.deepcopy(state)
        total, per = {}, {}
        for s in sats:
            try:
                msg, usage = _sync_one(parent, s)
                d = _deltas(state, s["url"], usage)
                per[s["url"]] = sum(u + v for u, v in d.values())
                for n, (u, v) in d.items():
                    tu, tv = total.get(n, (0, 0)); total[n] = (tu + u, tv + v)
                _status[s["url"]] = {"ok": True, "at": int(time.time()), "msg": msg}
            except Exception as e:
                _status[s["url"]] = {"ok": False, "at": int(time.time()), "msg": str(e)}
                log.error("附属节点 %s 同步失败: %r", s["url"], e)
        # 先记账再回写:回写调用失败就回滚读数下轮重来;进程恰好死在两步之间只会少算,不会重复扣
        _write_traffic(state)
        try:
            _writeback(me, total)
        except Exception as e:
            if not str(e).startswith("本机 s-ui 没接受"):
                _write_traffic(before)
            for s in sats:
                _status[s["url"]] = {"ok": False, "at": int(time.time()), "msg": f"流量回写失败: {e}"}
            log.error("附属节点流量回写失败: %r", e)
            return
        for url, b in per.items():
            if b and _status[url]["ok"]:
                _status[url]["msg"] += f";流量回写 {b / 1048576:.1f} MiB"


def start_loop(log):
    # 后台线程:converter 是单进程 app.run,只会起一份;换成多 worker 部署时要挪到独立定时任务
    def run():
        while True:
            try:
                sync_all(log)
            except Exception:
                log.exception("附属节点同步异常")
            time.sleep(SYNC_INTERVAL)
    threading.Thread(target=run, daemon=True, name="satellite-sync").start()
