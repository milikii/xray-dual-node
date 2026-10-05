# xray-dual-node

面向 Claude Code / Codex 的 Xray 双节点部署 Skill，当前处于 **Phase 0 验证阶段**。
已在真实 Linode VPS + Cloudflare 上跑通 A′ 两节点、ECH、鉴权反例和来源限制。
尚无可用的 `xrayctl deploy`，没有发布生产 pin，客户端导入矩阵及证书自动化仍未验收。

执行方案见 [docs/PLAN.md](docs/PLAN.md)，实测进度见
[references/poc-results.md](references/poc-results.md)。后续 T1–T15 按方案在 T0 出口后实施。

已按用户最新选择实现：目标不支持 ML-KEM 时允许协商 X25519；生成配置不使用 REALITY
中继带宽限速；[SKILL.md](SKILL.md) 要求执行者不读取节点内容，只交付私有文件。
注意：当前 core 的客户端仍需提供混合群，不能把回退解释为任意旧客户端都能连接。

已有 PoC 配置可私密导出（不会启动服务）：

```bash
scripts/xrayctl show-links \
  --client-a /root/xray-poc/live/client-a.json \
  --client-b /root/xray-poc/live/client-b.json \
  --output-dir /root/xray-poc/export --xray /root/xray-poc/bin/xray
```

`links.txt` 恰好两行（A/B），另附两份完整客户端 JSON；目录 700、文件 600，
终端只显示路径和状态。详情见 [私密交付](references/private-export.md)。
产物由用户自行下载；AI 不预览、不回显链接或认证材料。真实 VPS 的临时服务目前已停止，
导出成功不等于节点正在运行。GUI 客户端导入仍待实测。

当前可复现的本地检查：

```bash
shellcheck tools/poc/local-routing.sh
tests/unit/private-export.sh
tools/poc/local-routing.sh --xray /absolute/path/to/verified/xray
```

测试二进制要求为 `v26.9.30`，下载来源和 SHA-256 见
[upstream-state.json](references/upstream-state.json)。脚本不下载或安装二进制；
只监听回环高端口，使用临时证书和 xray 生成的密钥，结束时清理进程及文件。
该脚本仅验证本地路由。真实 CF 实验另有 `prepare-live.sh`、`check-live-auth.sh`、
`check-original-fallback.sh`、`check-live-modes.sh`，均在 `tools/poc/`，都有 `--help`。
这些是 Phase 0 实验工具，不能当生产部署脚本使用；真实环境记录见上述 PoC 文档。

本次依用户要求没有使用 CF token、没有修改 DNS/zone 设置。源站使用两天有效的临时
自签证书，经现有 CF 配置回源成功；acme.sh、DNS-01、续期和 Full (Strict) 未验证。

Skill 完成后预定安装路径：Claude Code 用户级 `~/.claude/skills/xray-dual-node`、
项目级 `.claude/skills/xray-dual-node`；Codex 用户级 `~/.agents/skills/xray-dual-node`、
项目级 `.agents/skills/xray-dual-node`。路径已核对
[两家官方文档](references/source-audit.md#e0-官方文档核对)，实际加载测试尚未执行。

不得向仓库加入真实部署域名、IP、UUID、密码、CF token、证书私钥或抓包文件。
