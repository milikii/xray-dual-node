# 节点 B 移除 ECH

日期：2026-10-07。core：已校验的 Xray v26.9.30。
用户报告旧 B 配置在国内网络因 ECH 握手丢包而不可用，A 正常；本次按要求仅改变 ECH。
该网络根因由用户定位，本维护环境未在用户网络独立复现。国内可用性仍待用户验收。

## 改动范围

- `prepare-node-files.sh` 的 B 客户端不再写入 `echConfigList`。
- `scripts/lib/links.jq` 的 URI builder 不再输出 `ech` 参数；保留原 schema 的可选字段兼容。
- 主导出 fixture 移除 ECH，改为检查新 B URI/JSON 均无 ECH，其余 B 连接参数与输入相同。
- 网站集成测试检查实际生成的 B 客户端无 ECH，仍使用原 SNI、chrome、ALPN、ML-KEM 和 packet-up。
- 更新当前使用规程，保留 E7 历史记录并注明用户反馈“墙内不可用”；不再把 ECH 当作验收要求。

服务端模板、证书、A 客户端及 B 的 ML-KEM/packet-up 参数没有改变。
只修改导出器不会修改既有输入 JSON；已有 B 必须先在私有客户端副本中删除 ECH 字段再重新导出，
不能重新运行全节点生成器导致 UUID、密钥或路径轮换。步骤见 [客户端规程](../../references/client-compat.md#已有-b-客户端移除-ech)。

## 已执行的全套仓库验证

| 检查 | 结果 |
|---|---|
| `tests/check-skill.sh` | PASS：技能入口/引用、ShellCheck、脚本语法/帮助、空白 |
| `tests/unit/helper-contracts.sh` | PASS：安装器与归档校验 |
| `tests/unit/private-export.sh` | PASS：两条链接、新 B URI 无 ech、JSON 无 echConfigList、其余字段保留、私密输出与权限 |
| `tests/unit/reality-asn.py` | PASS：7 项 |
| `tests/unit/website.py` | PASS：3 项 |
| `tests/unit/news-site.py` | PASS：10 项 |
| `tests/unit/auth-results.py` | PASS：7 项 |
| `tests/unit/certificates.py` | PASS：公共证书验证、续签部署、回滚、回执及反例 |
| `tests/unit/acme-http.py` | PASS：回环 HTTP-01 挑战响应器 |
| `tests/unit/cf-cache-rule.py` | PASS：3 项 |
| `tools/poc/local-routing.sh --xray <verified-core> --base-port 29140` | PASS：回环路由、PROXY、来源/SNI 正反例 |
| `tools/poc/local-website.py --xray <verified-core> --base-port 29240` | PASS：A/B 实际上传下载、鉴权反例、网站、生成客户端无 ECH |
| skill-creator `quick_validate.py` | PASS |

以上均使用合成输入或隔离端口；配置、密钥和原始日志未输出到上下文。
本机未发现 `/etc/xray-skill` 的运行配置或现有私有客户端，不能把测试配置当作用户实际节点导出。

## 待完成的实际节点验收

待明确现有客户端所在目录/机器后，备份并仅删除 B 的 ECH 字段，用同版本 core 检查，
通过 `xrayctl show-links` 把实际节点重新导出到调用目录，内部比对 A 不变、B 仅移除 ECH。
不修改或重启服务端；不生成替代凭据。
用户更新订阅/导入后从国内验证 B 实际代理成功，收到结果后才结束连通性验收。
