# Verifier v8 — 验收标准（.env.local 加载）

在 v7 全部标准基础上，新增 .env.local 验收：

1. **v7 全部标准仍然通过**（共 40 项）。
2. **cwd 加载**：工作目录下 `.env.local` 中的 `RABBITCLI_BASE_URL` / `RABBITCLI_TOKEN` 生效（dry-run URL 与 authorization 头验证）。
3. **真实环境变量优先**：进程环境中已有的同名变量不被 .env.local 覆盖。
4. **配置目录加载**：`<config-dir>/.env.local` 中的变量同样生效。
5. **格式兼容**：支持注释（#）、`export ` 前缀、单双引号包裹的值。
6. **优先级组合**：.env.local 变量优先于配置文件顶层值（无激活环境时也生效）。
7. **gitignore**：项目 `.gitignore` 包含 `.env.local`。

## 运行方式

`bash verifier/v8/verify.sh`，退出码 0 即全部通过。
