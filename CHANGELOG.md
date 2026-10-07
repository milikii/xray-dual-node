# Changelog

## Unreleased

Xray-core 保持 v26.9.30。

- XHTTP 改为必须使用公共 CA 证书，默认 Let’s Encrypt + Cloudflare Full (Strict)。
  生成器不再自动生成自签证书，安装器要求提供 Certbot lineage；旧自签续期入口已废弃。
- 增加 Certbot HTTP-01/DNS-01 规程、持久 HTTP 验证响应器模板、私密部署钩子与续签演练检查。
  续签后校验证书/配置、重启 Xray、重载 Nginx，失败回滚并在恢复失败时保留私有备份。
- 已有节点迁移保留 UUID、密钥和链接；仅更新仓库不会自动迁移在线服务。
- 验收要求公共证书信任链、域名、私钥配对及有效期通过，且部署钩子真实执行；
  仅启用定时器或 Certbot 返回 0 不算续签验收成功。
- 隔离证书/回滚/HTTP-01、本地 A/B 代理和普通用户测试通过；真实 ACME 与 CF Strict
  仍须目标机验收，详见 [测试记录](docs/test-records/2026-10-07-public-certificates.md)。

## [0.1.0] - 2026-10-06

Xray-core: v26.9.30 (pre-release)

### Added

- Codex / Claude Code Skill：按部署、验收排错、生命周期、上游维护分流的执行规程。
- 双平台软链接安装、固定 core/hash、目标检查、私密文件生成/导出及常驻服务辅助步骤。
- ML-DSA on/off、已有公共 CA 证书输入、自签源站证书每日检查。
- 技能/辅助脚本测试与 CI，真实 VPS/CF、常驻恢复和私密交付记录。

### Fixed

- 测试结束后停止节点服务导致已交付链接不可用：服务常驻、自启，清理仅处理临时客户端。
- 文件导出不再向执行者输出 URI/JSON/认证材料，正常及失败路径只返回状态。

### Decisions and scope

- 目标可协商 X25519；不用 REALITY 中继带宽限速；默认 A′ 与 XHTTP packet-up。
- 由执行者编排任务，辅助脚本不是独立的自动升级/部署管理产品。
- 实测主环境为 Debian 13 amd64＋真实 CF。GUI 导入、其他 OS/架构及 ACME DNS-01
  保留未测标记，遇到对应环境由执行者验收。

Upstream refs:

- https://github.com/XTLS/Xray-core/releases/tag/v26.9.30
- https://github.com/XTLS/Xray-core/tree/b26a91de4f3294e26a0ad0a970b81a386a41f789
- https://github.com/XTLS/Xray-docs-next/tree/f2b306415344b9996d7f31775a12e8d2bd6809c6
