# Verifier v12 — 验收标准（Skills 版本感知更新）

在 v11 全部标准基础上，新增 skills update 验收：

1. **v11 全部标准仍然通过**（共 67 项）。
2. **install 幂等**：首次 install 后 status 全部为 current。
3. **outdated 检测与更新**：模拟旧版本安装（旧内容 + 匹配 marker）后，status 显示 outdated；`skills update` 将其更新为内置版本并回到 current。
4. **本地修改保护**：用户手改已安装技能后，status 显示 modified；install 和 update 都跳过不覆盖。
5. **update 只动变化的**：未变化的技能在 update 中 action 为 skip。
6. **hash 摘要**：`skills list` 输出含 sha256 字段。

## 运行方式

`bash verifier/v12/verify.sh`，退出码 0 即全部通过。
