# 验证资料索引

所有状态都区分源码核对、本地实验、真实 VPS/CF 验收；未测项不标 PASS。

| 文件 | 用途 | verified_against |
|---|---|---|
| [poc-results.md](poc-results.md) | E0–E11 逐项进度、命令、结果摘要和缺口 | v26.9.30，本地与真实 CF 核心链路 |
| [source-audit.md](source-audit.md) | 字段、CLI、Skill 官方文档及方案差异 | v26.9.30 + 文档 commit f2b3064 |
| [upstream-state.json](upstream-state.json) | 候选版本、资产哈希、实际核验范围 | checked_at 2026-10-05，verified_at 尚空 |
| [fallbacks-and-sni-routing.md](fallbacks-and-sni-routing.md) | E1 真实 CF 反例与 A′ 来源分流实验 | v26.9.30，Linode Debian 13 |
| [private-export.md](private-export.md) | 文件交付、AI 不接触节点内容、URI 字段依据 | v26.9.30；v2rayN f5747bb 源码；合成导出测试 |
| [anti-abuse.md](anti-abuse.md) | 不用 REALITY 中继带宽限速的防刷边界 | v26.9.30；E1/E3/E8；用户最新选择 |

生产参数推荐及其他知识库文件将在对应 PoC 完成后写入，不用空模板冒充已交付。
