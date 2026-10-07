# Xray 双节点 Skill

供 **Codex / Claude Code** 使用的技能，版本 **0.1.0**。AI 按需读取操作规程，
完成部署、验收、排错、升级回滚、卸载和上游维护；辅助脚本处理下载校验、私密配置生成等确定性步骤。

在一台 VPS 共用 443：A 为 VLESS＋REALITY＋Vision，B 为经 Cloudflare 的
VLESS＋XHTTP packet-up＋TLS，启用 VLESS Encryption 和客户端 ECH。
XHTTP 必须使用公共 CA 证书，默认 Let’s Encrypt + Certbot 自动续签与部署钩子，CF Full (Strict)。
签发失败不回退自签；续签后自动校验、重启 Xray、重载 Nginx，失败恢复旧证书。
允许目标协商 X25519，不用 REALITY 中继限速。节点内容只交付为私有文件，执行者只看到路径和状态。
最终回复另附实际 XHTTP 域名的 Cloudflare 缓存绕过表达式及设置步骤，可直接复制，详见 [CF 清单](references/cloudflare-checklist.md#缓存绕过表达式与最终交付)。
新部署的 XHTTP 域名默认附带 AI 资讯静态站：随机选择 AI 新闻、硬件、论文或综合类型及样式，
每三天从公开 RSS 更新标题、短摘要、日期和原文链接，失败保留旧页。普通访问展示网页，
节点路径经独立回环 Nginx 转发；详见 [网站规程](references/website.md)。

## 安装与调用

可以在要创建节点的 VPS 本机打开 Codex / Claude Code 并安装技能。
部署目标未明确时，技能先询问“是否在当前机器部署？”；确认后直接开始本机检查和部署，
选择其他机器时再收集远程连接信息。已经明确指定目标时不重复确认。

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
已测双节点、ECH、鉴权反例、来源限制、常驻服务和私密导出。
其他 Debian/Ubuntu 版本及 arm64 由执行者逐机验收，不扩大实测承诺。
新增网站模式已通过隔离环境的静态站、A/B 代理和来源反例测试；真实 CF/ECH 与 systemd 生命周期
仍需现场验收，见 [网站测试记录](docs/test-records/2026-10-07-website.md)。

带脚本的默认路径是 A′、每节点单用户、A enc=none、B packet-up。B′、多用户和特殊参数由
执行者核对源码后在副本中实现和验证，不宣称已有完整通用生成器。
GUI 导入边界见 [client-compat.md](references/client-compat.md)。

旧 PoC 曾使用自签证书，只保留为历史记录；当前部署路径已禁止自签。
公共证书验证、续签部署与失败回滚通过隔离测试；真实 ACME 签发/续签及 CF Full (Strict)
仍须在目标机验收，不把离线模拟标成真实签发。见 [证书规程](references/certificates.md)
和 [测试记录](docs/test-records)。

## 私密文件与维护

默认在调用技能时的当前目录交付 `links.txt`（A/B 两行）、`node-a.json`、`node-b.json`。
文件 600，保留当前目录权限；AI 不预览、不贴聊天/Issue。两份 JSON 默认本地端口相同，二选一启动。
节点按源站 IP 归属命名，例如 `US-oracle-reality`、`US-oracle-xhttp+tls+cdn`；日本使用 `JP` 前缀。
国家或运营商无法确认时使用 `ZZ` / `unknown` 并说明，不根据 CF CDN 边缘位置命名。
这种约束降低意外泄露，不能技术性隔离 root 权限的执行者。

上游跟进由执行者按 [MAINTENANCE.md](docs/MAINTENANCE.md) 执行：查官方变更 → 核对源码/文档
→ 更新技能 → 隔离及真实链路验证 → 更新 pin/知识库 → 提交发布。不会后台自动升级 VPS。
[当前计划](docs/PLAN.md) 记录本次 Skill 定位，早期 PoC/工具平台方案留作历史。

## 验证

```sh
tests/check-skill.sh
tests/unit/private-export.sh
tests/unit/helper-contracts.sh
python3 tests/unit/reality-asn.py
python3 tests/unit/website.py
python3 tests/unit/news-site.py
python3 tests/unit/auth-results.py
python3 tests/unit/certificates.py
python3 tests/unit/acme-http.py
python3 tests/unit/cf-cache-rule.py
tools/poc/local-routing.sh --xray /absolute/path/to/verified/xray
python3 tools/poc/local-website.py --xray /absolute/path/to/verified/xray
```

仓库 CI 只检查技能和辅助脚本，不含服务器凭据、不部署 VPS。
不得提交真实节点配置、部署域名/IP、UUID、token、密钥、证书或抓包。
