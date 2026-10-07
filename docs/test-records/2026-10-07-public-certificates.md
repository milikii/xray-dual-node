# 公共证书与 Certbot 续签修正

日期：2026-10-07。core：已校验的 v26.9.30。范围：技能/脚本更新，不修改在线节点。

## 变更与依据

旧生成器未传证书时会自动生成自签证书，安装器启用自签续期；该路径不能通过 Cloudflare
Full (Strict)。当前生成器强制公共证书校验，首次安装绑定 Certbot lineage，迁移脚本保留
节点凭据并设置公共证书及 Certbot 部署钩子。旧自签定时器模板已移除，兼容入口拒绝续签。

Certbot 官方 CLI 文档明确：普通 `renew --dry-run` 默认不运行 deploy hooks；
`--run-deploy-hooks` 在演练成功后用当前正式证书运行钩子，不安装 staging 证书。
官方来源及目标机签发/验收步骤见 [证书规程](../../references/certificates.md)。

## 已执行检查

| 检查 | 结果与范围 |
|---|---|
| `tests/check-skill.sh`、skill-creator `quick_validate.py` | PASS；入口、引用、脚本语法/帮助、ShellCheck、空白 |
| 私密导出、helper contracts、ASN、website、news-site、auth-results | PASS；已有行为回归 |
| `tests/unit/certificates.py` | PASS；公共信任、链完整性、域名/私钥/有效期校验与缺证书拒绝 |
| Certbot 部署事务 | PASS；模拟外部 service manager/Certbot，实际运行证书校验、文件安装、回执和失败恢复 |
| 故障注入 | PASS；Xray/Nginx 配置失败、restart/reload 失败恢复旧文件；恢复也失败时保留 700 私有备份 |
| 续签验收反例 | PASS；定时器无演练、Certbot 成功但未调用 hook、签发失败、续签配置变化均拒绝 PASS |
| `tests/unit/acme-http.py` | PASS；实际 Nginx 仅在回环测试端口服务 challenge，其他/越界路径 404 |
| `tools/poc/local-website.py` | PASS；网站、A/B 上传下载、鉴权/来源反例、后端故障，生成器使用测试 CA 签发的完整链 |
| 普通用户场景 | PASS；nobody 用户、PATH=/usr/bin:/bin 运行证书事务、HTTP-01 和完整网站集成；不要求 root 才能跑隔离测试 |

测试 CA 和私钥全在临时私有目录，生产校验器不信任它；仅修改一次性脚本副本的系统 CA 路径，
生产入口没有自定义信任根/运行根目录选项。事务测试的 `/etc`、`/opt`、`/run` 也只映射到临时
脚本副本，未写真实运行配置、未启停任何系统服务。运行文件不输出凭据，临时目录自动清理。
停止状态的服务不会因为证书部署被启动；节点配置在迁移和失败恢复中保持原内容。

## 仍须真实目标机验收

没有在本次维护环境申请用户域名证书，也没有运行真实 Certbot/systemd 续签或验证真实 CF Strict。
真实 HTTP-01/DNS-01 可达性、CA 签发、定时器触发、服务身份读取权限、Xray 重启/Nginx 重载、
CF 首页及 B 鉴权正反例，必须按规程逐项完成。用户贴出的其他机器日志不作为本次测试证据。
真实 Xray 重启会中断现有连接，不能称为无中断热重载；无网络/CA 保证可以确保将来每次续签都成功。
