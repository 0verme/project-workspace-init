# project-workspace-init

一个可复用、跨平台且非破坏性的 Skill，用于初始化 Git Main Workspace 与多 Agent Worktree Control Plane。

## 为什么存在

多 Agent 并行开发时，正式 Git 主工作区、任务 Worktree、状态文件和后续集成位置如果没有固定边界，容易出现以下问题：

- 把临时 Worktree 平铺到 Workspace Root，难以识别和清理；
- 在错误的 Repository 或错误的磁盘位置执行 clone、创建目录等操作；
- 用默认分支名、当前目录或操作系统信息猜测用户意图；
- 覆盖已有 `AGENTS.md`、`STATUS.md` 或未提交代码；
- 把 PR 已创建误认为已经合并。

本 Skill 只建立一个清晰的目录边界和控制面，不负责调度业务任务。

## 目录模型

初始化目标如下：

```text
<Workspace Root>/
├─ <repo>/
└─ <repo>_base/
   ├─ AGENTS.md
   ├─ STATUS.md
   ├─ status/
   ├─ integration/
   └─ worktrees/
```

- `<repo>/` 是正式 Git Main Workspace。
- `<repo>_base/` 是 Agent Control Plane，**不是 Git Repository**。
- 未来任务 Worktree 必须位于 `<repo>_base/worktrees/<task>`。
- 不要把临时 Worktree 平铺到 `<Workspace Root>/<repo>-issue-123` 等位置。

## Fail Closed 输入契约

执行任何 Git 或文件系统写操作前，必须显式提供以下两个参数：

1. `Repository`
2. `Workspace Root`

两者都没有默认值。Skill 不会从当前目录、当前 Git remote、操作系统、环境变量、`HOME`、历史记录、相邻目录、`AGENTS.md`、`STATUS.md` 或项目上下文推断任何参数。

支持的 Repository 形式：

```text
https://github.com/owner/repo
https://github.com/owner/repo.git
owner/repo
```

`owner/repo` 明确表示 GitHub Repository。只有 `repo` 这种有歧义的名称会被拒绝。

`Workspace Root` 必须是显式绝对路径：

```text
Windows: E:\workspace-root
POSIX:   /vol5/1000/ai-workspace
```

第一版要求该 Root 已经存在且是目录；脚本不会替用户猜测或创建一个错误的 Root。缺少参数、路径不是绝对路径、Root 不存在或参数格式不明确时，脚本会停止并报告 `NEEDS_INPUT` 或 `NEEDS_ATTENTION`，不执行写操作。缺参时只报告缺失参数，不扫描文件系统、不执行 `git`、不创建目录。

## 使用方式

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

脚本只依赖 Git、PowerShell 或 POSIX `sh` 及基础文件系统能力。运行环境必须能访问 GitHub，且对应平台的 `git` 在 `PATH` 中。

## Main Workspace 行为

- Main Workspace 不存在时，先读取 remote default branch，再 clone 到 `<Workspace Root>/<repo>`，并验证 `origin`、当前 branch、default branch与 clean working tree。
- Main Workspace 已存在时，只检查它是否为 Git Repository、`origin` 是否匹配输入、当前 branch、remote default branch以及 working tree 是否 clean。
- 已有未提交修改时只报告：

  ```text
  STATUS: NEEDS_ATTENTION
  Main Workspace: DIRTY
  ```

  不会 `reset`、`stash`、`clean`、覆盖 checkout、删除目录或自动提交。
- 不假定默认分支叫 `main`。已有 Main Workspace 如果不在 remote default branch，脚本只报告注意事项，不自动切换分支。

## Base Workspace 与幂等性

Base Workspace 缺失时创建；已经存在时保留。`status/`、`integration/`、`worktrees/` 缺失时创建。模板文件只在目标不存在时复制：

- 已有 `<repo>_base/AGENTS.md`：`KEEP`；
- 已有 `<repo>_base/STATUS.md`：`KEEP`。

重复执行不会重新 clone 已有 Repository，不会覆盖模板，不会破坏 Base 或用户代码。输出使用 `CREATED`、`EXISTS`、`KEEP`、`WARNING`、`NEEDS_INPUT`、`NEEDS_ATTENTION` 等明确状态。

## 跨机器安全边界

Main Repository 与它的 linked Worktree 必须位于同一运行环境和同一文件系统侧：

- Windows Main → Windows local Worktrees；
- Linux / FNOS Main → Linux / FNOS local Worktrees。

不要设计 Windows Git Main → NAS SMB/NFS linked Worktree，或 NAS Git Main → Windows linked Worktree。Windows 与 NAS 如需维护同一个 GitHub 项目，应各自 clone，再通过 Git remote 同步；不要跨机器共享 Git linked-worktree metadata。

## Legacy Worktree 检查

在两个参数都明确且 Main Workspace 可验证后，脚本会执行 `git worktree list`，并检查 Workspace Root 下类似 `<repo>-issue-*`、`<repo>-feature-*`、`<repo>-*` 的历史平铺目录。

发现时只报告：

```text
LEGACY WORKTREES DETECTED
```

并列出候选路径。不会移动、删除、repair 或自动 prune 有效 Worktree。

## Linux / FNOS 权限

Shell 脚本会先检查 Root 是否存在、是否为目录以及当前用户是否具备读取、进入和写入所需的权限。权限不足时只报告当前用户、目标目录和权限问题，不执行 `sudo`、`su`、`chmod -R 777`、`chown -R` 或 ACL 重置。

## 当前明确不负责什么

第一版不实现：

- Issue 自动调度；
- 自动创建业务任务；
- Task Worktree 生命周期管理；
- Conflict-aware Scheduler；
- Merge Train；
- Merge Coordinator；
- 自动 Merge PR；
- Web UI；
- 数据库。

## 验证重点

实现验证覆盖以下边界：缺少 `Repository`、缺少 `Workspace Root`、相对路径拒绝、全新目录初始化、重复执行、已有模板保护、Dirty Main Workspace、Linux / FNOS 无写权限以及历史平铺 Worktree 只报告不迁移。

## License

本项目采用 MIT License，详见 [`LICENSE`](LICENSE)。
