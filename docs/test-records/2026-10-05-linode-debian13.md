# 测试 VPS 准备记录

日期：2026-10-05。提供商 Linode，amd64 KVM，约 2 GB RAM、50 GB 根盘。
状态：**用户通过 Linode 后台完成重装，SSH 登录与基础检查通过**。
此记录不包含实例地址、密码、公钥、真实 UUID 或网络配置。

用户明确允许清空这台无保留数据的测试 VPS。原系统 Debian 13，根文件系统直接
位于 /dev/sda（无分区表），/dev/sdb 为 swap；运行旧 nginx 及两套 Xray。
检查通过后采用 Debian 13 官方网络安装器重新安装。

启动准备使用
[reinstall 固定 commit](https://github.com/bin456789/reinstall/tree/98f1e21013233d42750cc2e7a298a0818461d686)
的 Debian 安装流程。原工具不能识别 Linode 的无分区根盘磁盘 ID，首次准备退出，
没有重启；为本次操作加入按文件系统 UUID/容量识别目标盘以及平台 GRUB 检测。
运行时文件保存在仓库外，没有将一次性重装脚本作为 Skill 部署脚本交付。

Debian installer 内核下载后，SHA-256 与 Debian 官方 images/SHA256SUMS 一致：
`2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08`。
修改后的 initrd gzip 检查、GRUB 脚本检查均通过；设置了一次性安装启动项并重启。

本次修改把 preseed 放入 initrd，并在 partman/early_command 增加等待文件，原意是
在清盘前先验证安装器 SSH；安装完成后也保持暂停，便于检查新系统再启动。
重启后网络有响应，但 SSH 22 持续拒绝连接。怀疑 initrd preseed 使 SSH 的 screen
启动步骤执行过早，**尚无控制台证据，根因未确认**。
没有发送创建 `/run/reinstall-network-verified` 的指令，尚未解除清盘等待。
不能据此宣称已经清盘、重新安装成功或已恢复旧系统。

已请求用户通过 Linode LISH 打开安装器 Shell，执行：

```sh
mkdir -p /run/sshd
/usr/sbin/sshd
```

上述尝试没有完成重装。用户随后直接使用 Linode 后台重装，替代了该安装器流程。
重新连接时生成了新的独立 known_hosts 记录；原操作密钥失效，使用用户先前提供的
root 密码成功登录，再重新配置本任务操作公钥。没有更改用户密码。

## 后台重装后的实际检查

```text
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
DEBIAN_VERSION_FULL=13.5
Architecture: x86_64
Kernel: 6.12.88+deb13-amd64
Root: /dev/sda ext4, 49.5G
Swap: /dev/sdb, 496M
Listening TCP ports: 22 (IPv4 and IPv6), sshd
```

运行服务中没有旧 nginx、xray 或 xray-skill-preview；443/8001/8002 无监听。
这证明本次后台重装后的远程访问和基础环境可用，不将先前安装器尝试记为成功。

继续 T0：安装 PoC 需要的 jq/unzip/tshark，下载并验证候选二进制，在回环高端口重复
路由实验，通过后使用临时 systemd 服务运行真实 CF 测试。正式部署尚未执行。

## 真实 Cloudflare PoC

用户补充测试域名，并要求暂不使用 CF token。使用已有 DNS/proxied 设置及临时自签源站
证书，未修改 CF DNS/zone，未签发 ACME 证书。临时服务设 3600 秒运行上限。

- A′ 两节点实际代理均成功，trace 出口等于 VPS IPv6。
- CF 普通请求由初始 521 变为 404；非 CF 来源伪造 CDN SNI 失败。
- 伪装站 HTTP200，证书校验/TLS1.3/h2 成功；证书链 4648 字节，目标不支持 ML-KEM。
- ECH outer SNI 与 CF 回源 SNI 分别抓包确认；IP DoH 证书验证成功。
- 正确/省略 ML-DSA Verify 成功，错误 Verify/shortId/VLESS Encryption 失败。
- 原方案 A 返回 302，节点 B 无新连接；恢复 A′ 后 404。
- packet-up 与 auto 都正常；REALITY fallback 限速会拖慢正常节点 B。

原始带真实标识的材料留在 VPS 私有目录；脱敏命令、指标及限制见
[poc-results.md](../../references/poc-results.md)。

## 结束检查与清理

最终 server/client A/client B 三份配置均 `xray run -test -format json` 成功。
两节点再次代理成功，CDN 普通请求为 404；确认恢复 A′、B packet-up，fallback 限速为关闭。
随后停止全部 xray-poc 临时服务及客户端，443/8001/8002/20808/20809/20810 全部释放，
系统仅剩 SSH 22 监听，无 xray-poc 单元残留。

私有工作目录留在 VPS `/root/xray-poc/live`，目录权限 700、文件统一收紧到 600；
删除两次失败准备的废弃密钥目录。仓库扫描未发现本次真实域名、实例地址、密码或密钥。
本次没有交付可供长期运行的部署服务，也没有完成正式证书和客户端导入验收。

## 用户追加策略与私密导出验证

用户接受目标站协商 X25519，明确禁用 REALITY 中继限速防刷，要求节点链接以文件交付，
执行者尽量不接触内容。已更新 Skill 入口、计划和工具；历史限速实验数据保留但不再执行。

在 VPS 内使用已有配置运行 `xrayctl check-policy` 与 `show-links --xray ... --json`：

```text
[PASS] POLICY: REALITY fallback bandwidth limits absent
[PASS] EXPORT: 2 links, private JSON clients included
[PASS] remote export permissions and line count
[INFO] no listener on 443; exported PoC configuration only
```

两份完整客户端均通过现有 v26.9.30 二进制 `run -test -format json`。产物留在 VPS
`/root/xray-poc/export/links.txt`、`node-a.json`、`node-b.json`，目录 700、文件 600。
导出未轮换任何密钥，未启动服务，未改 CF/DNS。执行者只收到上述状态和路径，没有读回产物。
这是已有 PoC 配置的文件导出，不是新增连通验收或 GUI 导入验证。

本地 `tests/unit/private-export.sh` 通过：权限/行数、URI 参数编码、IPv6、稳定重复导出、
无凭据 stdout/stderr、错误 core、解析失败、跟踪模式、symlink/hardlink 拒绝、并发锁。
ShellCheck、Bash 语法及 Skill frontmatter 校验通过；源码路径和命令见仓库。
