# Windows 示例

以下示例使用占位路径。`E:\workspace-root` 只是首次 bootstrap 的显式输入示例，不是 Skill 默认路径。

## 首次 bootstrap

在 PowerShell 中，从 Skill 包目录运行：

```powershell
.\scripts\init-workspace.ps1 `
  -Repository https://github.com/0verme/data-warehouse-visualized.git `
  -Root E:\workspace-root
```

也可以使用明确的 GitHub short form：

```powershell
.\scripts\init-workspace.ps1 `
  -Repository 0verme/data-warehouse-visualized `
  -Root E:\workspace-root
```

预期结构：

```text
E:\workspace-root\
├─ data-warehouse-visualized\
└─ data-warehouse-visualized_base\
   ├─ AGENTS.md
   ├─ STATUS.md
   ├─ status\
   ├─ integration\
   └─ worktrees\
```

bootstrap 完成后，`E:\workspace-root\data-warehouse-visualized_base\` 会被识别为日常操作的 Workspace Root。

## 初始化完成后的日常操作

如果当前目录或其父目录能找到：

```text
AGENTS.md
STATUS.md
worktrees\
```

则不再要求 `-Root`，也不重新调用 bootstrap。比如用户只说：

```text
处理 #65
```

可以自动得到：

```text
branch:   feat/issue-65
worktree: E:\workspace-root\data-warehouse-visualized_base\worktrees\issue-65
```

如果用户给出：

```text
branch: feat/issue-65-data-delivery
```

目录应为：

```text
E:\workspace-root\data-warehouse-visualized_base\worktrees\issue-65-data-delivery
```

而不是保留 `feat/` 作为目录层级。

## 约束

- 只有首次 bootstrap 才要求 `-Repository` 和 `-Root` 都显式提供；
- `-Root .`、`-Root ..`、`-Root ~\workspace` 或其他相对路径会被拒绝；
- 日常操作不要求用户提供 Worktree 绝对路径，默认路径始终位于已发现 base 的 `worktrees\` 下；
- 创建前检查 branch、已有 Worktree、目标目录和同一 Issue 的活跃 Worktree；
- 真实冲突时请求决策，不自动创建 `issue-65-2`、`issue-65-new` 或 `issue-65-copy`；
- 已有 Main Workspace dirty 时只报告 `STATUS: NEEDS_ATTENTION`，不会 reset、stash、clean 或 checkout 覆盖；
- 已有 `AGENTS.md` 或 `STATUS.md` 时输出 `KEEP`，不会覆盖。
