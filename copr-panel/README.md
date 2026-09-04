# copr-panel

s-ui / sing-box 的管理层。**不改、不重编 s-ui** —— 全部在它之上旁挂。

| 目录 | 是什么 |
|------|--------|
| `sui-converter/` | Flask 订阅转换器。抽 s-ui 的原生订阅 → 套分流规则 → 输出干净的 Clash 配置 `https://<域名>/get/<会员名>` |
| `web/` | Vue3 + Vite 管理面板。看板 / 节点 / 会员 / 分流编辑器 / 流量 / 设置。经 nginx `/panel/` 提供,同源反代 s-ui API |
| `deploy/` | 一键部署脚本。见 [`deploy/README.md`](deploy/README.md) |

## 快速开始

```bash
cd deploy
cp config.env.example config.env    # 至少填 DOMAIN 和 SUI_USER
sudo bash bootstrap.sh              # 装 s-ui → 证书 → 开节点 → converter → 面板 → 加固 → 自启
```

跑完只剩一件事:打开面板加会员,把 `https://<域名>/get/<会员名>` 发给他。

## 订阅是怎么出来的

```
客户端 → nginx /get/<name> → converter → s-ui 原生订阅(base64 URI 列表)
                                 ↓ 解析成 Clash proxies,注入 rules.json 的分流 + 防泄漏 DNS
                              Clash / mihomo 配置
```

- **回源**:`/get/<name>` 默认直接回源 s-ui 原生订阅,所以面板里新建的会员**立刻**能用,不需要注册到 `users.json`。`users.json` 只用于自定义映射(接第三方订阅)。
- **分流**:规则读 `rules.json`(默认值在 `rules.default.json`),面板「订阅分流」页可视化增删改、拖拽排序。
- **内联 GEOSITE/GEOIP,不用 rule-providers**:早期版本用 GitHub raw 上的 `.mrs` 规则集,国内客户端拉不到直接全崩。现在改成内联 `GEOSITE,xx` / `GEOIP,xx`,mihomo 自带数据,零外部下载。
- **防泄漏**:关 IPv6(服务器只有 v4 时防双栈绕过)、fake-ip 防污染、STUN/WebRTC 端口 REJECT、管理域名强制 DIRECT(连着 VPN 也能打开面板和更新订阅)。

## 改完怎么发上去

```bash
cd deploy && bash push.sh              # 本地构建面板 → 同步 → 远程 bootstrap.sh --update
bash push.sh --panel-only              # 只更新面板,不碰 converter
```

改节点/排障用 `deploy/` 里的 `ensure-*.sh`,都幂等可单独重跑,说明见 [`deploy/README.md`](deploy/README.md)。
