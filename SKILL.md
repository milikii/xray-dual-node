---
name: xray-dual-node
description: >-
  为 Codex、Claude Code 提供 Xray 双节点的部署、验收、排错、升级回滚、卸载和上游维护流程。
  支持在当前或远程 Debian/Ubuntu VPS 部署共用 443 的 VLESS REALITY 与 Cloudflare XHTTP 节点；
  执行后把两条节点链接写入私有文件，避免认证材料进入执行者上下文。
---

# Xray 双节点 Skill

由执行者读取环境、决定下一步并调用确定性辅助脚本。用户用自然语言提出任务；
无需另一个常驻管理程序。复用会话已有选择，只读取当前任务对应的规程。

## 任务入口

| 用户意图 | 读取/执行 |
|---|---|
| 新 VPS 部署、换机器部署 | [部署规程](references/deploy.md) |
| 节点不可用、验收、服务/证书检查 | [验收与排错](references/verify-and-diagnose.md) |
| 升级 core、回滚、备份恢复、轮换、卸载 | [生命周期](references/lifecycle.md) |
| 跟进作者更新、更新 Skill、发版 | [维护规程](docs/MAINTENANCE.md) |
| 导出/重新获取节点 | [私密交付](references/private-export.md)，运行 `scripts/show-links.sh` |

部署/升级前读 `versions.env` 和 [上游状态](references/upstream-state.json)。
本版基线为 v26.9.30，核验范围不等于所有客户端/系统均已测试。
资料超过 30 天或发现新 tag 时说明时效，继续用已测 pin，除非用户要求验证/升级新版。
首次使用时简要告知用户正在使用本 Skill。

## 输入与已确认选择

部署目标未明确时，先询问：“是否在当前机器部署？”等待用户选择，不自行默认本机或远程。
确认当前机器后，开始本机检查和部署，无需索要 SSH 用户、密码或密钥。
选择其他机器后，再收集缺失的远程连接信息，优先复用已有 SSH 配置。
用户已明确说“在这台机器部署”或已指定远程目标时，沿用该选择，不重复确认。
若选定环境不符（如非 Debian/Ubuntu 或无法访问宿主机的容器），说明具体问题并澄清目标。

复用已有主机、域名、证书方式和授权。缺少必要输入时只补问伪装域名、CF CDN 域名、
证书方式；客户端版本可以边执行边收集。节点所需公网地址先按部署规程自动识别，
无法可靠确定时再询问。不重复要求已给出的确认。
密码/token 使用私有文件或系统凭据通道，不写入仓库或命令参数。

- 默认 A′：REALITY 直听 443，target 指向回环 SNI router；B 为回环 XHTTP TLS。
  CDN SNI **且** CF 来源匹配才进入 B；伪装 SNI 中继真站；未知 SNI blackhole。
- A 为 Vision、chrome、encryption=none；B 为 packet-up、VLESS Encryption 的 ML-KEM
  认证组和客户端 ECH。B 地址默认 CDN 域名。
- 允许目标不支持 ML-KEM 时协商 **X25519**。本 core 客户端仍需提供混合群；旧指纹可能失败。
  不把“提供混合群”或 ML-DSA 签名误报为最终后量子密钥交换。
- **不用 REALITY 中继限速防刷**：省略 limitFallbackUpload/Download，不另设出口带宽限制
  替代它。正确伪装 SNI 的未鉴权连接仍会消耗中继带宽。
- ML-DSA 默认 on；目标 R13 证书条件不满足时用 off，并说明原因。
- 本会话选择不用 CF token、沿用已有 DNS。其他用户未选择时按部署规程确认模式，
  不把一次会话偏好误当所有环境的强制限制。

## 认证材料不进入执行者上下文

URI、UUID、REALITY 公钥/私钥、shortId、ML-DSA 材料、VLESS Encryption、随机路径、
配置全文、token、私钥和原始诊断日志均为私密材料；REALITY publicKey 也不能公开。

1. 在 VPS 内生成/解析/校验，通过文件传递秘密，禁用 set -x。不要把秘密拼入命令参数，
   不输出原始异常、配置 diff、抓包或日志。
2. 不用 cat/head/grep/read_file 等工具读回私密文件；排错让脚本只返回固定 ID、布尔值、
   退出码。新诊断先以合成数据验证无凭据回显。
3. 输入/备份在仓库外，目录 700、文件 600；运行配置和证书按需给服务组 640。
   节点交付到调用技能时的当前目录：开始任务时记住绝对路径，后续切换目录不改变交付位置。
   导出文件 600，保留当前目录权限；若位于仓库内，确保产物被 Git 忽略且未被跟踪。
   从配置提取的值留在脚本内处理。
4. 只用 show-links.sh 或兼容入口 xrayctl show-links 交付：links.txt 恰好 A/B 两行，附
   完整 JSON，具体位置与远程取回方式见 [私密交付](references/private-export.md)。
   按源站公网 IP 的国家代码和机房/运营商命名，如 `US-oracle-reality`、`US-oracle-xhttp+tls+cdn`；
   执行者核对归属后向导出器传入 `--country`、`--provider`，不用 CDN 边缘 IP 的位置。
   只返回路径、权限、状态；不预览、不贴链接、不生成终端 QR、不上传附件。
5. 用户自己用终端/SFTP 下载查看。这是降低意外泄露的工作流，不是对 root Agent 的系统隔离。

## 执行不变量

- 发现 `/etc/xray-skill` 就转诊断/生命周期，不调用生成器重新创建密钥。
- 目标 FAIL 不正常部署；ML-KEM 不支持是允许的回退。用户明确要求忽略不合格目标时
  记录例外和检查结果，不默认绕过。
- core 使用固定 tag/hash；字段查该 tag 源码/文档。run -test 单独通过不能证明字段被识别。
  不猜字段，不因测试失败删除鉴权、来源限制或 TLS 校验。
- 改配置先 check-policy.sh，再 run -test -format json（输出写私有日志），通过才重启。
  升级前保存旧二进制、配置、证书和服务单元，失败按规程回滚。
- 交付可用节点前确认 active/enabled、无临时运行时限、A/B 实际代理成功。导出不等于部署成功。
  清理仅停止本轮临时客户端，**保留用户节点服务运行**。
- 未要求轮换就保留 UUID、密钥、路径；普通升级保持原链接有效。
- 据实标 PASS/WARN/FAIL/未测试，GUI 导入和其他系统不能因源码兼容就标实测。

## 按需参考

- [客户端边界](references/client-compat.md)、[CF 清单](references/cloudflare-checklist.md)。
- [源码依据](references/source-audit.md)、[历史 PoC](references/poc-results.md)。
- [SNI 分流](references/fallbacks-and-sni-routing.md)、[防刷边界](references/anti-abuse.md)。
- [常驻修复记录](references/persistent-recovery.md)、[当前交付范围](docs/PLAN.md)。
