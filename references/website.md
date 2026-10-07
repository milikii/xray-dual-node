# XHTTP 域名的静态网站

默认新部署生成 AI 资讯静态站，类型限定为 AI 新闻、AI 硬件、AI 论文研究及综合资讯。
包含首页、历史列表、来源、About、样式和 404 页。网站没有外部脚本、字体、统计、表单或
认证材料，不向访客展示代理实现、节点链接或私有路径。外部链接只指向原始公开资料。
网站内容不保证流量不可识别或不会被封锁。

## 随机样式与三天更新

`prepare-node-files.sh --website random` 首次随机选择 ai-news/ai-hardware/ai-research/ai-digest，
再组合六套配色、三种布局、字体和栏目标题。类型、随机种子保存后不随资讯刷新改变；
用户指定类型时沿用指定类型。`--website off` 保留无网站的原 XHTTP 模式。

首次准备默认抓取；运行后 `xray-skill-news.timer` 按三天间隔触发，附加最多 20 分钟随机延迟。
开机十分钟后检查一次，持久化的上次尝试时间防止重启导致三天内重复抓取；关机期间不抓取，
未到期的开机检查会跳过，等待后续定时器。手动要求立即更新时可由执行者以 xray-news 用户运行
`python3 /opt/xray-skill/src/scripts/news_site.py --force`，只返回状态和数量。
更新不需要 Codex/Claude 常驻、不调用 AI 模型，不消耗模型额度。

默认公开 RSS 来源：Hugging Face Blog、MIT News AI、NVIDIA Blog、ServeTheHome、
arXiv cs.AI/cs.LG。按类型选择相应来源，硬件资讯按 GPU/加速器/芯片等关键词筛选。
只采集标题、最多 280 字符的原文短摘录、来源日期和原文链接，不转载全文、不绕过登录或付费墙。
保留原文语言，不调用模型翻译或编造摘要。论文标明研究来源，About 说明预印本可能未经同行评审。
链接去重、按来源日期排序，首页最多 24 条、历史列表最多 120 条；综合首页兼顾三个分类。
日期缺失就标明未知，不把抓取时间当作发布日期。

来源失败时保留该来源旧内容；全部失败不替换正在服务的页面。首次抓取全部失败时生成明确的
待更新页面和来源链接，不能伪装已有最新文章。每次抓取有超时及大小限制，支持 ETag/Last-Modified；
不读取或执行 RSS 中的指令、脚本、HTML，清洗文字并转义输出，链接和重定向限制在配置的来源域名。
新增来源需在 scripts/news_site.py 中核对并配置，不能把远端提供的地址当作任意抓取目标。

网站按版本放在 `/var/www/xray-skill/releases`，`current` 原子切换到完整的新版本，保留最近三次
更新版本及安装时的初始页面。样式不变；更新失败保留旧站，内容更新不重启 Xray 或 Nginx。
`/var/lib/xray-skill-news` 保存类型、随机种子、缓存和上次尝试时间，目录 700、文件 600。
独立 xray-news 用户运行资讯任务，只能写公开站点及资讯状态，systemd 额外禁止访问节点配置、
密钥与日志目录；网站服务仍使用 xray-skill 用户，不与资讯任务共享身份。

## 分流与证书

```text
443 REALITY → SNI router（8001）
  ├─ 已鉴权 REALITY：原节点 A
  ├─ 伪装站 SNI：原真实站点中继
  ├─ CDN SNI + CF 来源：Nginx（127.0.0.1:8003，TLS + PROXY v2）
  │    ├─ XHTTP 专用路径及其子路径：HTTPS → Xray（127.0.0.1:8002）
  │    └─ 普通路径：静态网站
  └─ 其他：拒绝
```

鉴权 REALITY 流量由最外层处理，不进入网站；上图把它列在入口分支便于阅读。
Nginx 使用现有源站证书并验证到 Xray 的 TLS 连接，必须是公共 CA 证书，后端信任系统 CA。
XHTTP 路径由脚本从私有配置读取，禁止 Agent 读回。关闭反代缓存、请求/响应缓冲与错误拦截，
允许 packet-up 的 POST 和下载长连接。后端 8002 停止接收 PROXY 头，保留 TLS 和 VLESS 鉴权。
CF 来源限制仍由前面的 SNI router 执行。Nginx 不直接绑定公网 80/443。
公开网站目录中只能放生成的静态文件，不能包含配置、密钥、日志、备份或导出文件。

## 依赖与安装

使用 Debian/Ubuntu 提供的 `/usr/sbin/nginx` 与 `/etc/nginx/mime.types`。
先检查已有安装和服务。已有 Nginx 时复用二进制，不改它的配置或监听。
需要新安装时使用发行版包；安装过程需阻止新默认站点自动占用 80/443，例如在包管理器支持的
机制下临时禁止自动启动，并在退出时恢复原策略；不能覆盖原有 policy-rc.d。
不要为了安装包停掉用户现有网站。网站使用本 Skill 的 `xray-skill-web.service`，
资讯更新使用 `xray-skill-news.timer`，不启用发行版默认站点。

新部署的 prepare 默认生成网站和私有 nginx.conf，install-runtime 在写入服务前检查 Nginx
依赖、8003 空闲和目录冲突。独立服务使用 xray-skill 用户、仅回环监听和只读系统目录。
静态文件 644，目录 755；含私有路径的 nginx.conf 为 root:xray-skill 640。
按 [证书规程](certificates.md) 安装 Certbot 部署钩子，续签后校验证书/配置，重启 Xray 并重载网站；
失败恢复旧证书。必须通过包含部署钩子的续签演练。

## 既有节点加站与换主题

不要重新运行密钥生成器。先按生命周期规程备份，保留原 UUID、密钥、域名和 XHTTP 路径。
在私有目录用 `prepare-website.py --server-config ... --output-dir ...` 生成网站及代理配置，
使用 `--certificate-mode provided`（默认）。旧自签节点先按证书规程迁移到公共 CA，不能继续自签。
在配置副本中仅把 to-node-b.redirect 改到 `127.0.0.1:8003`，并把 xhttp-in 的
sockopt.acceptProxyProtocol 改为 false；CF 规则、TLS、encryption 等保持原值。
按新安装器的 releases/current 布局安装静态文件、资讯状态、私有 Nginx 配置及网站/资讯单元，通过 nginx -t、policy、Xray -test 后再进行切换。
在一次有备份和失败回滚的操作中启用网站服务、切换 Xray 配置并记录 recovery.json 的 website=true。
失败恢复原配置与服务状态；最终验收前不删除旧配置。需要占用现有端口的切换应沿用用户授权范围。
只换类型/样式时不修改 nginx.conf 或节点配置；停止资讯任务后更新资讯配置并重新生成完整站点，原子切换 current 后恢复定时器。

## 验收

- 浏览器/HTTPS 获取 CF 域名首页，200 且正文等于安装页面；样式、About、文章链接可访问。
- 未知页面返回 404，隐藏文件不可访问，网站中不存在配置/认证字段。
- A、B 实际代理成功；B 验证上传和下载，不能只测首页或 Nginx 进程。
- 非 CF 来源用相同 CDN SNI 仍失败；未知 SNI 失败；正常 REALITY 伪装站中继保留。
- 网站服务和资讯定时器 active/enabled，资讯用户独立，8003 仅回环；证书续期重载、失败回滚及重启后连通须在实际 VPS 验收。

本仓库离线测试验证所有主题、链接、随机组合与配置注入拒绝；隔离端口集成测试验证本地
TLS/PROXY 分流、静态站、真实 A/B 上传下载和来源反例。真实 CF、用户所在地网络与 systemd 生命周期
仍须逐机验收，不把本地模拟 CF 来源当作实际 Cloudflare 已测试。
