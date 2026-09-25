# Verifier v5 — 验收标准（日志框架）

在 v4 全部标准基础上，新增日志能力验收：

1. **v4 全部标准仍然通过**（静态二进制、冒烟、去飞书化、三层架构、配置目录优先级、semver 单测、update 端到端、麒麟交叉编译）。
2. **日志文件生成**：以 `--debug` 运行一条命令后，`<config-dir>/logs/rabbitcli-YYYYMMDD.log` 存在，内容为 JSON Lines，含 `command start` / `command done`。
3. **HTTP 请求日志**：debug 级别下含 `http request` 记录（method/url/status/elapsed_ms）。
4. **级别过滤**：默认（warn）级别下，info/debug 记录不写入日志。
5. **敏感信息脱敏**：日志全文不出现请求中的 token 值（URL query 与参数中的 token/secret/key 均替换为 `***`）。
6. **日志目录可定制**：`RABBITCLI_LOG_DIR` 环境变量优先于 `<config-dir>/logs`。
7. **不破坏输出契约**：开启 debug 后 stdout 仍为纯 JSON envelope（不含日志行）。
8. **零依赖**：`go list -m all` 仅含模块自身；二进制仍静态链接。

## 运行方式

`bash verifier/v5/verify.sh`（无 Go 时自动下载工具链到 /tmp），退出码 0 即全部通过。
