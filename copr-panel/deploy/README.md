# deploy — 可复用部署脚手架

全靠 `config.env`,换服务器/域名只改它,脚本不写死任何值。

## 首次部署

```bash
cp config.env.example config.env    # 填 DOMAIN / 路径 / 强 CONV_ADMIN_SECRET / SSH_HOST
bash push.sh                        # 本地构建面板 → 同步 → 远程 install.sh
```

## 分阶段(破坏性递增)

| 阶段 | 命令 | 影响 |
|------|------|------|
| 1 面板 | `bash push.sh --panel-only` | 零影响(新增 nginx location + 静态,不碰 converter/sing-box) |
| 2 分流 | `bash push.sh` | 几乎无影响(换 converter + 重启 Flask,代理不断,订阅重拉一次) |
| 3 节点 | 服务器上 `sudo bash optimize-nodes.sh` | fq/缓冲零影响;HY2/VLESS 改动走面板 runbook(闪断) |

## 复用要点

- `install.sh` 幂等,每步先备份到 `/root/copr-panel-backup/<时间戳>`,可回滚。
- `--panel-only` 只更新面板,不动 converter。
- converter 部署**保留** `users.json` / `rules.json`(用户与规则不丢)。
- nginx 用 `envsubst` 从模板生成,变量全来自 config.env。
- 未来新机:改 config.env 的 DOMAIN/SSH_HOST 即可,一条 `push.sh` 复现。

## 回滚

```bash
ls /root/copr-panel-backup/         # 找时间戳
# 恢复 nginx: cp <bk>/*.conf /etc/nginx/sites-enabled/ && systemctl reload nginx
# 恢复 converter: cp <bk>/converter.py.bak /opt/sui-converter/converter.py && systemctl restart sui-converter
# 恢复节点: 导入 <bk>/s-ui.db.bak
```
