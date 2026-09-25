# Verifier 索引

| 版本 | 创建时间 | 测量内容 | 与上一版差异 |
| --- | --- | --- | --- |
| v1 | 2026-09-25 | 构建成功、5 项命令冒烟测试、去飞书化 grep、三层架构存在性、输出契约 | 首版 |
| v2 | 2026-09-25 | v1 全部 + update 命令注册、compareVersions 单元断言、registry 查询、`update --check` 端到端 | 新增自升级能力验收 |
| v3 | 2026-09-25 | v2 全部 + `--config-dir` 写入/读取/`_dir` 展示、MYCLI_CONFIG_DIR 环境变量、flag 优先级 | 新增自定义配置目录（类 npm prefix）验收 |
| v4 | 2026-09-25 | Go 版重构：静态二进制（ldd 验证）、二进制冒烟、去飞书化、三层架构、配置目录优先级、CompareVersions 单测、update --check 端到端（GitHub Releases）、麒麟 arm64/loong64 交叉编译 | 项目重构为 Go，替代 v1-v3 的 TS 版验收 |
| v5 | 2026-09-25 | v4 全部 + 日志框架：日志文件生成、HTTP 请求日志、级别过滤、token 脱敏、RABBITCLI_LOG_DIR、stdout 契约不受污染、零依赖 | 新增 slog 日志框架验收 |
| v6 | 2026-09-25 | v5 全部 + 环境切换器：env add/use/list 持久化、dry-run 生效路径、--env 与 RABBITCLI_ENV 覆盖及优先级、未知环境结构化错误、config show 的 _env | 新增环境切换器验收 |
| v7 | 2026-09-25 | v6 全部 + 日志按大小切割：轮转文件生成、单文件不超阈值、跨文件内容连续、默认 10MB、清理逻辑兼容轮转文件名 | 新增日志按大小切割验收 |
| v8 | 2026-09-25 | v7 全部 + .env.local：cwd/配置目录加载、真实环境变量优先、格式兼容、覆盖配置文件、gitignore | 新增 .env.local 验收（补记：此前漏登记） |
| v9 | 2026-09-25 | v8 全部 + 名字单一来源：`-X Name=acmecli` 构建期改名、ACMECLI_* 前缀派生、日志/配置目录名派生、忽略旧前缀、无硬编码 getenv | 新增改名自动派生验收 |
| v10 | 2026-09-25 | v9 全部 + Skills（embed/list/install/new）、schema 自省、auth device flow（httptest 模拟）、输出消毒单测 | 新增四项 Agent 能力验收（补记） |
| v11 | 2026-09-25 | v10 全部 + 服务注册表：放文件即生效、删文件即消失、schema/help 联动、防重名、demo 迁移 | 新增接口自动识别验收 |
| v12 | 2026-09-25 | v11 全部 + skills 版本感知：install 幂等、outdated 检测与更新、本地修改保护、sha256 摘要、只更新变化的 | 新增 skills update 验收 |
| v13 | 2026-09-25 | v12 全部 + 版本 flag：-v/--version/-version/--v/version 五种写法、ldflags 注入值一致、改名派生 | 新增版本输出验收 |

运行记录追加在 `runs/` 目录。
