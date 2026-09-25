# Verifier v11 — 验收标准（服务注册表 / 接口自动识别）

在 v10 全部标准基础上，新增接口自动注册验收：

1. **v10 全部标准仍然通过**（共 60 项）。
2. **放文件即生效**：向 `internal/services/` 写入一个注册 `probe` 服务的临时 .go 文件，重新构建后 `rabbitcli probe +ping` 可用且输出 `ok:true`；`schema` 列表含 probe；`--help` 的 Registered services 含 probe。
3. **删文件即消失**：删除该临时文件重新构建后，`rabbitcli probe` 返回 unknown command（退出码 2）。
4. **注册表防重名**：源码中存在 duplicate 注册 panic 保护（grep 检查）。
5. **demo 已迁移**：`internal/cli/cmd_demo.go` 不存在，`internal/services/demo.go` 存在。

## 运行方式

`bash verifier/v11/verify.sh`，退出码 0 即全部通过。
