# Skill 0.1.0 验证记录

日期：2026-10-06。用户要求按 Codex/Claude Skill 交付，并完成提交 push。
core 基线 v26.9.30，Skill 版本独立为 0.1.0。

## 平台发现

重新抓取 OpenAI 和 Claude 官方 skills 页面，核对共同 frontmatter、用户/项目目录及软链接。
`install-skill.sh` 将同一仓库安装到两处；合成目录验证幂等、冲突拒绝及 force 保留旧内容。

实际平台协议输出（仅记录判定，不记录其他技能/账户信息）：

```text
[PASS] Codex skills/list discovered xray-dual-node; no agent turn invoked
[PASS] Claude initialize command discovery includes xray-dual-node; no prompt/agent turn sent
```

Codex 使用 app-server initialize → skills/list；Claude 使用 stream-json initialize 的 command list。
这是实际发现证据，没有发送用户任务，没有声称完成所有自然语言自动触发场景。
Claude plugin validate 在此安装中对目录返回空 contents，单文件又按 JSON manifest 解释，
因此没有把该工具的“success”当作 Skill 内容验证；元数据另经 Skill validator 检查。

## 核心、目标与配置生成

- `fetch-xray.sh` 下载固定官方 ZIP，SHA-256 与 versions.env 相符，明确提取 xray/geoip/geosite。
- 合成 ZIP 测试覆盖匹配哈希、篡改拒绝、已有目录不覆盖；不会修改真实 pin。
- `check-reality-dest.sh` 对会话目标返回 R01–R04/R06–R09/R11–R13 PASS，R05 为允许的
  X25519 回退，R10 归属检查保持 WARN。证书 DER 总长 4648 字节。
- 排除列表中的 Apple 目标得到 R08 FAIL 和退出码 4。
- 文档域名/地址的合成配置分别测试 ML-DSA on、off 和 provided-certificate 输入，
  三组 server/A/B 均通过 v26.9.30 run -test；on/off 两组私有 JSON 导出也通过核心自检。
  provided 测试使用自签 fixture 验证输入/密钥匹配路径，不冒充公共 CA/DNS-01 实测。
- 回环路由实验两种 tunnel/dokodemo-door 名称、来源/SNI 正反例、原 A fallbacks 反例通过。

## 本机隔离安装与生命周期

控制机 Debian 13，安装前 `/etc/xray-skill`、`/opt/xray-skill`、相关单元均不存在。
使用合成节点资料，测试服务仅监听 127.0.0.1:443，不对外发布或修改真实 VPS：

```text
[PASS] isolated first installation, service startup and private backup
[PASS] injected startup failure detected; original unit/config restored and service active
[PASS] local fixture stopped and detached; private artifacts archived; no service listener remains
```

验证首次安装无需运行中的临时 PoC 服务。备份含配置/证书/单元/core/软链接，保存在 root
私有目录。注入 ExecStart=/bin/false 后检测到停服，恢复原单元和配置后重新 active，
配置逐字节未变。最后停止/禁用本机测试服务，将新建单元与运行数据移至私有归档，移除测试用户。
这验证了 Agent 执行规程的恢复操作，不是跨版本升级或通用自动回滚程序的全覆盖测试。

## 真实 VPS 持续运行检查

在真实 VPS 运行 check-service.sh：服务 active/enabled/无时限、专用用户、配置/无中继限速、
回环端口、证书有效期、自签续期 timer、A/B 同版本代理及认证反例、CF 根路径和非 CF
来源反例通过。沿用原密钥/链接，未启停或重新部署真实服务。先前恢复记录仍适用。

## 发布检查

tests/check-skill.sh、helper-contracts.sh、private-export.sh、ShellCheck、Bash --help/语法、
Skill frontmatter validator 和 Markdown 相对引用检查通过。
GitHub CI 配置执行同类本地检查和固定 core 的回环实验，不持有 VPS 凭据。
本地通过不等于 GitHub Actions 已完成；推送后的远端运行状态单独报告。

未测：完整 GUI 导入矩阵、其他 OS/架构、ACME DNS-01/Full (Strict)、B′ 完整部署、
真实新 tag 的跨版本升级。规程要求执行者在遇到相应任务时补验证，不以首版发布覆盖未测事实。
