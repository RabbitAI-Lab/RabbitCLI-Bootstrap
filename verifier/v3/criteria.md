# Verifier v3 — 验收标准

在 v2 全部标准基础上，新增"可自定义配置目录"（类 npm prefix）的验收：

1. **v2 全部标准仍然通过**（构建、冒烟、去飞书化、三层架构、输出契约、自升级）。
2. **`--config-dir` 全局参数**：`mycli config --config-dir <dir> set foo bar` 后，`<dir>/config.json` 存在且含 `"foo": "bar"`。
3. **读取一致性**：`config --config-dir <dir> show` 能读回该值，且输出 `_dir` 字段指向该目录。
4. **环境变量**：`MYCLI_CONFIG_DIR=<dir> mycli config set baz qux` 写入对应目录。
5. **优先级**：`--config-dir` 优先于 `MYCLI_CONFIG_DIR`。

## 运行方式

`bash verifier/v3/verify.sh`，退出码 0 即全部通过。
