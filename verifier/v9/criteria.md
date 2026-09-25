# Verifier v9 — 验收标准（名字单一来源，前缀自动派生）

在 v8 全部标准基础上，新增"改名自动派生"验收：

1. **v8 全部标准仍然通过**（共 45 项，使用默认名 rabbitcli）。
2. **构建期改名**：`make build NAME=acmecli` 产出 `bin/acmecli`，无需改源码。
3. **环境变量前缀派生**：acmecli 二进制识别 `ACMECLI_BASE_URL` / `ACMECLI_TOKEN`（dry-run URL 与 authorization 头验证），不再响应 RABBITCLI_* 同名变量。
4. **日志文件名派生**：`ACMECLI_LOG_DIR` 生效，日志文件名为 `acmecli-YYYYMMDD.log`。
5. **配置目录派生**：HOME 隔离下默认配置目录为 `~/.config/acmecli`。
6. **单一来源**：源码中除 name.go 默认值与文档注释外，不含硬编码的 `RABBITCLI_` getenv 调用（grep 检查 os.Getenv 全部走 EnvVar()）。

## 运行方式

`bash verifier/v9/verify.sh`，退出码 0 即全部通过。
