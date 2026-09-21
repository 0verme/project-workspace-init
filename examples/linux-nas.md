# Linux / FNOS 示例

以下示例使用 POSIX 绝对路径。`/vol5/1000/ai-workspace` 只是首次 bootstrap 的显式输入示例，不是 Skill 默认路径。

## 首次 bootstrap

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

bootstrap 完成后，`/vol5/1000/ai-workspace/data-warehouse-visualized_base/` 会被识别为日常操作的 Workspace Root。

如果 `Repository` 已在 GitHub 创建但仍然完全为空（没有 branch、default branch 或 commit），这也是合法的 bootstrap 场景。脚本会走 `Empty Repository Bootstrap`：

```text
Remote State: EMPTY_REPOSITORY
Main Workspace: /vol5/1000/ai-workspace/data-warehouse-visualized/
Local branch: main
Remote origin: configured
Remote main: not created yet
```

此路径使用本地 `git init -b main`，只配置 `origin`，不会生成 README、自动 commit 或 push；同时仍创建 `data-warehouse-visualized_base/` 及其控制面目录。

## 初始化完成后的日常操作

当前目录或其父目录包含完整的：

```text
AGENTS.md
STATUS.md
worktrees/
```

时，Skill 自动识别 base，不再要求 `--root` 或 Worktree 绝对路径，也不重新运行 bootstrap。

用户只说：

```text
处理 #65
```

即可生成：

```text
branch:   feat/issue-65
worktree: /vol5/1000/ai-workspace/data-warehouse-visualized_base/worktrees/issue-65
```

如果目标 branch 是 `feat/issue-65-data-delivery`，Worktree 名称为 `issue-65-data-delivery`，不会生成 `worktrees/feat/issue-65-data-delivery`。

## 约束

- 只有首次 bootstrap 才要求 `--repository` 和 `--root` 都显式提供；
- `--root .`、`--root ..`、`--root ~/workspace` 或其他相对路径会被拒绝；
- Root 不存在或当前用户没有读取、进入、写入权限时，只报告 `NEEDS_ATTENTION`；
- 日常创建前检查 branch、已有 Worktree、目标目录和同一 Issue 的活跃 Worktree；
- 真实冲突时请求用户决策，不自动创建 `issue-65-2`、`issue-65-new` 或 `issue-65-copy`；
- 脚本不会执行 `sudo`、`su`、`chmod -R 777`、`chown -R` 或 ACL 重置；
- 已有 Main Workspace dirty、已有模板或历史平铺 Worktree 时只报告，不覆盖、移动、删除或 repair。

## 跨机器边界

FNOS 上的 Main Repository 只能与同一 FNOS / Linux 文件系统侧的 linked Worktree 配合。Windows 与 FNOS 如需维护同一 GitHub 项目，应各自 clone，通过 Git remote 同步，不要共享 linked-worktree metadata。
