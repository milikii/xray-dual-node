# B 客户端 auto、h2 与 v2rayNG Extra 核对

日期：2026-10-07。core：Xray v26.9.30。

用户在去掉 ECH 后仍无法从国内使用 B，提出 mode、ALPN 与 v2rayNG Extra 空值的疑问。
当前维护环境没有实际运行节点或用户 Android 客户端；本次核对源码并做隔离对照，不把新默认值当成已定位的根因。

## 源码事实

- Xray v26.9.30 `transport/internet/splithttp/dialer.go`：普通 TLS 的 auto 选择 packet-up；
  `decideHTTPVersion` 对 h2 和 h2,http/1.1 均选择 HTTP/2 传输。auto 不是网络故障重试/探测开关。
- `infra/conf/transport_method.go`：Extra 可省略，mode 可为 auto 或 packet-up。
- v2rayNG commit `6fe3893bfd37865dc677111fa48aef14c0a41efd`：`FmtBase.kt` 分别读取 URI 的
  mode/extra/alpn，`VlessFmt.kt` 读取 encryption；`BaseServerActivity.kt` 仅在 Extra 非空时验证 JSON。
- 中文资源中的 `XHTTP Extra 原始 JSON，格式：{ XHTTPObject }` 是界面标签，不是缺少必填对象的错误。

不可变源码链接见 [客户端规程](../../references/client-compat.md#v2rayng-的-modeextra-和-alpn)。
这次没有编译/运行 Android GUI，源码版本不代表用户的安装版本。

## 改动

新 B 客户端默认 mode=auto、ALPN=[h2]，不生成 Extra 或 ECH。
导出器增加 auto 支持，仍按输入保留旧 packet-up/ALPN；ML-KEM、凭据、路径、TLS 校验不变。
服务端仍为 packet-up，ALPN 保留 h2,http/1.1，因为现有 Nginx 到 Xray 的反代使用 HTTP/1.1。
不改变线上服务或自动覆盖旧客户端，未声称已有节点重新导出。

## 已测

`tools/poc/local-website.py --xray <verified-core> --base-port 29440`：

| 客户端模式 | 客户端 ALPN | Extra | 上传/下载 | 错误凭据 |
|---|---|---|---|---|
| packet-up | h2,http/1.1 | 无 | PASS | 拒绝 |
| packet-up | h2 | 无 | PASS | 拒绝 |
| auto | h2 | 无 | PASS | 拒绝 |

三组使用相同 packet-up 服务端、相同 ML-KEM 认证配置和 Nginx HTTP/1.1 上游，每次只改变一个客户端设置。
A 代理、网站/来源反例、后端错误不被首页覆盖也通过。实际生成器的有站/无站 B 客户端均校验为 auto/h2、无 Extra/ECH。

`tests/unit/private-export.sh` 通过：新 URI 为 mode=auto、alpn=h2，无 extra/ech；
旧 packet-up、h2,http/1.1 仍可导出并保留输入，其他连接参数/权限/私密输出回归通过。
`tests/check-skill.sh`、skill-creator `quick_validate.py` 通过。

## 待定位

旧配置与新配置本地均可连，不足以确认用户国内故障来自 mode 或 ALPN。
需要用户的 v2rayNG 应用/内置 core 版本、超时/TLS/HTTP/鉴权失败类别，再检查实际导入和真实 CF 链路。
不读取真实链接或配置到上下文，不擅自把 VLESS Encryption 改成 none。
