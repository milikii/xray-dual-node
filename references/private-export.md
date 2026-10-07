# 私密节点文件交付

verified_against: Xray-core v26.9.30 配置；本仓库合成输入测试；真实 VPS 文件导出与 core 自检；GUI 导入待 E9。
用户于 2026-10-05 要求节点内容尽量不进入 Codex/Claude 等执行者上下文。
此约定覆盖生成、部署、验收、日志、诊断、升级/回滚及交付，不只最后一步。

## 已实现的接口

开始任务时记录当前目录的绝对路径为 `delivery_dir`。默认把三份节点文件直接交付到该目录，
不要因随后进入 Skill 目录或连接远程主机而改变交付位置。用户明确指定其他输出位置时沿用其选择。
本机导出时在交付目录执行脚本，可用 Skill 的绝对路径调用；省略 `--output-dir` 即使用脚本当前目录。

```sh
# skill_dir 为 Skill 的绝对路径，delivery_dir 为任务开始时记录的目录。
cd -- "$delivery_dir"
"$skill_dir/scripts/show-links.sh" --country "$country" --provider "$provider" \
  --xray /usr/local/bin/xray-skill-xray --json
```

命令行只有文件路径。脚本在本机读取内容，stdout 只输出 PASS、links=2、文件路径和
GUI 导入尚未验证的状态；stderr 只输出固定错误提示。禁止 Agent 读取或预览产物。
`--xray` 可选，提供时先用该二进制测试两份 JSON；不启动进程或连接服务器。
省略时只执行结构校验，不应声称核心测试或连通验收通过。

默认输入为 `/etc/xray-skill/secrets/client-{a,b}.json`，默认输出为当前工作目录。
`/etc/xray-skill` 是运行配置来源，不是默认交付位置。
导出必须传入 `--country` 和 `--provider`；不再生成笼统的 `node-a` / `node-b` 分享名称。
输入各含唯一的 `node-a` / `node-b` VLESS outbound、一个 vnext、一个用户；当前支持经
PoC 验证的嵌套配置格式。复杂传输参数、未知配置字段和多用户不静默丢弃，直接拒绝。
整体配置中的日志/路由/入站不导出，JSON 使用选中节点和新的回环 SOCKS/HTTP 入站。

产物：

| 文件 | 内容 | 权限 |
|---|---|---|
| `links.txt` | 恰好两条 VLESS URI，A/B 顺序，每条单独一行 | 600 |
| `node-a.json` | A 完整客户端；SOCKS 10808、HTTP 10809，仅回环监听 | 600 |
| `node-b.json` | B 完整客户端；与 A 使用相同本地端口，二选一启动 | 600 |

导出到当前目录时保留其权限，要求归当前运行用户所有且组/其他用户不可写；不对整个工作目录 chmod。
其他输出目录要求 700，输入要求 700/600（VPS 正式运行使用 root）。
路径须为绝对路径，使用字母/数字/`_-.`/斜杠，不接受符号链接、不符合权限要求的目录、硬链接文件
或标准输出设备。在仓库中交付时，先确保三个产物和 `.export.*` 被 Git 忽略且未被跟踪；
本仓库已配置忽略规则，脚本会检查。其他仓库也需核对，不能把节点文件加入提交。
路径或权限不合格时说明具体障碍，不静默退回 `/etc`。临时文件同样为 600，锁串行化并发导出。
先完整生成、验证，再逐文件原子替换，最后提交 `links.txt`；不是三个文件跨断电的事务。
解析/测试失败保留旧文件；进程正常退出或信号退出时清理临时文件。
SIGKILL/断电可能留下一份私有临时目录，仍应视为密钥备份处理。

不支持 `--qr`、终端 URI/JSON 输出或通过工具附件预览。
远程部署时，先在目标机私有目录导出，再通过已有 SSH/SFTP 通道将三份文件取回
执行者最初记录的 `delivery_dir`。传输使用 umask 077，先下载到本地 700 临时目录，
核对文件权限及目标不是符号链接/硬链接后放入交付目录；不读回内容，不覆盖无关同名文件。
最终报告调用端的三个绝对路径；取回失败则明确交付未完成，不把远程 `/etc` 路径当作完成交付。

最终交付另附 [CF 缓存绕过表达式与设置步骤](cloudflare-checklist.md#缓存绕过表达式与最终交付)。
`python3 scripts/show-cf-cache-rule.py` 只输出运行配置中的 XHTTP 域名表达式，允许直接展示并复制；
它不输出节点路径或认证字段。`show-links.sh` 的输出约定不变，禁止预览三份节点文件。

权限和流程不能阻止已取得 root 权限的进程主动读取文件；它们旨在避免工具输出、上下文、
命令参数、PR、运行日志中的意外泄露。已有对话中用户提供的 VPS 登录信息也不会被此机制消除。

## IP 归属与节点命名

执行者使用部署时确定的源站公网 IP，查询 HTTPS IP 地理位置服务（如 ipwho.is 的指定 IP 查询）
返回的国家代码及 ASN/ISP/组织信息，必要时与云厂商实例区域或用户已提供的机房信息核对。
远程部署必须查询远程源站 IP；B 也沿用同一源站归属，不查询 CF 域名的边缘 IP 来命名。
已有配置中的地址仅在脚本内提取并用于查询，原始配置/认证字段不进入上下文，也不发送给查询服务。
查询设置超时，失败不阻止交付；无法确认国家用 `ZZ`，无法确认运营商用 `unknown`，并报告未确认项。
IP 地理库的位置是估计值，冲突时优先采用已确认的实例区域，不虚构物理机房。

- `country`：两位大写国家/地区代码，例如 `US`、`JP`、`DE`，不限于美国、日本。
- `provider`：小写运营商/机房名，空格和标点归一为连字符；只允许字母、数字及单个分隔连字符，
  最长 64 字符。例如 Oracle Corporation / Oracle Cloud 归一为 `oracle`，Amazon AWS 为 `aws`。
  有已确认的租用厂商品牌时使用该品牌，否则使用 IP 的 ASN/组织名称，不猜测转售商。
- A 名称：`国家-provider-reality`；B 名称：`国家-provider-xhttp+tls+cdn`。

例如日本 Oracle 为 `JP-oracle-reality` 和 `JP-oracle-xhttp+tls+cdn`。
分享 URI 的 fragment 使用 URL 编码（`+` 写成 `%2B`），导出 JSON 的 outbound tag 使用同一可读名称。
文件名仍为 `links.txt`、`node-a.json`、`node-b.json`。原运行配置的 tag、密钥和连接参数不变；
重新导出时复用已核对的归属信息，只有 IP/机房变化或用户要求时重新核对。
导出脚本只负责验证名称参数和生成文件，不进行网络查询，不把名称当作地理位置已实测的证明。

## URI 字段依据

- 基础结构：[Xray VLESS 分享链接提案 #91](https://github.com/XTLS/Xray-core/issues/91)。
  该旧正文不能单独证明新参数或 VLESS Encryption 支持。
- 参数核对：[v2rayN VLESSFmt.cs @ f5747bb](https://github.com/2dust/v2rayN/blob/f5747bb3212ad65c362bd82a19e520b2db4c38b0/v2rayN/ServiceLib/Handler/Fmt/VLESSFmt.cs)
  与 [BaseFmt.cs](https://github.com/2dust/v2rayN/blob/f5747bb3212ad65c362bd82a19e520b2db4c38b0/v2rayN/ServiceLib/Handler/Fmt/BaseFmt.cs)。
  源码读取 encryption、pbk、sid、spx、pqv 及 XHTTP mode/host/path；当前不导出 ech 参数。
- IPv6 地址加方括号，查询值及节点名称逐项 URL 编码，名称不嵌入真实地址。
  没有把 ML-DSA Verify 或长 Encryption 字段截短。JSON 保留这些认证参数。
- 这是源码兼容依据，不能代替各固定版本 GUI 的实际导入与连通测试，E9 保持未完成。

## 当前测试

`tests/unit/private-export.sh` 使用合成数据，验证两行输出、权限、稳定重复导出、IPv6、
特殊字符、ML-DSA/Encryption 编码、新 URI/JSON 无 ECH、异常/跟踪模式无秘密输出、错误 core 退出、
符号链接/硬链接/公开目录拒绝、原文件保留以及并发锁。测试日志仅报告检查结果。
内部 `scripts/lib/links.jq` 只能由受控导出器调用，直接使用 jq 会输出秘密。
