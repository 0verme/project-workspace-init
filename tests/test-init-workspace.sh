#!/usr/bin/env sh
# Integration tests for the POSIX bootstrap script.
# The fake Git shim makes remote states deterministic without creating commits
# or branches on GitHub.

set -eu

script_dir=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
script_path="$script_dir/scripts/init-workspace.sh"
real_git=$(command -v git)
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/project-workspace-init-tests.XXXXXX")
fake_git="$fixture_dir/fake-git"
cp "$script_dir/tests/fake-git.sh" "$fake_git"
chmod +x "$fake_git"

cleanup() {
    rm -rf "$fixture_dir"
}
trap cleanup EXIT HUP INT TERM

export REAL_GIT=$real_git
export FAKE_GIT_LOG="$fixture_dir/git.log"
export PATH="$fixture_dir:$PATH"
cp "$fake_git" "$fixture_dir/git"
chmod +x "$fixture_dir/git"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    haystack=$1
    needle=$2
    printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null ||
        fail "expected output to contain: $needle\n$haystack"
}

assert_not_contains() {
    haystack=$1
    needle=$2
    if printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null; then
        fail "expected output not to contain: $needle\n$haystack"
    fi
}

run_bootstrap() {
    set +e
    test_output=$(sh "$script_path" "$@" 2>&1)
    test_exit=$?
    set -e
}

new_case() {
    case_root="$fixture_dir/$1"
    mkdir -p "$case_root"
}

assert_successful_empty_workspace() {
    root=$1
    main="$root/empty"
    base="$root/empty_base"
    [ -d "$main/.git" ] || fail 'empty main workspace was not created as a Git repository'
    [ -d "$base/status" ] || fail 'status directory was not created'
    [ -d "$base/integration" ] || fail 'integration directory was not created'
    [ -d "$base/worktrees" ] || fail 'worktrees directory was not created'
    [ -f "$base/AGENTS.md" ] || fail 'AGENTS.md was not created'
    [ -f "$base/STATUS.md" ] || fail 'STATUS.md was not created'
    [ "$($real_git -C "$main" symbolic-ref --quiet --short HEAD)" = 'main' ] ||
        fail 'empty main workspace is not on main'
    [ "$($real_git -C "$main" config --get remote.origin.url)" = 'https://github.com/test/empty.git' ] ||
        fail 'empty main workspace origin is incorrect'
    if $real_git -C "$main" rev-parse --verify HEAD >/dev/null 2>&1; then
        fail 'empty bootstrap created an automatic commit'
    fi
    if $real_git -C "$main" show-ref --verify --quiet refs/remotes/origin/main; then
        fail 'empty bootstrap unexpectedly created origin/main'
    fi
    if grep -F ' push ' "$FAKE_GIT_LOG" >/dev/null 2>&1; then
        fail 'empty bootstrap attempted a push'
    fi
}

# 1. Missing Repository and 2. missing Workspace Root never mutate anything.
new_case missing-input
run_bootstrap --root "$case_root"
[ "$test_exit" -eq 2 ] || fail 'missing Repository did not exit with 2'
assert_contains "$test_output" 'STATUS: NEEDS_INPUT'
assert_contains "$test_output" 'Repository'
[ -z "$(find "$case_root" -mindepth 1 -print -quit)" ] || fail 'missing Repository mutated the root'

run_bootstrap --repository test/empty
[ "$test_exit" -eq 2 ] || fail 'missing Workspace Root did not exit with 2'
assert_contains "$test_output" 'STATUS: NEEDS_INPUT'
assert_contains "$test_output" 'Workspace Root'

# 3. An unconfirmed repository is not treated as an empty repository.
new_case missing-remote
run_bootstrap --repository test/missing --root "$case_root"
[ "$test_exit" -eq 2 ] || fail 'missing repository did not stop with exit 2'
assert_contains "$test_output" 'STATUS: NEEDS_ATTENTION'
assert_contains "$test_output" 'Remote State: REPOSITORY_NOT_FOUND'
[ -z "$(find "$case_root" -mindepth 1 -print -quit)" ] || fail 'missing repository created a workspace'

# 4. Empty remote bootstrap creates local main, origin, and the control plane.
new_case empty
run_bootstrap --repository test/empty --root "$case_root"
[ "$test_exit" -eq 0 ] || fail "empty repository bootstrap failed:\n$test_output"
assert_contains "$test_output" 'STATUS: SUCCESS'
assert_contains "$test_output" 'Remote State: EMPTY_REPOSITORY'
assert_not_contains "$test_output" 'NEEDS_ATTENTION'
assert_successful_empty_workspace "$case_root"

# 5. Rerunning a correct empty bootstrap is safe and preserves existing files.
printf 'preserve me\n' > "$case_root/empty_base/AGENTS.md"
run_bootstrap --repository test/empty --root "$case_root"
[ "$test_exit" -eq 0 ] || fail "empty repository rerun failed:\n$test_output"
assert_contains "$test_output" 'Main Workspace: '
assert_contains "$test_output" '(EXISTS)'
assert_contains "$test_output" 'Base Workspace: '
assert_contains "$test_output" '(EXISTS)'
[ "$(cat "$case_root/empty_base/AGENTS.md")" = 'preserve me' ] || fail 'rerun overwrote AGENTS.md'
assert_successful_empty_workspace "$case_root"

# 6. An existing non-Git target is a conflict, not an overwrite opportunity.
new_case local-non-git
mkdir "$case_root/empty"
run_bootstrap --repository test/empty --root "$case_root"
[ "$test_exit" -eq 2 ] || fail 'non-Git target did not stop with exit 2'
assert_contains "$test_output" 'STATUS: NEEDS_ATTENTION'
assert_contains "$test_output" 'not a Git repository'
[ ! -e "$case_root/empty_base" ] || fail 'non-Git target created a partial base'

# 7. An existing local repository with a mismatched origin is never repaired.
new_case origin-mismatch
mkdir "$case_root/empty"
$real_git init -q -b main "$case_root/empty"
$real_git -C "$case_root/empty" remote add origin https://github.com/other/repository.git
printf 'main' > "$case_root/empty/.git/fake-default-branch"
run_bootstrap --repository test/empty --root "$case_root"
[ "$test_exit" -eq 2 ] || fail 'origin mismatch did not stop with exit 2'
assert_contains "$test_output" 'STATUS: NEEDS_ATTENTION'
assert_contains "$test_output" 'does not match the requested Repository'
[ ! -e "$case_root/empty_base" ] || fail 'origin mismatch created a partial base'
[ "$($real_git -C "$case_root/empty" config --get remote.origin.url)" = 'https://github.com/other/repository.git' ] ||
    fail 'origin mismatch was modified'

# 8. A normal repository with main still uses clone/bootstrap.
new_case existing-main
run_bootstrap --repository test/main --root "$case_root"
[ "$test_exit" -eq 0 ] || fail "main repository bootstrap failed:\n$test_output"
assert_contains "$test_output" 'Remote State: EXISTING_REPOSITORY'
assert_contains "$test_output" 'Current Branch: main'
[ "$($real_git -C "$case_root/main" rev-parse --verify HEAD >/dev/null 2>&1; echo $?)" -eq 0 ] ||
    fail 'normal repository did not receive a commit from the fake clone'
[ "$($real_git -C "$case_root/main" config --get remote.origin.url)" = 'https://github.com/test/main.git' ] ||
    fail 'normal repository origin is incorrect'

# 9. A non-main remote default branch remains non-main.
new_case existing-develop
run_bootstrap --repository test/develop --root "$case_root"
[ "$test_exit" -eq 0 ] || fail "non-main repository bootstrap failed:\n$test_output"
assert_contains "$test_output" 'Remote State: EXISTING_REPOSITORY'
assert_contains "$test_output" 'Current Branch: develop'
assert_contains "$test_output" 'Default Branch: develop'
[ "$($real_git -C "$case_root/develop" symbolic-ref --quiet --short HEAD)" = 'develop' ] ||
    fail 'non-main default branch was forced to main'

printf '%s\n' 'PASS: init-workspace bootstrap scenarios (9 groups)'
