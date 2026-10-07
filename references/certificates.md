# 公共证书与自动续签

默认且必须采用 **Let’s Encrypt 公共可信证书 + Certbot 自动续签 + Cloudflare Full (Strict)**。
其他公共 CA 的证书也必须通过系统信任链、域名、有效期与密钥匹配检查，并接入已验收的续签设施。
本仓库自动安装路径使用 Certbot。自签证书、Cloudflare Origin CA、ACME staging 测试证书
均不满足这项公共信任要求；不退回 Full、不关闭 TLS 校验、不询问是否接受自签。

这是 XHTTP 自有域名的**源站证书**；REALITY 使用的目标站域名无需用户申请证书。
有既有节点时保留 UUID、REALITY 密钥、Encryption、路径和客户端文件，只迁移证书。

## 1. 优先复用，再申请

先在目标机内部检查既有 Certbot lineage、续签配置和定时器，只返回状态与路径。
`/etc/letsencrypt/live/CERT_NAME/` 是稳定目录，内部链接指向 archive 中的当前证书；
不直接使用某个 archive 序号文件。有效既有证书优先复用，避免重复签发触发限额。
已有 `provided` 标记并不证明有自动续签，仍须执行第 3、4 节。

发行版依赖为 `certbot`、`ca-certificates`、`openssl`，网站/HTTP-01 还需 Nginx。
先按 [网站规程](website.md#依赖与安装) 检查已有服务，防止安装包自动启动默认站点抢占端口。
签发、演练和原始诊断全部写入目标机 700 目录内的 600 日志；不打印 Certbot 原始输出，
不把私钥、Cloudflare token、证书文件或节点配置读回模型。

## 2. 首次签发

### 默认 HTTP-01（无需 Cloudflare token）

Let’s Encrypt HTTP-01 使用公网 **TCP 80**，443 上的 REALITY/SNI 分流不能替代它。
核对域名 A/AAAA、CAA、DNS 传播与安全组/防火墙，确保每个已发布地址都能正确响应挑战。
可保留橙云；`http://域名/.well-known/acme-challenge/验证值` 必须到达同一个 webroot，
不能被缓存、WAF/验证码、Access、重写或强制 HTTPS 截走。
初次还没证书时尤其要排除该路径的 HTTPS 跳转，否则 Strict 下可能出现 526。
只对验证路径做必要例外，保留其他网站规则与 XHTTP 来源限制；不改灰云绕过节点 ACL。

80 已有网站时，在其原配置中增加 webroot challenge location，校验后重载；不停止现有网站。
80 空闲时可安装下面的**常驻**独立响应器。以下为目标机 root 命令（普通用户用本机 sudo）：

```sh
install -d -m 755 /etc/xray-skill-acme /var/lib/xray-skill-acme/.well-known/acme-challenge
install -m 644 templates/acme-nginx.conf /etc/xray-skill-acme/nginx.conf
install -m 644 templates/systemd/xray-skill-acme.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now xray-skill-acme.service
```

该服务使用发行版 www-data 用户，只返回 challenge 文件，其他路径 404；与 8003 上的
网站服务分开。系统完全关闭 IPv6 时去掉模板中的 `[::]:80`，同时纠正不可达 AAAA。
先放一个随机测试文件，用 HTTP 请求并在脚本内部比较响应，返回匹配布尔值，再删除它。
本机源站测试和经 CF 的域名测试都要做；任何一步失败先修挑战链路，不反复申请证书。

首次 ACME 注册需要同意 CA 服务条款；按用户的部署授权执行。复用已有账户及联系信息。
无邮箱时可使用 Certbot 的 `--register-unsafely-without-email`；邮箱不作为部署前置条件。
以下示例只含保留文档域名，执行者替换为用户的 XHTTP 域名；可先以同样参数加 `--dry-run`
验证挑战，不把 staging 证书安装到节点。生产签发：

```sh
install -d -m 700 /var/log/xray-skill-acme
umask 077
if certbot certonly --non-interactive --agree-tos --register-unsafely-without-email \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --webroot --webroot-path /var/lib/xray-skill-acme \
    --cert-name cdn.example.com -d cdn.example.com \
    > /var/log/xray-skill-acme/issue.log 2>&1; then
    printf '[PASS] ACME: certificate issued\n'
else
    printf '[FAIL] ACME: issuance failed; inspect categories locally, no self-signed fallback\n'
fi
```

签发失败即停止后续生成/安装，分类处理 DNS、CAA、80 不通、CF 规则或限额，不输出原始日志。
成功也要调用 `check-public-cert.sh`，不能仅凭 Certbot 退出码就声称证书合格。
HTTP 响应器、webroot 与路径例外在初次签发后必须保留，未来续签仍依赖它们。

### 80 不可用时：自动 DNS-01

使用发行版 `python3-certbot-dns-cloudflare`；token 只存目标机 root 的 600 私有文件，
目录 700，不让用户把 token 粘贴进聊天。权限限于所需 zone 的 DNS 编辑，具体范围以插件官方要求为准。
用 `certbot certonly --dns-cloudflare --dns-cloudflare-credentials /private/cloudflare.ini`
替代上面 webroot 参数，仍指定 Let’s Encrypt 生产目录、域名、非交互注册参数并私密记录输出。
凭据文件保留供自动续签，禁止用每次人工加 TXT 的 manual 模式冒充无人值守续签。
DNS API 授权缺失时只补问必要凭据的私有文件位置；不索要远程 VPS 或降级证书。
DNS-01 不需要 HTTP 响应器，但也必须通过第 4 节演练。

## 3. 安装与已有节点迁移

生成节点时**必须**传 `--origin-cert`、`--origin-key`，生成器在生成节点密钥前执行：

```sh
scripts/check-public-cert.sh \
  --cert /etc/letsencrypt/live/cdn.example.com/fullchain.pem \
  --key /etc/letsencrypt/live/cdn.example.com/privkey.pem --hostname cdn.example.com
```

检查叶证书非自签、公共链完整、域名匹配、至少 14 天有效期、证书与私钥匹配。
新安装通过 `install-runtime.sh --certbot-lineage /etc/letsencrypt/live/cdn.example.com ...`
自动安装部署钩子。它要求准备目录的证书与该 lineage 一致。

**已有节点**不跑 prepare/install，不重建配置。备份后直接执行：

```sh
scripts/configure-certbot-renewal.sh --lineage /etc/letsencrypt/live/cdn.example.com
```

该脚本立即迁移源站证书、配置 Certbot deploy hook、启用 `certbot.timer`，成功后停用旧
`xray-skill-selfsigned.timer`。网站更新定时器和节点凭据不变。旧自签续期入口已拒绝续签。
如果有另一个手工部署钩子，先在目标机内部核对，只移除本实例重复的证书拷贝/重启操作；
保留其他站点的 hooks，不并存未经核对的两套续签逻辑。

续签成功触发 `/etc/letsencrypt/renewal-hooks/deploy/xray-skill.sh`，它：

1. 仅处理绑定的 `RENEWED_LINEAGE`，用运行配置里的 XHTTP 域名验证新证书。
2. 在运行锁下备份并安装证书和私钥到 `/etc/xray-skill/certs/origin/`，root:xray-skill 640。
3. 网站的后端 TLS 信任设为系统公共 CA；检查 policy、Xray 配置及 Nginx 配置。
4. 对原本运行的 Xray **执行重启**，Nginx 平滑重载；失败恢复旧证书和配置并恢复服务。
   Xray 的 service 没有 ExecReload，不能描述成两者都无中断热重载。停用的服务不会被擅自启动。
5. 全部成功才写入私有部署回执。节点链接不变，无需重新导入客户端。

Certbot 的 `live` 路径仅用于签发/续签，服务读取受限的副本，不能只改 live 软链接却忘了同步副本。

## 4. 必须验收自动续签

```sh
scripts/check-certbot-renewal.sh --dry-run
scripts/check-service.sh --json
```

第一步实际执行 `certbot renew --cert-name CERT_NAME --dry-run --run-deploy-hooks`。
Certbot 官方说明：普通 dry-run 默认**不运行 deploy hooks**；加该选项后挑战成功才运行，
使用当前有效证书，而非 staging 证书。演练会重启运行中的 Xray，沿用本次部署/修复授权执行。
脚本要求部署回执发生变化，并验证安装证书、定时器、钩子与续签配置，再记录演练证据。
Certbot 退出 0 但没有执行部署钩子时仍 FAIL；演练失败会清除旧的成功标记。

不带参数的 `check-certbot-renewal.sh` 是只读检查，不反复签发或重启服务；
续签配置/部署钩子变化后旧证据失效，需要重做演练。定时器启用只是前提，不代表未来一定续签成功。
最后验证 CF Full (Strict) 下首页和 A/B 实际代理：网站 200、B 鉴权正反例通过；
HTTP 526、签发失败、演练未运行均不能标完成。临时网络/CA 故障保留现有节点并明确未通过项。
自动续签由 systemd/Certbot 完成，不需要 Codex/Claude 在线。发行版定时器定期检查，
由 Certbot 按证书续期窗口决定是否签发，不按固定“每 90 天”硬编码。

## 官方依据与测试边界

- [Let’s Encrypt 验证方式](https://letsencrypt.org/docs/challenge-types/)：HTTP-01 的 80 端口与 DNS-01。
- [Certbot 使用文档](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates)：自动续签、webroot、deploy hooks。
- [Certbot CLI 官方源文档](https://github.com/certbot/certbot/blob/master/certbot/docs/cli-help.txt)：`--dry-run` 与 `--run-deploy-hooks`。
- [Cloudflare DNS 插件](https://certbot-dns-cloudflare.readthedocs.io/en/stable/)：凭据权限与自动挑战。

2026-10-07 核对官方文档。仓库使用隔离 CA、临时目录和模拟 Certbot/systemd 测试拒绝、部署、回滚及
回执逻辑；测试 CA 只被测试副本信任，不给生产脚本增加信任覆盖入口。真实 ACME 签发、续签及
Cloudflare Full (Strict) 必须在用户的目标机逐项验收，不把用户粘贴的另一台机器日志算作本次实测。
