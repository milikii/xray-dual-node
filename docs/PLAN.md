# Xray 双节点一键部署 Skill：实施方案 v0.1

状态：执行 T0，尚未通过 Phase 0 出口；生产部署脚本未交付。
用户于 2026-10-05 指示“按方案来”，D1–D10 按原方案默认项推进。
本文记录执行约束、方案修订和任务顺序；PoC 的事实以带证据的
[poc-results.md](../references/poc-results.md) 为准，不能把待测设计写成已验证结论。

## 已采用的设计选择

| 决策 | 选择 | 生效条件 |
|---|---|---|
| D1 | A′ 为默认，B′ 为备选 | A′ 必须通过 E2、E3、E4 |
| D2 | 443 对全网开放；CDN SNI 与 CF 源 IP 联合匹配才允许进入 B；不用 REALITY 中继带宽限速 | E3 的真实 CF 正例、非 CF 反例均通过；外围连接控制另行验收 |
| D3 | 默认 pin 已测预览 tag；显式 latest-prerelease 解析一次写锁文件 | 当前 v26.9.30 仅为测试候选 |
| D4 | 节点 A VLESS Encryption 默认 off | on 为显式开关 |
| D5 | 错误 SNI 默认 blackhole | camouflage 为显式开关 |
| D6 | ML-DSA 目标默认 on | 必须通过 E6；不通过按原方案改 off，并记录原因 |
| D7 | 默认 Agent 在 VPS 本地执行，同时支持 SSH | 本次实际用 SSH 操作测试 VPS |
| D8 | manage-dns 默认 on | 限用户提供且 token 可管理的 CDN 域名 |
| D9 | 最小 token 权限 Zone:Read + DNS:Edit，人工核对 zone 设置 | Zone Settings:Read 可选，不默认扩权 |
| D10 | 节点 B 地址默认 CDN 域名 | address 可覆盖，SNI/Host 不变 |

本次会话覆盖：用户已提供测试 VPS 与两个域名，并要求先不用 CF token。
T0 使用已有 proxied DNS、临时自签源站证书，不操作 DNS/zone；生产 DNS-01/续期仍未验收。
后台重装由用户完成，远程 SSH 与干净系统已检查通过。

2026-10-05 用户追加选择（覆盖原方案相应条款）：目标不支持 ML-KEM 时接受协商
X25519；不用 REALITY 限速防刷；交付为含两条节点链接的私有文件，执行者只获取路径和状态。
本轮据此提前实现 T9/T12 中的私密导出与 Skill 约束部分，不表示其余 T1–T15 已通过。

## 拓扑与协议

A′：VLESS + RAW + REALITY + Vision 直接监听 443；REALITY target 指向回环
SNI router，xver=2。router 嗅探 TLS，仅在 CDN SNI 与 CF 源网段同时命中时
经 freedom redirect + PROXY v2 转往回环 XHTTP 入站。伪装 SNI 转真实目标；
其他按 D5 处理。B 为 VLESS + XHTTP packet-up + TLS + VLESS Encryption，
客户端另加 ECH。节点 A/B 的 UUID、路径和密钥在重复部署时复用。

B′：SNI front 监听 443，伪装 SNI 转回环 REALITY，CDN SNI 且 CF 来源转 B。
两种拓扑必须都进配置测试和端到端测试。不能因 A′ 失败就假定 B′ 已通过。

ECH 的客户端到 CF 段与 CF 到源站段分开验收；源站 SNI 用 E5 抓包证明。
原方案 A 的 VLESS fallbacks 与 REALITY target 是不同阶段；E1 保留反例。

## T0 已发现的修订

1. **`xray run -test` 不能证明字段被识别。** v26.9.30 配置读取使用普通 JSON
   decoder。必须同时核对源码类型、官方文档和实际行为，不能靠未知字段未报错推断支持。
2. **`trustedXForwardedFor` 是 Header 名单，不是可信 IP 段。** 源码读取 XFF
   的第一个地址；列表中任一 Header 存在就允许覆盖。不能把它当 CF 来源认证，
   也不能把它描述为按优先级读取 CF-Connecting-IP 的值。
3. **ML-DSA 有目标证书长度条件。** 当前文档要求 target 返回证书长度大于 3500，
   需用 `xray tls ping` 检查。R01–R12 要补此门控，不能仅因普通预检通过就默认开启。
   文档还说明服务端开启签名不会强制旧客户端验证，原降级表“必须全局关闭”需由 E6 修正。
4. **`vlessenc` 两组输出使用相同算法前缀。** 必须按 `Authentication: ML-KEM-768,
   Post-Quantum` 组配对提取 encryption/decryption，不能仅匹配 mlkem768x25519plus。
5. **A′ 的 fallback 限速也覆盖 CF 到 B。** CF 普通 TLS 同样走 REALITY 未鉴权
   中继，limitFallback* 不按 SNI 区分。用户已否决该防刷方式；生成配置省略两个字段，
   E8 限速数据仅保留为历史证据，常规工具不再开启它们。
6. **证书直连验收必须发送 PROXY 头。** acceptProxyProtocol=true 时，裸
   `openssl s_client` 直连 B 不能证明证书有问题；C04 需经临时的本地 PROXY 转发器。
7. **防火墙独立表的 accept 不覆盖其他表的 drop。** P11 仍须检查已有规则；
   nft 使用其原生 meter/limit 语法，不能照抄 iptables 的 hashlimit 模块名。
8. **preflight 保持只读。** 原表“自动修复”归入 deploy 显式执行阶段，之后重跑预检；
   preflight --yes 也不安装包、不改时钟或防火墙。
9. **备份必须在切换活动二进制之前。** S04 只暂存候选版本；S10 保存旧二进制目标、
   config/state/lock 后才提交变更，否则首次回滚可能错误恢复到新版本。
10. **本 pin 的 TLS XHTTP auto 默认选择 packet-up。** E10 两种模式均完成真实 CF 下载，
    撤销“auto 吞吐预期接近 0”的断言；部署仍按用户要求显式锁定 packet-up。
11. **临时配置/备份测试需显式 `-format json`。** 随机文件后缀会影响格式识别；
    S09、升级和回滚测试不能把格式推断失败误报为配置不兼容。
12. **解析格式要以实际 CLI/API 为准。** 本版本公钥标签为 `Password (PublicKey)`；
    CF 两个 IP 列表末尾没有换行，按文件分别 split 后合并，避免拼接出无效 CIDR。
13. **offer 混合群不代表协商混合群。** 本次目标支持 TLS1.3/h2，证书链长度满足 ML-DSA
    文档条件；但目标不支持 X25519MLKEM768，ServerHello 实际使用 X25519。R05 记录
    已接受的 X25519 协商回退（可提示能力差异，不阻止部署）。输出必须如实区分
    ML-DSA 签名、客户端提供混合群、最终密钥交换算法。V06 分别记录 offer 与 negotiated；
    回退不意味着旧 fingerprint 无需提供混合群，也不关闭节点 B 的 VLESS Encryption。
14. **文件交付覆盖原 show-links 终端输出规范。** `show-links` 保留命令名称，只写私有
    `links.txt`（A/B 两行）及 JSON 客户端，返回路径/计数/状态。取消自动终端链接、QR、
    配置全文输出；`--json` 输出状态元数据。生成、验收、升级、诊断均不得将认证材料
    放入 argv、工具输出或模型上下文。详见 [private-export.md](../references/private-export.md)。

核心真实 CF PoC 已通过 E1/E2/E3/E4/E5/E7/E11；E6 同版本客户端验证通过，E8/E10 已有短样本。
E0 实际触发、E9 GUI 导入矩阵等仍待完成。A′ 继续作为候选默认，不把 T0 标为全部完成。

源码和文档出处见 [source-audit.md](../references/source-audit.md)。以上条目分清源码事实、
文档要求和本项目推论；尚未进行的线上测试保持 PENDING。

## 接口与部署约束

统一入口 `scripts/xrayctl`，实现原方案的 preflight、check-dest、deploy、verify、
diag、show-links、add-client、remove-client、update、rollback、cert-check、
refresh-cf-ips、rotate、backup、restore、uninstall。每个脚本均有 --help。

必需输入：reality-dest、cdn-domain、cf-token-file、acme-email；可选 alt、channel、
xray-tag、topology、wrong-sni-policy、node-a-enc、mldsa、manage-dns、node-b-address、
clients、ech-doh、yes、takeover。原参数默认值和退出码 0–8 保留。
未实现的选项不得静默接受；危险操作的既有明确授权不重复询问。

版本只能来自审定后的 versions.env 或锁文件。密钥用 xray 子命令生成，shortIds
用 openssl 随机生成，不提交真实域名、IP、UUID、token、证书或捕获流量。
示例仅用 example.com、203.0.113.10、全零 UUID。分享链接只由 show-links 写入私有文件。
AI 不读取或预览文件，用户自行下载打开。

部署顺序：锁与参数汇总 → 预检/依赖修复重测 → 严格 check-dest → 解析并暂存版本
→ 用户与目录 → 复用或首次生成密钥 → CF IP/DNS → DNS-01 证书 → 临时渲染和 -test
→ 旧状态备份、原子提交、启动 → 防火墙和 timer → staging 续期演练 → verify
→ 导出链接 → CF 人工核对清单。失败恢复旧状态；首次部署失败则停服务保留现场。

落地路径仍为 /opt/xray-skill、/etc/xray-skill、/var/lib/xray-skill/backups、
/var/log/xray-skill，独立 xray-skill.service，非 root 服务用户与最小能力。
所有脚本使用 Bash、set -Eeuo pipefail、掩码日志、flock；不引入 Python 运行时。
检查列表的 JSON 输出必须是一个可解析数组，不能混入人类日志；私密导出 `--json`
返回单个元数据对象（无节点内容）。配置须 -test 后才重启。

## 验收与维护

P01–P15、R01–R12、C01–C05、V01–V21 按用户原方案实施，修订见上文。
V21 改为所有 REALITY 入站不含限速字段；当前独立 `check-policy` 已实现，未来默认 verify
执行该项，`--full` 仅额外跑 V20 幂等检查。不再用限速负载作为验收。幂等对比在本机进行，
只返回是否相等，不打印节点链接或其内容。未测、依赖缺失不能输出 PASS；
证书 dry-run 不覆盖正式 home/证书；SNI 来源规则必须同时有正反例。
更新先测试候选、备份再切换，V01–V14 失败自动回滚；保留最近两个版本。
默认卸载保留配置与备份；DNS 只删除 state 记录为本工具创建的 record id。

维护跟踪 Xray releases、相关源码目录、Xray-docs-next、CF IP/ECH、客户端 releases。
每周一 02:00 UTC 检测，新增预览版至少观察 72 小时，经实测后才推荐。
知识超过 30 天告知用户但仍用 pin；月度复测 E7/E9。未完成实测时 verified_at 保持空。

## 任务顺序与出口

| 任务 | 产出/完成标准 | 状态 |
|---|---|---|
| T0 | E0–E11（含 E1b）证据、方案修订；真实 VPS + CF 实测后用户确认 | 执行中 |
| T1 | 仓库骨架、common/os/state、shellcheck+bats CI、掩码测试 | 待 T0 出口 |
| T2 | 校验下载与版本切换、versions.env、密钥解析变体测试 | 待执行 |
| T3 | P01–P15，Debian 12/Ubuntu 24.04 容器检查 | 待执行 |
| T4 | R01–R12，合格/Apple/重定向三个真实域名测试 | 待执行 |
| T5 | 两拓扑模板，黄金测试与 pin 二进制 -test | 待执行 |
| T6 | CF DNS、acme.sh、C01–C05 真实签发 | 待执行 |
| T7 | nft/ufw、CF timer、幂等与卸载残留检查 | 待执行 |
| T8 | S00–S15 全新 VPS 部署，重跑分享链接不变 | 待执行 |
| T9 | 链接与 JSON，E9 客户端导入验证 | 私密导出与合成测试已实现；GUI 导入待测 |
| T10 | verify/diag，路由错误、cron 删除、停服务的故障注入 | 待执行 |
| T11 | 更新、回滚、备份恢复、卸载及失败回滚测试 | 待执行 |
| T12 | SKILL.md、README、openai.yaml、软链接安装，两平台实际加载 | Skill 入口与私密规则已实现；安装/触发待测 |
| T13 | 所有 references 参数出处与 verified_against | 待执行 |
| T14 | upstream-watch、workflow、维护手册，issue 生成验证 | 待执行 |
| T15 | 全新 VPS 完整验收记录，通过后发布 v0.1.0 | 待执行 |

按原 §11 出口：“Phase 0 结束时提交……交你确认后才进入 Phase 1”。
测试 VPS 重装是用户追加且明确授权的 T0 环境准备；不等同于 Xray 部署通过。
