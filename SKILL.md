---
name: project-workspace-init
description: Safely bootstrap Git main workspaces and manage initialized-project worktrees without repeatedly requesting paths.
license: MIT
metadata:
  version: "1.1.1"
  platforms: "Windows, Linux, FNOS"
---

# Project Workspace Init

本 Skill 有两个严格分开的阶段：

1. **项目级 bootstrap / init**：只负责首次建立 Main Workspace 与 Agent Control Plane。
2. **初始化完成后的日常操作**：负责在已有 Control Plane 下定位项目、生成 branch 与 Worktree 名称，并创建或复用任务 Worktree。

不能因为日常操作缺少初始化时的参数，就重新进入 bootstrap。尤其不能在已经识别出 `<repo>_base/` 后再次要求用户提供 `Workspace Root` 或 Worktree 绝对路径。

为消除旧版本中“Workspace Root”名称的歧义：

- **bootstrap 输入的 Workspace Root** 是用户首次明确提供的绝对路径。它是 `<repo>/` 与 `<repo>_base/` 的共同父目录。
- **初始化完成后的 Workspace Root** 是自动发现的 base / Control Plane 目录，即 `<repo>_base/`。日常 Worktree 默认放在 `<Workspace Root>/worktrees/<worktree-name>`。

## 1. 先判定阶段，再检查输入

每次调用 Skill，第一步必须是只读的 initialized-workspace 探测，而不是先检查 `Repository` / `Workspace Root` 参数。

一个目录只有同时满足以下条件才是已初始化的 base：

- `AGENTS.md` 是普通文件；
- `STATUS.md` 是普通文件；
- `worktrees/` 是目录。

探测顺序：

1. 从当前目录开始，检查当前目录本身；
2. 逐级检查每个父目录本身；
3. 对当前目录及每个父目录，可以检查其直接子目录中的候选 base；优先选择与当前 Git remote / 元数据明确对应的候选，只有唯一候选时才按唯一候选处理；不得递归扫描无关目录。

选择规则：

- 优先选择离当前目录最近的完整 base；
- 多个候选只有在 `STATUS.md`、已有项目配置或 Git remote 能可靠指向同一个项目时才可自动选择；
- 候选互相冲突且无法可靠区分时，报告冲突并询问用户，不得猜测。

### 找到完整 base：进入日常模式

找到完整 base 后：

- 自动将该 base 目录识别为日常操作的 `Workspace Root`；
- 不再要求用户提供 `Workspace Root`；
- 不重新调用 bootstrap，不 clone，不重建目录，不覆盖模板；
- 不要求用户提供 Worktree 绝对路径；
- 先从已有信息解析 `Repository`，只有确实无法可靠识别时才询问 Repository。

这次只读探测是唯一允许在缺少 bootstrap 参数时进行的文件系统检查。它不等于从当前目录猜测首次初始化参数。

### 没找到完整 base：进入 bootstrap 模式

只有未找到完整 base 时，才执行下面的 bootstrap 输入契约。此时不得把当前目录、当前 Git Repository、当前 remote、环境变量、历史命令、相邻目录、`AGENTS.md`、`STATUS.md` 或其他上下文当作默认输入。

## 2. Bootstrap 输入契约（仅首次初始化）

首次 bootstrap 必须显式获得以下两个值：

```text
Repository: <GitHub URL or owner/repo>
Workspace Root: <explicit absolute path>
```

任一缺失时：

```text
STATUS: NEEDS_INPUT
```

并且只列出缺失的值。此阶段禁止：

- 猜测默认路径；
- 默认使用当前目录；
- 默认使用当前 Git Repository；
- 默认使用当前 Git remote；
- 自行选择其他 Repository；
- 因缺参而扫描、clone、创建目录或执行其他写操作。

`Workspace Root` 必须是用户明确提供的绝对路径。相对路径、`~`、`.`、`..` 或无法访问的路径不能被静默改写。

支持的 `Repository` 形式：

- `https://github.com/<owner>/<repo>`；
- `https://github.com/<owner>/<repo>.git`；
- `<owner>/<repo>`，明确解释为 GitHub Repository。

裸 `<repo>` 有歧义，必须拒绝。

仅在 bootstrap 模式调用本 Skill 包中的初始化脚本：

Windows：

```powershell
.\scripts\init-workspace.ps1 -Repository <repository> -Root <absolute-path>
```

Linux / FNOS：

```sh
./scripts/init-workspace.sh --repository <repository> --root <absolute-path>
```

这些脚本是 **bootstrap-only**。初始化完成后，日常 Worktree 操作不得为了获得路径而再次调用它们。

## 3. Bootstrap 结果与目录边界

成功的 bootstrap 产生以下结构：

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
- `<repo>_base/` 是非 Git 的 Agent Control Plane；
- bootstrap 完成后，`<repo>_base/` 就是日常规则中的 `Workspace Root`；
- 所有任务 Worktree 默认属于 `<repo>_base/worktrees/`，不得平铺到共同父目录。

Bootstrap 必须先探测远程状态，再选择对应路径。远程状态至少分为：

```text
REPOSITORY_NOT_FOUND
EMPTY_REPOSITORY
EXISTING_REPOSITORY
```

- `REPOSITORY_NOT_FOUND`：仓库不存在、无权限访问或无法确认存在。停止并返回当前等价的 `NEEDS_INPUT` / `NEEDS_ATTENTION`，不得创建目录。
- `EMPTY_REPOSITORY`：GitHub 仓库已确认存在，但没有 remote branch、没有 default branch。空仓库是合法的首次 bootstrap 场景，不是异常。
- `EXISTING_REPOSITORY`：至少有一个 remote branch / commit，并且可以读取真实 default branch。

### Existing Repository Bootstrap

`EXISTING_REPOSITORY` 必须继续使用正常的 clone / alignment 流程：

1. 读取 remote advertised default branch，不假设名字是 `main`；
2. 将显式 Repository clone 到 `<Bootstrap Workspace Root>/<repo>`（不存在时）；
3. 验证 `origin`、当前 branch、remote default branch 和 clean working tree。

### Empty Repository Bootstrap

`EMPTY_REPOSITORY` 不调用 clone，也不要求远端先创建 `origin/main`。当 `<repo>/` 不存在时：

1. 在 `<Bootstrap Workspace Root>/<repo>` 执行本地 `git init -b main`；
2. 配置 `origin` 为用户明确提供的 Repository；
3. 验证当前 branch 为 `main`、origin 正确且 working tree clean；
4. 不创建 commit、不生成 README、不 push，也不制造 placeholder 文件。

空仓库成功时仍返回项目现有的成功状态 `STATUS: SUCCESS`，并明确报告 `Remote State: EMPTY_REPOSITORY`、`Remote main: not created yet`。本地 `main` 存在而 `origin/main` 尚不存在是正常状态。

### Common Bootstrap Rules

1. 只创建缺失目录与缺失模板，不覆盖已有 `AGENTS.md`、`STATUS.md` 或用户数据；
2. 重复执行时保持幂等，不重新 clone、不删除 branch / Worktree、不 reset、不 stash、不自动提交；
3. Main Workspace 已存在但 dirty、remote 不一致、处于 detached HEAD、权限不足或其他安全条件不满足时，返回 `STATUS: NEEDS_ATTENTION`，不得自行修复；
4. 空仓库中已经存在的 Main Workspace 也必须是目标仓库、`main` branch；origin 不一致时停止，不能擅自修改。

## 4. 已初始化项目的 Repository 解析

进入日常模式后，按以下优先级解析 Repository：

1. base 中 `STATUS.md`、`AGENTS.md`、项目配置或其他已有元数据里的真实 `Repository` 字段；
2. 当前目录或当前 Worktree 的 `origin` remote；
3. `STATUS.md` 记录的 Main Workspace，或与 `<repo>_base` 对应的 Main Workspace 的 `origin`；
4. 已有 Worktree / Git 元数据中明确记录的 Repository。

必须忽略模板占位值，例如 `<owner>/<repo>`、`<absolute-path>` 和空值。只有来源互相一致，或经过 Git remote 验证后，才算“可靠识别”。

- 能可靠识别时，直接继续，不要求用户重复输入 Repository；
- 没有任何可靠来源时，只询问 `Repository`；
- 来源互相冲突时，列出冲突来源并询问用户选择；不得自行选择其他仓库。

日常模式下，`Repository` 可以作为用户主动提供的校验或消歧信息，但不是默认必填项。

## 5. 日常创建 / 复用 Worktree

当用户要求“开 Worktree”“处理 Issue”“开分支”或“开始任务”时，按以下流程推进：

### 5.1 先定位 Main 与 Worktree 根目录

- 使用已发现的 base 目录作为 `Workspace Root`；
- 从 `STATUS.md`、已记录配置或对应 Git remote 定位 Main Workspace；
- 在写入前检查 Main 的 Repository、branch、权限和 working tree；
- Worktree 目标默认固定为：

```text
<Workspace Root>/worktrees/<worktree-name>
```

用户没有提供 Worktree 绝对路径不是 `NEEDS_INPUT` 的理由。用户明确给出的路径只有在位于该 Workspace Root 下且通过冲突检查时才可使用；否则报告路径边界冲突。

### 5.2 生成 branch

按以下优先级决定 branch：

1. 用户明确指定的 branch：直接使用；
2. 只有 Issue 编号：`feat/issue-<number>`；
3. 有 Issue 编号和可靠标题 / 任务语义：`feat/issue-<number>-<short-slug>`；
4. 只有明确任务描述：`feat/<short-kebab-slug>`；
5. 用户只给 Worktree 名称：在没有冲突时使用 `feat/<worktree-name>`；
6. 仍无法形成稳定、非空且安全的名称时才询问用户。

branch 名必须保留 Git 语义并经过安全校验；不得包含空格、控制字符、连续无意义分隔符或非法 ref 片段。已有明确 branch 时不得为了美化而改名。

### 5.3 生成 Worktree 名称

按以下优先级生成 `worktree-name`：

1. 用户明确指定的 Worktree 名称：直接使用；
2. 已明确目标 branch：从 branch 生成安全目录名；
3. 有 GitHub Issue 编号：`issue-<number>-<short-slug>`；没有可靠标题时使用 `issue-<number>`；
4. 有明确任务描述：生成简短 kebab-case 名称；
5. 只有在以上信息都不存在或无法可靠生成时才询问用户。

目录名生成规则：

- 将 branch 的常见类型前缀（如 `feat/`、`fix/`、`chore/`、`refactor/`、`hotfix/`）从目录名中去掉；
- 将剩余 `/` 转为 `-`，清理非法字符，合并重复 `-`，去掉首尾分隔符；
- 保持简洁稳定，不为了“完美命名”反复询问；
- 例如：

```text
branch:   feat/issue-65-data-delivery
worktree: <Workspace Root>/worktrees/issue-65-data-delivery
```

不得默认生成 `feat-issue-65-data-delivery`，也不得把 branch 中的 `/` 原样带入目录层级。

### 5.4 创建前冲突检查

创建 branch 或 Worktree **之前**必须检查：

- branch 是否已存在（本地 ref、远端跟踪 ref 或已有 Worktree）；
- `git worktree list --porcelain` 中是否已有该 branch 或目标路径；
- 目标目录是否已存在，即使它尚未被 Git 管理；
- `STATUS.md`、任务元数据和现有 branch / Worktree 中，同一个 Issue 是否已有活跃 Worktree；
- Main 与现有 Worktree 是否处于可安全操作的状态。

处理规则：

- 目标 branch 与目标路径已经是同一任务的现有 Worktree 时，优先复用并报告现状；
- branch 已存在但被其他 Worktree 使用时，优先复用那个 Worktree，不能再为同一 branch 创建第二个任务目录；
- branch 已存在但尚未关联 Worktree、目标目录不存在时，可以在确认仓库状态后复用该 branch，不要盲目 `-b` 创建同名 branch；
- 目标目录存在但不是预期 Worktree，或同一 Issue 已有不一致的活跃 Worktree 时，报告真实冲突并请求用户决策；
- 冲突时禁止自动制造 `issue-65-2`、`issue-65-new`、`issue-65-final`、`issue-65-copy` 等垃圾 branch / 目录；只有用户明确选择新名称或明确授权拆分任务后才可继续。

冲突检查未通过时不得产生部分 branch、空目录或半初始化 Worktree。创建成功后更新 `STATUS.md` 的 Issue / Task、Branch、Worktree、State、Conflict Risk、PR 和 Notes。

## 6. 哪些情况仍然返回 NEEDS_INPUT

`NEEDS_INPUT` 只表示确实缺少不可安全推断的信息，不能用来索要本可自动生成的路径：

### Bootstrap 模式

- 没有完整 initialized base，且缺少 `Repository`；
- 没有完整 initialized base，且缺少 `Workspace Root`；
- `Workspace Root` 不是明确绝对路径；
- `Repository` 不是可识别的 GitHub URL / `owner/repo`；
- 用户提供的两个值互相矛盾且无法验证。

### 日常模式

- 找到多个无法区分的 initialized base；
- Repository 没有任何可靠来源，或已有来源互相冲突；
- 用户没有提供名称、branch、Issue 编号或任务描述，因而无法稳定生成 Worktree 名称；
- 发生真实 branch / Worktree / 目标目录 / 同一 Issue 冲突，需要用户决定复用、改名、关闭旧任务或拆分任务；
- 用户明确给出的 Worktree 路径越过 Workspace Root，且没有其他可接受路径。

以下情况**不是**日常 `NEEDS_INPUT`：

- 用户没有提供 Workspace Root；
- 用户没有提供 Worktree 绝对路径；
- 用户没有提供 branch，但有 Issue 或明确任务描述；
- 用户没有提供 branch 名称，但有明确 Worktree 名称。

权限不足、Main dirty、remote 不一致、Git 不可用、目录类型错误或脚本 / 网络失败应返回 `STATUS: NEEDS_ATTENTION`，而不是反复索要 Workspace Root；远程已确认存在但为空不属于这些异常。

## 7. 安全边界与状态

- Main Repository 与 linked Worktree 必须位于同一运行环境和同一文件系统侧；
- 不跨 Windows / Linux / FNOS 共享 linked-worktree metadata；
- 不自动执行 `git reset --hard`、`git clean`、force push、删除 branch、删除或移动已有 Worktree、自动 stash、自动 commit 或自动 push；
- Dirty Main 或冲突只报告事实、路径和下一步，不以破坏数据换取“干净”；
- `READY` 不等于 `MERGED`，创建 PR 也不等于已合并；
- 使用 `CREATED`、`EXISTS`、`KEEP`、`REUSED`、`WARNING`、`NEEDS_INPUT`、`NEEDS_ATTENTION` 等可行动状态。

`STATUS.md` 是当前状态快照，不是长日志。状态、Worktree、冲突风险、PR、集成基线、阻塞项或下一步改变时才更新。

## 8. 明确不负责的内容

本 Skill 不实现自动 Merge PR、Merge Train、Merge Coordinator、跨机器 linked-worktree 同步、Web UI 或数据库。它负责 bootstrap 判定、已初始化 Workspace 发现，以及日常任务 Worktree 的安全命名、复用与冲突检查；不把 Issue 调度扩展成无需用户授权的自动化合并流程。

所有文本文件（包括 Markdown、JSON、YAML、PowerShell 和 Shell）必须保持 UTF-8。修改中文后检查 diff；出现 replacement character、连续问号占位符或其他乱码时停止并修复。
