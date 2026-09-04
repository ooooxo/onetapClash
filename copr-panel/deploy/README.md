# deploy — 可复用部署脚手架

全靠 `config.env`,换服务器/域名只改它,脚本不写死任何值。

## 真·一键(全新机器)

```bash
cp config.env.example config.env    # 至少填 DOMAIN 和 SUI_USER
sudo bash bootstrap.sh              # 装 s-ui → 证书 → 节点 → converter → 面板 → 加固 → 自启
```

跑完就能用:**你只需要打开面板加会员**,订阅地址 `https://<域名>/get/<会员名>` 立即可用。

`bootstrap.sh` 编排下面这些脚本,每个都幂等、可单独重跑:

| 脚本 | 干什么 | 什么时候单独跑 |
|------|--------|----------------|
| `ensure-sui.sh` | 静默装 s-ui、设账号/端口、**清空 webListen** | 面板报「后端不可达」时 |
| `ensure-nodes.sh` | 经 API 建 Hysteria2 + VLESS-Reality 入站,放行端口 | 会员链接不可用 / 没有节点时 |
| `ensure-services.sh` | 开机自启、崩溃重启、证书续期钩子、每分钟看门狗 | 服务不会自动拉起时 |
| `harden.sh` | fail2ban + ufw + sshd 开公钥登录 | 只想做安全加固时 |

## 两个必须知道的坑(都已在脚本里修掉)

1. **`webListen` 不能填域名。** s-ui 面板里设了「面板域名」会把 `webListen` 写成域名,于是它
   只绑那个公网 IP;而 nginx 反代的是 `127.0.0.1:<端口>` → 连不上 → 前端一律报
   「后端不可达」,但 s-ui 自己看起来完全正常,极难排查。`ensure-sui.sh` 会把它清空。

2. **发给 s-ui 的 JSON 必须紧凑,不能带空格。** s-ui 把 `client.inbounds` 原样存成 BLOB,
   SQLite 见 BLOB 会先按 JSONB 解析:`[1, 2]`(6 字节)恰好撞上 JSONB 头部长度而被解成乱码
   → `malformed JSON`,会员保存失败;`[1,2]`(5 字节)长度对不上,退回文本解析才正常。
   表现就是「会员绑一个节点能建、绑两个必失败」。前端 `JSON.stringify` 天然紧凑,
   自己写脚本时注意 `json.dumps(..., separators=(',',':'))`。

## 日常更新(已部署过的机器)

```bash
bash push.sh                        # 本地构建面板 → 同步 → 远程 install.sh
```

## 各步骤的破坏性

| 动作 | 命令 | 影响 |
|------|------|------|
| 更新面板 | `bash push.sh --panel-only` | 零影响(只换静态文件,不碰 converter / sing-box) |
| 更新分流 | `bash push.sh` | 几乎无影响(换 converter + 重启 Flask ~1s,代理不断,订阅重拉一次) |
| 开/改节点 | `sudo bash ensure-nodes.sh` | s-ui 重载 sing-box,**在线用户闪断一次**;已存在的 tag 会跳过,不会重建 |
| 系统加固 | `sudo bash harden.sh` | 会 `ufw --force reset` 重建规则,**必须在 ensure-nodes.sh 之前跑**,否则冲掉节点端口 |
| 自启/调优 | `sudo bash ensure-services.sh` | 零影响(enable + drop-in + sysctl fq/BBR,不重启服务) |

## 复用要点

- `install.sh` 幂等,每步先备份到 `/root/copr-panel-backup/<时间戳>`,可回滚。
- `--panel-only` 只更新面板,不动 converter。
- converter 部署**保留** `users.json` / `rules.json`(用户与规则不丢)。
- nginx 用 `envsubst` 从模板生成,变量全来自 config.env。
- 未来新机:改 config.env 的 DOMAIN/SSH_HOST 即可,一条 `bootstrap.sh` 从零复现。
- `ensure-services.sh` 里带了 fq + BBR + 大缓冲的 sysctl(原 `optimize-nodes.sh` 的有用部分)。

## 回滚

```bash
ls /root/copr-panel-backup/         # 找时间戳
# 恢复 nginx: cp <bk>/*.conf /etc/nginx/sites-enabled/ && systemctl reload nginx
# 恢复 converter: cp <bk>/converter.py.bak /opt/sui-converter/converter.py && systemctl restart sui-converter
# 恢复节点: 导入 <bk>/s-ui.db.bak
```
