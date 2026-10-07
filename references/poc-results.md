# Phase 0 实测记录

checked_at: 2026-10-05
verified_against: Xray-core v26.9.30（控制机、Linode Debian 13 amd64、真实 Cloudflare）
phase0_exit: NOT_READY

历史说明：本文件保留原实验设计的完成情况。2026-10-06 用户明确改为 Agent Skill 交付，
当前范围见 [PLAN.md](../docs/PLAN.md)。新验证见当日发布记录；Skill 发布不覆盖本表中的未测项。

## 环境与版本

本地控制机：Debian 13 amd64、OpenSSL 3.5.7、systemd。
CLI：codex-cli 0.160.0、Claude Code 2.1.283。
测试 VPS 已由用户授权清空；重装进度独立记录于
[测试记录](../docs/test-records/2026-10-05-linode-debian13.md)。
先在控制机做回环实验，后在重装后的 VPS 重复，并另外完成下述真实 CF 实验。
VPS 使用 OpenSSL 3.5.6，系统时区 Etc/UTC，NTPSynchronized=yes。
用户已提供伪装与 CDN 域名，并明确要求暂不使用 CF token；实际域名/IP/密钥仅留在 VPS。

候选二进制的真实输出：

```text
Xray 26.9.30 (Xray, Penetrates Everything.) b26a91d (go1.27.1 linux/amd64)
SHA256(Xray-linux-64.zip)=f851110beaff16e78d643f0ccfd9524b4a44dfd59bae3e34bb52bba378f7690e
```

实际下载 SHA-256 与 release assets.digest、`.zip.dgst` 的 SHA2-256 三者一致。
`xray help` 列出 x25519、uuid、mldsa65、mlkem768、vlessenc；生成材料只保存在临时目录，
不收入本记录。arm64 仅读取资产元数据，未测试。

## 逐项状态

| ID | 已执行与结论 | 未完成部分 |
|---|---|---|
| E0 | 官方安装路径、name/description、openai.yaml 文档核对；本机 CLI 版本确认 | 两平台实际安装、自动触发、显式调用 |
| E1 | PASS：真实 CF 请求在原 A 返回 302，8 秒抓包窗口 B 新连接数为 0；相同 CDN SNI 下证书等于直连 target；恢复 A′ 后为 404 | 无法代替所有 CF zone 配置的测试 |
| E1b | 当前 pin 行为 PASS：chrome 120 key share 无 4588 时失败，chrome 当前包含 4588 时成功；最低 tag 的依赖源码已比较 | 未执行历史服务端二进制对照 |
| E2 | PASS：真实 CF 经 freedom PROXY v2 到 XHTTP；B 用户日志来源等于测试客户端的 VPS IPv6 | XFF 可伪造性/复杂代理链尚未测试，不把 Header 机制当 IP 认证 |
| E3 | PASS：真实 CF 来源进入 B，VPS 直接伪造 CDN SNI 失败；回环允许/拒绝来源正反例均通过 | 本次 CF 入站来源为 IPv4，未单独构造 CF IPv6 回源 |
| E4 | 本次目标 PASS：回落与直连的 DER 证书、TLS1.3、cipher、h2、JA3S 相等；5 组握手时间已测 | 未测 JA4S、跨地域、长时间稳定性；完整 R01–R12 脚本仍属 T4 |
| E5 | PASS：抓包看到 CF 回源 SNI 为用户 CDN 域名，ALPN offer 为 h2,http/1.1 | 仅本次 zone 配置 |
| E6 | 同 pin 客户端 PASS：正确 ML-DSA Verify 成功，省略 Verify 仍成功，错误 Verify 失败；目标证书链 4648 字节 | GUI/旧客户端矩阵、开关前后握手体积与延迟对照 |
| E7 | 历史 PASS：223.5.5.5 TLS IP 校验成功，客户端从它获取 ECH 后实际代理成功；outer SNI 为 cloudflare-ech.com | 当时未测用户所在地网络；用户后续反馈“墙内不可用”，定位到 ECH 扩展丢包，当前 B 已移除 ECH；移除后的国内连通待用户实测 |
| E8 | 历史限速副作用已验证：128 KiB/s fallback 限速也拖慢 B；用户已否决该防护方式，常规工具已移除限速实验 | 外围 nft 防刷测试仍未完成 |
| E9 | PENDING | v2rayN/v2rayNG/Mihomo/sing-box 各固定版本导入及实际连接 |
| E10 | 短样本 PASS：1 MiB 下载 packet-up 0.346s，auto 0.289s；源码表明 TLS 的 auto 选 packet-up | 多轮/大负载吞吐、extra/xmux 推荐值，不能据短样本做容量推荐 |
| E11 | PASS：控制机与真实 VPS 上，两别名均 -test 及来源正反例成功；CF 实验使用 tunnel | arm64 尚未执行 |

## 可复现命令与实际输出

下载并校验官方候选后执行（路径由操作者指定）：

```bash
shellcheck tools/poc/local-routing.sh
bash -n tools/poc/local-routing.sh
tools/poc/local-routing.sh --xray /absolute/path/to/verified/xray
```

shellcheck 及 Bash 语法检查均退出 0；最终实验输出如下：

```text
[PASS] E2-config redirect, PROXY v2 and XHTTP encryption accepted
[PASS] E11-config dokodemo-door and tunnel accepted
[PASS] decoder-negative-control unknown field silently accepted; -test alone is insufficient
[PASS] decoder-positive-control known field with wrong type rejected
[PASS] E2-E3-local dokodemo-door allowed source traverses REALITY xver=2, routing.source, freedom PROXY v2, XHTTP TLS (404)
[PASS] E3-negative dokodemo-door same CDN SNI with other source blocked
[PASS] SNI-negative dokodemo-door unrecognized SNI blocked
[PASS] camouflage-local dokodemo-door relays local TLS fixture (404, certificate verified)
[PASS] E2-E3-local tunnel allowed source traverses REALITY xver=2, routing.source, freedom PROXY v2, XHTTP TLS (404)
[PASS] E3-negative tunnel same CDN SNI with other source blocked
[PASS] SNI-negative tunnel unrecognized SNI blocked
[PASS] camouflage-local tunnel relays local TLS fixture (404, certificate verified)
[PASS] E1-local original fallbacks proposal returns target certificate for CDN SNI
LOCAL_POC: PASS (real Cloudflare and authenticated client traffic remain untested)
```

本地使用 127.0.0.2 作为允许来源、127.0.0.3 作为不允许来源，**不冒充 CF IP**。
SNI 采用保留文档域名；TLS fixture 为短期自签证书，由 curl 显式信任该测试证书。
E1 比较 DER 证书逐字节相等，目标证书和 B 证书不同。
本节回环实验没有发送已鉴权 VLESS 业务；Encryption 的实际正反例见下一节。

首轮采用 OpenSSL s_server fixture，出现 TLS alert 和回落超时；改用 Xray TLS fixture
后通过。失败原因未确定，不能据最终本地 PASS 推导任意 OpenSSL/真实目标均兼容，
应在 E4 继续复测。

VPS 首次复测暴露监听就绪的竞争：只等待 443 不代表最后一个 TLS fixture 已启动。
已改为等待四个监听全部就绪，再复测通过。该问题与先前 OpenSSL fixture 超时分别记录。

## 真实 VPS + CF：无 token 流程

实际参数由操作者提供，下列示例只使用文档域名/IP。工作目录包含密钥，必须为私有目录。

```bash
tools/poc/prepare-live.sh --xray /absolute/path/to/verified/xray \
  --work-dir /root/xray-poc/live --dest example.com --cdn cdn.example.com --address 203.0.113.10
# 配置 -test 成功后，显式创建临时 xray-poc 和两个 xray-poc-client-{a,b} systemd 服务。
# 三个单元均设 UMask=0077、RuntimeMaxSec=3600，日志留在私有工作目录。
tools/poc/check-live-auth.sh --xray /absolute/path/to/verified/xray --work-dir /root/xray-poc/live
tools/poc/check-original-fallback.sh --xray /absolute/path/to/verified/xray --work-dir /root/xray-poc/live
tools/poc/check-live-modes.sh --xray /absolute/path/to/verified/xray --work-dir /root/xray-poc/live
```

本次源站自签证书只用于 PoC；CF 现有配置接受该证书。DNS 已是 proxied，未创建/修改
DNS 记录，没有使用 token，没有签发 ACME 证书，也没有验收证书续期。
正式服务用户、加固 systemd 单元和 nft 防火墙尚未交付；后续已实现私有链接文件导出，
不代表客户端 GUI 导入或生产服务验收通过，见 private-export.md。

两节点经 SOCKS 到 CF trace 均返回 VPS 的公网 IPv6；正确伪装 SNI 经源站返回 HTTP/2 200；
非 CF 来源伪造 CDN SNI、错误 SNI 均 curl exit=35。CDN 普通请求得到 HTTP/2 404。

鉴权反例实际输出：

```text
[PASS] node-a-baseline expected=success curl_exit=0
[PASS] node-b-baseline expected=success curl_exit=0
[PASS] node-a-without-mldsa-verification expected=success curl_exit=0
[PASS] node-a-wrong-mldsa-verification expected=failure curl_exit=35
[PASS] node-a-wrong-shortid expected=failure curl_exit=35
[PASS] node-a-chrome120-fingerprint expected=failure curl_exit=35
[PASS] node-b-wrong-vless-encryption expected=failure curl_exit=35
AUTH_POC: PASS (same-core clients; GUI compatibility untested)
```

额外抓包确认 chrome120 的 key share 为 GREASE + 29（X25519），当前 chrome 为 GREASE +
4588（X25519MLKEM768）+ 29；分别失败和成功。**客户端提供混合群不等于最终使用它**：
所选目标不支持混合群，实际 ServerHello 为 group 29。不能宣称本节点 A 的密钥交换为后量子。

E1 真实反例最终输出：

```text
ORIGINAL_A_CF_STATUS=302
ORIGINAL_A_B_CONNECTIONS=0
[PASS] original-A CDN SNI receives camouflage certificate; actual CF probe opens zero connections to B
[PASS] A-prime config restored
```

比较 target 的证书时须保持相同 SNI；本次目标对 CDN SNI 与伪装 SNI 返回不同证书。
最初恢复测试还暴露扩展名问题：随机后缀备份需要 `-format json`；已修正并完整重跑，
最后确认 A′ 恢复且 CF 返回 404。原 A 的结果不被记录为 A′ 的证书失败。

E4 直接/回落均为 TLS_AES_256_GCM_SHA384、TLS1.3、ALPN h2、证书验证 0，DER 相同。
JA3S 均为 `15af977ce25de452b96affa2addb1036`。五次 appconnect 秒数：

| 方式 | 5 次样本（秒） | 中位数 |
|---|---|---|
| 直连 | 0.017066, 0.032644, 0.019151, 0.019199, 0.018209 | 0.019151 |
| 回落 | 0.019140, 0.018505, 0.017934, 0.018182, 0.020173 | 0.018505 |

差异处于该短样本的网络波动范围，不能解释为回落加速。

E5/E7 以 tshark 现场解析 ClientHello，导出元数据（原始含域名/IP 的数据仅留 VPS）：

```text
VPS -> DoH IP: TLS IP verification OK
Xray client -> CF edge: SNI=cloudflare-ech.com; ECH extension type=65037
CF edge -> VPS: SNI=<CDN_DOMAIN>; ALPN offer=h2,http/1.1
Authenticated node B request: success; exit IP=<VPS_IPV6>
```

抓包时另一次普通 curl 请求不会启用 ECH，不能把该请求的明文 CDN SNI 混作 Xray 客户端证据。
ECH 源码在取不到配置时设置无效配置使连接失败，出处见 source-audit。
以上仅保留为历史证据；用户后续报告带 ECH 的 B 在其国内网络不可用（GFW 丢弃含 type 65037
扩展的握手）。此网络根因由用户反馈，本仓库未在该网络独立复现；当前配置不再启用 ECH。

E8/E10 的固定 1 MiB、单次下载历史实验（单位 bytes/s；限速阶段已从当前脚本移除）：

```text
[PASS] packet-up {"bytes":1048576,"seconds":0.345944,"bytes_per_second":3031057}
[PASS] auto {"bytes":1048576,"seconds":0.288862,"bytes_per_second":3630024}
[PASS] limited {"bytes":1048576,"seconds":7.397546,"bytes_per_second":141746}
[PASS] REALITY fallback limit also throttles legitimate node B traffic
MODE_POC: PASS (short samples, not a capacity benchmark or tuning recommendation)
[PASS] baseline server and client B restored
```

限速测试设 afterBytes=0、bytesPerSec=131072、burstBytesPerSec=131072；只为验证作用范围，
不是生产推荐值。原“auto 在 CF 后预期接近 0”的判断被本 pin 的源码与实测否定。
随后用户明确要求不用 REALITY 限速防刷；当前 check-live-modes.sh 只测 packet-up/auto，
不再复现 limited 阶段。V21 改为配置无 REALITY 限速字段的检查，旧日志仅作否决依据。

目标最终协商 X25519 已获用户接受，不因缺少目标 ML-KEM 支持阻断部署；仍保留
客户端必须提供混合群的当前 core 行为，不将 X25519 密钥交换标为后量子。

## Phase 0 尚未完成的部分

E0 实际 Skill 加载/触发、E6 GUI 与握手体积对照、E9 导入矩阵，以及表中列出的剩余项目。
当前不再索要 CF token；这是用户明确选择的无 token PoC。生产证书/续期需另行实现和验收。
依原方案 T0 出口，不能将本次核心链路成功标为完整 Phase 0 或正式部署完成。

## 本轮结束状态

最终配置测试、A/B 实际代理、CF 404 均再次通过。所有临时服务已停止，实验端口已释放；
私有配置与现场证据保留在 VPS `/root/xray-poc/live`（700/600），不在仓库中。
所有 `tools/poc/*.sh` 通过 shellcheck、Bash 语法检查和 --help 检查。
