# RabbitCLI-Bootstrap（Go 版）

一个通用的、对人和 AI Agent 都友好的 CLI 脚手架。**纯 Go 标准库实现，零依赖，编译产出静态单文件二进制**，目标机器无需安装任何运行时（包括 Node、Go 本身），直接执行即可；原生支持麒麟操作系统（linux/amd64、arm64、loong64）。

## 特性

- **静态单二进制** — `CGO_ENABLED=0` 静态链接，`ldd` 显示 not a dynamic executable，拷贝即运行
- **三层命令体系** — Shortcuts（`+` 前缀，智能默认值）→ 服务命令（与 API 端点 1:1 映射）→ Raw API（任意接口调用）
- **结构化输出契约** — 成功输出到 stdout、退出码 0；错误输出到 stderr、非零退出码；判断成功用 `ok == true`
- **多种输出格式** — `--format json|pretty|table|ndjson|csv`，默认 JSON envelope
- **Dry Run** — `--dry-run` 预览请求不实际发送
- **分页控制** — `--page-all` / `--page-limit` / `--page-delay`，通用 cursor 协议
- **配置管理** — 交互式 `config init`；配置目录三级优先（类 npm prefix）：`--config-dir` > `RABBITCLI_CONFIG_DIR` > `~/.config/rabbitcli`；文件权限 0600，token 脱敏展示
- **自升级** — `rabbitcli update` 查询 GitHub Releases 下载匹配 GOOS/GOARCH 的资产，原子替换自身二进制
- **环境切换器** — 命名环境（dev/staging/prod）各自保存 baseUrl/token，调试时一键切换后端；优先级 `--env` > `RABBITCLI_ENV` > `env use` 持久化
- **日志框架** — 基于标准库 `log/slog`（零依赖），JSON Lines 按天落盘到 `<config-dir>/logs/`，token 自动脱敏，不污染 stdout/stderr 输出契约
- **Agent Skills** — 内置 SKILL.md（go:embed 随二进制分发），`skills install` 一键装进 Agent，`skills new` 脚手架自定义技能
- **schema 自省** — `rabbitcli schema [group]` 输出机器可读的命令/参数结构，Agent 可自助发现用法
- **MCP Server** — `rabbitcli mcp` 一条命令把全部接口注册为 MCP tools（stdio），本地 Agent（ZCode / Claude Desktop / Cursor）直连即用，零依赖手写协议实现
- **输出消毒** — API 返回文本中的 ANSI/OSC 终端控制序列自动剥离，防终端注入，JSON 结构不变
- **可选认证** — `auth login` 实现 OAuth2 device flow（RFC 8628，需服务端两个端点），不配置也能用静态 token，完全不强制

## 构建

```bash
make build            # 当前平台 → bin/rabbitcli
make release          # 全平台交叉编译 → dist/（含麒麟 arm64/loong64）
make install          # 安装到 /usr/local/bin
go test ./...         # 单元测试
```

没有 make 的环境可用等价的快捷脚本 `build.sh`（只需 Go 工具链）：

```bash
./build.sh                          # 当前平台 → bin/rabbitcli（含静态链接自检）
./build.sh --release                # 全平台交叉编译 → dist/ + SHA256SUMS.txt
./build.sh --name acmecli           # 改名构建
./build.sh --version 1.2.3          # 指定版本号
./build.sh --install / --clean      # 安装到 /usr/local/bin / 清理产物
```

版本号通过 ldflags 注入：`go build -ldflags "-X github.com/RabbitAI-Lab/RabbitCLI-Bootstrap/internal/cli.Version=1.0.0"`（Makefile 已封装，`make build VERSION=1.0.0`）。
查询版本：`rabbitcli -v` / `--version` / `-version` / `--v` / `version` 均可，输出 `<名字> <版本>`（随 NAME 派生）。

## 快速开始

```bash
./bin/rabbitcli config init                                  # 1. 交互式配置
./bin/rabbitcli demo +hello                                  # 2. 示例 shortcut
./bin/rabbitcli api GET /v1/items --params '{"limit":10}' --dry-run   # 3. 预览请求
```

## 三层命令体系

```bash
rabbitcli demo +hello                    # 1. Shortcuts（+ 前缀）
rabbitcli demo items list                # 2. 资源命令（1:1 映射端点）
rabbitcli api POST /v1/items --data '{"name":"Ada"}' --dry-run   # 3. Raw API
```

## 输出契约

成功（stdout，退出码 0）：

```json
{ "ok": true, "data": { }, "meta": { } }
```

错误（stderr，非零退出码，用法错误为 2）：

```json
{ "ok": false, "error": { "type": "api|config|usage|network|internal", "code": 404, "message": "...", "hint": "..." } }
```

判断成功检查 `ok == true` 或退出码，**不要**用 `code == 0`。

## Agent Skills 与 schema

```bash
rabbitcli skills list                          # 内置技能（go:embed 随二进制分发，含 sha256 摘要）
rabbitcli skills install --dir ~/.agents/skills  # 装进 Agent 的技能目录
rabbitcli skills status                        # 每个技能状态：new/outdated/current/modified
rabbitcli skills update                        # 只更新有变化的技能（CLI 升级后跑这个）
rabbitcli skills new my-svc                    # 从模板脚手架新技能
rabbitcli schema                               # 全部命令组的机器可读 schema
rabbitcli schema api                           # 单个命令组的 flags/positionals/示例
```

自定义技能放在 `internal/cli/skills/<name>/SKILL.md`，重新构建即随二进制分发。

## MCP Server（给本地 Agent 用）

`rabbitcli mcp` 启动一个 stdio MCP（Model Context Protocol）服务器，把**所有命令组**（内置 + 自注册服务）自动注册为 MCP tools，本地 Agent 无需任何胶水代码即可调用：

```bash
rabbitcli mcp                                  # 启动 stdio MCP 服务器（全部接口）
rabbitcli mcp --list                           # 查看将注册的 tools 清单
rabbitcli mcp --tools api,demo                 # 只暴露指定命令组
rabbitcli mcp --prefix rabbitcli_ --env dev    # 工具名加前缀；--env/--config-dir 透传给每次调用
rabbitcli mcp --timeout 60                     # 单次调用子进程超时（秒，默认 300，0 = 不限）
```

Agent 客户端配置（stdio 类型，command = 本二进制路径）：

```json
{ "mcpServers": { "rabbitcli": { "command": "/usr/local/bin/rabbitcli", "args": ["mcp"] } } }
```

设计要点：

- **每个命令组 = 一个 tool**，描述（子命令/flags/示例）由 `CommandSchema` 自动生成；新增服务文件后 MCP 侧零配置自动出现
- **tool 调用 = 子进程执行** `rabbitcli <group> <args...>`，stdout 的 JSON envelope 原样作为结果；失败（非零退出码）时 stderr envelope + `isError:true`，与 CLI 行为完全一致
- **协议零依赖**：纯标准库实现 JSON-RPC 2.0（换行分帧），支持 `initialize` / `tools/list` / `tools/call` / `ping`，兼容 MCP 协议版本 2024-11-05 / 2025-03-26 / 2025-06-18
- stdout 专属协议通道，日志照常只写文件；长调用不阻塞并发 ping


## 可选认证（OAuth2 device flow）

```bash
rabbitcli config set authDeviceUrl https://auth.example.com/device/code
rabbitcli config set authTokenUrl  https://auth.example.com/token
rabbitcli config set authClientId  your-client-id
rabbitcli auth login             # 打印验证 URL+code，轮询直至完成（--no-wait 立即返回）
rabbitcli auth status            # token 来源与脱敏展示
rabbitcli auth logout
```

不配置这三个端点时 auth 完全不影响使用——静态 token（config / .env.local / 环境变量）照常工作。

### 服务端要求与选型

`auth login` 走 OAuth2 Device Authorization Flow（RFC 8628），**需要服务端实现两个端点**：

| 端点 | 职责 |
| --- | --- |
| `POST {authDeviceUrl}` | 收 client_id → 返回 `device_code` / `user_code` / `verification_uri` |
| `POST {authTokenUrl}` | 轮询接口：用户未确认返回 `{"error":"authorization_pending"}`（CLI 自动重试，含 `slow_down` 处理）；确认后返回 `{"access_token":"...","expires_in":...}` |

推荐服务端（均原生支持 Device Flow）：

| 项目 | 语言 | 特点 |
| --- | --- | --- |
| **Casdoor** | Go | 国产、中文文档、Docker 一条命令启动，国内团队首选 |
| **Keycloak** | Java | 最成熟的开源 IdP，功能全家桶 |
| **Zitadel / Authentik / Logto** | Go / Py / TS | 云原生、现代化 UI |
| **Ory Hydra** | Go | 只做协议层，用户体系接你已有的 |
| **Dex** | Go | 桥接 LDAP/GitHub/SAML 等后端 |

中间件层：oauth2-proxy、Pomerium、Traefik ForwardAuth、APISIX/Kong 网关插件。
自研库：Go 用 `ory/fosite`（含 Device Flow）或 `go-oauth2/oauth2`；Node.js 用 `node-oidc-provider`。

没有服务端时不必折腾：`.env.local` 里放 `RABBITCLI_TOKEN` 即可，auth 相关命令留空不碍事。

## .env.local

用户私有变量（如 token）放在 `.env.local`，不写入配置文件、不随代码提交（已在 `.gitignore` 中）：

```bash
# ./.env.local 或 <配置目录>/.env.local
RABBITCLI_TOKEN=your-token
RABBITCLI_BASE_URL=https://dev-api.example.com
```

- 加载位置：先 `./.env.local`（当前工作目录），再 `<配置目录>/.env.local`
- **真实环境变量永远优先**，.env.local 只填补未设置的变量
- 支持注释（`#`）、`export` 前缀、单双引号值
- `RABBITCLI_TOKEN` / `RABBITCLI_BASE_URL` 会覆盖配置文件中的对应值；`RABBITCLI_ENV`、`RABBITCLI_LOG_*` 等现有环境变量也可写在 .env.local 里

## 环境切换

```bash
rabbitcli env add dev --base-url https://dev-api.example.com --token xxx
rabbitcli env add prod --base-url https://api.example.com
rabbitcli env use dev            # 持久切换（写入配置 current_env）
rabbitcli env list               # 查看全部环境，active 标记当前
rabbitcli env current            # 当前环境名
rabbitcli env remove dev

rabbitcli api GET /v1/items --env prod     # 一次性覆盖，不改持久配置
RABBITCLI_ENV=staging rabbitcli api ...    # 环境变量覆盖
```

选择优先级：`--env` flag > `RABBITCLI_ENV` 环境变量 > `env use` 持久值 > 顶层 baseUrl/token。
`config show` 的 `_env` 字段显示当前生效环境；环境值覆盖顶层同名配置键。

## 日志

```bash
rabbitcli api GET /v1/items --debug      # debug 级别（含每次 HTTP 请求记录）
rabbitcli api GET /v1/items --verbose    # info 级别
RABBITCLI_LOG_LEVEL=debug rabbitcli ...  # 环境变量控制
RABBITCLI_LOG_DIR=/var/log/rabbitcli rabbitcli ...  # 自定义日志目录
```

- 位置：`<配置目录>/logs/rabbitcli-YYYYMMDD.log`（JSON Lines），可用 `RABBITCLI_LOG_DIR` 覆盖
- 级别：`--debug` > `--verbose` > `RABBITCLI_LOG_LEVEL` > 默认 `warn`
- 脱敏：URL query 与参数中的 token/secret/key 值一律记录为 `***`，授权头从不记录
- 轮转：按天切分 + 按大小切割（单文件超过 `RABBITCLI_LOG_MAX_SIZE` 字节、默认 10MB 时切为 `rabbitcli-YYYYMMDD.N.log`），自动清理 14 天前的日志
- 日志只写文件，stdout/stderr 的输出契约不受影响

## 自升级

```bash
rabbitcli update --check                      # 只检查新版本
rabbitcli update                              # 下载并原子替换自身二进制
rabbitcli update --repo owner/name --check    # 指定 GitHub 仓库
```

发布资产命名约定：`rabbitcli-linux-amd64`、`rabbitcli-darwin-arm64`、`rabbitcli-windows-amd64.exe`（GOOS-GOARCH 后缀），`make release` 产物即符合该约定。

## 项目结构

```
cmd/rabbitcli/main.go       # 入口
internal/cli/
  router.go             # 命令路由与全局 flag
  args.go               # 参数解析（--k=v / --k v / 布尔 flag，任意位置）
  output.go             # 输出契约与格式化（json/pretty/table/ndjson/csv）
  config.go             # 配置读写（三级目录优先，0600）
  httpapi.go            # HTTP 客户端（认证、分页、dry-run）
  update.go             # 自升级（Releases 查询、semver 比较、原子替换）
  cmd_config.go         # config 命令组
  registry.go           # 服务注册表（RegisterService）
  cmd_api.go            # raw API 调用
  cmd_update.go         # update 命令
  mcpserver.go          # MCP stdio 服务器（JSON-RPC，零依赖）
  cmd_mcp.go            # mcp 命令组（tools 注册与子进程执行）
  update_test.go        # 版本比较单测
internal/services/      # 你的接口放这里：放一个 .go 文件即自动注册（demo.go 为示例）
Makefile                # build / release / install
verifier/               # 验收标准与运行记录
```

## 如何扩展

1. 在 `internal/services/` 下新建你的服务文件（如 `billing.go`），`init()` 中 `cli.RegisterService` 自我注册——无需改路由，详见 `开发文档.md`；
2. 在 `internal/cli/router.go` 的 switch 中注册新命令组；
3. 未封装的端点始终可通过 `rabbitcli api` 直接调用。

## 重命名

名字是单一来源：`internal/cli/name.go` 的 `Name` 变量，构建期注入即可改名，无需动源码：

```bash
make build NAME=acmecli        # 产出 bin/acmecli
```

改名后以下全部自动跟随：

- 环境变量前缀：`ACMECLI_TOKEN`、`ACMECLI_BASE_URL`、`ACMECLI_CONFIG_DIR`、`ACMECLI_LOG_*`……（旧前缀不再生效）
- 默认配置目录：`~/.config/acmecli`
- 日志文件名：`acmecli-YYYYMMDD.log`
- 自升级资产命名：`make release NAME=acmecli` 产出 `acmecli-linux-amd64` 等

如需修改源码默认名，只改 `name.go` 一处。

## License

MIT
