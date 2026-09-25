# Verifier v6 — 验收标准（环境切换器）

在 v5 全部标准基础上，新增环境切换能力验收：

1. **v5 全部标准仍然通过**（静态二进制、冒烟、日志框架、去飞书化、三层架构、配置目录、semver 单测、update、麒麟交叉编译）。
2. **env 命令组**：`env add/use/list/current/remove` 全部可用；`env use` 持久化到配置文件 `current_env`。
3. **生效路径**：`env use dev` 后，`api --dry-run` 的 URL 指向 dev 的 baseUrl。
4. **一次性覆盖**：`--env prod` flag 优先于持久化的 current_env；`RABBITCLI_ENV` 环境变量同样生效且低于 flag。
5. **未知环境报错**：使用不存在的环境时返回结构化 config 错误。
6. **config show 显示当前环境**：输出含 `_env` 字段。

## 运行方式

`bash verifier/v6/verify.sh`，退出码 0 即全部通过。
