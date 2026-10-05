# 防刷边界：不用 REALITY 中继限速

verified_against: Xray-core v26.9.30；E1/E3 实测；2026-10-05 用户选择。

生成的配置省略 `limitFallbackUpload`、`limitFallbackDownload`。`check-policy` 拒绝
任何 REALITY 入站含这两个字段，即使值为零也不接受，防止模板重新引入限速路径。
升级/迁移旧配置应只删除这两个字段，保持认证材料不变，然后测试配置并验收。
`check-live-modes.sh` 现在仅比较 packet-up/auto，不再执行限速实验。

防护保留三条路由边界：

1. CDN SNI 且来源为 CF 网段才允许进入 B；只伪造 CDN SNI 不足以进入 B。
2. 未知 SNI 默认 blackhole，减少无关中继。
3. 伪装 SNI 未鉴权连接仍中继真实目标，以保留原始握手行为。

第 3 类不能靠上述 SNI 规则完全阻止带宽消耗。不得宣称“不限速仍能杜绝刷流量”，
也不静默改成拒绝所有 REALITY 未鉴权连接。连接数/新建连接频率的外围控制与持续流量
带宽限速不是同一机制；原 nft 防护尚未实现/验收，不应报告为已启用。

E8 历史实验曾把 B 从约 3.03 MB/s 限制到 142 KB/s：A′ 的 CF TLS 同样是 REALITY
未鉴权中继。该结果仅用于否决这个限速方案，不再作为默认 `verify --full` 的流量测试。
V21 改为检查“所有 REALITY 入站不含限速字段”，不构造开启限速的负载测试。
CF ACL 不能替代 TLS 身份验证；PoC 自签证书和当前 zone 接受它的行为不等于 Full (Strict) 已验收。

源码、文档见 [source-audit.md](source-audit.md)，实际路由证据见
[fallbacks-and-sni-routing.md](fallbacks-and-sni-routing.md)。
