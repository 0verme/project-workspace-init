#!/usr/bin/env sh
# Deterministic GitHub probe/clone shim used by test-init-workspace.sh.
# Local Git operations are delegated to REAL_GIT.

set -eu

real_git=${REAL_GIT:?REAL_GIT must point to the real git executable}
workdir=''
if [ "${1-}" = '-C' ]; then
    workdir=$2
    shift 2
fi

command=${1-}
if [ -n "${FAKE_GIT_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$FAKE_GIT_LOG"
fi

remote_branch() {
    remote_key=$1
    case "$remote_key" in
        test/empty) printf '%s' '' ;;
        test/main) printf '%s' 'main' ;;
        test/develop) printf '%s' 'develop' ;;
        test/missing) return 1 ;;
        *) return 1 ;;
    esac
}

if [ "$command" = 'ls-remote' ]; then
    shift
    mode=''
    repository_ref=''
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --heads|--symref)
                mode=$1
                shift
                ;;
            -*|HEAD)
                shift
                ;;
            *)
                if [ -z "$repository_ref" ]; then
                    repository_ref=$1
                fi
                shift
                ;;
        esac
    done

    if [ "$repository_ref" = 'origin' ]; then
        marker="$workdir/.git/fake-default-branch"
        if [ -f "$marker" ]; then
            branch=$(cat "$marker")
        else
            branch=''
        fi
    else
        remote_key=$(printf '%s' "$repository_ref" | sed -e 's#^https://github.com/##' -e 's#\.git$##')
        if ! branch=$(remote_branch "$remote_key"); then
            printf 'fatal: repository %s not found\n' "$repository_ref" >&2
            exit 128
        fi
    fi

    if [ "$mode" = '--heads' ]; then
        if [ -n "$branch" ]; then
            printf '0000000000000000000000000000000000000000 refs/heads/%s\n' "$branch"
        fi
    elif [ "$mode" = '--symref' ] && [ -n "$branch" ]; then
        printf 'ref: refs/heads/%s\tHEAD\n' "$branch"
        printf '0000000000000000000000000000000000000000\tHEAD\n'
    fi
    exit 0
fi

if [ "$command" = 'clone' ]; then
    shift
    branch=''
    repository_url=''
    destination=''
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --origin)
                shift 2
                ;;
            --branch)
                branch=$2
                shift 2
                ;;
            https://github.com/*)
                repository_url=$1
                shift
                destination=$1
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    "$real_git" init -q -b "$branch" "$destination"
    "$real_git" -C "$destination" remote add origin "$repository_url"
    printf 'seed for %s\n' "$branch" > "$destination/seed.txt"
    "$real_git" -C "$destination" config user.name 'Test User'
    "$real_git" -C "$destination" config user.email 'test@example.invalid'
    "$real_git" -C "$destination" add seed.txt
    "$real_git" -C "$destination" commit -q -m 'test seed'
    printf '%s' "$branch" > "$destination/.git/fake-default-branch"
    exit 0
fi

if [ -n "$workdir" ]; then
    exec "$real_git" -C "$workdir" "$@"
else
    exec "$real_git" "$@"
fi
