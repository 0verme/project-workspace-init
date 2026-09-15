# Windows 示例

以下示例使用占位路径。`E:\workspace-root` 只是显式输入示例，不是 Skill 默认路径；Skill 没有默认 Repository 或 Workspace Root。

## 初始化

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

## 约束

- `-Repository` 和 `-Root` 都必须显式提供。
- `-Root .`、`-Root ..`、`-Root ~\workspace` 或其他相对路径会被拒绝。
- 已有 Main Workspace dirty 时只报告 `STATUS: NEEDS_ATTENTION`，不会 reset、stash、clean 或 checkout 覆盖。
- 已有 `AGENTS.md` 或 `STATUS.md` 时输出 `KEEP`，不会覆盖。
- 任务 Worktree 应位于 `E:\workspace-root\data-warehouse-visualized_base\worktrees\<task>`，不应位于 Workspace Root 平铺位置。
