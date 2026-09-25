# Verifier v7 — 验收标准（日志按大小切割）

在 v6 全部标准基础上，新增日志按大小切割验收：

1. **v6 全部标准仍然通过**（静态二进制、冒烟、日志框架、环境切换器等，共 35 项）。
2. **大小切割**：设 `RABBITCLI_LOG_MAX_SIZE=2048` 连续运行多条 debug 命令后，日志目录出现 `rabbitcli-YYYYMMDD.log` 及 `rabbitcli-YYYYMMDD.N.log` 轮转文件，且除最后写入的文件外每个文件 ≤ 阈值 + 单条日志最大长度（允许 1KB 余量）。
3. **切割后内容连续**：所有轮转文件合并后仍包含多条 `command start` 记录（无内容丢失）。
4. **默认阈值**：不设环境变量时 MaxLogSize 为 10MB（通过源码常量检查）。
5. **过期清理兼容**：清理逻辑能正确解析轮转文件名（`rabbitcli-YYYYMMDD.N.log`）的日期（源码检查 `strings.Cut(stem, ".")` 存在）。

## 运行方式

`bash verifier/v7/verify.sh`，退出码 0 即全部通过。
