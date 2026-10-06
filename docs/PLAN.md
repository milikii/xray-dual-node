# Skill 0.1.0 交付范围

2026-10-06 用户明确：交付供 Codex / Claude 使用的 Skill，执行者负责整个任务，脚本只辅助
确定性操作。这覆盖早期“必须实现完整 xrayctl 管理平台和定时上游机器人”的施工安排。
Skill 是否交付，以执行者有完整的任务规程、支持材料和验证证据判断。

首版包括任务分流入口、双平台安装、部署/验收/排错/生命周期/上游维护规程，固定版本和哈希，
目标检查、私密生成、运行服务安装、文件交付辅助脚本，以及测试、版本记录和实际运行证据。
Skill 版本为 0.1.0，默认 core 为 v26.9.30，两个版本分别管理。

默认 A′、CF 来源限制、未知 SNI blackhole、A enc=none、B packet-up＋Encryption＋ECH；
目标不支持 ML-KEM 可回退 X25519；不用 REALITY 中继限速；只交付私有节点文件。
本会话不用 CF token，其他环境由执行者根据用户的 DNS/证书设施选择。

未执行的 GUI 导入、其他 OS/架构、B′ 完整部署和 ACME DNS-01 仍标未测，不能因发布 Skill
改写为成功。执行者遇到对应环境仍需验收。CI 只验证技能和脚本，不操作 VPS、不自动升级。

[历史方案](history/PLAN-v0.1-original.md) 用于追溯。其“Phase 0 出口/未完成 CLI”属于旧产品
安排，不再是当前 Skill 任务的执行门槛。维护与发版见 [MAINTENANCE.md](MAINTENANCE.md)。
