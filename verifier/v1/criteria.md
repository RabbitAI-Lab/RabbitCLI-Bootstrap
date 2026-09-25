# Verifier v1 — 验收标准

针对交付物 `/mnt/agents/output/cli-scaffold`（通用 CLI 脚手架）。

## 标准

1. **构建通过**：`npm run build`（tsc）退出码 0，产出 `dist/cli.js`。
2. **冒烟测试**：
   - `mycli --help` 退出码 0；
   - `mycli demo +hello` 退出码 0，stdout 含 `"ok":true`；
   - `mycli api GET /v1/items --dry-run` 退出码 0，stdout 含 `"dry_run":true`；
   - `mycli badcmd` 退出码 2；
   - `mycli demo items list --format table` 在无配置环境下报结构化错误（非零退出码或 dry-run 正常）。
3. **去飞书化**：全项目（除 node_modules/package-lock/verifier 外）grep 不命中
   `飞书|feishu|lark|larksuite|Lark|Feishu|LarkSuite`（不区分大小写）。
4. **三层架构存在**：src 中包含 shortcuts（`+` 前缀）、资源命令、raw api 三类命令实现。
5. **输出契约**：成功 envelope 含 `ok:true`，错误 envelope 含 `ok:false`。

## 运行方式

`bash verifier/v1/verify.sh`，退出码 0 即全部通过。
