# Linux / FNOS 示例

以下示例使用 POSIX 绝对路径。`/vol5/1000/ai-workspace` 只是显式输入示例，不是 Skill 默认路径。

## 初始化

```sh
./scripts/init-workspace.sh \
  --repository https://github.com/0verme/data-warehouse-visualized.git \
  --root /vol5/1000/ai-workspace
```

也可以使用明确的 GitHub short form：

```sh
./scripts/init-workspace.sh \
  --repository 0verme/data-warehouse-visualized \
  --root /vol5/1000/ai-workspace
```

预期结构：

```text
/vol5/1000/ai-workspace/
├─ data-warehouse-visualized/
└─ data-warehouse-visualized_base/
   ├─ AGENTS.md
   ├─ STATUS.md
   ├─ status/
   ├─ integration/
   └─ worktrees/
```

## 约束

- `--repository` 和 `--root` 都必须显式提供；脚本没有默认值。
- `--root .`、`--root ..`、`--root ~/workspace` 或其他相对路径会被拒绝。
- 第一版要求 Root 已存在。Root 不存在或当前用户没有读取、进入、写入权限时，只报告 `NEEDS_ATTENTION`。
- 脚本不会执行 `sudo`、`su`、`chmod -R 777`、`chown -R` 或 ACL 重置。
- 已有 Main Workspace dirty、已有模板或历史平铺 Worktree 时只报告，不覆盖、移动、删除或 repair。
- 任务 Worktree 应位于 `/vol5/1000/ai-workspace/data-warehouse-visualized_base/worktrees/<task>`。

## 跨机器边界

FNOS 上的 Main Repository 只能与同一 FNOS / Linux 文件系统侧的 linked Worktree 配合。Windows 与 FNOS 如需维护同一 GitHub 项目，应各自 clone，通过 Git remote 同步，不要共享 linked-worktree metadata。
