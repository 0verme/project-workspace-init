# project-workspace-init

一个仅用于首次初始化的 Pi Skill：将 Git Main Workspace 与 Agent Control Plane 安全地 bootstrap 到用户明确指定的位置。初始化完成后，本 Skill 不参与后续项目操作。

## 职责边界

仅用于用户明确要求初始化 workspace，或系统正在为尚未初始化的项目执行首次 bootstrap。**不用于**功能开发、Bug 修复、Issue / PR、文档、测试、发布、branch / task worktree 管理、项目发现或其他日常操作。

bootstrap 需要用户明确提供：

```text
Repository: <GitHub URL or owner/repo>
Workspace Root: <explicit absolute path>
```

支持 `https://github.com/owner/repo`、`https://github.com/owner/repo.git` 和 `owner/repo`。拒绝有歧义的裸 repo 名及非绝对路径。

目标完整初始化后，脚本返回 `STATUS: ALREADY_INITIALIZED` 和 Repository、Main Workspace、Control Plane 路径，然后立即退出，不执行写入或其他操作。

## 安装

### Linux / FNOS / NAS

```sh
mkdir -p ~/.pi/agent/skills

git clone https://github.com/0verme/project-workspace-init.git \
  ~/.pi/agent/skills/project-workspace-init

chmod +x ~/.pi/agent/skills/project-workspace-init/scripts/init-workspace.sh
```

### Windows

将此 Skill 安装到实际运行 Pi 的用户目录：`~/.pi/agent/skills/project-workspace-init`。初始化脚本使用 Windows PowerShell 5.1 或更新版本。

安装后重新启动 Pi 会话。用户明确要求首次初始化时使用 `/skill:project-workspace-init`。

## Bootstrap

### Windows PowerShell

```powershell
.\scripts\init-workspace.ps1 `
  -Repository https://github.com/owner/repo.git `
  -Root E:\workspace-root
```

### Linux / FNOS

```sh
./scripts/init-workspace.sh \
  --repository https://github.com/owner/repo.git \
  --root /vol5/1000/ai-workspace
```

Workspace Root 必须是现存、可访问的绝对路径。脚本区分三种远程状态：

- `REPOSITORY_NOT_FOUND`：无法确认仓库，停止且不创建目标目录；
- `EMPTY_REPOSITORY`：本地使用 `git init -b main` 并配置 `origin`，不创建 commit、README 或 push；
- `EXISTING_REPOSITORY`：读取真实 remote default branch 后 clone，并验证 `origin`、branch 和 clean state。

创建的目录结构：

```text
<Workspace Root>/
├── <repo>/
└── <repo>_base/
    ├── AGENTS.md
    ├── STATUS.md
    ├── status/
    ├── integration/
    └── worktrees/
```

`AGENTS.md` 和 `STATUS.md` 已存在时保留原文件。STATUS 模板只记录初始化级信息。Bootstrap 不重写已有 `.gitignore`，也不根据目录名擅自改变源码或构建产物的 Git 跟踪策略。脚本不执行 `reset`、`clean`、`stash`、自动 commit 或 push。

## 验证

POSIX bootstrap 测试使用 fake Git 远程探测，不会访问或修改 GitHub：

```sh
sh tests/test-init-workspace.sh
```

测试覆盖输入校验、远程状态、现存与空仓库 bootstrap、冲突保护、幂等 terminal result 和无写入行为。

## License

MIT，详见 [`LICENSE`](LICENSE)。
