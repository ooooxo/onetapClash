# copr-panel

`copr.site`(s-ui / sing-box)的管理层。**不改、不重编 s-ui**——在它之上做旁挂:

- `sui-converter/` — **onetapclash 壳层 2.0**(Flask)。抽 s-ui 节点、套模块化分流、输出干净订阅 `http://copr.site/get/<user>`。升级自服务器上现有的 `/opt/sui-converter`。
- `web/` — Vue3 + Vite 管理面板(看板/探针、节点+TLS+预设、会员增删改批量、模块化分流编辑器、流量、设置)。经 nginx `copr.site/panel/`,同源反代 s-ui API。*(待建)*
- `deploy/` — nginx location + systemd unit + 幂等安装脚本。*(待建)*

## 地址不变保证

converter 2.0 的路由 / `users.json` 映射与 1.0 **完全一致**:
- `GET /get/<user>`、`/admin/users`(需 `X-Admin-Secret`)照旧。
- 用户订阅地址 `copr.site/get/<name>` **不变**,9 个用户无需换订阅。
- 只有「生成的内容」变好(分流 + DNS)。重启 converter = Flask 1 秒,**代理流量不断**。

## converter 2.0 改了什么

1. **模块化分流** — 规则从硬编码改为读 `rules.json`(`rules.default.json` 为默认)。面板/`/admin/rules` 可视化增删改、拖拽排序。模块:广告拦截 / 国内直连 / 电报 / 流媒体 / AI / 国外 / 自定义。
2. **DNS 修流媒体卡顿** — `fake-ip-filter: geosite:cn`(修国内漏代理);代理域名走境外 DoH(`proxy-server-nameserver` + `nameserver-policy`)→ 流媒体 CDN 就近服务器出口,不再“低延迟却卡”。
3. **rule-providers `.mrs`** — MetaCubeX 自动更新规则集,替代旧的 3 条硬编码。

## 部署阶段(破坏性递增,均先备份、可回滚)

1. **面板**（零影响）：静态包 + nginx `/panel/` + 同源反代 `/panel/api/`→s-ui。不碰 sing-box。
2. **分流**（几乎无影响）：换 `converter.py` + `rules.json`，重启 `sui-converter`。代理不断。
3. **性能修复**（有闪断,需你点头 + 低峰）：HY2 `ignore_client_bandwidth`、VLESS→真 Reality、qdisc fq。重启 sing-box。
