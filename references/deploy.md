# 执行者部署规程

verified_against: core v26.9.30；Debian 13 amd64/真实 CF 记录见 docs/test-records。
由 Agent 逐步执行，仅修改用户授权的 VPS；不要把控制机当部署目标。

## 1. 输入与已有环境

需要 VPS 访问方式、伪装域名、CF CDN 域名和证书方式；客户端版本可边执行边收集。
先检查 `/etc/xray-skill`、服务和 443。已有部署转诊断或生命周期，不调用生成器重新生成密钥。
通过 SSH 工作时复制整个 Skill 到 `/root/xray-skill-src`，保留 scripts/templates/versions.env 的相对关系。
不要把真实域名/IP、密码、token 写入仓库。以下命令从目标机 Skill 根目录执行。

## 2. 预检与目标

缺依赖时在部署授权内安装，再运行只读检查：

```sh
apt-get update
apt-get install -y curl jq unzip openssl iproute2 ca-certificates zstd util-linux
scripts/preflight.sh --json
scripts/check-reality-dest.sh --strict --json example.com
```

域名替换为用户提供的值。预检本身不修复系统；执行者处理时钟、依赖和防火墙后重测。
443 被其他服务占用时先识别/备份，不直接杀进程；8001/8002 必须空闲。至少 512 MB 内存、
1 GB 磁盘；检查 systemd/权限和公网连通。放行 TCP 443，不改 SSH 规则，另核对安全组。
目标 R03/R04/R06/R07 失败不能正常部署。R05 是允许的 X25519 回退；R13 不通过用 mldsa off。
R10/ASN 归属属于辅助核对，缺少资料不伪造 PASS。备用目标须分别验证。

## 3. CF 与证书

按 [CF 清单](cloudflare-checklist.md) 确认橙云、回源 443、SSL/WAF/缓存。
不用 token 时保留用户已有 DNS；记录缺失/错误由用户面板修正，不用灰云绕过来源限制。
不能把 DNS 解析得到的 CF 地址误当 VPS 地址。

- **Full＋自签**：用户接受这种模式时用默认自签源站证书，开启每日检查/续签；不需要 token。
  这不提供公共 CA 信任或 Strict 的源站身份校验。
- **公共 CA 证书＋Full (Strict)**：提供目标机上的 fullchain/key，确认 SAN/完整链及有效期
  超过 14 天。执行者验收既有续期任务安装到运行位置，并测试重载。
- 用户要求新建 ACME/DNS-01 时，查当日 acme.sh 官方 tag/校验来源，用 VPS 私有凭据文件，
  先 staging 再正式签发，然后使用 provided 模式。这一分支没有本仓库真实签发证据，必须
  现场补验收；不能在缺少凭据时假装完成，也不擅自切换证书模式。

## 4. 固定 core 与私有文件

```sh
scripts/fetch-xray.sh --output-dir /root/xray-work/bin
scripts/prepare-node-files.sh \
  --xray /root/xray-work/bin/xray --work-dir /root/xray-work/prepared \
  --dest example.com --cdn cdn.example.com --address 203.0.113.10 --mldsa on
```

fetch 按 versions.env 固定 tag/hash，只提取官方 ZIP 三个明确文件；也可用已经校验的缓存。
prepare 只生成私有文件并测试，不启动服务。输出目录必须新建，避免覆盖旧密钥。
已有 CA 证书追加 `--origin-cert /private/fullchain.pem --origin-key /private/key.pem`。
读取真实文件的操作留在脚本内，Agent 不读回配置/密钥/原始日志。

当前脚本覆盖 A′、单用户/单目标、A enc=none、B packet-up、ML-DSA on/off。
B′、多用户、A encryption 或特殊传输参数，由执行者在副本中依据 pin 源码实现，做隔离及
鉴权反例验证；不得静默接受未实现的参数。多用户每人导出独立的 A/B 两行文件。

## 5. 安装常驻运行

```sh
scripts/install-runtime.sh --work-dir /root/xray-work/prepared --xray-dir /root/xray-work/bin
```

首次安装创建专用用户，迁移配置/证书/客户端文件，先以服务用户运行 -test 再启用常驻服务。
只接管空闲 443 或路径匹配的临时 PoC 服务。self-signed 模式带证书检查；provided 模式由
执行者安排续期。失败保留私有输入，按诊断处理，不删除运行目录后盲目重跑。

## 6. 验收与交付

按 [验收规程](verify-and-diagnose.md) 验证 A/B 实际代理、来源反例和服务自启；不能只看 active。

```sh
scripts/show-links.sh --xray /usr/local/bin/xray-skill-xray --json
```

交付 `/etc/xray-skill/client/links.txt`（两行）和两份 JSON，回复仅包含路径/权限/状态。
保留服务运行，只清理临时测试客户端。
