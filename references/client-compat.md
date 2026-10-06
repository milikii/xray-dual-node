# 客户端与协议边界

verified_against: Xray-core v26.9.30 实测；v2rayN f5747bb URI 源码。

| 能力 | 已知结论 | 边界 |
|---|---|---|
| 同版本 Xray JSON A/B | 两节点代理成功，错误认证失败 | 真实 VPS/CF |
| A ML-KEM | 当前 chrome 提供混合群，目标可协商 X25519 | 旧 chrome120 不提供混合群时失败 |
| A ML-DSA | 正确 Verify 成功，错误失败，省略仍可连接 | 不等于旧客户端必须让整个服务器关闭签名 |
| B XHTTP | packet-up 已测；本 tag TLS auto 也选 packet-up | 仍显式固定 packet-up |
| B VLESS Encryption | ML-KEM 认证组已测，错误 encryption 失败 | 不支持者不能仅删除客户端字段 |
| B ECH | 223.5.5.5 DoH 与 CF outer SNI 已测 | 用户网络/其他客户端仍须测试 |
| v2rayN URI | pbk/sid/spx/pqv/ech/mode/encryption 已核对源码 | GUI 导入尚未实测 |
| v2rayNG/Mihomo/sing-box 等 | 依据具体版本/core | 不预填成功矩阵 |

排错先问客户端版本/内置 core；URI 导入丢字段时让用户试随附 JSON。
不要让用户贴真实链接/配置到聊天；可报告缺哪个字段，或在其机器上返回字段存在与否。
不支持 XHTTP 的客户端不能用 B。去掉客户端 ECH 属于用户选择的降级，不能静默删除后宣称
ECH 成功；也不能因目标回退 X25519 就改用不提供混合群的旧指纹。
参数来源见 [private-export.md](private-export.md)，源码核对不等于 GUI 实测。
