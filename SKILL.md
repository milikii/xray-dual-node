---
name: xray-dual-node
description: >-
  在 Debian/Ubuntu VPS 上验证和维护共用 443 的 Xray REALITY 与 Cloudflare XHTTP 双节点方案，
  并将两条节点链接导出为私有文件。适用于此双节点方案的施工、PoC、排错和私密交付；
  当前为 Phase 0 工具集，尚未提供生产一键部署。
---

# Xray 双节点

先读 [实施进度](docs/PLAN.md) 和 [版本状态](references/upstream-state.json)。
当前可运行命令为 `scripts/xrayctl show-links`、`check-policy` 及 `tools/poc/` 实验工具。
`deploy`、`verify`、升级/回滚/证书自动化仍未交付；不能将 PoC 成功报告为生产部署完成。

## 本项目已确定的行为

- A′ 默认候选：A 的 REALITY 直听 443，target 经回环 SNI 路由器分流。
  CDN SNI **且** CF 来源才进 B；伪装 SNI 中继真站；其他 SNI 默认 blackhole。
- **允许目标站协商 X25519。** 不因目标不支持 ML-KEM 阻止部署或换域名。
  当前 core 的客户端仍须提供混合群，使用已测 `chrome`；这不是兼容任意旧客户端的开关。
  结果区分“客户端提供 ML-KEM”与“实际协商 X25519”，不能标为后量子密钥交换成功。
- **不使用 REALITY 中继带宽限速防刷。** 所有生成/迁移配置省略 `limitFallbackUpload`
  和 `limitFallbackDownload`，不运行开启这些字段的实验。修改后执行 `check-policy`。
  正确伪装 SNI 的未鉴权连接仍会产生中继带宽；按 [防刷边界](references/anti-abuse.md) 如实说明。
- B 固定 `packet-up`，开启 VLESS Encryption，客户端 ECH；密钥由已校验 core 生成。
  ML-DSA 与 ECH 的支持范围见实测，不能凭字段存在推断 GUI 客户端兼容。
- 本次用户选择不用 CF token，使用已有 DNS。不得为完成实验自行索要或使用其他 CF 凭据。

## 节点内容不进入执行者上下文

节点 URI、UUID、REALITY 公钥/私钥、shortId、ML-DSA 材料、VLESS Encryption、随机路径、
客户端/服务端配置、token 和证书私钥都属于私密材料，包括名称为 publicKey 的认证材料。

1. 在 VPS 内由脚本生成、读取、校验和传递，凭据参数使用文件输入，禁止把内容插入命令行。
   文件放仓库外，目录 700、文件 600；服务所需配置按原计划授予专用组的最小读取权限。
2. 不使用工具 `cat`/`head`/`read_file`/`grep` 查看私密文件；不让 `jq` 把提取的秘密返回工具输出。
   不预览、不上传为附件、不生成终端二维码、不把链接贴进回复或 PR。
3. 禁用 `set -x`，不输出原始配置差异、命令异常、客户端日志或抓包。
   校验程序只返回 PASS/FAIL、计数和公共能力信息；原始诊断留私有文件，不让 Agent 读回。
   如需补诊断，写只输出固定检查项/布尔值的脚本，先用合成数据验证没有泄露。
4. **交付只运行 `xrayctl show-links`。** 名字保留兼容，行为为文件导出；没有打印内容的参数。
   默认 `links.txt` 恰好两行，A 在前、B 在后，同时生成两个完整 JSON 客户端文件。
   不直接调用内部 `links.jq` 将真实输入输出到终端。
5. 最终回复只给路径、权限和服务/兼容性状态。需要本地文件时用用户授权的 SCP/SFTP 传输，
   不读取文件内容；用户在自己的终端或客户端打开。多用户每人导出独立文件，禁止静默选第一个用户。

具体命令、权限和导出限制见 [私密交付](references/private-export.md)。
这是减少进入模型上下文的措施，不是对拥有 root 权限的执行者建立操作系统隔离。

## 执行顺序

复用会话中已提供的参数、选择和授权，只有必需信息缺失时再询问。
使用已校验的候选/锁定版本，不能凭示例 tag 拼 latest URL。当前没有生产 pin。

1. 查 [PoC 结果](references/poc-results.md)，仅执行仍需要的实验；未知字段查
   [源码审计](references/source-audit.md)，不能只凭 `xray run -test` 接受未知字段判断支持。
2. 目标检查失败不能跳过；但目标不支持 ML-KEM 按已接受的 X25519 协商处理。
   证书/TLS/ALPN 的其他失败仍然失败，ML-DSA 需满足已测目标证书条件。
3. 任何配置变更先运行 `check-policy` 和同版本 `xray run -test -format json`，
   后者的全部输出重定向到私有日志；只在通过后重启。密钥和路径复用，不能为导出重新生成。
4. 正式部署完成后必须先验收再导出；当前只可导出已留存的 PoC 配置，必须注明服务是否运行。
   URI 参数已做源码核对，GUI 导入仍待 E9；需要时用户可用随附私有 JSON。
5. [计划](docs/PLAN.md) 中未验收项目保留未完成状态。不要伪造证书续期、GUI 导入、
   两平台自动触发或真实 CF 验证证据。

## 按需参考

- [private-export.md](references/private-export.md)：文件交付与保密接口。
- [anti-abuse.md](references/anti-abuse.md)：不使用 REALITY 带宽限速的防刷边界。
- [poc-results.md](references/poc-results.md)：已验证行为和剩余 E 项。
- [fallbacks-and-sni-routing.md](references/fallbacks-and-sni-routing.md)：原方案 A 的反例与 A′ 验证。
- [source-audit.md](references/source-audit.md)：pin 源码、配置字段、官方平台路径。
- [upstream-state.json](references/upstream-state.json)：版本、资产校验和核验日期。
- [docs/PLAN.md](docs/PLAN.md)：任务顺序、接口修订、未交付功能。
