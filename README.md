# Xray 双节点 Skill

供 **Codex / Claude Code** 使用的技能，版本 **0.1.0**。AI 按需读取操作规程，
完成部署、验收、排错、升级回滚、卸载和上游维护；辅助脚本处理下载校验、私密配置生成等确定性步骤。

在一台 VPS 共用 443：A 为 VLESS＋REALITY＋Vision，B 为经 Cloudflare 的
VLESS＋XHTTP packet-up＋TLS，启用 VLESS Encryption 和客户端 ECH。
允许目标协商 X25519，不用 REALITY 中继限速。最终只交付私有节点文件，执行者只看到路径和状态。

## 安装与调用

```sh
git clone https://github.com/milikii/xray-dual-node.git
cd xray-dual-node
scripts/install-skill.sh
```

| 平台 | 默认安装位置 | 调用 |
|---|---|---|
| Codex | `~/.agents/skills/xray-dual-node` | `$xray-dual-node` |
| Claude Code | `~/.claude/skills/xray-dual-node` | `/xray-dual-node` |

安装器将同一仓库软链接到两处。项目安装用 `--project /absolute/project`；冲突默认拒绝，
`--force` 先备份旧内容。安装后开新会话让平台发现技能。自然语言也可以触发：

> 使用 xray-dual-node，在这台 Debian VPS 部署双节点。沿用我提供的 CF 域名，不用 CF token。
> 完成后只告诉我节点文件路径，不显示内容。

> 按 xray-dual-node 排查节点不可用，保留原密钥和链接。

> 按 xray-dual-node 检查作者新 release，核对改动并更新技能，实测后再升级节点。

入口为 [SKILL.md](SKILL.md)，任务编排由执行者完成，没有要求用户掌握的独立 deploy CLI。
现存 `xrayctl` 只兼容私密导出和策略检查。

## 实测边界

core 固定 **v26.9.30**，哈希在 [versions.env](versions.env)。Debian 13 amd64＋真实 VPS/CF
已测双节点、ECH、鉴权反例、来源限制、常驻服务、自签证书检查和私密导出。
其他 Debian/Ubuntu 版本及 arm64 由执行者逐机验收，不扩大实测承诺。

带脚本的默认路径是 A′、每节点单用户、A enc=none、B packet-up。B′、多用户和特殊参数由
执行者核对源码后在副本中实现和验证，不宣称已有完整通用生成器。
GUI 导入边界见 [client-compat.md](references/client-compat.md)。

本次测试沿用 CF 橙云 DNS 和 **Full 模式可接受的自签源站证书**，未使用 token。
自签证书不能用于 Full (Strict)。也支持传入公共 CA 证书，由执行者对接并验收原有续期设施。
未伪称已实测 ACME/DNS-01。操作见 [部署规程](references/deploy.md)，记录见 [测试记录](docs/test-records)。

## 私密文件与维护

默认交付 `/etc/xray-skill/client/links.txt`（A/B 两行），附 `node-a.json`、`node-b.json`。
目录 700、文件 600，用户自己下载；AI 不预览、不贴聊天/Issue。两份 JSON 默认本地端口相同，二选一启动。
这种约束降低意外泄露，不能技术性隔离 root 权限的执行者。

上游跟进由执行者按 [MAINTENANCE.md](docs/MAINTENANCE.md) 执行：查官方变更 → 核对源码/文档
→ 更新技能 → 隔离及真实链路验证 → 更新 pin/知识库 → 提交发布。不会后台自动升级 VPS。
[当前计划](docs/PLAN.md) 记录本次 Skill 定位，早期 PoC/工具平台方案留作历史。

## 验证

```sh
tests/check-skill.sh
tests/unit/private-export.sh
tests/unit/helper-contracts.sh
tools/poc/local-routing.sh --xray /absolute/path/to/verified/xray
```

仓库 CI 只检查技能和辅助脚本，不含服务器凭据、不部署 VPS。
不得提交真实节点配置、部署域名/IP、UUID、token、密钥、证书或抓包。
