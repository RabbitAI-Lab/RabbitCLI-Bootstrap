# Verifier v4 — 验收标准（Go 版重构）

1. **静态二进制**：`CGO_ENABLED=0 go build` 成功产出 `bin/rabbitcli`；`ldd` 显示 static / not a dynamic executable。
2. **冒烟测试**（全部用二进制直接运行，不依赖 Node）：
   - `rabbitcli --help` 退出码 0；
   - `rabbitcli demo +hello` 退出码 0，stdout 含 `"ok": true`；
   - `rabbitcli api GET /v1/items --dry-run` 退出码 0，stdout 含 `"dry_run": true`；
   - `rabbitcli badcmd` 退出码 2；
   - `rabbitcli demo items list` 无网络时输出结构化错误（stderr 含 `"ok": false`，非零退出码）。
3. **去飞书化**：源码（排除 verifier/bin/dist/vendor）grep 不命中 `feishu|lark|飞书`（不区分大小写）。
4. **三层架构存在**：`+hello` shortcut、items 资源命令、api raw 命令均存在。
5. **配置目录三级优先**：`--config-dir` 写入/读取/`_dir`；`RABBITCLI_CONFIG_DIR` 生效；flag 优先于环境变量。
6. **版本比较单测**：`go test ./internal/cli` 通过（compareVersions 断言）。
7. **自升级检查端到端**：`rabbitcli update --check --repo cli/cli`（真实 GitHub 仓库）退出码 0 且含 `update_available`。
8. **麒麟平台可编译**：`GOOS=linux GOARCH=arm64`、`GOARCH=loong64` 交叉编译成功。

## 运行方式

`bash verifier/v4/verify.sh`（无 Go 时自动下载工具链到 /tmp），退出码 0 即全部通过。
