# Linux / FNOS 示例

以下命令仅用于首次 bootstrap。`/vol5/1000/ai-workspace` 必须由用户明确提供，且为已存在的绝对路径。

```sh
./scripts/init-workspace.sh \
  --repository https://github.com/0verme/data-warehouse-visualized.git \
  --root /vol5/1000/ai-workspace
```

也支持明确的 `owner/repo`：

```sh
./scripts/init-workspace.sh \
  --repository 0verme/data-warehouse-visualized \
  --root /vol5/1000/ai-workspace
```

成功后目录为：

```text
/vol5/1000/ai-workspace/
├── data-warehouse-visualized/
└── data-warehouse-visualized_base/
    ├── AGENTS.md
    ├── STATUS.md
    ├── status/
    ├── integration/
    └── worktrees/
```

对空远程仓库，脚本在本地初始化 `main` 并设置 `origin`，不创建 commit、README 或 push。完整结构再次初始化时返回 `ALREADY_INITIALIZED`，报告 Repository、Main Workspace 和 Control Plane 后退出。

Root 缺失、无效或不可访问时停止；不会推测路径。已有模板不会被覆盖。
