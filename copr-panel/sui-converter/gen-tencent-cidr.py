#!/usr/bin/env python3
# 生成 tencent-cidr.txt:从 RIPEstat 拉腾讯 ASN 的已宣告网段,合并后写入(converter 的"腾讯直连"内置规则读它)。
# 用法: python3 gen-tencent-cidr.py   —— 幂等,网段没变就不产生 diff;更新后提交并 push.sh 部署。
# 需要:能访问 stat.ripe.net;只用标准库。任一 ASN 拉取失败或为空直接报错退出,不覆盖旧文件。
import ipaddress, json, os, sys, urllib.request

ASNS = ["AS132203", "AS45090"]   # 腾讯境外(微信 HK/SG 等)、腾讯境内
API = "https://stat.ripe.net/data/announced-prefixes/data.json?resource={}"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tencent-cidr.txt")

nets = []
for asn in ASNS:
    with urllib.request.urlopen(API.format(asn), timeout=30) as r:
        prefixes = [p["prefix"] for p in json.load(r)["data"]["prefixes"]]
    if not prefixes:
        sys.exit(f"{asn} 没拉到任何网段,不覆盖 {OUT}")
    nets += [ipaddress.ip_network(p) for p in prefixes]

v4 = ipaddress.collapse_addresses(n for n in nets if n.version == 4)
v6 = ipaddress.collapse_addresses(n for n in nets if n.version == 6)
lines = [str(n) for n in [*v4, *v6]]

tmp = OUT + ".tmp"
with open(tmp, "w") as f:
    f.write(f"# 腾讯 {' '.join(ASNS)} 已宣告网段(合并后)。由 gen-tencent-cidr.py 生成,不要手改。\n")
    f.write("\n".join(lines) + "\n")
os.replace(tmp, OUT)
print(f"{len(lines)} 条 → {OUT}")
