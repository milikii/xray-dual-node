# 已有 PoC 的常驻恢复

> 历史记录：文中的自签续期已废弃，不可用于新部署或当前维护。公共证书和续签执行 [证书规程](certificates.md)。


verified_against: Xray-core v26.9.30；Linode Debian 13；真实 CF；2026-10-06。

## 停服根因与修复

用户报告节点不可用时，VPS 的 Xray 进程数和 443 监听数均为 0。
前一轮清理停止了临时服务，只导出了链接，没有安装开机自启的常驻服务。
恢复原配置后，A/B 实际代理均成功，说明此次故障不需要轮换 UUID、密钥或链接。

本次恢复时，`tools/poc/activate-live.sh` 将已验证且正在运行的 `xray-poc.service` 转为常驻服务。
首版已将相同实现整理为 `scripts/install-runtime.sh`，旧路径保留兼容入口；新辅助脚本也允许
443 空闲的首次安装，当前使用方法见 [deploy.md](deploy.md)。下文保留当时恢复过程。
它是本次固定 v26.9.30 候选的恢复工具，不是通用 deploy/update 命令；只接受尚无
`/etc/xray-skill` 和 `xray-skill.service` 的首次迁移，避免覆盖已有部署。
中途失败可能留下暂存目录，须先诊断再处理，不可用它反复覆盖安装。

```sh
# 先用已校验的原始二进制检查配置并恢复 xray-poc.service。
# 所有 Xray 检查及运行输出必须留在私有日志，不能读回节点内容。
tools/poc/activate-live.sh \
  --work-dir /root/xray-poc/live \
  --xray-dir /root/xray-poc/bin
```

工具保持认证与路由数据不变，仅迁移证书/日志路径；以专用 `xray-skill` 用户运行，
限制可写路径和能力，开启 `Restart=on-failure` 与开机自启，不设 `RuntimeMaxSec`。
配置先由该服务用户执行 `-test`；切换失败时尝试恢复源 PoC 服务，保留原始私有文件。
成功后必须再测两节点代理，不能只凭 systemd active 宣布节点可用。

## 无 CF token 的源站证书

本次既有 CF 设置接受自签源站证书。保留原证书私钥，证书有效期改为 365 天；
`xray-skill-selfsigned.timer` 每日检查，不足 30 天时重新签发。
根目录 `/etc/xray-skill/recovery.json` 必须显式标记 `certificate_mode=self-signed`，
续期脚本不处理 ACME/其他证书。字段从私有配置中读取，不把域名/密钥放入工具输出。
安装新证书后先测试配置再重启，失败恢复旧证书。

这不是公共 CA 证书，不适用于 CF Full (Strict)；不声称 DNS-01/ACME 已经完成。
没有使用 token，没有修改 CF DNS 或 zone。原始两天证书仍留在 PoC 目录中仅作备份，
常驻服务使用 `/etc/xray-skill/certs/origin/` 的新证书。

当前运行位置：

| 路径/单元 | 用途 |
|---|---|
| `/opt/xray-skill/bin/xray-v26.9.30/` | core 与路由资产 |
| `/usr/local/bin/xray-skill-xray` | 固定版本软链接 |
| `/etc/xray-skill/config.json` | 640 root:xray-skill 的运行配置 |
| `/etc/xray-skill/secrets/client-{a,b}.json` | root 私有导出输入 |
| `/etc/xray-skill/client/links.txt` | 两条原节点链接，600 |
| `xray-skill.service` | 常驻节点服务，非 root |
| `xray-skill-selfsigned.timer` | 每日自签证书检查 |

## 已验收

- 两节点正常认证成功，错误 ML-DSA/shortId/Encryption 失败。
- 另一台机器访问伪装入口得到 HTTP 200，CF 回源得到 XHTTP 的 HTTP 404。
- `xray-skill.service` active/enabled，User=xray-skill，RuntimeMaxUSec=infinity。
- 原证书续签成功；再次运行续期服务退出 0，有效期充足时不重签、不重启节点。
- 新导出与原 `/root/xray-poc/export/links.txt` 逐字节一致，执行者未读回内容。

未测试整机重启、GUI 客户端导入和 ACME 续期。常驻恢复不代表完整 T1–T15 已完成。
后续清理仅停止验收用的临时客户端，不得停止已交付服务。
