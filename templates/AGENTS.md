# Agent Workspace Rules

> Source template version: `1.1.2`

本文件由 `project-workspace-init` 首次 bootstrap 时复制到 initialized base。它描述项目协作边界；具体项目可以在 **Project-specific Rules** 中追加规则，但不得放宽安全约束。

## 两阶段输入规则

本模板必须区分“首次 bootstrap”和“已初始化后的日常操作”，不能把 bootstrap 的输入要求全局套用到每个任务。

### 首次 bootstrap

只有找不到完整 initialized base 时，才要求用户显式提供：

```text
Repository: <GitHub URL or owner/repo>
Workspace Root: <explicit absolute path>
```

此阶段禁止猜测当前目录、当前 Git Repository、当前 remote、环境变量、历史记录或其他仓库。任一缺失时返回 `STATUS: NEEDS_INPUT`，不得 clone、创建目录或写文件。

### 日常操作

以下三个条件同时成立时，目录就是 initialized base：

- `AGENTS.md` 是普通文件；
- `STATUS.md` 是普通文件；
- `worktrees/` 是目录。

从当前目录开始检查当前目录及父目录，也可检查这些目录的直接子目录中的候选 base；优先选择与当前 Git remote / 元数据明确对应的候选，只有唯一候选时才按唯一候选处理，不得递归扫描无关项目。找到后：

- 自动将该 base 目录识别为日常 `Workspace Root`；
- 默认 Worktree 路径为 `<Workspace Root>/worktrees/<worktree-name>`；
- 不再次要求 Workspace Root；
- 不要求用户提供 Worktree 绝对路径；
- 不重新运行 bootstrap。

日常 Repository 优先从 `STATUS.md`、`AGENTS.md`、项目配置、当前 / Main Workspace 的 `origin` 和已有 Git 元数据解析。模板占位值不算可靠来源；只有无法可靠识别或来源冲突时才询问 Repository。

### Resolved Workspace Context（一次解析并锁定）

发现 initialized base 后，立即建立本次任务的 `Resolved Workspace Context`，至少记录：

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

根目录一次锁定（只解析一次）：

```text
CONTROL_PLANE_ROOT = detected initialized base
WORKTREE_ROOT     = CONTROL_PLANE_ROOT/worktrees
```

验证成功后，后续不得根据 repo 名、当前路径、parent、remote 或 `_base` 重新拼接 Workspace Root。若后续信息与已锁定根目录冲突，返回 `NEEDS_ATTENTION`，不得静默切换。已锁定 `/path/dbx-plugin-SchemaSeed_base` 时不得产生 `/path/dbx-plugin-SchemaSeed_base_base`，也不得回到共同父目录重新推导 `_base`。

## Workspace Layout

```text
<Bootstrap Workspace Root>/
├─ <repo>/
│  └─ Git Main Workspace
└─ <repo>_base/
   ├─ AGENTS.md
   ├─ STATUS.md
   ├─ status/
   ├─ integration/
   └─ worktrees/
```

- `<repo>/` 是正式 Main Workspace；
- `<repo>_base/` 是 Agent Control Plane，不是 Git Repository；
- bootstrap 完成后 `<repo>_base/` 是日常规则中的 Workspace Root；
- 任务 Worktree 只能位于 `<repo>_base/worktrees/<task>`；
- 禁止把任务 Worktree 平铺为 `<Bootstrap Workspace Root>/<repo>-issue-123` 或 `<Bootstrap Workspace Root>/<repo>-feature-name`；
- Main Repository 与 linked Worktree 必须在同一个运行环境和同一文件系统侧，不跨 Windows、Linux、FNOS 共享 linked-worktree metadata。

## Git / Worktree Rules

- bootstrap 阶段才要求 Repository 与 bootstrap Workspace Root 都由用户显式提供；
- 日常 Git / 文件系统写操作先确认已发现 initialized base 和可靠 Repository，不要求重复提供 Workspace Root 或 Worktree 绝对路径；
- 不假定 remote default branch 名为 `main`，先读取并记录真实 default branch；
- 远程状态分为 `REPOSITORY_NOT_FOUND`、`EMPTY_REPOSITORY` 和 `EXISTING_REPOSITORY`；空仓库是合法 bootstrap 场景；
- `EMPTY_REPOSITORY` 使用本地 `main` + `origin` 初始化，不自动创建首个 commit、README、placeholder 或 push；
- 开始任务前确认 Main Workspace 的 `origin`、branch 和 working tree 状态；
- 每个任务使用独立 Worktree 和独立 branch，不要在 Main Workspace 直接开发任务；
- 默认 Worktree 路径为 `<Workspace Root>/worktrees/<worktree-name>`；
- 新建 Worktree 的 canonical path 为 `<CONTROL_PLANE_ROOT>/worktrees/<worktree-name>`；branch 中的 `/` 不得成为目录层级。

### Branch 与 Worktree 自动生成

branch 按以下优先级生成：

1. 用户明确指定 branch；
2. Issue 编号：`feat/issue-<number>`；
3. Issue 编号 + 稳定标题：`feat/issue-<number>-<short-slug>`；
4. 明确任务描述：`feat/<short-kebab-slug>`；
5. 只有 Worktree 名称：无冲突时使用 `feat/<worktree-name>`。

Worktree 名称按以下优先级生成：

1. 用户明确指定 Worktree 名称；
2. 已明确 branch：去掉常见类型前缀并将 `/` 转为 `-`；
3. Issue：`issue-<number>-<short-slug>`，没有标题时为 `issue-<number>`；
4. 明确任务描述的简短 kebab-case；
5. 无法可靠生成时才询问。

例如 `feat/issue-65-data-delivery` 必须生成：

```text
<Workspace Root>/worktrees/issue-65-data-delivery

branch:   feat/issue-4-host-api-contract
canonical: <CONTROL_PLANE_ROOT>/worktrees/issue-4-host-api-contract
```

而不是保留 `feat/` 作为目录层级；branch 中的 `/` 不得成为目录层级。

### 创建前判定与安全恢复

创建 / 复用必须按固定顺序执行：

1. Detect initialized base；
2. 锁定 `CONTROL_PLANE_ROOT` 与 `WORKTREE_ROOT`；
3. 解析 Repository；
4. 解析 Main Workspace；
5. 解析目标 branch；
6. 生成 canonical Worktree path；
7. 读取 `git worktree list --porcelain`；
8. 先匹配 branch，再匹配 canonical path；
9. 分类为 `REUSED`、`STALE_WORKTREE_METADATA`、`SAFE_TEMP_RESIDUE` 或 `REAL_CONFLICT`；
10. 最后才决定复用、prune、新建或停止。

`git worktree list --porcelain` 失败时返回 `NEEDS_ATTENTION`，不得猜测或 prune。

| 分类 | 判定 | 自动动作 |
| --- | --- | --- |
| `REUSED` | canonical 完全匹配，或目标 branch 已绑定另一个健康 Worktree | 复用真实路径，不重新创建、不 STOP |
| `STALE_WORKTREE_METADATA` | metadata 有记录但物理目录已明确不存在，且没有 lock、已排除权限/挂载异常 | 在正确 Main Workspace 执行 `git worktree prune`，复查后按 canonical 创建 |
| `SAFE_TEMP_RESIDUE` | 目录不是 Worktree / Repository，目录为空，并证明由本轮当前操作创建 | 只清理该空目录后重试 |
| `REAL_CONFLICT` | 真实 Worktree、Repository、未知用户数据或任务身份冲突 | 不删除、不移动、不覆盖；按情况 `NEEDS_INPUT` 或 `NEEDS_ATTENTION` |

完全匹配的任务直接 `State: REUSED`。branch 已被其他路径的健康 Worktree 使用时，也必须 `State: REUSED`；branch 的真实绑定优先于 canonical path，以真实 Git branch 绑定为准，不因为旧路径不符合最新 canonical 命名而 STOP、移动或重命名。canonical path 只约束新建 Worktree。

Git metadata 指向不存在的物理目录时，只有能确认目录确实不存在、父目录可访问、没有 `lock` 且不是权限 / 网络挂载异常，才是 `STALE_WORKTREE_METADATA`；否则 `NEEDS_ATTENTION`，不得 prune。

目标目录只有在同时满足“为空、不是 Git Worktree、不是 Git Repository、由本轮当前操作创建”时才是 `SAFE_TEMP_RESIDUE`，只允许删除空目录本身，不得使用 `rm -rf`。未知非空目录或归属无法证明时是 `REAL_CONFLICT`，返回 `NEEDS_INPUT`，不得删除、`git clean` 或自动生成 `-2` / `-new` / `-final`。

健康 Worktree 即使有 staged changes、unstaged changes 或 untracked user files，也保留用户数据并按 `REUSED` 报告 `DIRTY`；不得 prune、删除、移动、覆盖、reset、clean 或重建。只有身份冲突或必须迁移 / 删除才能继续时才 `NEEDS_INPUT`。locked / inaccessible Worktree 或无法证明 stale 时 `NEEDS_ATTENTION`。

旧规范路径（例如 `worktrees/issue-4`）只要 branch、Git metadata 和任务身份正确，就执行 `REUSE existing healthy worktree`。冲突或 dirty 状态未解决前，不产生新的部分 branch 或半初始化 Worktree。

## 安全 Git 规则

- 禁止删除、移动或覆盖仍真实存在且可能承载用户工作的健康 Worktree；
- 以下属于允许的安全恢复，不视为破坏性 Worktree 操作：
  1. 复用已绑定目标 branch 的健康 Worktree；
  2. 对物理目录已确认不存在的 stale worktree metadata 执行 `git worktree prune`；
  3. 清理由本轮当前操作创建、已确认为空、且不属于 Git Worktree / Git Repository 的临时目录；
  4. 健康旧 Worktree 路径不符合最新命名规范时继续复用，不为了路径规范化迁移或阻断任务。
- 除上述可证明安全的恢复外，不自动执行 `git reset --hard`、`git clean -fd`、`git clean -fdx`、force push、删除 branch、自动 stash、自动 commit 或自动 push；
- 已有冲突、未提交修改、remote 不一致或权限问题时先停止并报告，不以破坏数据换取“干净”状态；
- `READY != MERGED`；PR 创建成功不等于已合并；
- 只提交当前任务直接相关的文件，不把其他 Agent 的改动带入提交。

## Source Code and Generated Artifacts

核心原则：源代码目录看职责，生成目录看仓库既有约定，不得仅根据目录名一刀切。

### Source Code

- 不得仅根据目录名称判断文件是否应该提交。
- `ui/`、`frontend/`、`web/` 等目录如果包含项目正式源码，应正常纳入 Git 管理。
- 不得把 `ui/`、`frontend/`、`web/` 作为通用忽略目录。
- 不得因为初始化阶段而禁止正常的 UI / frontend 开发。

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

- bootstrap 不重写已有仓库的 `.gitignore`，不得通用追加 `ui/`、`frontend/`、`web/`、`dist/` 或 `build/`。
- 不运行 `git rm -r --cached ...` 来替项目改变跟踪状态；已有跟踪内容和项目发布模型必须保留。
- 空仓库没有技术栈和发布模型证据时，不擅自生成针对生成产物的忽略规则；技术栈明确后可以添加项目匹配的最小 `.gitignore`，但不能误伤正式源码目录。

## Task Lifecycle

推荐状态：

```text
PLANNED → IN_PROGRESS → READY → INTEGRATING → MERGED
                 │             │
                 ├→ TEST_FAILED ├→ CONFLICT
                 └→ BLOCKED     └→ BLOCKED

任何未完成任务也可以进入 CANCELLED。
```

- `READY != MERGED`；
- PR 创建成功不等于 `MERGED`，只有远端明确确认合并后才能标记 `MERGED`；
- `CONFLICT`、`TEST_FAILED`、`BLOCKED` 必须记录原因和下一步，不得伪装成 `READY`；
- 状态变化后更新 `STATUS.md`，但不要把它变成长日志。

## Parallel Development Rules

- 并行前先识别文件所有权、公共接口和潜在 Hotspot Files；
- 两个 Agent 不得同时写同一个文件或同一个 Worktree；
- 每个任务明确 branch、Worktree、目标、验证命令和交付状态；
- 共享接口、Schema、parser、配置或基础设施变更要提高 Conflict Risk，并在集成前协调；
- Agent 只提交自己负责的、与任务直接相关的文件。

## Integration / Merge Queue Rules

- 集成以明确的 Integration Baseline 为准，并在集成前检查 branch 是否已更新；
- 按依赖关系和 Conflict Risk 排队；`HIGH` 风险任务优先专项审查，不自动合并；
- 集成前后运行与改动直接相关的最小验证集；多 PR Integration 或最终合并时才扩大范围；
- 冲突必须标记 `CONFLICT` 并由负责人解决，禁止自动选择一侧、丢弃改动或强制 push；
- 合并结果必须有可追溯的 commit、验证记录和状态更新。

## Definition of Done

任务只有在以下条件全部满足后才可标记 `READY`：

- 代码、文档和配置完成，且改动范围符合任务；
- 相关测试或检查已运行并记录结果；
- 没有已知的未处理 blocker 或 conflict；
- Worktree 状态、branch、PR 和 Notes 已更新到 `STATUS.md`；
- 没有把 `READY`、PR 创建或 CI 通过误报为 `MERGED`。

标记 `MERGED` 还必须确认目标 branch 已实际包含该变更。

## Risk-based Testing Strategy

开发阶段只运行与修改直接相关的最小测试集。默认不要运行全量 `pytest`、全量 lint、全仓 build 或重复运行未受影响的测试。

以下情况才扩大测试范围：

- 公共基础设施或跨模块接口；
- 数据模型 / Schema；
- 核心 parser / compiler / planner；
- 高风险回归；
- 多 PR Integration；
- 最终合并或发版。

测试失败时保持 `TEST_FAILED`，记录命令、关键输出和复现条件。

## UTF-8 / 中文编码规则

所有文本文件统一使用 UTF-8，包括 `.md`、`.json`、`.yaml`、`.yml`、`.ts`、`.tsx`、`.js`、`.py`、`.ps1` 和 `.sh`。

修改包含中文的文件后必须检查 diff。不得出现 Unicode replacement character、连续问号占位符或其他乱码；不得为了修复编码而无意义地重写整个文件并制造巨大 diff。命令、路径、API 名称和错误原文保持原样，解释使用中文。

## STATUS.md 更新规则

`STATUS.md` 是当前控制面快照，不是事件长日志。至少维护以下内容：

- Project
- Bootstrap Root（如需追溯首次初始化位置）
- Workspace Root（当前日常 base 目录）
- Current Main
- Active Tasks
- Merge Queue
- Integration Baseline
- Hotspot Files
- Blocked
- Recently Merged
- Cleanup Queue
- Next Actions

Active Task 至少包含 `Issue / Task`、`Branch`、`Worktree`、`State`、`Conflict Risk`、`PR` 和 `Notes`。`Conflict Risk` 只能使用 `LOW`、`MEDIUM` 或 `HIGH`。

## Agent Behavior

- 先读当前目录及父目录可达的规则、状态和相关代码；
- 先判定是否存在完整 initialized base，再决定是否需要 bootstrap 输入；
- 日常操作尽量自动识别 Repository、生成 branch 和 Worktree 名称；
- 只在 Repository 无法识别、名称无法生成、候选有歧义或发生真实冲突时询问；
- 只做授权范围内的最小改动，并在交付时说明文件、命令、结果和剩余风险；
- 发现 dirty Main、权限不足、冲突、编码异常或不一致 remote 时只报告，不自行破坏性修复；
- 不把计划、PR、CI 通过或本地成功误称为合并完成。

## Project-specific Rules

- 在此追加项目专属规则、必要的验证命令和敏感目录说明；
- 项目专属规则不得覆盖本文件的安全、编码、Worktree 位置和状态语义约束；
- 项目专属规则不得把 bootstrap 的显式输入要求扩大为日常 Worktree 操作的全局要求。
