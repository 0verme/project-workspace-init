#!/usr/bin/env sh
# Contract tests for the declarative daily Worktree rules.
#
# project-workspace-init does not ship a daily Worktree command: its runtime
# policy is SKILL.md and the copied templates. These tests keep the three
# policy sources aligned and protect the ten recovery scenarios from regressions.

set -eu

script_dir=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
policy_files="SKILL.md README.md templates/AGENTS.md"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    file=$1
    needle=$2
    grep -F -- "$needle" "$script_dir/$file" >/dev/null 2>&1 ||
        fail "$file does not contain: $needle"
}

assert_not_contains() {
    file=$1
    needle=$2
    if grep -F -- "$needle" "$script_dir/$file" >/dev/null 2>&1; then
        fail "$file contains forbidden legacy rule: $needle"
    fi
}

assert_all_contain() {
    needle=$1
    for file in $policy_files; do
        assert_contains "$file" "$needle"
    done
}

# Every source must describe the same resolved-root and recovery vocabulary.
for required in \
    'Resolved Workspace Context' \
    'CONTROL_PLANE_ROOT' \
    'WORKTREE_ROOT' \
    'Current Task' \
    'Target Branch' \
    'Canonical Worktree Path' \
    'Existing Worktree Path (if any)' \
    'git worktree list --porcelain' \
    'REUSED' \
    'STALE_WORKTREE_METADATA' \
    'SAFE_TEMP_RESIDUE' \
    'REAL_CONFLICT' \
    'git worktree prune' \
    'NEEDS_INPUT' \
    'NEEDS_ATTENTION'; do
    assert_all_contain "$required"
done

# Test 1: canonical Worktree is healthy and fully matching.
assert_contains SKILL.md 'CASE A：canonical Worktree 已存在且完全匹配'
assert_contains SKILL.md 'State: REUSED'
assert_contains SKILL.md '直接复用，不重新创建，不 STOP。'

# Test 2: branch binding wins over a non-canonical but healthy path.
assert_all_contain 'branch 的真实绑定优先'
assert_all_contain '不为了路径规范化迁移'
assert_all_contain 'REUSE existing healthy worktree'

# Test 3: missing physical directory is stale metadata only after proof.
assert_contains SKILL.md 'CASE C：Git metadata 存在但物理目录不存在'
assert_all_contain '物理目录已明确不存在'
assert_all_contain '没有 lock'

# Test 4: the detected base cannot become <repo>_base_base.
assert_all_contain '_base_base'
assert_all_contain '不得静默切换'

# Test 5: branch slashes never become Worktree directory levels.
assert_all_contain 'feat/issue-4-host-api-contract'
assert_all_contain '<CONTROL_PLANE_ROOT>/worktrees/issue-4-host-api-contract'
assert_all_contain "branch 中的 \`/\` 不得成为目录层级"

# Test 6: only a proven, empty residue from this operation is removable.
assert_contains SKILL.md "D1 \`SAFE_TEMP_RESIDUE\`"
assert_all_contain '由本轮当前操作创建'
assert_all_contain '目录为空'
assert_all_contain "不得使用 \`rm -rf\`"

# Test 7: unknown non-empty data is an input conflict, never an auto suffix.
assert_contains SKILL.md "D2 \`REAL_CONFLICT\`"
assert_all_contain '未知非空目录'
assert_all_contain 'NEEDS_INPUT'
assert_all_contain '不得删除'

# Test 8: dirty healthy Worktrees retain user data and can be reused.
assert_all_contain 'staged changes'
assert_all_contain 'unstaged changes'
assert_all_contain 'untracked user files'
assert_all_contain "报告 \`DIRTY\`"
assert_all_contain '不得 prune、删除、移动、覆盖'

# Test 9: lock or inaccessible state is not stale.
assert_all_contain 'locked / inaccessible Worktree'
assert_all_contain "返回 \`NEEDS_ATTENTION\`"
assert_all_contain '不得 prune'

# Test 10: root locking is an invariant for the rest of the task.
assert_all_contain "后续不得根据 repo 名、当前路径、parent、remote 或 \`_base\`"
assert_all_contain '一次锁定'
assert_all_contain 'Control Plane Root'

# The old absolute prohibition must not return in any policy source.
for file in $policy_files; do
    assert_not_contains "$file" "严禁自动执行 \`git reset --hard\`、\`git clean -fd\`、\`git clean -fdx\`、force push、删除 branch、删除或移动已有 Worktree"
    assert_not_contains "$file" '不自动删除或移动已有 branch / Worktree'
done

printf '%s\n' 'PASS: Worktree recovery policy scenarios (10 cases)'
