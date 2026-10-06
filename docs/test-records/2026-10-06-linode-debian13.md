# 测试节点停服恢复

日期：2026-10-06。Xray-core v26.9.30；Linode Debian 13 amd64；真实 Cloudflare。
用户报告节点不可用。执行者全程仅接收状态、计数、时间和文件路径，不读取节点文件内容。

初始检查：Xray 进程数 0、443 监听数 0，xray-poc inactive，没有持久服务单元。
原自签源站证书到期时间为 2026-10-07 14:24:27 UTC。
原因：上次测试清理停止了临时服务，链接导出没有建立常驻服务。

先恢复原配置，确认原两条客户端均可代理；随后执行 `activate-live.sh` 迁移至
`xray-skill.service`，开启自启、故障重启，以专用用户运行，保留认证材料与来源/SNI 规则。
自签源站证书使用原密钥续签至 2027-10-06 14:07:58 UTC，开启每日检查定时器。
未使用 CF token，未修改 DNS/zone，未启用 REALITY 中继限速。

迁移后实际输出摘要：

```text
persistent service: active
boot startup: enabled
service user: xray-skill
runtime time limit: infinity
renewal timer: enabled
[PASS] node-a-baseline expected=success curl_exit=0
[PASS] node-b-baseline expected=success curl_exit=0
[PASS] node-a-without-mldsa-verification expected=success curl_exit=0
[PASS] node-a-wrong-mldsa-verification expected=failure curl_exit=35
[PASS] node-a-wrong-shortid expected=failure curl_exit=35
[PASS] node-a-chrome120-fingerprint expected=failure curl_exit=35
[PASS] node-b-wrong-vless-encryption expected=failure curl_exit=35
[PASS] renewal task runs successfully and retains a valid certificate
[PASS] service and daily timer active; no crash restarts
[PASS] exported links unchanged from the original file
[INFO] external camouflage request HTTP=200
[INFO] external Cloudflare origin request HTTP=404
[PASS] public REALITY camouflage and Cloudflare origin reachable
```

正式运行配置为 `/etc/xray-skill/config.json`，文件交付为
`/etc/xray-skill/client/links.txt`；与旧 `/root/xray-poc/export/links.txt` 内容完全相同。
私密导出中的两份完整客户端通过已安装 core 的 `run -test -format json`。
这里只完成本次故障恢复和自签证书检查，不标记通用 deploy、ACME/Strict、GUI 导入验收完成。
本次结束保留常驻服务和续期 timer 运行；临时验收客户端由测试脚本清理。
ShellCheck 和 Skill 校验通过；三个已安装 systemd 单元在 VPS 上 `systemd-analyze verify`
通过。控制机没有这些运行路径，故单元运行环境检查以 VPS 上的结果为准。
