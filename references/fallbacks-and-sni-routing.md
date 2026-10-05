# REALITY fallback 与 SNI 分流

verified_against: v26.9.30，本地实验和 Linode VPS + 真实 CF

`tools/poc/local-routing.sh` 生成临时证书、UUID、REALITY 密钥、shortId 和 VLESS
Encryption，所有服务仅监听回环高端口。

E1 反例将普通 TLS ClientHello 的 SNI 设为 cdn.example.com，REALITY serverNames
只含 example.com，target 指向一张独立的本地 TLS 证书；VLESS fallbacks 的 CDN name
指向另一张证书的 B 入站。实际收到的证书与 target 的 DER 完全相等。
这支持“普通 TLS 未通过 REALITY 鉴权而走 target”的解释，不证明真实 CF 已测试。

A′ 实验将 target 指向 SNI router 并设 xver=2；router 的来源规则只允许 127.0.0.2。
该地址发往 CDN SNI 的请求，经 freedom PROXY v2 转发后拿到 B 证书及 HTTP 404；
来自 127.0.0.3 的同 SNI 请求失败。两个 router 协议别名均重跑正反例。
伪装 SNI 能拿到 fixture 证书，随机错误 SNI 失败。

后续真实 CF 测试中，A′ 的普通请求为 404，两个节点均能代理请求；伪造 CDN SNI 的
非 CF 请求失败。原 A 返回 302，8 秒抓包窗口内 B 无新连接，证书等于相同 SNI 的
直连 target；恢复 A′ 后回到 404。原 target 会按 SNI 返回不同证书，比较必须保持同 SNI。

真站与 A′ 回落的 TLS1.3、h2、cipher、证书和 JA3S 相等；客户端 ECH 与 CF 回源 SNI
分别抓包确认。REALITY limitFallbackDownload 实测会同时限制 B，不能用它区分两类中继。
仍待 CF IPv6 回源专项测试；B′ 是备选设计，本轮没有运行 B′，不将它列为已验证。

出处与解释限制见 [source-audit.md](source-audit.md)；完整命令和输出见
[poc-results.md](poc-results.md)。
