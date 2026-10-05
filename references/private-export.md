# 私密节点文件交付

verified_against: Xray-core v26.9.30 配置；本仓库合成输入测试；真实 VPS 文件导出与 core 自检；GUI 导入待 E9。
用户于 2026-10-05 要求节点内容尽量不进入 Codex/Claude 等执行者上下文。
此约定覆盖生成、部署、验收、日志、诊断、升级/回滚及交付，不只最后一步。

## 已实现的接口

```sh
scripts/xrayctl show-links \
  --client-a /root/xray-poc/live/client-a.json \
  --client-b /root/xray-poc/live/client-b.json \
  --output-dir /root/xray-poc/export \
  --xray /root/xray-poc/bin/xray --json
```

命令行只有文件路径。脚本在本机读取内容，stdout 只输出 PASS、links=2、文件路径和
GUI 导入尚未验证的状态；stderr 只输出固定错误提示。禁止 Agent 读取或预览产物。
`--xray` 可选，提供时先用该二进制测试两份 JSON；不启动进程或连接服务器。
省略时只执行结构校验，不应声称核心测试或连通验收通过。

默认输入为 `/etc/xray-skill/secrets/client-{a,b}.json`，默认输出为 `/etc/xray-skill/client/`。
输入各含唯一的 `node-a` / `node-b` VLESS outbound、一个 vnext、一个用户；当前支持经
PoC 验证的嵌套配置格式。复杂传输参数、未知配置字段和多用户不静默丢弃，直接拒绝。
整体配置中的日志/路由/入站不导出，JSON 使用选中节点和新的回环 SOCKS/HTTP 入站。

产物：

| 文件 | 内容 | 权限 |
|---|---|---|
| `links.txt` | 恰好两条 VLESS URI，A/B 顺序，每条单独一行 | 600 |
| `node-a.json` | A 完整客户端；SOCKS 10808、HTTP 10809，仅回环监听 | 600 |
| `node-b.json` | B 完整客户端；与 A 使用相同本地端口，二选一启动 | 600 |

目录 700，归当前运行用户所有（VPS 正式运行使用 root）。输入要求同样为 700/600。
路径须为绝对路径，使用字母/数字/`_-.`/斜杠，不接受符号链接、非私有目录、硬链接文件、
仓库内输出或标准输出设备。临时文件同样为 600，锁串行化并发导出。
先完整生成、验证，再逐文件原子替换，最后提交 `links.txt`；不是三个文件跨断电的事务。
解析/测试失败保留旧文件；进程正常退出或信号退出时清理临时文件。
SIGKILL/断电可能留下一份私有临时目录，仍应视为密钥备份处理。

不支持 `--qr`、终端 URI/JSON 输出或通过工具附件预览。用户可以用自己的 SFTP 客户端
下载文件，或在用户本地终端运行以下命令（替换示例主机）：

```sh
(umask 077; scp root@203.0.113.10:/root/xray-poc/export/links.txt ./xray-links.txt)
```

权限和流程不能阻止已取得 root 权限的进程主动读取文件；它们旨在避免工具输出、上下文、
命令参数、PR、运行日志中的意外泄露。已有对话中用户提供的 VPS 登录信息也不会被此机制消除。

## URI 字段依据

- 基础结构：[Xray VLESS 分享链接提案 #91](https://github.com/XTLS/Xray-core/issues/91)。
  该旧正文不能单独证明新参数或 VLESS Encryption 支持。
- 参数核对：[v2rayN VLESSFmt.cs @ f5747bb](https://github.com/2dust/v2rayN/blob/f5747bb3212ad65c362bd82a19e520b2db4c38b0/v2rayN/ServiceLib/Handler/Fmt/VLESSFmt.cs)
  与 [BaseFmt.cs](https://github.com/2dust/v2rayN/blob/f5747bb3212ad65c362bd82a19e520b2db4c38b0/v2rayN/ServiceLib/Handler/Fmt/BaseFmt.cs)。
  源码读取 encryption、pbk、sid、spx、pqv、ech 及 XHTTP mode/host/path。
- IPv6 地址加方括号，查询值逐项 URL 编码，名称固定 `node-a` / `node-b`，不嵌入真实地址。
  没有把 ML-DSA Verify 或长 Encryption 字段截短。JSON 保留这些认证参数。
- 这是源码兼容依据，不能代替各固定版本 GUI 的实际导入与连通测试，E9 保持未完成。

## 当前测试

`tests/unit/private-export.sh` 使用合成数据，验证两行输出、权限、稳定重复导出、IPv6、
特殊字符、ML-DSA/ECH/Encryption 编码、异常/跟踪模式无秘密输出、错误 core 退出、
符号链接/硬链接/公开目录拒绝、原文件保留以及并发锁。测试日志仅报告检查结果。
内部 `scripts/lib/links.jq` 只能由受控导出器调用，直接使用 jq 会输出秘密。
