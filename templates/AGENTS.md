# Agent Workspace Rules

本文件是由 `project-workspace-init` 首次初始化时复制的控制面规则模板。它描述协作边界；具体项目可以在 **Project-specific Rules** 中追加规则，但不得放宽安全约束。

## Workspace Layout

```text
<Workspace Root>/
├─ <repo>/
│  └─ Git Main Workspace
└─ <repo>_base/
   ├─ AGENTS.md
   ├─ STATUS.md
   ├─ status/
   ├─ integration/
   └─ worktrees/
```

- `<repo>/` 是正式 Main Workspace。
- `<repo>_base/` 是 Agent Control Plane，不是 Git Repository。
- 任务 Worktree 只能位于 `<repo>_base/worktrees/<task>`。
- 禁止把任务 Worktree 平铺为 `<Workspace Root>/<repo>-issue-123` 或 `<Workspace Root>/<repo>-feature-name`。
- Main Repository 与 linked Worktree 必须在同一个运行环境和同一文件系统侧。Windows、Linux、FNOS 不跨机器共享 Git linked-worktree metadata。

## Git / Worktree Rules

- 执行 Git 或文件系统写操作前，必须确认用户明确提供了 `Repository` 与 `Workspace Root`；禁止从当前目录、当前 remote、操作系统、环境变量或历史记录推断。
- 不假定 remote default branch 名为 `main`；先读取并记录真实 default branch。
- 开始任务前确认 Main Workspace 的 `origin`、branch 和 working tree 状态。
- 每个任务使用独立 Worktree 和独立 branch；不要在 Main Workspace 直接开发任务。
- 保持改动小而聚焦。不得覆盖其他 Agent 的未提交代码。
- 严禁自动执行 `git reset --hard`、`git clean -fd`、`git clean -fdx`、force push、删除 branch、删除或移动已有 Worktree、自动 stash 或自动提交。
- 已有冲突或未提交修改时先停止并报告，不以破坏数据换取“干净”状态。

## Task Lifecycle

推荐状态：

```text
PLANNED → IN_PROGRESS → READY → INTEGRATING → MERGED
                 │             │
                 ├→ TEST_FAILED ├→ CONFLICT
                 └→ BLOCKED     └→ BLOCKED

任何未完成任务也可以进入 CANCELLED。
```

- `READY != MERGED`。
- PR 创建成功不等于 `MERGED`；只有远端明确确认合并后才能标记 `MERGED`。
- `CONFLICT`、`TEST_FAILED`、`BLOCKED` 必须记录原因和下一步，不得伪装成 `READY`。
- 状态变化后及时更新 `STATUS.md`，但不要把它变成长日志。

## Parallel Development Rules

- 并行前先识别文件所有权、公共接口和潜在 Hotspot Files。
- 两个 Agent 不得同时写同一个文件或同一个 Worktree。
- 每个任务明确 branch、Worktree、目标、验证命令和交付状态。
- 共享接口、Schema、parser、配置或基础设施变更要提高 Conflict Risk，并在集成前协调。
- Agent 只提交自己负责的、与任务直接相关的文件；不得把其他任务的改动一起提交。

## Integration / Merge Queue Rules

- 集成以明确的 Integration Baseline 为准，并在集成前检查 branch 是否已更新。
- 按依赖关系和 Conflict Risk 排队；`HIGH` 风险任务优先进行专项审查，不自动合并。
- 集成前后运行与改动直接相关的最小验证集；多 PR 集成或最终合并时才扩大验证范围。
- 冲突必须标记 `CONFLICT` 并由负责人解决。禁止自动选择一侧、丢弃改动或强制 push。
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

- 先读规则、状态和相关代码，再行动。
- 输入、路径、branch、remote 或权限不明确时停止询问；宁可 `NEEDS_INPUT`，不要猜测。
- 只做授权范围内的最小改动，并在交付时说明文件、命令、结果和剩余风险。
- 发现 dirty Main、权限不足、冲突、编码异常或不一致 remote 时只报告，不自行修复破坏性问题。
- 不把计划、PR、CI 通过或本地成功误称为合并完成。

## Project-specific Rules

- 在此追加项目专属规则、必要的验证命令和敏感目录说明。
- 项目专属规则不得覆盖本文件的安全、输入、编码、Worktree 位置和状态语义约束。
