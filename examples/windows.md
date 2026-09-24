# Windows 示例

以下命令仅用于首次 bootstrap。`E:\workspace-root` 必须由用户明确提供，且为已存在的绝对路径。

```powershell
.\scripts\init-workspace.ps1 `
  -Repository https://github.com/0verme/data-warehouse-visualized.git `
  -Root E:\workspace-root
```

也支持明确的 `owner/repo`：

```powershell
.\scripts\init-workspace.ps1 `
  -Repository 0verme/data-warehouse-visualized `
  -Root E:\workspace-root
```

成功后目录为：

```text
E:\workspace-root\
├── data-warehouse-visualized\
└── data-warehouse-visualized_base\
    ├── AGENTS.md
    ├── STATUS.md
    ├── status\
    ├── integration\
    └── worktrees\
```

空远程仓库会在本地初始化 `main` 并设置 `origin`，不创建 commit、README 或 push。完整结构再次初始化时返回 `ALREADY_INITIALIZED`，报告 Repository、Main Workspace 和 Control Plane 后退出。

Root 缺失、无效或不可访问时停止；不会推测路径。已有模板不会被覆盖。
