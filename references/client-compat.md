# 客户端与协议边界

verified_against: Xray-core v26.9.30 实测；v2rayN f5747bb URI 源码；v2rayNG 6fe3893 URI/UI 源码。

| 能力 | 已知结论 | 边界 |
|---|---|---|
| 同版本 Xray JSON A/B | 两节点代理成功，错误认证失败 | 真实 VPS/CF |
| A ML-KEM | 当前 chrome 提供混合群，目标可协商 X25519 | 旧 chrome120 不提供混合群时失败 |
| A ML-DSA | 正确 Verify 成功，错误失败，省略仍可连接 | 不等于旧客户端必须让整个服务器关闭签名 |
| B XHTTP | 客户端默认 auto；本 tag TLS auto 实际选 packet-up，Extra 无需填写 | 服务端保持 packet-up；用户网络仍须实测 |
| B ALPN | 客户端仅 h2；旧 h2,http/1.1 配置仍允许重新导出 | 源站保留 HTTP/1.1 供 Nginx 反代使用，不能一并删除 |
| B VLESS Encryption | ML-KEM 认证组已测，错误 encryption 失败 | 不支持者不能仅删除客户端字段 |
| B TLS | SNI 为自有 CDN 域名，不配置 ECH；链接不含 ech 参数 | 用户报告旧 ECH 配置在国内不可用；去除后的国内连通待用户实测 |
| v2rayN URI | pbk/sid/spx/pqv/mode/encryption 已核对源码 | GUI 导入尚未实测 |
| v2rayNG URI/UI | 已核对 mode、extra、alpn、encryption 解析，Extra 空值合法 | Android GUI/用户版本未实测，须核对应用和内置 core 版本 |
| Mihomo/sing-box 等 | 依据具体版本/core | 不预填成功矩阵 |

排错先问客户端版本/内置 core；URI 导入丢字段时让用户试随附 JSON。
不要让用户贴真实链接/配置到聊天；可报告缺哪个字段，或在其机器上返回字段存在与否。
不支持 XHTTP 的客户端不能用 B。当前明确不启用 ECH，不要求客户端获取 ECH/DoH 配置；
ML-KEM 认证组、指纹和 TLS 证书验证保持；新客户端默认 auto/h2，不填额外 XHTTP 参数。
也不能因目标回退 X25519 就改用不提供混合群的旧指纹。
参数来源见 [private-export.md](private-export.md)，源码核对不等于 GUI 实测。

## 已有 B 客户端移除 ECH

只在目标机的私有客户端文件副本中删除 B outbound 的 `streamSettings.tlsSettings.echConfigList`，
不能重跑 `prepare-node-files.sh` 生成全新节点密钥。通常输入为 `/etc/xray-skill/secrets/client-b.json`。
以同版本 Xray 执行 `run -test`，比较前后 JSON，确认差异仅为这个字段；日志和配置不读回上下文。
保留 600 私有备份，通过后原子替换客户端文件，保留原用户/权限；不修改服务端、不重启服务。
原客户端没有该字段时保持文件原样。

随后复用原国家/机房名称运行 `scripts/xrayctl show-links`，把链接和完整 JSON 重新导出到
调用技能时的当前目录。导出器的 schema 仍兼容旧字段，但不会输出 URI 的 `ech` 参数；
完整 JSON 保留输入字段，因此旧客户端必须先按上述步骤删除 ECH 再导出。
只返回“新 URI 无 ech、B JSON 无 echConfigList、A 不变、其他 B 连接参数不变”的布尔结果。
用户应更新订阅/重新导入 B，确认客户端没有继承旧 ECH 设置；国内实际代理成功前标记“待用户实测”。

[Xray 作者 XHTTP 指南 #4113](https://github.com/XTLS/Xray-core/discussions/4113) 的快速入门说明
一般只需填 path，其余参数已有默认值，CDN 优选时 SNI 填域名；该指南未要求 ECH。
移除 ECH 的操作只删除该字段；用户另外要求调整 mode/ALPN 时，按下面的配置逐项验证。

## v2rayNG 的 mode、Extra 和 ALPN

新生成的节点 B 使用下列客户端设置；无需更改服务端即可与现有 packet-up 入站配合：

| v2rayNG 项目 | 设置 |
|---|---|
| 传输协议 | xhttp |
| XHTTP 模式 | auto |
| ALPN | h2 |
| XHTTP Extra | 留空，不粘贴对象格式提示文字 |
| TLS / SNI | TLS 开启，SNI 为节点自有 CDN 域名，保留证书验证 |
| ECH | 留空 |
| Host / path / encryption | 保留从节点导入的原值，不能拿示例路径或其他节点的 encryption 覆盖 |

`XHTTP Extra 原始 JSON，格式：{ XHTTPObject }` 是界面标签，不是“缺少必填 JSON”的报错。
v2rayNG 仅在 Extra 非空时检查 JSON；默认设置直接放在 mode/host/path 字段，不需要再包装进 Extra。
当前技能不生成高级 Extra，URI 无 extra 参数是预期结果；不能为了填满界面复制网上的额外参数。

Xray v26.9.30 的普通 TLS 客户端在 auto 模式下实际选择 packet-up，不会自动在所有传输模式间探测重试。
因此 auto 是使用默认选择，不能单凭从 packet-up 改成 auto 就认定连通故障已修复。
旧客户端显式 packet-up 仍可导出；不会在导出时偷偷改变既有 mode/ALPN。

ALPN 表示这次 TLS 握手可协商的应用协议。`h2,http/1.1` 会提供两个选项，支持 h2 的端点通常选 h2；
列出 http/1.1 不等于实际使用了 HTTP/1.1。B 客户端收紧为 h2 可避免向 CF 提供 HTTP/1.1 选项。
这与源站反代是不同的 TLS 连接：当前 Nginx `proxy_http_version 1.1` 连接 Xray 8002，
该源站入站仍需支持 http/1.1。不要搜索替换所有 ALPN 或为此改动 Nginx/服务端模式。

排错时记录 v2rayNG **应用版本和内置 core 版本**，以及超时、TLS 失败、HTTP 状态或鉴权失败类别。
界面能导入 XHTTP 不代表内置 core 支持当前完整 VLESS Encryption 配置；核对 encryption 是否完整保留，
不因其他 CDN 节点可用就擅自把本节点的 encryption 改成 none。其服务端配置必须匹配，另作独立验证。
本地 Xray 测试通过不覆盖 Android 导入、用户网络或真实 CF/WAF 行为；国内连接成功仍由用户确认。

源码依据：

- [Xray TLS auto 选择与 HTTP 版本判定](https://github.com/XTLS/Xray-core/blob/v26.9.30/transport/internet/splithttp/dialer.go)。
- [Xray Extra 可选及 mode 校验](https://github.com/XTLS/Xray-core/blob/v26.9.30/infra/conf/transport_method.go)。
- [v2rayNG URI 解析](https://github.com/2dust/v2rayNG/blob/6fe3893bfd37865dc677111fa48aef14c0a41efd/V2rayNG/app/src/main/java/com/v2ray/ang/fmt/FmtBase.kt)：mode/extra/alpn 分别读取。
- [v2rayNG Extra 空值校验](https://github.com/2dust/v2rayNG/blob/6fe3893bfd37865dc677111fa48aef14c0a41efd/V2rayNG/app/src/main/java/com/v2ray/ang/ui/server/BaseServerActivity.kt)。
- [v2rayNG 中文标签](https://github.com/2dust/v2rayNG/blob/6fe3893bfd37865dc677111fa48aef14c0a41efd/V2rayNG/app/src/main/res/values-zh-rCN/strings.xml)。

上述为已核对的源码快照，不代表用户安装了同一版本。
