# Verifier v13 — 验收标准（版本 flag）

在 v12 全部标准基础上，新增版本输出验收：

1. **v12 全部标准仍然通过**（共 74 项）。
2. **四种写法**：`-v`、`--version`、`-version`、`--v` 均输出 `<name> <version>` 并退出码 0；`rabbitcli version` 子命令同样可用。
3. **版本号来源**：构建时 ldflags 注入（`make build VERSION=x.y.z`），输出与注入值一致。
4. **名字派生**：`NAME=acmecli` 构建的二进制输出 `acmecli <version>`。

## 运行方式

`bash verifier/v13/verify.sh`，退出码 0 即全部通过。
