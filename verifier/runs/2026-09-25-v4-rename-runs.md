# Verifier v4 运行记录（重命名 mycli → rabbitcli）

## 2026-09-25 run 1
- 结果：PASS=4 FAIL=14，退出码 1
- 失败项：构建失败——sed 全局替换未覆盖目录名 `cmd/mycli`（go build 找不到包路径）
- 处置：`mv cmd/mycli cmd/rabbitcli`

## 2026-09-25 run 2（最终）
- 命令：`bash verifier/v4/verify.sh`
- 结果：PASS=18 FAIL=0，退出码 0
- 变更范围：`*.go` 全局替换（含 `MYCLI_CONFIG_DIR` → `RABBITCLI_CONFIG_DIR`、配置目录 `.config/mycli` → `.config/rabbitcli`）、`go.mod` module 路径、Makefile ldflags 注入路径与产物名、README/说明书、verifier v4 脚本与标准
- 实测值：update --check --repo cli/cli 返回 latest = v2.101.0；arm64/loong64 交叉编译正常
