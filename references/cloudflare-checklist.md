# Cloudflare 核对

verified_against: 2026-10-06 真实 CF；每个 zone 的具体规则由执行者再次核对。

| 项目 | 要求 |
|---|---|
| DNS | CDN 域名 A/AAAA 指向 VPS，proxied 开启；不用 token 时由用户面板确认 |
| SSL | 自签证书用 Full；公共 CA 完整证书可用 Full (Strict)；Full 不校验源站证书身份 |
| 回源 | 443，SNI 为 CDN 域名；自定义 Origin SNI/Host 后须重新验证分流 |
| ECH | DoH 取到配置并实际使用，不能只看客户端字段存在 |
| WAF/挑战 | XHTTP 路径不能触发 Bot/Under Attack/验证码 |
| 缓存/改写 | 排除 Cache Everything，不向 XHTTP 响应注入/改写页面 |
| WebSocket/gRPC | 当前 packet-up 不依赖这两个开关 |
| 来源 | 443 对 REALITY 客户端开放；只有 CF 可进 B 的条件在 SNI 路由层检查 |

默认网站模式下 CDN 根路径应返回 200 且正文匹配已安装主页，文章/样式可访问，未知页 404。
旧部署或 `--website off` 模式根路径返回默认 404 是正常回源证据；两者均不能证明认证/ECH 已通过。
XHTTP 专用路径不得缓存、改写或被网站错误页替换，静态站不启用 Cloudflare 注入/自动改写功能。
521/522/525/526 按诊断规程查进程、网络、TLS、证书模式。
客户端→CF 的 ECH outer SNI 与 CF→源站的 SNI 分开检查；不按 cloudflare-ech.com 分源站流量。
