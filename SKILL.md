---
name: project-workspace-init
description: Safely bootstrap Git main workspaces and manage initialized-project worktrees without repeatedly requesting paths.
license: MIT
metadata:
  version: "1.1.2"
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

### Resolved Workspace Context（一次解析并锁定）

找到完整 base 后，立即建立本次任务唯一的 `Resolved Workspace Context`。它至少包含：

```text
Repository
Main Workspace
Control Plane Root
Worktree Root
Default Branch
Current Task
Target Branch
Canonical Worktree Path
Existing Worktree Path (if any)
```

其中根目录字段必须在确认 initialized base 后一次锁定：

```text
CONTROL_PLANE_ROOT = detected initialized base
WORKTREE_ROOT     = CONTROL_PLANE_ROOT/worktrees
```

`Control Plane Root` 就是被确认同时包含普通文件 `AGENTS.md`、普通文件 `STATUS.md` 和目录 `worktrees/` 的 initialized base。后续不得根据 repo 名、当前路径、parent、remote 或 `_base` 重新拼接 Workspace Root。`Control Plane Root` 与 `Worktree Root` 一旦验证成功，在本次任务后续生命周期中不可重新计算或漂移。若后续信息与已锁定的根目录冲突，返回 `STATUS: NEEDS_ATTENTION`，不得静默切换到另一个 Workspace。

例如已锁定：

```text
CONTROL_PLANE_ROOT = /vol5/1000/ai-workspace/dbx-plugin-SchemaSeed_base
WORKTREE_ROOT       = /vol5/1000/ai-workspace/dbx-plugin-SchemaSeed_base/worktrees
```

后续不得生成 `dbx-plugin-SchemaSeed_base_base`，也不得退回共同父目录重新推导 `_base`。后续步骤只填充或校验 context 中尚未解析的 Repository、Main、branch 和任务字段；不得覆盖已锁定的根目录。

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

## Source Code and Generated Artifacts

核心原则：源代码目录看职责，生成目录看仓库既有约定，不得仅根据目录名一刀切。

### Source Code

- 不得仅根据目录名称判断文件是否应该提交。
- `ui/`、`frontend/`、`web/` 等目录如果包含项目正式源码，应正常纳入 Git 管理。
- 不得把 `ui/`、`frontend/`、`web/` 作为通用忽略目录。
- 不得因为 bootstrap 阶段而禁止正常的 UI / frontend 开发。

### Generated Artifacts

- `dist/`、`build/`、`.next/`、`coverage/` 等通常属于生成产物，默认倾向于不提交；这只是默认倾向，不是硬性安全边界。
- 不得机械地将这些目录加入 `.gitignore`。必须优先检查：
  1. 仓库现有 `.gitignore`；
  2. Git 当前是否已经跟踪这些目录（例如 `git ls-files`）；
  3. README、CONTRIBUTING、AGENTS 等现有约定；
  4. CI/CD、GitHub Pages、Release、npm/package 发布方式；
  5. 项目自身的构建与分发模型。
- 如果仓库已经跟踪相关构建产物，或者它们承担部署、分发、Release 等明确职责，不得擅自删除、忽略或停止提交。
- 对于新仓库，如果无法确认是否需要提交生成产物，应采用保守策略，不要替用户做不可逆的结构性决定。

### UI Initialization

- 初始化阶段不要在没有需求的情况下擅自引入 React、Vue、Vite、Next.js 等新的 UI 技术栈。
- 这不是“禁止 UI 开发”。如果项目本身就是 Web / UI 项目、仓库已经存在 UI 技术栈、用户明确要求开发 UI，或当前任务涉及 UI，则应正常进行 UI 开发。

### Bootstrap 与 `.gitignore`

- bootstrap 脚本只负责 Main Workspace 与 Agent Control Plane 的安全初始化，不重写已有仓库的 `.gitignore`。
- 脚本不得通用追加 `ui/`、`frontend/`、`web/`、`dist/` 或 `build/`，也不得运行 `git rm -r --cached ...` 来替项目改变跟踪状态。
- 空仓库没有技术栈和发布模型证据时，bootstrap 不擅自生成针对生成产物的忽略规则；后续可在技术栈明确后添加项目匹配的最小 `.gitignore`，但不得包含会误伤正式源码目录的通用规则。

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

当用户要求“开 Worktree”“处理 Issue”“开分支”或“开始任务”时，按以下固定顺序推进：

1. `Detect initialized base`：只读探测完整 initialized base；
2. `Lock CONTROL_PLANE_ROOT`：锁定 `CONTROL_PLANE_ROOT` 与 `WORKTREE_ROOT`，后续不得重新拼接；
3. `Resolve Repository`：从可靠元数据和 Git remote 解析并校验 Repository；
4. `Resolve Main Workspace`：定位并校验 Main Workspace、权限和 working tree；
5. `Resolve target branch`：按任务信息确定目标 branch；
6. `Resolve canonical worktree path`：用锁定的 `WORKTREE_ROOT` 和 worktree name 生成 canonical path；
7. 在写入前读取 `git worktree list --porcelain`；
8. 先按目标 branch 匹配真实 Git Worktree 绑定；
9. 没有 branch 绑定时，再按 canonical path 匹配；
10. 将结果分类为 `REUSED`、`STALE_WORKTREE_METADATA`、`SAFE_TEMP_RESIDUE` 或 `REAL_CONFLICT`；
11. 只有分类完成后，才决定 `reuse`、`prune`、`create` 或停止并报告。

branch 的真实 Git 绑定优先于重新计算出来的 canonical path。不得因为已有健康 Worktree 的路径较旧或不够漂亮，就移动、重命名或阻断任务。

### 5.1 先定位 Main 与 Worktree 根目录

- 使用已锁定 context 中的 `CONTROL_PLANE_ROOT`，不要再次执行 base 发现或路径拼接；
- 使用 `WORKTREE_ROOT = CONTROL_PLANE_ROOT/worktrees`，日常文档中的 `Workspace Root` 指向这个已发现的 Control Plane；
- 从 `STATUS.md`、已记录配置或对应 Git remote 定位 Main Workspace；
- 在写入前检查 Main 的 Repository、branch、权限和 working tree；
- 新建 Worktree 的 canonical path 固定为：

```text
<CONTROL_PLANE_ROOT>/worktrees/<worktree-name>
```

用户没有提供 Worktree 绝对路径不是 `NEEDS_INPUT` 的理由。用户明确给出的路径只有在位于已锁定 `CONTROL_PLANE_ROOT` 下且通过冲突检查时才可使用；否则报告路径边界冲突。

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

branch:   feat/issue-4-host-api-contract
canonical: <CONTROL_PLANE_ROOT>/worktrees/issue-4-host-api-contract
```

不得默认生成 `feat-issue-65-data-delivery`；branch 中的 `/` 不得成为目录层级。

### 5.4 创建前判定与安全恢复

创建 branch 或 Worktree **之前**，严格按本节顺序检查：

- `git worktree list --porcelain` 是否可读；不可读时返回 `STATUS: NEEDS_ATTENTION`，不得猜测或 prune；
- branch 是否已存在（本地 ref、远端跟踪 ref 或已有 Worktree）；
- canonical 目标目录是否已存在，即使它尚未被 Git 管理；
- `STATUS.md`、任务元数据和现有 branch / Worktree 中，同一个 Issue / Task 是否已有活跃 Worktree；
- Main 与候选 Worktree 是否位于同一运行环境和文件系统侧，且身份可以可靠匹配。

始终先匹配 branch，再匹配 path。以下分类是唯一允许的自动决策入口：

| 分类 | 必须证明的状态 | 允许的动作 |
| --- | --- | --- |
| `REUSED` | branch/path 匹配，或目标 branch 已绑定另一个健康 Worktree；Git metadata 正常 | 直接复用并报告实际路径，不重新创建、不 STOP |
| `STALE_WORKTREE_METADATA` | `git worktree list --porcelain` 有记录，但物理目录已明确不存在、没有 lock，且可排除权限/挂载异常 | 在当前仓库执行安全 `git worktree prune`，重新读取状态后按 canonical path 创建 |
| `SAFE_TEMP_RESIDUE` | canonical 目录不是 Worktree / Repository，目录为空，且能证明由本轮当前操作创建 | 只删除这个已证明为空的临时目录，重新检查后继续 |
| `REAL_CONFLICT` | 真实 Worktree、Repository、未知用户数据或任务身份冲突，无法安全自动判断 | 不删除、不移动、不覆盖，按冲突类型返回 `NEEDS_INPUT` 或 `NEEDS_ATTENTION` |

#### CASE A：canonical Worktree 已存在且完全匹配

如果 branch 匹配、path 匹配且 Git Worktree metadata 正常：

```text
State: REUSED
```

直接复用，不重新创建，不 STOP。

#### CASE B：目标 branch 已绑定另一个健康 Worktree

如果目标 branch 已绑定 `git worktree list --porcelain` 中的另一个路径，并且该路径真实存在、Git 状态正常、branch 正确且没有身份冲突：

```text
State: REUSED
```

继续使用已有的实际路径。branch 的真实绑定优先于 canonical path；不得因为路径不符合最新命名规范而 STOP、移动或自动重命名。canonical path 只约束新建 Worktree，已有健康 Worktree 的 Git 绑定优先。

#### CASE C：Git metadata 存在但物理目录不存在

只有同时确认以下事实时才判定为 `STALE_WORKTREE_METADATA`：

- 只读读取了 `git worktree list --porcelain`；
- 对应物理目录确实不存在；
- 能访问其父目录，并能排除权限不足、网络挂载异常或暂时不可访问；
- 该 Worktree 没有 `lock`，也没有必须保留的锁定意图。

确认后允许在正确的 Main Workspace 上执行：

```bash
git worktree prune
```

再次读取 `git worktree list --porcelain`。stale metadata 已清理后，才允许按 canonical path 重新建立 Worktree。不能证明 stale 时不得 prune，并返回 `STATUS: NEEDS_ATTENTION`。

#### CASE D：canonical 目录存在但不是有效 Worktree

- **D1 `SAFE_TEMP_RESIDUE`**：目录为空，已确认不是 Git Worktree、不是 Git Repository，并且能证明由本轮当前操作创建。只允许删除该目录本身（优先使用等价于 `rmdir` 的空目录删除），然后重试；不得使用 `rm -rf`。
- **D2 `REAL_CONFLICT`**：目录包含任何未知文件（即未知非空目录），或即使为空也无法证明归属本轮操作。返回 `NEEDS_INPUT`，报告真实路径和冲突，不得删除、`git clean`、自动改名成 `-2`、`-new` 或 `-final`。
- 如果目录存在但无法可靠读取、无法确认是否为空或无法判断是否为 Repository，则返回 `NEEDS_ATTENTION`，不得当作安全残留。

#### CASE E：健康 Worktree 有未提交修改

已有 Worktree 只要物理目录、Git metadata、branch 和身份都正常，即使存在 staged changes、unstaged changes 或 untracked user files，仍按 `REUSED` 处理并明确报告 `DIRTY`。

不得 prune、删除、移动、覆盖、reset、clean 或重建。如果该 Worktree 对应本任务且任务安全边界允许，可继续复用；若身份冲突，或必须迁移/删除才能继续，则返回 `NEEDS_INPUT`。

#### CASE F：路径只是旧规范

旧版本生成的路径（例如 `worktrees/issue-4`）只要 branch 正确、Git metadata 正常、对应同一 Issue / Task 且无身份冲突，就必须复用：

```text
REUSE existing healthy worktree
```

canonical path 主要约束新建 Worktree，不为了路径规范化迁移健康旧 Worktree。

#### locked / inaccessible Worktree

Worktree 被 `lock`、路径暂时不可访问、权限不足、网络挂载异常，或无法证明物理目录确实不存在时，都不能判定为 stale。返回 `STATUS: NEEDS_ATTENTION`，说明无法确认的原因；不得 prune、删除或移动。

冲突检查未通过时不得产生部分 branch、空目录或半初始化 Worktree。创建或复用成功后更新 `STATUS.md` 的 Issue / Task、Branch、Worktree、State、Conflict Risk、PR 和 Notes。

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
- `REAL_CONFLICT` 中存在真实用户数据、Repository、任务身份冲突，或必须迁移/删除才能继续，需要用户决定复用、改名、关闭旧任务或拆分任务；
- 用户明确给出的 Worktree 路径越过已锁定的 `CONTROL_PLANE_ROOT`，且没有其他可接受路径。

健康 Worktree 的旧路径、branch 已绑定的非 canonical 路径、stale metadata，以及已证明由本轮创建且为空的安全临时残留，都不是 `NEEDS_INPUT` 的理由。

以下情况**不是**日常 `NEEDS_INPUT`：

- 用户没有提供 Workspace Root；
- 用户没有提供 Worktree 绝对路径；
- 用户没有提供 branch，但有 Issue 或明确任务描述；
- 用户没有提供 branch 名称，但有明确 Worktree 名称。

权限不足、Main dirty、remote 不一致、Git 不可用、目录类型错误、`git worktree list --porcelain` 失败、locked / inaccessible Worktree 或无法证明目录确实不存在时，应返回 `STATUS: NEEDS_ATTENTION`，而不是反复索要 Workspace Root；远程已确认存在但为空不属于这些异常。

## 7. 安全边界与状态

- Main Repository 与 linked Worktree 必须位于同一运行环境和同一文件系统侧；
- 不跨 Windows / Linux / FNOS 共享 linked-worktree metadata；
- 禁止删除、移动或覆盖仍真实存在并可能承载用户工作的健康 Worktree；
- 以下操作属于允许的安全恢复，不视为破坏性 Worktree 操作：
  1. 复用已绑定目标 branch 的健康 Worktree；
  2. 对物理目录已确认不存在的 stale worktree metadata 执行 `git worktree prune`；
  3. 清理由本轮当前操作创建、已确认为空、且不属于 Git Worktree / Git Repository 的临时目录；
  4. 已有健康 Worktree 路径不符合最新命名规范时继续复用，不为了路径规范化迁移或阻断任务。
- 除上述可证明安全的恢复外，不自动执行 `git reset --hard`、`git clean`、force push、删除 branch、自动 stash、自动 commit 或自动 push；
- Dirty Main 或冲突只报告事实、路径和下一步，不以破坏数据换取“干净”；
- `READY` 不等于 `MERGED`，创建 PR 也不等于已合并；
- 使用 `CREATED`、`EXISTS`、`KEEP`、`REUSED`、`WARNING`、`NEEDS_INPUT`、`NEEDS_ATTENTION` 等可行动状态。

`STATUS.md` 是当前状态快照，不是长日志。状态、Worktree、冲突风险、PR、集成基线、阻塞项或下一步改变时才更新。

## 8. 明确不负责的内容

本 Skill 不实现自动 Merge PR、Merge Train、Merge Coordinator、跨机器 linked-worktree 同步、Web UI 或数据库。它负责 bootstrap 判定、已初始化 Workspace 发现，以及日常任务 Worktree 的安全命名、复用与冲突检查；不把 Issue 调度扩展成无需用户授权的自动化合并流程，也不删除无法证明安全的冲突对象。

所有文本文件（包括 Markdown、JSON、YAML、PowerShell 和 Shell）必须保持 UTF-8。修改中文后检查 diff；出现 replacement character、连续问号占位符或其他乱码时停止并修复。
