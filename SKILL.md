---
name: project-workspace-init
description: Safely initialize Git main workspaces and multi-agent worktree control planes with explicit Repository and Workspace Root inputs.
license: MIT
metadata:
  version: "1.0.0"
  platforms: "Windows, Linux, FNOS"
---

# Project Workspace Init

Initialize a predictable pair of directories for a Git project and its Agent Control Plane. This Skill is intentionally narrow: it establishes the workspace boundary and records safe operating rules; it does not schedule tasks or manage task Worktree lifecycles.

## Mandatory input contract

Before invoking either script, require both values explicitly from the user:

```text
Repository: <GitHub URL or owner/repo>
Workspace Root: <explicit absolute path>
```

There are no defaults. Never infer either value from:

- the current working directory or current Git Repository;
- a current Git remote;
- the operating system;
- environment variables or `HOME`;
- historical commands, neighboring directories, project context, `AGENTS.md`, `STATUS.md`, or any default configuration.

If one value is missing, ask only for that value and return `STATUS: NEEDS_INPUT`. Do not scan the file system, run `git`, create a directory, clone, or perform any other mutation. If the Root is relative, reject it and request an explicit absolute path.

Accepted Repository forms in version 1:

- `https://github.com/<owner>/<repo>`;
- `https://github.com/<owner>/<repo>.git`;
- `<owner>/<repo>`, explicitly interpreted as a GitHub Repository.

A bare `<repo>` is ambiguous and must be rejected.

## Execution

Run the platform-specific script from this Skill package. The script location is resolved from the package itself; the caller's current directory is not used as a target or as a source of defaults.

Windows:

```powershell
.\scripts\init-workspace.ps1 -Repository <repository> -Root <absolute-path>
```

Linux / FNOS:

```sh
./scripts/init-workspace.sh --repository <repository> --root <absolute-path>
```

The Root must already exist as an accessible directory in version 1. This makes a typo or an unavailable mount an attention state rather than an accidental new location.

## Resulting layout

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

`<repo>/` is the formal Git Main Workspace. `<repo>_base/` is the Agent Control Plane and must not be initialized as a Git Repository. All future task Worktrees belong under `<repo>_base/worktrees/<task>`; do not recommend flat siblings such as `<Workspace Root>/<repo>-issue-123`.

## Main Workspace contract

When `<repo>` does not exist:

1. Read the remote's advertised default branch without assuming it is named `main`.
2. Clone the explicit Repository into `<Workspace Root>/<repo>`.
3. Verify `origin`, the checked-out branch, the remote default branch, and a clean working tree.

When `<repo>` exists, inspect it without changing it:

- it must be a Git Repository whose top level is the requested Main Workspace;
- `origin` must identify the explicit Repository;
- current branch and remote default branch must be readable;
- working tree must be clean.

A dirty or otherwise unsafe Main Workspace returns `STATUS: NEEDS_ATTENTION`. In particular, a dirty Main reports `Main Workspace: DIRTY` and stops. Never reset, clean, stash, overwrite checkout, delete branches or Worktrees, or auto-commit.

## Base Workspace contract

Create only missing directories and missing template files. Existing Base data is retained. Existing `AGENTS.md` and `STATUS.md` always produce `KEEP`; explicit inputs authorize checking and initializing the target structure, not overwriting user data.

The operation is idempotent:

- no re-clone when Main Workspace already exists;
- no overwrite of templates;
- no destructive change to Base or user code;
- repeated execution converges on the same layout.

Use the result labels `CREATED`, `EXISTS`, `KEEP`, `WARNING`, `NEEDS_INPUT`, and `NEEDS_ATTENTION` as actionable states.

## Legacy and platform boundary checks

After both inputs are explicit and Main Workspace validation succeeds, inspect `git worktree list` and look for likely legacy flat directories directly under Workspace Root. If found, report `LEGACY WORKTREES DETECTED` and paths only. Do not move, delete, repair, or prune them.

Main Repository and linked Worktrees must remain on the same runtime and file-system side. Windows Main uses Windows local linked Worktrees; Linux / FNOS Main uses Linux / FNOS local linked Worktrees. Separate machines should clone separately and synchronize through Git remotes rather than sharing linked-worktree metadata.

On Linux / FNOS, check Root existence and permissions before writes. If the current user cannot safely access the target, report the user, target, and permission issue. Never invoke `sudo`, `su`, recursive ownership changes, recursive `777` permissions, or ACL resets.

## Templates and status rules

The copied `AGENTS.md` requires the control plane to distinguish `READY` from `MERGED`; creating a PR never means that it was merged. Recommended states are `PLANNED`, `IN_PROGRESS`, `READY`, `INTEGRATING`, `CONFLICT`, `TEST_FAILED`, `BLOCKED`, `MERGED`, and `CANCELLED`.

`STATUS.md` is a concise current-state board, not a long log. Keep its sections and update them when task state, Worktree, conflict risk, PR state, integration baseline, blockers, or next actions change.

All text files, including Markdown, JSON, YAML, TypeScript, JavaScript, Python, PowerShell, and Shell files, must remain UTF-8. After editing Chinese text, inspect the diff and stop if replacement-character glyphs, repeated question-mark placeholders, or other mojibake appears. Do not rewrite an entire file merely to repair encoding.

## Explicit non-goals

Version 1 does not implement Issue scheduling, business-task creation, task Worktree lifecycle management, Conflict-aware Scheduler, Merge Train, Merge Coordinator, automatic PR merging, Web UI, or a database.
