# Verifier v2 — 验收标准

在 v1 全部标准基础上，新增自升级能力的验收：

1. **v1 全部标准仍然通过**（构建、冒烟、去飞书化、三层架构、输出契约）。
2. **update 命令注册**：`mycli update --help` 退出码 0，帮助文本含 `--check` 与 `--registry`。
3. **版本比较逻辑正确**：`compareVersions` 单元断言——
   `("1.2.0","1.1.9")>0`、`("0.1.0","0.1.0")==0`、`("0.9.9","0.10.0")<0`、`("v1.0.1","1.0.0")>0`。
4. **registry 查询可用**：`fetchLatestVersion("typescript")` 返回合法版本字符串（需网络；记录查询到的版本值）。
5. **`mycli update --check` 端到端**：退出码 0 且 stdout 含 `update_available` 字段。

## 运行方式

`bash verifier/v2/verify.sh`，退出码 0 即全部通过。
