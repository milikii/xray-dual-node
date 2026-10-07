# 客户端与协议边界

verified_against: Xray-core v26.9.30 实测；v2rayN f5747bb URI 源码。

| 能力 | 已知结论 | 边界 |
|---|---|---|
| 同版本 Xray JSON A/B | 两节点代理成功，错误认证失败 | 真实 VPS/CF |
| A ML-KEM | 当前 chrome 提供混合群，目标可协商 X25519 | 旧 chrome120 不提供混合群时失败 |
| A ML-DSA | 正确 Verify 成功，错误失败，省略仍可连接 | 不等于旧客户端必须让整个服务器关闭签名 |
| B XHTTP | packet-up 已测；本 tag TLS auto 也选 packet-up | 仍显式固定 packet-up |
| B VLESS Encryption | ML-KEM 认证组已测，错误 encryption 失败 | 不支持者不能仅删除客户端字段 |
| B TLS | SNI 为自有 CDN 域名，不配置 ECH；链接不含 ech 参数 | 用户报告旧 ECH 配置在国内不可用；去除后的国内连通待用户实测 |
| v2rayN URI | pbk/sid/spx/pqv/mode/encryption 已核对源码 | GUI 导入尚未实测 |
| v2rayNG/Mihomo/sing-box 等 | 依据具体版本/core | 不预填成功矩阵 |

排错先问客户端版本/内置 core；URI 导入丢字段时让用户试随附 JSON。
不要让用户贴真实链接/配置到聊天；可报告缺哪个字段，或在其机器上返回字段存在与否。
不支持 XHTTP 的客户端不能用 B。当前明确不启用 ECH，不要求客户端获取 ECH/DoH 配置；
ML-KEM 认证组、packet-up、指纹、ALPN 和 TLS 证书验证保持不变。
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
本次仅移除 ECH，不据此同时调整既有 ML-KEM 或 packet-up 参数。
