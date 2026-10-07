# 执行者部署规程

verified_against: core v26.9.30；Debian 13 amd64/真实 CF 记录见 docs/test-records。
由 Agent 逐步执行，先确定部署目标，只修改用户选定的机器。

## 1. 输入与已有环境

开始时记录调用技能的当前目录绝对路径为 `delivery_dir`，在切换目录或 SSH 前保存，供最终交付使用。
同时记录调用用户及其 uid/gid；普通用户可在本机通过已有 sudo 权限执行系统操作，
先做 `sudo -n true` 检查。不能因为需要 root 就判断必须提供远程 VPS。
无提权权限时说明具体本机权限障碍；认证通过用户自己的终端/系统通道完成，不在聊天里收密码。
私有节点文件从 root 目录交付给原调用用户时，由脚本以 600 安装到记录的目录并设置原 uid/gid，
禁止读回内容、改变整个 home 的权限或把用户文件永久留成 root 所有。

目标未明确时，首先询问：“是否在当前机器部署？”等待回答后再进入对应分支：
- 是：直接开始本机检查和部署，无需远程连接信息。
- 否：再收集远程机器的 SSH 地址、用户、端口和认证方式中缺失的项，优先复用已有 SSH 配置和凭据。
会话中已明确本机或远程目标时直接沿用，不重复确认。目标未确定前不安装依赖或改动服务。

在选定目标机读取系统版本、当前权限、systemd 状态，检查 `/etc/xray-skill`、服务和 443。
已有部署转诊断或生命周期，不调用生成器重新生成密钥。
本机部署无需 SSH 连接信息，不要求用户提供 VPS IP、登录密码或密钥才能开始检查。
若选定环境不支持部署，说明实际障碍并澄清目标，不自行切换机器。
复用会话信息，只补问缺失的伪装域名和 CF CDN 域名；客户端版本可边执行边收集。
节点 `--address` 优先使用用户已指定的公网地址，否则结合本机网络地址与公网出口探测核对；
多地址、NAT 或探测结果不一致而无法确定客户端可达地址时再询问。不要使用回环/私网地址，
也不要把出口探测成功当作入站可达证明，最终仍须实际代理验收。
通过 SSH 工作时复制整个 Skill 到目标机 `/root/xray-skill-src`，保留 scripts/templates/versions.env 的相对关系。
不要把真实域名/IP、密码、token 写入仓库。以下命令从目标机 Skill 根目录执行。

## 2. 预检与目标

缺依赖时在部署授权内安装，再运行只读检查：

```sh
apt-get update
apt-get install -y curl jq unzip openssl iproute2 ca-certificates zstd util-linux python3 certbot
scripts/preflight.sh --json
scripts/check-reality-dest.sh --strict --json --source-ip "$source_ip" example.com
```

域名替换为用户提供的 REALITY 伪装站；`source_ip` 使用已确认的部署目标公网 IP，
远程部署不可误用控制机 IP。REALITY 域名是要伪装的真实 HTTPS 站点，通常无需用户拥有；
XHTTP 域名是用户控制并经 Cloudflare 代理到源站的域名，两者不要混用。
预检本身不修复系统；执行者处理时钟、依赖和防火墙后重测。
443 被其他服务占用时先识别/备份，不直接杀进程；8001/8002 必须空闲，默认网站还需 8003 空闲。至少 512 MB 内存、
1 GB 磁盘；检查 systemd/权限和公网连通。放行 TCP 443，不改 SSH 规则，另核对安全组。
目标 R03/R04/R06/R07 失败不能正常部署。R05 是允许的 X25519 回退；R13 不通过用 mldsa off。
R10 通过 RIPEstat 对比源站与目标 DNS 解析 IP 的 ASN，显示具体 AS 编号和匹配/不匹配/未知数量。
相同 ASN 仅是选站参考，不代表相同国家/物理机房，也不证明域名可用；不同 ASN 不阻止部署。
查询服务只收到公网 IP，不发送域名配置或认证材料。查询失败标 WARN，禁止伪造相同结果；
解析回源站自身则 FAIL，避免自连接回环。多 IP 最多查询 8 个并报告省略数，结果只代表此次 DNS 快照。
备用目标须分别验证。详细判定及向用户解释的格式见 [REALITY 目标验收](reality-target.md)。

## 3. CF 与证书

按 [CF 清单](cloudflare-checklist.md) 确认橙云、回源 443、SSL/WAF/缓存。
不用 token 时保留用户已有 DNS；记录缺失/错误由用户面板修正，不用灰云绕过来源限制。
不能把 DNS 解析得到的 CF 地址误当 VPS 地址。

必须按 [公共证书与自动续签](certificates.md) 先复用或申请 Let’s Encrypt 证书，再生成节点。
CF 使用 **Full (Strict)**。默认用 Certbot HTTP-01 webroot，无需 CF token；验证路径保持可达，
80 不可用才转自动 DNS-01。不得生成自签或以 Origin CA 代替公共 CA，也不降低 TLS 校验。
首次签发、续签 deploy hook、定时器和包含 hook 的演练都是交付要求。
既有节点只迁移证书/续签设施，禁止重新生成节点密钥。

## 4. 固定 core 与私有文件

默认启用每三天更新的 AI 资讯静态网站，按 [网站规程](website.md) 准备 Nginx 依赖并检查已有实例；
不要启用发行版默认站点。用户明确不需要网站时传 `--website off`。

```sh
scripts/fetch-xray.sh --output-dir /root/xray-work/bin
scripts/prepare-node-files.sh \
  --xray /root/xray-work/bin/xray --work-dir /root/xray-work/prepared \
  --dest example.com --cdn cdn.example.com --address 203.0.113.10 --mldsa on \
  --origin-cert /etc/letsencrypt/live/cdn.example.com/fullchain.pem \
  --origin-key /etc/letsencrypt/live/cdn.example.com/privkey.pem
```

fetch 按 versions.env 固定 tag/hash，只提取官方 ZIP 三个明确文件；也可用已经校验的缓存。
prepare 只生成私有文件并测试，不启动服务。输出目录必须新建，避免覆盖旧密钥。
`--origin-cert`、`--origin-key` 必填，缺失或公共证书校验不通过时拒绝生成。
读取真实文件的操作留在脚本内，Agent 不读回配置/密钥/原始日志。

当前脚本覆盖 A′、单用户/单目标、A enc=none、B 客户端 auto/h2、服务端 packet-up、ML-DSA on/off。
B 的 Extra 不生成额外 JSON，v2rayNG 中留空即可。客户端 TLS 的 auto 在本 pin 选择 packet-up，
仍需用户所在地网络实测，不能据此声称已解决所有 B 连接失败。
`--website random` 为默认值，也可固定 ai-news/ai-hardware/ai-research/ai-digest；
不把用户指定类型改成随机。样式首次随机后固定，资讯由独立三天定时任务更新。
准备时默认首次抓取；`--website-fetch off` 仅用于离线准备/测试，不能将空站声称为已有最新资讯。
网站文件在准备目录生成，安装器负责独立服务、定时器和权限。
B′、多用户、A encryption 或特殊传输参数，由执行者在副本中依据 pin 源码实现，做隔离及
鉴权反例验证；不得静默接受未实现的参数。多用户每人导出独立的 A/B 两行文件。

## 5. 安装常驻运行

```sh
scripts/install-runtime.sh --work-dir /root/xray-work/prepared --xray-dir /root/xray-work/bin \
  --certbot-lineage /etc/letsencrypt/live/cdn.example.com
scripts/check-certbot-renewal.sh --dry-run
```

首次安装创建专用用户，迁移配置/证书/客户端文件，先以服务用户运行 -test 再启用常驻服务。
只接管空闲 443 或路径匹配的临时 PoC 服务。安装公共证书和 Certbot 部署钩子，启用 certbot.timer；
随后必须通过包含 deploy hooks 的续签演练。失败保留私有输入，按诊断处理，不删除运行目录后盲目重跑。

## 6. 验收与交付

按 [验收规程](verify-and-diagnose.md) 验证 A/B 实际代理、来源反例和服务自启；不能只看 active。
按 [私密交付的命名规程](private-export.md#ip-归属与节点命名) 核对源站 IP 的国家及机房/运营商，
得到 `country`、`provider`，用于两条节点的名称。

```sh
scripts/show-links.sh --country "$country" --provider "$provider" \
  --output-dir "$delivery_dir" --xray /usr/local/bin/xray-skill-xray --json
```

本机部署在记录的当前目录执行导出（可通过 Skill 绝对路径调用脚本），交付该目录下的
`links.txt`（两行）、`node-a.json`、`node-b.json`，节点文件只报告路径/权限/状态。
另外执行 `python3 scripts/show-cf-cache-rule.py`，把实际 XHTTP 域名的缓存绕过表达式放入
最终回复的可复制代码块，并附 Cloudflare 设置动作与部署状态，见 [CF 清单](cloudflare-checklist.md#缓存绕过表达式与最终交付)。
远程部署按 [私密交付](private-export.md) 将三份文件取回调用技能的当前目录。
保留服务运行，只清理临时测试客户端。
