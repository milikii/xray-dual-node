# 由执行者维护 Xray 双节点 Skill

Skill 0.1.0，核对日期 2026-10-06，默认 core v26.9.30。
维护由用户调用 Codex/Claude 后执行，不依赖定时机器人，也不自动替换 VPS 上的 core。
仓库 CI 只验证技能/辅助脚本；发布 Skill 与升级节点分别处理。

## 用户如何发起

可以直接说：

> 用 xray-dual-node 跟进 Xray-core 作者的新版本。核对源码/文档，更新技能和测试，
> 报告对现有节点的影响，通过后提交 push。

或者：

> 按 xray-dual-node 把这台节点升级到指定 tag，保留原链接，准备失败回滚。

前者默认维护仓库，不默认修改在线节点；后者包含指定 VPS 的升级授权。
复用已有会话参数/授权，缺什么再问，不让用户重复提供凭据。

## 1. 查看上游并固定候选

执行者查看 [官方 releases](https://github.com/XTLS/Xray-core/releases)、
[官方文档](https://github.com/XTLS/Xray-docs-next)，以及下列相关路径的差异：

- `infra/conf/`：字段名、类型、默认值、废弃项。
- `transport/internet/reality/` 与 `go.mod` 的 REALITY 依赖。
- `transport/internet/splithttp/`、`transport/internet/tls/`：XHTTP/ECH。
- `proxy/vless/encryption/`、`main/commands/`：Encryption 与密钥生成命令输出。
- 实际使用的客户端 release/链接导入源码、CF ECH 和 IP 段公布信息。

记录候选 tag/commit、发布日期、release note、文档 commit、资产 SHA-256。
预览版默认观察 72 小时；确认的安全修复单独评估时效，不能仅因关键词命中就断言漏洞。
无法访问上游时保留已核验 pin，并说明此次没有核实新版本。

## 2. 判断哪些变化影响此 Skill

产出一张旧→新字段/行为表，包含出处与影响。例如：

| 变化类型 | 更新位置 |
|---|---|
| target/password 等字段变化 | 配置生成辅助脚本、源码依据、兼容说明 |
| x25519/vlessenc CLI 输出变化 | 私密解析逻辑与合成解析测试 |
| REALITY 群/ML-DSA 行为 | 目标检查、客户端指纹、认证反例与能力描述 |
| XHTTP/ECH/分享参数变化 | 生成/导出、客户端兼容说明、实际链路测试 |
| 运行路径/资产变化 | 下载校验、systemd 模板、生命周期规程 |

不把上游所有新特性都自动设为默认。保留用户确认的 X25519 回退、不做 REALITY 中继限速、
私密文件交付原则。协议字段和默认值必须有当前候选的源码/文档依据。

## 3. 在工作副本更新并验证

1. 在维护分支/工作副本中更新 `versions.env` 的候选 tag/hash，不改在线 core。
   当前脚本有 v26.9.30 的明确版本约束与单元目录，核实后一起更新，不能仅删掉版本检查。
2. 更新 SKILL.md 的任务判断和相应 references；只保留执行者需要的信息，长细节放引用文件。
3. 跑 `tests/check-skill.sh`、`tests/unit/private-export.sh`、`tests/unit/helper-contracts.sh`，
   并对生成配置运行候选 core 的 -test。未知字段可能被忽略，还需核对源码和实际行为。
4. 跑 `tools/poc/local-routing.sh` 的路由正反例；脚本版本门控随候选适配，不能冒用旧结果。
5. 在隔离环境/测试 VPS 验证 A/B 代理、CF 来源正反例、B 无 ECH、目标握手、证书、服务重启，
   根据上游变化追加吞吐/稳定性和实际客户端导入测试。
6. 对生命周期变更演练失败恢复：旧 core、配置、证书、单元、元数据全部恢复并再次连接。
   测试不停止用户正在使用的服务；需要占用同一 443 时先明确安排切换窗口或使用独立 VPS。

每个结果记录日期、tag、客户端版本、命令、脱敏输出和未测范围。
原始配置/日志/抓包留在测试机私有目录，Issue/PR/CI 不含链接、UUID、密钥或随机路径。
失败候选不替换默认版本；适配不能以去掉来源校验或鉴权来伪造成功。
当前 B 已按用户网络反馈移除 ECH，保持其他参数不变，最终由用户所在网络验收。

## 4. 更新知识库和发布 Skill

验证后修改：

- `versions.env`：批准后的 pin 和资产哈希。
- `references/upstream-state.json`：实际核验日期、源码/文档 commit、核验范围。
- `references/`：参数出处与能力矩阵；未测项继续未测。
- `docs/test-records/`：实际证据。
- `VERSION` / `CHANGELOG.md`：Skill 版本、Xray tag、变化、影响和已知边界。

修复/文档用 PATCH，兼容的上游跟进/新增能力用 MINOR，破坏配置/链接/默认拓扑的改变用 MAJOR。
0.x 版本仍在发布说明中明确不兼容变化，不用版本号掩盖用户需要重新导入的事实。
先验证、提交、push，再在用户要求发布版本时推相应 tag；不能将历史未测项改成已完成。
AI 应在 PR/提交说明中说明改什么、依据、验证结果，保持描述与最终实现一致。

## 5. 更新实际 VPS

按 [生命周期规程](../references/lifecycle.md)：暂存候选 → 配置自检 → 私有备份 →
切换 core/配置/单元 → 重启 → 同 core 代理和外网验收 → 失败恢复。
普通升级保留 UUID/密钥/path；文件导出只返回路径，检查旧链接是否仍有效。
仅维护仓库不等于所有已部署 VPS 自动更新；在交付说明里明确本次改了哪一层。

定期由用户发起复核目标站、实际客户端、用户所在地网络连通和 CF IP 列表。
超过 30 天或发现新 release 时提示知识时效，继续使用已核验版本，不能自动浮动。
