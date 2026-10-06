# 验证资料索引

所有状态都区分源码核对、本地实验、真实 VPS/CF 验收；未测项不标 PASS。

| 文件 | 用途 | verified_against |
|---|---|---|
| [poc-results.md](poc-results.md) | E0–E11 逐项进度、命令、结果摘要和缺口 | v26.9.30，本地与真实 CF 核心链路 |
| [source-audit.md](source-audit.md) | 字段、CLI、Skill 官方文档及方案差异 | v26.9.30 + 文档 commit f2b3064 |
| [upstream-state.json](upstream-state.json) | 固定版本、资产哈希、实际核验范围 | checked_at/verified_at 2026-10-06；范围明确，不代表所有平台 |
| [fallbacks-and-sni-routing.md](fallbacks-and-sni-routing.md) | E1 真实 CF 反例与 A′ 来源分流实验 | v26.9.30，Linode Debian 13 |
| [private-export.md](private-export.md) | 文件交付、AI 不接触节点内容、URI 字段依据 | v26.9.30；v2rayN f5747bb 源码；合成导出测试 |
| [persistent-recovery.md](persistent-recovery.md) | 停服根因、常驻恢复、自签证书续期与验收 | v26.9.30；2026-10-06 真实 VPS/CF |
| [anti-abuse.md](anti-abuse.md) | 不用 REALITY 中继带宽限速的防刷边界 | v26.9.30；E1/E3/E8；用户最新选择 |
| [deploy.md](deploy.md) | Agent 部署步骤及辅助脚本边界 | v26.9.30；生成/常驻流程实测 |
| [verify-and-diagnose.md](verify-and-diagnose.md) | 结构化检查、实际代理与私密排错 | v26.9.30；真实 CF |
| [lifecycle.md](lifecycle.md) | Agent 编排升级、备份、回滚、卸载 | 当前布局；隔离安装/失败恢复演练 |
| [cloudflare-checklist.md](cloudflare-checklist.md) | 不同 DNS/证书模式下的人工核对 | 当前 CF 设置；其他 zone 逐机检查 |
| [client-compat.md](client-compat.md) | 客户端支持与未测范围 | 同 core 实测，GUI 源码核对 |

后续上游跟进由执行者按 [维护规程](../docs/MAINTENANCE.md) 更新，新增事实必须补充出处与测试范围。
