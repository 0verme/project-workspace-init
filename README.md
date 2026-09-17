# project-workspace-init

一个可复用、跨平台且非破坏性的 Skill，用于：

- 首次 bootstrap Git Main Workspace 与 Agent Control Plane；
- 在初始化完成后自动发现项目 Workspace；
- 自动生成并安全创建 / 复用日常任务 Worktree。

## 核心行为：两个阶段，不重复索要路径

本 Skill 严格区分两个阶段：

### 1. 首次 bootstrap / init

只有找不到完整 initialized base 时才进入 bootstrap。此时必须由用户显式提供：

```text
Repository: <GitHub URL or owner/repo>
Workspace Root: <explicit absolute path>
```

此阶段不猜测当前目录、当前 Git Repository、当前 remote、环境变量、历史记录或其他项目。缺少任一值时返回 `STATUS: NEEDS_INPUT`，不执行 clone、创建目录或其他写操作。

### 2. 初始化完成后的日常 Worktree 操作

每次调用时先做只读探测：从当前目录开始逐级检查当前目录及父目录是否包含：

```text
AGENTS.md
STATUS.md
worktrees/
```

同时满足这三个条件的目录就是 initialized base。它会被自动识别为日常操作的 `Workspace Root`：

```text
<Workspace Root>/worktrees/<worktree-name>
```

因此，用户只说“处理 #65”“开一个 Worktree”或“开分支”时：

- 不再要求 `Workspace Root`；
- 不再要求 Worktree 绝对路径；
- 不重新触发 bootstrap；
- 优先从 `STATUS.md`、`AGENTS.md`、已有配置和 Git remote 解析 Repository；
- 只有 Repository 确实无法识别、名称无法生成或存在真实冲突时才询问。

这里的两个名称含义需要区分：bootstrap 命令的 `Workspace Root` 是 `<repo>/` 与 `<repo>_base/` 的共同父目录；初始化成功后，日常规则中的 `Workspace Root` 是已经发现的 `<repo>_base/`。

## 安装到 Pi

### Linux / FNOS / NAS

在实际运行 Pi 的用户环境中执行：

```sh
mkdir -p ~/.pi/agent/skills

git clone https://github.com/0verme/project-workspace-init.git \
  ~/.pi/agent/skills/project-workspace-init

chmod +x ~/.pi/agent/skills/project-workspace-init/scripts/init-workspace.sh
```

安装完成后重新启动 Pi 会话，然后在 Pi 中使用：

```text
/skill:project-workspace-init
```

### 已安装后的更新

```sh
cd ~/.pi/agent/skills/project-workspace-init
git pull --ff-only
```

### Pi 用户与 `HOME`

Skill 必须安装到**实际运行 Pi 的用户**对应的目录：

```text
~/.pi/agent/skills/
```

如果 Pi 通过 Pi Web、systemd、Docker 或其他用户运行，SSH 登录用户的 `HOME` 可能不是 Pi 实际读取的 `HOME`。应在对应的运行环境中先检查：

```sh
whoami
echo "$HOME"
```

## Initialized base 识别规则

只读探测允许在没有 bootstrap 参数时执行，但不能把探测结果当成首次 bootstrap 的默认参数。

探测顺序：

1. 检查当前目录本身；
2. 逐级检查父目录本身；
3. 对当前目录及每个父目录，可检查其直接子目录中的候选 base；优先选择与当前 Git remote / 元数据明确对应的候选，只有唯一候选时才按唯一候选处理；不得递归扫描无关项目。

完整 base 必须有普通文件 `AGENTS.md`、普通文件 `STATUS.md` 和目录 `worktrees/`。最近且能被 `STATUS.md`、已有元数据或 Git remote 验证的候选优先；多个候选无法区分时才返回 `NEEDS_INPUT`。

找到 base 后，日常 Repository 解析优先级为：

1. base 中 `STATUS.md`、`AGENTS.md` 或项目配置的真实 `Repository` 字段；
2. 当前目录或当前 Worktree 的 `origin`；
3. `STATUS.md` 记录的 Main Workspace，或对应 Main Workspace 的 `origin`；
4. 现有 Worktree / Git 元数据。

模板占位值（如 `<owner>/<repo>`）不算可靠信息。只有所有来源一致或已由 Git remote 验证，才自动继续；没有可靠来源时只询问 Repository。

## Bootstrap 输入契约（仅首次初始化）

首次 bootstrap 使用：

```text
Repository: <GitHub URL or owner/repo>
Workspace Root: <explicit absolute path>
```

支持的 Repository 形式：

```text
https://github.com/owner/repo
https://github.com/owner/repo.git
owner/repo
```

裸 `<repo>` 有歧义，会被拒绝。Workspace Root 必须是显式绝对路径：

```text
Windows: E:\workspace-root
POSIX:   /vol5/1000/ai-workspace
```

第一版要求该 bootstrap Root 已经存在且是目录；脚本不会替用户猜测或创建错误的位置。相对路径、缺参、路径不可用或 Repository 格式不明确时，bootstrap 停止并报告 `NEEDS_INPUT` 或 `NEEDS_ATTENTION`。

**重要：**初始化完成后不要再次调用 bootstrap 脚本来创建任务 Worktree。脚本是 bootstrap-only；日常操作使用本 Skill 的发现、命名、复用和冲突检查规则。

## Bootstrap 目录模型

```text
<Bootstrap Workspace Root>/
├─ <repo>/
└─ <repo>_base/
   ├─ AGENTS.md
   ├─ STATUS.md
   ├─ status/
   ├─ integration/
   └─ worktrees/
```

- `<repo>/` 是正式 Git Main Workspace；
- `<repo>_base/` 是 Agent Control Plane，**不是 Git Repository**；
- bootstrap 完成后 `<repo>_base/` 就是日常规则中的 Workspace Root；
- 任务 Worktree 必须位于 `<repo>_base/worktrees/<task>`，不要平铺到共同父目录。

## 日常 Worktree 自动生成规则

用户要求开 Worktree、处理 Issue、开分支或开始任务时，默认使用：

```text
<Workspace Root>/worktrees/<worktree-name>
```

### branch 生成优先级

1. 用户明确指定 branch：直接使用；
2. Issue 编号：`feat/issue-<number>`；
3. Issue 编号 + 稳定标题语义：`feat/issue-<number>-<short-slug>`；
4. 明确任务描述：`feat/<short-kebab-slug>`；
5. 只有 Worktree 名称：无冲突时使用 `feat/<worktree-name>`；
6. 无法得到稳定、安全名称时才询问。

例如“处理 #65”可以自动生成：

```text
branch:   feat/issue-65
worktree: <Workspace Root>/worktrees/issue-65
```

### Worktree 名称生成优先级

1. 用户明确指定 Worktree 名称；
2. 已明确 branch：去掉常见类型前缀并把 `/` 转为 `-`；
3. Issue：`issue-<number>-<short-slug>`，没有标题时为 `issue-<number>`；
4. 明确任务描述的简短 kebab-case；
5. 只有无法可靠生成时才询问。

例如：

```text
branch:   feat/issue-65-data-delivery
worktree: <Workspace Root>/worktrees/issue-65-data-delivery
```

不生成 `worktrees/feat/issue-65-data-delivery`，也不因为缺少绝对路径而返回 `NEEDS_INPUT`。

### 创建前冲突检查

创建 branch / Worktree 前必须检查：

- branch 是否已存在（本地、远端跟踪 ref 或已有 Worktree）；
- `git worktree list --porcelain` 中是否已有该 branch 或目标路径；
- 目标目录是否已经存在；
- 同一个 Issue 是否已有活跃 Worktree；
- Main 与现有 Worktree 是否可安全操作。

可以复用完全匹配的现有任务。branch 已被其他 Worktree 使用时优先复用已有 Worktree；branch 存在但没有 Worktree 时，可在验证后复用，不要再次用 `-b` 创建同名 branch。真实冲突必须报告并请求用户决定，禁止自动生成 `issue-65-2`、`issue-65-new`、`issue-65-final` 或 `issue-65-copy` 等垃圾名称。

## 哪些情况仍会 NEEDS_INPUT

### 首次 bootstrap

- 未发现完整 initialized base，且缺少 Repository；
- 未发现完整 initialized base，且缺少 Workspace Root；
- Root 不是显式绝对路径；
- Repository 不是可识别的 GitHub URL / `owner/repo`；
- 用户提供的 Repository 与 Root 或现有目标互相矛盾。

### 已初始化后的日常操作

- 多个 base 无法可靠区分；
- Repository 没有可靠来源或来源互相冲突；
- 没有 Worktree 名称、branch、Issue 编号或任务描述，无法稳定生成名称；
- branch、目标目录或同一 Issue 存在真实冲突，需要用户选择复用 / 改名 / 关闭旧任务 / 拆分任务；
- 用户明确提供了越过 Workspace Root 的路径。

以下情况不是日常 `NEEDS_INPUT`：没有提供 Workspace Root、没有提供 Worktree 绝对路径、没有提供 branch 但有 Issue / 任务描述。权限不足、Dirty Main、remote 不一致、Git 不可用或目录类型错误应报告 `NEEDS_ATTENTION`。

## 使用 bootstrap 脚本

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

脚本只在 bootstrap 阶段使用，依赖 Git、PowerShell 或 POSIX `sh` 及基础文件系统能力。运行环境必须能访问 GitHub，且对应平台的 `git` 在 `PATH` 中。

## Main Workspace 与安全边界

- Main Workspace 不存在时，先读取 remote default branch，再 clone 到 `<Bootstrap Workspace Root>/<repo>`；
- Main Workspace 已存在时，只检查 Git top level、`origin`、branch、remote default branch和 working tree；
- Dirty Main 只报告 `STATUS: NEEDS_ATTENTION`，不会 reset、stash、clean、覆盖 checkout 或自动提交；
- 不假定默认分支叫 `main`；已有 Main 不在 remote default branch 时不自动切换；
- Main Repository 与 linked Worktree 必须在同一运行环境和同一文件系统侧；Windows 与 FNOS 如需维护同一 GitHub 项目，应各自 clone，通过 Git remote 同步；
- 不自动删除或移动已有 branch / Worktree，不 force push，不自动 merge。

## Legacy Worktree 检查

bootstrap 在 Main Workspace 可验证后，会检查共同父目录下的历史平铺目录，并只报告：

```text
LEGACY WORKTREES DETECTED
```

不会移动、删除、repair 或自动 prune 有效 Worktree。日常操作只使用发现的 base 下的 `worktrees/`。

## Linux / FNOS 权限

Shell 脚本会检查 Root 是否存在、是否为目录以及当前用户是否具备读取、进入和写入权限。权限不足时只报告用户、目标和权限问题，不执行 `sudo`、`su`、递归 `777`、递归 `chown` 或 ACL 重置。

## 当前不负责的内容

本 Skill 不实现自动 Merge PR、Merge Train、Merge Coordinator、跨机器 linked-worktree metadata 同步、Web UI 或数据库；也不会在没有用户授权时自动删除冲突对象或合并分支。

## 验证重点

验证应覆盖：

- 首次 bootstrap 缺少 Repository / Workspace Root 时只返回 `NEEDS_INPUT`；
- 已有 `AGENTS.md`、`STATUS.md`、`worktrees/` 时自动识别 base，不再次索要 Workspace Root；
- `处理 #65` 自动生成 branch 与 Worktree；
- 从 `feat/issue-65-data-delivery` 生成 `issue-65-data-delivery` 而非嵌套 `feat/` 目录；
- 已有 branch、目标目录或同 Issue Worktree 时报告冲突，不创建 `-2` / `-new` / `-copy`；
- 模板保护、Dirty Main、权限不足和历史平铺 Worktree 只报告不破坏。

## License

本项目采用 MIT License，详见 [`LICENSE`](LICENSE)。
