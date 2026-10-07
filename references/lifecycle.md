# 执行者生命周期规程

verified_against: v26.9.30 的运行布局；回滚算法须在每次版本迁移时现场验证。
更新/备份/恢复/卸载由 Agent 编排命令，不依赖未实现的 xrayctl 子命令。

## 备份

备份包含秘密，只放 VPS root 私有目录。操作前确认是本 Skill 管理的实例。

```sh
umask 077
install -d -m 700 /var/lib/xray-skill/backups
```

创建唯一时间戳目录，记录当前二进制软链接目标及服务是否 enabled/active（内容留文件内），
使用 `tar --zstd` 备份 `/etc/xray-skill`、本 Skill 的 systemd 单元与定时器、当前二进制和
geo 资产。保留当前与前一已验证版本。tar 输出/错误留私有日志，报告只给备份路径/权限。
启用网站时还须备份 `/var/www/xray-skill`、`xray-skill-web.service` 和网站的 enabled/active 状态；
AI 资讯站还包含 `/var/lib/xray-skill-news`、`xray-skill-news.service`、`xray-skill-news.timer` 及其状态。
`/etc/xray-skill/nginx.conf` 含 XHTTP 私有路径，只进入私有备份，不读回到上下文。
检查归档可读取和文件数量，并在私有临时目录演练恢复；不把含秘密的归档传入聊天/Issue。

## 升级 core

1. 用户要求升级时，先读 MAINTENANCE.md 验证候选 tag。维护报告本身不授权立即改运行节点。
2. 固定新 tag/hash，暂存到新的版本目录，保留旧目录。fetch-xray.sh 只下载当前 versions.env
   中的 pin；验证其他 tag 时在维护工作副本更新 pin/hash，不能临时改正在使用的仓库数据。
3. 拷贝配置到私有暂存目录。只根据该 tag 官方文档/源码改受影响字段，不动 UUID/密钥/path。
   由新 core 执行 -test，并跑 check-policy。配套测试脚本的版本约束要随验证证据更新。
4. **切换前备份**配置、证书、旧 core、软链接、版本元数据和 systemd 单元。此版 service
   WorkingDirectory 含 core 版本目录，升级时也须更新它，不能只改软链接。
5. 用一个带 flock 和失败 trap 的目标机 Shell 执行事务：原子安装已测试配置/单元、切换 core
   软链接、更新 recovery.json 中 tag、daemon-reload、restart；原始输出全留私有日志。
6. 调用 check-service.sh 并完成外部入口/客户端必要检查。任一失败则触发下面的回滚；
   成功才清理多余旧版本、更新私有导出，确认旧链接是否保持一致。

Agent 应先在隔离测试端口或测试 VPS 演练这次升级/回滚，不把一次 core 配置测试当作升级成功。
不得使用 wget 覆盖当前 xray 文件再重启的方式升级。

## 回滚/恢复

使用本工具此前在 root 私有目录中创建的备份；用户提供外部归档时先在隔离目录检查路径和
链接，禁止绝对路径/`..` 越界，不直接解到根目录。先用旧 core 测试恢复配置，再恢复旧
配置、证书、单元、软链接和版本元数据，daemon-reload 后恢复原 active/enabled 状态。
运行 check-service 和外部入口验证，确认旧链接仍可用。失败时保留两套现场，不清空全部配置。
只恢复软链接而不恢复配套配置/证书/单元不算回滚完成。
网站模式恢复时同时恢复静态站、current 相对链接、资讯缓存与定时器、Nginx 配置和服务，
先检查配置，再恢复原服务状态；备份/恢复前停止更新定时器和正在运行的资讯任务，完成后恢复原状态。
普通升级/重启不重新生成页面，换主题只替换静态文件；给旧节点加站按 [网站规程](website.md) 迁移。
provided 证书续期部署 hook 必须验证并重载 `xray-skill-web.service`，同时使 Xray 使用新证书。

## 增删用户与轮换

默认生成器是每节点一名用户，不能通过重跑 prepare 来“加用户”。
Agent 在私有配置副本内用固定 core 生成新 UUID，保留原 clients，并为新用户生成单独客户端
配置；测试/备份/提交后单独导出该用户两条链接。删除用户按已授权名称匹配，不打印 ID。
短 ID、REALITY 密钥、VLESS Encryption、path 等轮换会影响客户端，先说明具体影响并复用
用户已明确的轮换授权；没有轮换指令就不能换。新的材料仍由 core/openssl 生成，文件传递。

## CF IP 更新

分别获取 CF 官方 ips-v4 和 ips-v6，独立按换行 split 后合并，不能直接串联无尾换行文件。
验证 CIDR/非空，保留旧缓存；只更新 sni-router 的 CF source 列表。配置先 policy/-test 再重启，
做真实 CF 正例与非 CF 反例。失败恢复旧配置。执行者在维护时检查缓存时效，不假称已安装每日刷新机器人。

## 卸载

确认用户要卸载的是本 Skill 实例；先备份。停用 xray-skill.service 和 xray-skill-selfsigned.timer，
若启用了网站，也停用并删除 `xray-skill-web.service`；删除本 Skill 的 systemd 单元并 daemon-reload，
资讯站还需停用 `xray-skill-news.timer`、停止 `xray-skill-news.service` 并删除这两个单元；
删除本 Skill 的二进制/软链接和运行用户。不要停用其他站点的 nginx.service 或卸载共享 Nginx。
如果先前设置了独立 nft 表，只删除该表；不清空全机防火墙，不卸载共享依赖或删除其他代理服务。
默认保留 `/etc/xray-skill` 和备份目录，明确告诉用户其中含秘密。
网站目录 `/var/www/xray-skill` 默认保留，明确列出；用户要求清除本实例数据时才删除。
资讯状态目录 `/var/lib/xray-skill-news` 同样默认保留；独立 xray-news 用户仅在确认专属本实例后移除。
只有用户明确要求清除才删除保留数据；DNS 只处理本次明确创建且记录了 ID 的记录，
本会话无 token/未创建 DNS，因此卸载不改 Cloudflare DNS。
最后检查本服务 inactive、单元不存在、443 不再由本实例监听，报告残留数据路径，不输出内容。
