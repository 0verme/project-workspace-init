#!/usr/bin/env sh
# Initialize a Git Main Workspace and its non-Git Agent Control Plane.
# The caller must provide both --repository and --root explicitly.

set -eu

# This command is bootstrap-only. The Skill must not invoke it for daily
# Worktree operations after an initialized base has been discovered.

stop_needs_input() {
    reason=${1-}
    shift || true

    printf '%s\n' 'STATUS: NEEDS_INPUT'
    if [ -n "$reason" ]; then
        printf 'Reason: %s\n' "$reason"
    fi
    printf '%s\n' 'Missing:'
    for item in "$@"; do
        printf '%s\n' "- $item"
    done
    printf '%s\n' 'No Git or filesystem mutations were made.'
    exit 2
}

stop_attention() {
    headline=$1
    reason=${2-}

    printf '%s\n' 'STATUS: NEEDS_ATTENTION'
    printf '%s\n' "$headline"
    if [ -n "$reason" ]; then
        printf 'Reason: %s\n' "$reason"
    fi
    printf '%s\n' 'No destructive Git or filesystem mutations were made.'
    exit 2
}

repository=
root=
repository_seen=0
root_seen=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repository)
            if [ "$repository_seen" -eq 1 ] || [ "$#" -lt 2 ] || [ "${2#--}" != "$2" ]; then
                stop_needs_input 'Use --repository <GitHub URL or owner/repo> exactly once.'
            fi
            repository=$2
            repository_seen=1
            shift 2
            ;;
        --root)
            if [ "$root_seen" -eq 1 ] || [ "$#" -lt 2 ] || [ "${2#--}" != "$2" ]; then
                stop_needs_input 'Use --root <explicit absolute path> exactly once.'
            fi
            root=$2
            root_seen=1
            shift 2
            ;;
        *)
            stop_needs_input 'Only --repository and --root are accepted.'
            ;;
    esac
done

repository_missing=0
root_missing=0
if [ "$repository_seen" -eq 0 ] || [ -z "$repository" ]; then
    repository_missing=1
fi
if [ "$root_seen" -eq 0 ] || [ -z "$root" ]; then
    root_missing=1
fi
if [ "$repository_missing" -eq 1 ] && [ "$root_missing" -eq 1 ]; then
    stop_needs_input '' 'Repository' 'Workspace Root'
elif [ "$repository_missing" -eq 1 ]; then
    stop_needs_input '' 'Repository'
elif [ "$root_missing" -eq 1 ]; then
    stop_needs_input '' 'Workspace Root'
fi

case "$root" in
    /*) ;;
    *) stop_needs_input 'Workspace Root must be an explicit POSIX absolute path.' ;;
esac
case "$root" in
    .|..|~|~/*|*/./*|*/../*|*/.|*/..) \
        stop_needs_input 'Workspace Root must not be a relative path or contain . / .. path segments.'
        ;;
esac

parse_repository() {
    candidate=$1
    case "$candidate" in
        ''|*[![:space:]]*) ;;
        *) return 1 ;;
    esac

    case "$candidate" in
        */) candidate=${candidate%/} ;;
    esac
    case "$candidate" in
        *.git) candidate=${candidate%.git} ;;
    esac

    case "$candidate" in
        https://github.com/*) rest=${candidate#https://github.com/} ;;
        */*) rest=$candidate ;;
        *) return 1 ;;
    esac

    case "$rest" in
        */*) owner=${rest%%/*}; name=${rest#*/} ;;
        *) return 1 ;;
    esac
    case "$name" in
        */*) return 1 ;;
    esac
    case "$owner" in
        [A-Za-z0-9]*) ;;
        *) return 1 ;;
    esac
    case "$name" in
        [A-Za-z0-9]*) ;;
        *) return 1 ;;
    esac
    case "$owner" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    case "$name" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
    esac

    REPOSITORY_NAME=$name
    REPOSITORY_IDENTITY="$owner/$name"
    REPOSITORY_CLONE_URL="https://github.com/$owner/$name.git"
    return 0
}

parse_remote_identity() {
    candidate=$1
    case "$candidate" in
        */) candidate=${candidate%/} ;;
    esac
    case "$candidate" in
        *.git) candidate=${candidate%.git} ;;
    esac

    case "$candidate" in
        https://github.com/*) rest=${candidate#https://github.com/} ;;
        git@github.com:*) rest=${candidate#git@github.com:} ;;
        ssh://git@github.com/*) rest=${candidate#ssh://git@github.com/} ;;
        *) return 1 ;;
    esac
    case "$rest" in
        */*) owner=${rest%%/*}; name=${rest#*/} ;;
        *) return 1 ;;
    esac
    case "$name" in
        */*) return 1 ;;
    esac
    case "$owner" in
        [A-Za-z0-9]*) ;;
        *) return 1 ;;
    esac
    case "$name" in
        [A-Za-z0-9]*) ;;
        *) return 1 ;;
    esac
    case "$owner" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    case "$name" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
    esac

    REMOTE_IDENTITY="$owner/$name"
    return 0
}

normalize_identity() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

if ! parse_repository "$repository"; then
    stop_needs_input 'Repository must be a GitHub URL or an explicit owner/repo value.'
fi

if ! command -v git >/dev/null 2>&1; then
    stop_attention 'Git is unavailable.' 'Put git in PATH and retry.'
fi

if [ ! -d "$root" ]; then
    stop_attention 'Workspace Root is unavailable.' "Root does not exist as a directory: $root"
fi
if [ ! -r "$root" ] || [ ! -x "$root" ] || [ ! -w "$root" ]; then
    current_user=$(id -un 2>/dev/null || printf '%s' 'unknown')
    stop_attention 'Workspace Root permissions are insufficient.' "User: $current_user; Target: $root; required read, enter, and write permissions are not all available."
fi

script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)
template_root=$(CDPATH='' cd "$script_dir/../templates" 2>/dev/null && pwd -P) || \
    stop_attention 'Skill templates are unavailable.' "Expected templates under: $script_dir/../templates"
agents_template="$template_root/AGENTS.md"
status_template="$template_root/STATUS.md"
if [ ! -f "$agents_template" ] || [ ! -f "$status_template" ]; then
    stop_attention 'Skill templates are unavailable.' "Expected templates under: $template_root"
fi

root_path=$(CDPATH='' cd "$root" && pwd -P)
main_path="$root_path/$REPOSITORY_NAME"
base_path="$root_path/${REPOSITORY_NAME}_base"
expected_identity=$(normalize_identity "$REPOSITORY_IDENTITY")

path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

# Capture Git output without letting a read-only failure terminate the script.
GIT_OUTPUT=''
GIT_EXIT=0
git_capture() {
    working_directory=$1
    shift
    set +e
    GIT_OUTPUT=$(git -C "$working_directory" "$@" 2>&1)
    GIT_EXIT=$?
    set -e
}

git_capture_global() {
    set +e
    GIT_OUTPUT=$(git "$@" 2>&1)
    GIT_EXIT=$?
    set -e
}

DEFAULT_BRANCH=''
DEFAULT_ERROR=''
get_default_branch() {
    repository_ref=$1
    working_directory=${2-}
    if [ -n "$working_directory" ]; then
        git_capture "$working_directory" ls-remote --symref "$repository_ref" HEAD
    else
        git_capture_global ls-remote --symref "$repository_ref" HEAD
    fi
    if [ "$GIT_EXIT" -ne 0 ]; then
        DEFAULT_BRANCH=''
        DEFAULT_ERROR="Unable to read remote default branch: ${GIT_OUTPUT:-git returned a non-zero exit code.}"
        return 1
    fi

    tab=$(printf '\t')
    suffix="${tab}HEAD"
    while IFS= read -r line; do
        case "$line" in
            "ref: refs/heads/"*"$suffix")
                branch=${line#ref: refs/heads/}
                branch=${branch%"$suffix"}
                DEFAULT_BRANCH=$branch
                DEFAULT_ERROR=''
                return 0
                ;;
        esac
    done <<EOF
$GIT_OUTPUT
EOF
    DEFAULT_BRANCH=''
    DEFAULT_ERROR='The remote did not advertise a default branch.'
    return 1
}

INSPECT_VALID=0
INSPECT_DIRTY=0
INSPECT_CURRENT_BRANCH=''
INSPECT_DEFAULT_BRANCH=''
INSPECT_REASONS=''
INSPECT_REASON_COUNT=0
add_inspect_reason() {
    if [ -z "$INSPECT_REASONS" ]; then
        INSPECT_REASONS=$1
    else
        INSPECT_REASONS="$INSPECT_REASONS; $1"
    fi
    INSPECT_REASON_COUNT=$((INSPECT_REASON_COUNT + 1))
}

inspect_main() {
    working_directory=$1
    expected=$2
    INSPECT_VALID=0
    INSPECT_DIRTY=0
    INSPECT_CURRENT_BRANCH=''
    INSPECT_DEFAULT_BRANCH=''
    INSPECT_REASONS=''
    INSPECT_REASON_COUNT=0

    git_capture "$working_directory" rev-parse --show-toplevel
    if [ "$GIT_EXIT" -ne 0 ]; then
        add_inspect_reason 'Main Workspace is not a Git repository.'
        return 1
    fi
    main_real=$(CDPATH='' cd "$working_directory" 2>/dev/null && pwd -P) || {
        add_inspect_reason 'Main Workspace cannot be entered.'
        return 1
    }
    top_real=$(CDPATH='' cd "$GIT_OUTPUT" 2>/dev/null && pwd -P) || {
        add_inspect_reason 'Main Workspace Git top level cannot be resolved.'
        return 1
    }
    if [ "$main_real" != "$top_real" ]; then
        add_inspect_reason 'Main Workspace Git top level does not match the requested path.'
        return 1
    fi

    git_capture "$working_directory" rev-parse --is-inside-work-tree
    if [ "$GIT_EXIT" -ne 0 ] || [ "$GIT_OUTPUT" != 'true' ]; then
        add_inspect_reason 'Main Workspace is not a non-bare Git working tree.'
    fi

    git_capture "$working_directory" config --get remote.origin.url
    if [ "$GIT_EXIT" -ne 0 ] || [ -z "$GIT_OUTPUT" ]; then
        add_inspect_reason 'origin is missing.'
    else
        if ! parse_remote_identity "$GIT_OUTPUT"; then
            add_inspect_reason "origin '$GIT_OUTPUT' is not a supported GitHub remote."
        elif [ "$(normalize_identity "$REMOTE_IDENTITY")" != "$expected" ]; then
            add_inspect_reason "origin '$GIT_OUTPUT' does not match the requested Repository '$expected'."
        fi
    fi

    if get_default_branch origin "$working_directory"; then
        INSPECT_DEFAULT_BRANCH=$DEFAULT_BRANCH
    else
        add_inspect_reason "$DEFAULT_ERROR"
    fi

    git_capture "$working_directory" symbolic-ref --quiet --short HEAD
    if [ "$GIT_EXIT" -ne 0 ] || [ -z "$GIT_OUTPUT" ]; then
        add_inspect_reason 'Main Workspace is detached or its current branch cannot be read.'
    else
        INSPECT_CURRENT_BRANCH=$GIT_OUTPUT
        if [ -n "$INSPECT_DEFAULT_BRANCH" ] && [ "$INSPECT_CURRENT_BRANCH" != "$INSPECT_DEFAULT_BRANCH" ]; then
            add_inspect_reason "Current branch '$INSPECT_CURRENT_BRANCH' is not remote default branch '$INSPECT_DEFAULT_BRANCH'."
        fi
    fi

    git_capture "$working_directory" status --porcelain=v1 --untracked-files=all
    if [ "$GIT_EXIT" -ne 0 ]; then
        add_inspect_reason 'Unable to read Main Workspace working tree status.'
    elif [ -n "$GIT_OUTPUT" ]; then
        INSPECT_DIRTY=1
        add_inspect_reason 'Main Workspace: DIRTY'
    fi

    if [ "$INSPECT_REASON_COUNT" -eq 0 ]; then
        INSPECT_VALID=1
        return 0
    fi
    return 1
}

main_exists=0
if path_exists "$main_path"; then
    main_exists=1
    if [ ! -d "$main_path" ]; then
        stop_attention 'Workspace preflight failed.' "Main Workspace path is not a directory: $main_path"
    fi
fi

if path_exists "$base_path"; then
    if [ ! -d "$base_path" ]; then
        stop_attention 'Workspace preflight failed.' "Base Workspace path is not a directory: $base_path"
    fi

    git_capture "$base_path" rev-parse --show-toplevel
    if [ "$GIT_EXIT" -eq 0 ]; then
        stop_attention 'Workspace preflight failed.' 'Base Workspace is inside an existing Git repository; Base must remain non-Git.'
    fi

    for directory_name in status integration worktrees; do
        directory_path="$base_path/$directory_name"
        if path_exists "$directory_path" && [ ! -d "$directory_path" ]; then
            stop_attention 'Workspace preflight failed.' "Base entry is not a directory: $directory_path"
        fi
    done
    for file_name in AGENTS.md STATUS.md; do
        file_path="$base_path/$file_name"
        if path_exists "$file_path" && [ ! -f "$file_path" ]; then
            stop_attention 'Workspace preflight failed.' "Base template target is not a regular file: $file_path"
        fi
    done

    base_needs_write=0
    for directory_name in status integration worktrees; do
        if ! path_exists "$base_path/$directory_name"; then
            base_needs_write=1
        fi
    done
    for file_name in AGENTS.md STATUS.md; do
        if ! path_exists "$base_path/$file_name"; then
            base_needs_write=1
        fi
    done
    if [ "$base_needs_write" -eq 1 ] && { [ ! -r "$base_path" ] || [ ! -x "$base_path" ] || [ ! -w "$base_path" ]; }; then
        current_user=$(id -un 2>/dev/null || printf '%s' 'unknown')
        stop_attention 'Workspace permissions are insufficient.' "User: $current_user; Target: $base_path; required read, enter, and write permissions are not all available."
    fi
fi

main_status=
if [ "$main_exists" -eq 1 ]; then
    inspect_main "$main_path" "$expected_identity" || true
    if [ "$INSPECT_DIRTY" -eq 1 ]; then
        stop_attention 'Main Workspace: DIRTY' "$INSPECT_REASONS"
    fi
    if [ "$INSPECT_VALID" -ne 1 ]; then
        stop_attention 'Main Workspace: NEEDS_ATTENTION' "$INSPECT_REASONS"
    fi
    main_status=EXISTS
else
    if ! get_default_branch "$REPOSITORY_CLONE_URL"; then
        stop_attention 'Main Workspace cannot be cloned safely.' "$DEFAULT_ERROR"
    fi
    clone_default_branch=$DEFAULT_BRANCH

    git_capture "$root_path" clone --origin origin --branch "$clone_default_branch" "$REPOSITORY_CLONE_URL" "$main_path"
    if [ "$GIT_EXIT" -ne 0 ]; then
        clone_message=${GIT_OUTPUT:-git clone returned a non-zero exit code.}
        stop_attention 'Main Workspace clone failed.' "$clone_message"
    fi

    inspect_main "$main_path" "$expected_identity" || true
    if [ "$INSPECT_DIRTY" -eq 1 ]; then
        stop_attention 'Main Workspace: DIRTY' "$INSPECT_REASONS"
    fi
    if [ "$INSPECT_VALID" -ne 1 ]; then
        stop_attention 'Cloned Main Workspace verification failed.' "$INSPECT_REASONS"
    fi
    main_status=CREATED
fi

legacy_count=0
for candidate in "$root_path"/"$REPOSITORY_NAME"-*; do
    if [ -d "$candidate" ]; then
        legacy_count=$((legacy_count + 1))
    fi
done

worktree_warning=''
git_capture "$main_path" worktree list
if [ "$GIT_EXIT" -ne 0 ]; then
    worktree_warning="git worktree list failed: ${GIT_OUTPUT:-git returned a non-zero exit code.}"
fi

base_status=''
status_directory_status=''
integration_directory_status=''
worktrees_directory_status=''
agents_status=''
status_file_status=''
if ! path_exists "$base_path"; then
    if mkdir "$base_path"; then
        base_status=CREATED
    else
        stop_attention 'Base Workspace initialization failed.' "Unable to create: $base_path"
    fi
else
    base_status=EXISTS
fi

for directory_name in status integration worktrees; do
    directory_path="$base_path/$directory_name"
    if ! path_exists "$directory_path"; then
        if ! mkdir "$directory_path"; then
            stop_attention 'Base Workspace initialization failed.' "Unable to create: $directory_path"
        fi
        state=CREATED
    else
        state=EXISTS
    fi
    case "$directory_name" in
        status) status_directory_status=$state ;;
        integration) integration_directory_status=$state ;;
        worktrees) worktrees_directory_status=$state ;;
    esac
done

for file_name in AGENTS.md STATUS.md; do
    target_path="$base_path/$file_name"
    if ! path_exists "$target_path"; then
        source_path="$template_root/$file_name"
        if ! cp "$source_path" "$target_path"; then
            stop_attention 'Base Workspace initialization failed.' "Unable to create: $target_path"
        fi
        state=CREATED
    else
        state=KEEP
    fi
    case "$file_name" in
        AGENTS.md) agents_status=$state ;;
        STATUS.md) status_file_status=$state ;;
    esac
done

printf '%s\n' 'STATUS: SUCCESS'
printf 'Repository: %s\n' "$REPOSITORY_IDENTITY"
printf 'Workspace Root: %s\n' "$root_path"
printf 'Main Workspace: %s (%s)\n' "$main_path" "$main_status"
printf 'Current Branch: %s\n' "$INSPECT_CURRENT_BRANCH"
printf 'Default Branch: %s\n' "$INSPECT_DEFAULT_BRANCH"
printf '%s\n' 'Origin: VERIFIED'
printf '%s\n' 'Working Tree: CLEAN'
printf 'Base Workspace: %s (%s)\n' "$base_path" "$base_status"
printf 'Base/status: %s\n' "$status_directory_status"
printf 'Base/integration: %s\n' "$integration_directory_status"
printf 'Base/worktrees: %s\n' "$worktrees_directory_status"
printf 'Base/AGENTS.md: %s\n' "$agents_status"
printf 'Base/STATUS.md: %s\n' "$status_file_status"

if [ "$legacy_count" -gt 0 ]; then
    printf '%s\n' 'LEGACY WORKTREES DETECTED'
    for candidate in "$root_path"/"$REPOSITORY_NAME"-*; do
        if [ -d "$candidate" ]; then
            printf '%s\n' "- $candidate"
        fi
    done
fi

if [ -n "$worktree_warning" ]; then
    printf 'WARNING: %s\n' "$worktree_warning"
fi
