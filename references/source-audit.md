# Phase 0 上游核对

checked_at: 2026-10-06
verified_against: Xray-core v26.9.30（源码/CLI，加核心线上 PoC；详见 poc-results）

## 不可变来源

- [Xray-core v26.9.30](https://github.com/XTLS/Xray-core/releases/tag/v26.9.30)，
  commit `b26a91de4f3294e26a0ad0a970b81a386a41f789`。
- [Xray 文档快照](https://github.com/XTLS/Xray-docs-next/tree/f2b306415344b9996d7f31775a12e8d2bd6809c6)，
  文档没有假定与 core 同 tag；与 core 源码交叉核对。
- [REALITY 依赖版本](https://github.com/XTLS/Xray-core/blob/v26.9.30/go.mod)，
  `v0.0.0-20260908062103-8cdf7bf9c7f0`。

## 字段与行为

| 项目 | 已查事实 | 来源 |
|---|---|---|
| freedom redirect/proxyProtocol | 位于 outbound.settings，版本 1/2 | [freedom.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/infra/conf/freedom.go) |
| tunnel/dokodemo-door | 两个名字映射到同一个 DokodemoConfig | [xray.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/infra/conf/xray.go) |
| trustedXForwardedFor | streamSettings.sockopt 下的 Header 名称数组 | [transport_sockopt.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/infra/conf/transport_sockopt.go) |
| XFF 来源覆盖 | 任一指定 Header 存在，读取 XFF 首地址；不读取 CF-Connecting-IP 的值 | [headers.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/common/protocol/http/headers.go) |
| REALITY target/dest | target 优先，保留 dest 别名 | [transport_security.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/infra/conf/transport_security.go) |
| REALITY password/publicKey | password 优先，保留 publicKey 别名 | 同上 |
| ML-DSA seed/verify | seed 32 字节，verify 1952 字节；CLI 名为 mldsa65 | 同上；[mldsa65.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/main/commands/all/mldsa65.go) |
| vlessenc | 两组前缀均为 mlkem768x25519plus；第二组才是 ML-KEM-768 认证 | [vlessenc.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/main/commands/all/vlessenc.go) |
| 配置 JSON | 普通 Decoder，不使用 DisallowUnknownFields | [loader.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/infra/conf/serial/loader.go) |
| REALITY target 拨号/xver | target 连接后写 PROXY 头；ML-KEM 检查见握手流程 | [tls.go](https://github.com/XTLS/REALITY/blob/8cdf7bf9c7f0/tls.go) |
| x25519 公钥输出 | 实际标签 Password (PublicKey)，不能只匹配 Password | [curve25519.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/main/commands/all/curve25519.go) |
| XHTTP auto | 先设 packet-up；security=REALITY 时才选择 stream-one/stream-up | [dialer.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/transport/internet/splithttp/dialer.go) |
| ECH 获取失败 | 设置无效 ECH 配置使连接失败，未直接清空 ECH 配置 | [ech.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/transport/internet/tls/ech.go) |
| fingerprint 名称 | 支持 hellochrome_120 和 chrome；现场 key share 对比见 PoC | [tls.go](https://github.com/XTLS/Xray-core/blob/v26.9.30/transport/internet/tls/tls.go) |

## 文档要求与待测推论

[REALITY 文档](https://github.com/XTLS/Xray-docs-next/blob/f2b306415344b9996d7f31775a12e8d2bd6809c6/docs/config/transports/reality.md)
说明 ML-DSA 要求 target 返回证书长度 >3500，并说明未开启客户端验证时仍可连接。
这与原方案兼容性降级表有差异，E6 必须实测，不能先发布全局关闭要求。

同一文档说明 fallback 限速对每个未鉴权连接生效，默认 0 表示关闭。
因此 A′ 中 CF 普通 TLS 到 B 也处于限速范围；后续 E8/E10 实测证实该影响，数据见 PoC。

[sockopt 文档](https://github.com/XTLS/Xray-docs-next/blob/f2b306415344b9996d7f31775a12e8d2bd6809c6/docs/config/transports/sockopt.md)
要求 acceptProxyProtocol 开启时先发送 PROXY 头，C04 不能裸连 B 测试。

[freedom 文档](https://github.com/XTLS/Xray-docs-next/blob/f2b306415344b9996d7f31775a12e8d2bd6809c6/docs/config/outbounds/freedom.md)
描述 finalRules 及服务器代理入站的私有/保留地址兜底限制。
路由规则仍需明确禁止内网，验证域名解析后的目标也受限制。

## E0 官方文档核对

- [OpenAI 官方 Skill 文档](https://learn.chatgpt.com/docs/build-skills)
  （从 https://developers.openai.com/codex/skills/ 跳转）：用户级 `$HOME/.agents/skills`，
  项目级 `.agents/skills`，支持目录软链接；必需字段 name、description，
  可选 agents/openai.yaml。不能因为本机系统 Skill 存在于 ~/.codex/skills 就改写官方安装路径。
- [Claude Code 官方 Skill 文档](https://code.claude.com/docs/en/skills)：用户级
  `~/.claude/skills`、项目级 `.claude/skills`，支持 `/skill-name`。
- 本机 CLI：codex-cli 0.160.0、Claude Code 2.1.283。仅版本检查与文档阅读；
  2026-10-06 通过 Codex app-server skills/list 和 Claude stream-json initialize 的 command list
  实际发现本 Skill；未发送模型任务，未把元数据发现等同于完整自然语言任务测试。
  官方技能页面同日重新抓取核对。Claude plugin validate 在本环境不递归验证普通/软链接技能
  子目录，不能把其空 contents 成功当作加载证据；加载证据来自 initialize command list。

v26.9.8 release 正文仅转向 v26.9.9，后者转向 v26.9.30；不能把原方案有关最低版本
的论断说成已由 release note 证实。[v26.9.8 的 go.mod](https://github.com/XTLS/Xray-core/blob/v26.9.8/go.mod)
已引用相同 REALITY `8cdf7bf9c7f0`，而
[v26.7.28](https://github.com/XTLS/Xray-core/blob/v26.7.28/go.mod) 引用 `9234c772ba8f`。
当前 pin 上旧 fingerprint 失败、新 fingerprint 成功已实测；历史服务端二进制对照未执行。
