# Cloudflare 核对

verified_against: 2026-10-06 真实 CF；每个 zone 的具体规则由执行者再次核对。

| 项目 | 要求 |
|---|---|
| DNS | CDN 域名 A/AAAA 指向 VPS，proxied 开启；不用 token 时由用户面板确认 |
| SSL | 必须 Full (Strict) + 公共 CA 完整证书，默认 Let’s Encrypt；不得回退自签/Full |
| 回源 | 443，SNI 为 CDN 域名；自定义 Origin SNI/Host 后须重新验证分流 |
| 客户端 TLS | B 使用 CDN 域名作为 SNI，不配置 ECH，不要求 DoH 获取 ECH；国内连通单独实测 |
| WAF/挑战 | XHTTP 路径不能触发 Bot/Under Attack/验证码 |
| 缓存/改写 | 排除 Cache Everything，不向 XHTTP 响应注入/改写页面 |
| WebSocket/gRPC | 当前 packet-up 不依赖这两个开关 |
| 来源 | 443 对 REALITY 客户端开放；只有 CF 可进 B 的条件在 SNI 路由层检查 |

默认网站模式下 CDN 根路径应返回 200 且正文匹配已安装主页，文章/样式可访问，未知页 404。
旧部署或 `--website off` 模式根路径返回默认 404 是正常回源证据；两者均不能证明节点鉴权及用户网络连通已通过。
XHTTP 专用路径不得缓存、改写或被网站错误页替换，静态站不启用 Cloudflare 注入/自动改写功能。
521/522/525/526 按诊断规程查进程、网络、TLS、证书模式。
客户端→CF 与 CF→源站均使用 CDN 域名作为 SNI，分别检查；不按 cloudflare-ech.com 分源站流量。

HTTP-01 使用 80 端口：仅 `/.well-known/acme-challenge/` 路径直达持久 webroot，排除挑战/缓存/强制 HTTPS。
详见 [证书规程](certificates.md)；不修改 XHTTP 的 CF 来源限制来解决签发问题。

## 缓存绕过表达式与最终交付

部署完成后，回复中必须提供**已替换为实际 XHTTP 域名**的可复制表达式，并说明设置动作。
用目标机上的脚本从私有运行配置中提取并验证域名，不读回整个配置或 XHTTP 随机路径：

```sh
python3 scripts/show-cf-cache-rule.py
```

默认读取 `/etc/xray-skill/config.json`，普通用户通过本机 sudo 执行；远程部署在目标机执行。
只有准备目录时可传 `--server-config /private/prepared/server.json`，但必须说明部署尚未完成。
脚本只输出域名表达式，错误只输出固定提示，不连接 Cloudflare、不创建规则。
默认按**整个 XHTTP 域名**绕过缓存，包含节点路径和静态网站，三天更新的资讯无需等待边缘缓存过期。
不影响同 zone 的其他域名；代价是该域名的静态资源也会回源。

最终回复应包含下面三项，示例域名必须替换为本次配置的真实域名，不让用户自行猜填：

1. Cloudflare → 对应网站 → **Caching / 缓存 → Cache Rules / 缓存规则 → Create rule**。
   选择 **Custom filter expression / 自定义筛选表达式 → Edit expression / 编辑表达式**，粘贴：

   ```text
   (http.host eq "cdn.example.com")
   ```

2. **Cache eligibility / 缓存资格 → Bypass cache / 绕过缓存**，然后保存并部署。
3. 若有同样匹配该域名的其他缓存规则，把本条放在它们之后，避免后续的 Eligible for cache 覆盖它。
   不能只粘表达式而不选择 Bypass cache；这是缓存规则，不是 WAF 的 Skip 规则。

不要默认拼接 `or (http.request.uri.path contains "/health")`：域名条件已经覆盖本域名的 `/health`，
这个 OR 还会匹配同 zone 其他域名上包含 `/health` 的路径。仅当用户明确要求额外范围时按其范围生成。
表达式允许出现在聊天中，因为只含用于配置 Cloudflare 的域名；不包含 UUID、密钥、URI 或私有路径。
节点文件仍按 [私密交付](private-export.md) 处理，不预览其内容。

已有规则也要在最终回复保留表达式。未使用 API/面板实际核验时标注“待在 Cloudflare 保存部署”，
不能把生成表达式当作规则已启用。条件允许时在 A/B 验收前先配置，完成后再次交付表达式。
验收结合生效规则顺序及实际响应，不能只靠一次 `MISS` 判断；绕过缓存可能显示 `DYNAMIC`，
不要求响应头一定为 `BYPASS`。缓存绕过不同时豁免 WAF、验证码或 Access，相关问题仍分别处理。

官方依据（2026-10-07 核对）：[创建缓存规则](https://developers.cloudflare.com/cache/how-to/cache-rules/create-dashboard/)、
[缓存资格](https://developers.cloudflare.com/cache/how-to/cache-rules/settings/#cache-eligibility)、
[顺序与优先级](https://developers.cloudflare.com/cache/how-to/cache-rules/order/)。
