---
name: project-workspace-init
description: Safely bootstrap a Git main workspace and its agent control plane. This skill is initialization-only and does not manage daily branches, tasks, or worktrees.
license: MIT
metadata:
  version: "2.0.0"
  platforms: "Windows, Linux, FNOS"
---

# Project Workspace Init

## 1. Purpose and Trigger

This skill ONLY applies when:

- The user explicitly asks to initialize / bootstrap a project workspace; or
- The system is performing the first workspace bootstrap for a project that is not initialized yet.

Do NOT use this skill for normal feature development, bug fixes, Issue implementation,
PR work, documentation changes, testing, release work, normal branch creation, task
worktree creation, worktree reuse or cleanup, existing-project repository discovery, or
other project operations.

Its lifecycle ends when bootstrap returns a result. Once initialization is complete,
this skill takes no part in subsequent project work.

## 2. Required Inputs

The user must explicitly provide both values for first-time bootstrap:

```text
Repository: <GitHub URL or owner/repo>
Workspace Root: <explicit absolute path>
```

Never infer either value from the current directory, Git remote, environment, history,
neighboring directories, or project files. If either is missing, return `STATUS: NEEDS_INPUT`,
list only the missing or invalid value(s), and make no filesystem or Git changes.

`NEEDS_INPUT` is limited to:

- Missing `Repository` or `Workspace Root`;
- Invalid / ambiguous `Repository`, non-absolute `Workspace Root`, or an explicit user-stated conflict between the two inputs.

Supported Repository forms:

- `https://github.com/<owner>/<repo>`
- `https://github.com/<owner>/<repo>.git`
- `<owner>/<repo>`

Reject a bare repository name because it is ambiguous. `Workspace Root` must be an
explicit absolute path to an existing, accessible directory. Reject relative paths, `~`,
`.`, and `..` rather than rewriting them.

Run the platform bootstrap script from this skill package:

```powershell
.\scripts\init-workspace.ps1 -Repository <repository> -Root <absolute-path>
```

```sh
./scripts/init-workspace.sh --repository <repository> --root <absolute-path>
```

## 3. Already Initialized

Before remote probing or any write, check whether the requested target is already
initialized. It is initialized only when all of these hold:

- `<Workspace Root>/<repo>/` exists as a Git Main Workspace and its `origin` identifies
the requested Repository;
- `<Workspace Root>/<repo>_base/` exists and is not a Git repository;
- `<repo>_base/AGENTS.md` and `<repo>_base/STATUS.md` are regular files;
- The `<repo>_base/status/`, `integration/`, and `worktrees/` directories exist.

If all checks pass, return this terminal result and stop:

```text
STATUS: ALREADY_INITIALIZED
Repository: <owner>/<repo>
Main Workspace: <absolute path>
Control Plane: <absolute path>
```

This path performs no writes, remote operations, task discovery, or other project work.
Do not continue after `ALREADY_INITIALIZED`. Do not inspect an Issue, infer a task,
create a branch or worktree, update task status, or run project orchestration.

## 4. Repository State

For a target that is not already initialized, probe the explicitly supplied remote before
creating the target. Classify it as exactly one of:

- `REPOSITORY_NOT_FOUND`: the repository is missing, inaccessible, or cannot be reliably
confirmed. Stop with `STATUS: NEEDS_ATTENTION`; do not create workspace directories.
- `EMPTY_REPOSITORY`: the repository is confirmed to exist but has no branch, default
branch, or commit.
- `EXISTING_REPOSITORY`: the repository has commits and a readable remote default branch.

Do not treat an inaccessible remote as an empty repository.

## 5. Existing Repository Bootstrap

For `EXISTING_REPOSITORY`:

1. Read the remote's actual advertised default branch; do not assume it is named `main`.
2. Clone the supplied Repository to `<Workspace Root>/<repo>` if that path does not exist.
3. Verify the Main Workspace Git root, `origin`, current branch against the remote default
branch, and clean working-tree state.
4. If a pre-existing Main Workspace conflicts with the requested Repository, branch, or
safety checks, stop with `STATUS: NEEDS_ATTENTION`; never repair it automatically.

## 6. Empty Repository Bootstrap

For `EMPTY_REPOSITORY`, when `<Workspace Root>/<repo>` does not exist:

1. Run `git init -b main` at that path.
2. Set `origin` to the explicitly supplied Repository.
3. Verify the Git root, `main` branch, matching `origin`, and clean working-tree state.
4. Do not create a commit, README, placeholder file, or push.

A local `main` without `origin/main` is expected. Report `Remote State: EMPTY_REPOSITORY`
and `Remote main: not created yet`.

## 7. Control Plane Creation

Create the Agent Control Plane beside the Main Workspace:

```text
<Workspace Root>/
├── <repo>/
└── <repo>_base/
    ├── AGENTS.md
    ├── STATUS.md
    ├── status/
    ├── integration/
    └── worktrees/
```

The Main Workspace is the formal Git repository. The Control Plane is not a Git
repository. Create only missing directories and missing templates. Use
`templates/AGENTS.md` and `templates/STATUS.md` as initial content.

`STATUS.md` records initialization-level facts only:

- Repository;
- Main Workspace;
- Control Plane Root;
- Workspace Version;
- Initialization Status.

This skill never maintains task or development state.

## 8. Safety and Idempotency

- Preserve every existing file and directory, including existing `AGENTS.md` and
  `STATUS.md`; never replace user data.
- Never repeat a clone, reset, clean, stash, checkout over user data, commit, or push to
  force initialization through.
- Do not rewrite an existing `.gitignore`, alter the repository's file-tracking policy,
  generate a technology stack, or overwrite source code.
- If a destination contains conflicting or unsafe data, Main Workspace verification
  fails, permissions are insufficient, Git is unavailable, remote state is uncertain,
  or a script fails, stop with `STATUS: NEEDS_ATTENTION` and explain the reason.
- Initialization must be safe to retry. A complete target returns `ALREADY_INITIALIZED`
  without writes; incomplete targets may only receive missing bootstrap directories and
  templates after all safety checks pass.

## 9. Result

Return one of these outcomes:

- `STATUS: SUCCESS` — first bootstrap completed; report Repository, Main Workspace,
  Control Plane, remote state, branch, origin, and working-tree verification.
- `STATUS: ALREADY_INITIALIZED` — the requested complete structure already exists; report
  Repository, Main Workspace, and Control Plane, then exit.
- `STATUS: NEEDS_INPUT` — a required bootstrap input is missing or invalid; do not mutate
  anything.
- `STATUS: NEEDS_ATTENTION` — a safety, permission, Git, remote, or initialization failure
  requires user attention; do not make destructive repairs.
