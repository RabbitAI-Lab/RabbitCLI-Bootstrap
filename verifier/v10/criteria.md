# Verifier v10 — 验收标准（Skills / schema / auth / 输出消毒）

在 v9 全部标准基础上，新增四项能力验收：

1. **v9 全部标准仍然通过**（共 51 项）。
2. **schema 自省**：`schema` 列出全部 8 个命令组；`schema api` 输出含 params/data/dry-run 等 flag 定义；未知组返回 usage 错误。
3. **Skills**：`skills list` 列出内置 rabbitcli-shared / rabbitcli-demo（含 frontmatter 描述）；`skills install --dir` 复制 SKILL.md 到目标目录；`skills new` 从模板生成新技能骨架。
4. **auth（可选）**：未配置 OAuth 端点时 `auth login` 返回结构化 config 错误（含"可选"提示）；`auth status` 输出 token 来源（脱敏）；`go test` 用 httptest 模拟 device flow 全流程（pending → token 落盘）。
5. **输出消毒**：`go test` 覆盖 ANSI 颜色、OSC 超链接、C0 控制符、嵌套 map/slice/key 消毒，保留 \n\t 与非字符串值。

## 运行方式

`bash verifier/v10/verify.sh`，退出码 0 即全部通过。
