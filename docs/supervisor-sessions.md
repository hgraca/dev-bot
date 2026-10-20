---
layout: page
title: Supervisor sessions
description: The owning-project contract for supervisor sessions.
nav_section: docs
---

# Supervisor sessions

A project with `supervisor: true` runs sessions that work **across** the managed
projects registered in the global config's `projects` array. Memory already
scopes itself that way (see [`devbot:memory-management`](/modules/agentic/memory));
this document defines the same contract for every other module.

## The rule

A supervisor session has no single "current project". Before any project-scoped
action:

1. **Resolve the owning project** from the files the action concerns — never
   from the session's working directory.
2. **Read that project's config**, project-first then global
   (`commit_memory`, `worktrees`, `devbot_dir`, `datasources`, `modules`).
3. **Run repo-scoped commands in that project** (`git -C <owner>`, `gh --repo`,
   `make` from `<owner>`, containers belong to `<owner>`).
4. **Write into the owner**, not into the supervisor. A change belongs to the
   supervisor only when it spans projects or is coordination-level (plans,
   cross-repo decisions, session notes).

In a non-supervisor project the owner of every path is the project itself, so
these rules are inert and the existing single-project behaviour stands.

## Resolving the owner

```bash
devbot tool project-for-path src/foo.ts          # table
devbot tool project-for-path src/foo.ts --json   # machine-readable
```

The tool maps the path to the **longest registered project** that contains it
(path-component boundaries respected), then prints that project's name, path,
whether it is a supervisor, and the resolved `commit_memory`, `worktrees`,
`devbot_dir`, `datasources` and `modules`. It exits `3` when no registered
project contains the path — treat that as "the supervisor owns it" only if the
path is genuinely workspace-level; otherwise stop and ask.

The same resolution is available in Bash as
`_devbot_resolve_project_for_path <path> [default]` and in Python as
`src/_shared/resolve_project.py`.

## Module contracts

### Tier 1 — actions that currently target the wrong repository

| Module                             | Contract                                                                                                                                                                                                                                                                                                                                        |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **git**                            | The worktree is created in the **owning project**, using the owner's `worktrees` setting, and commits are made with `git -C <worktree>`. `worktree.sh create` and `enabled` take `--project <dir>` and refuse a supervisor root (even with commits); a repository with no commits asks for an initial commit. `git-report` takes `--cwd <dir>`. |
| **github**                         | PRs, reviews, releases and `gh` reads target the **owner's** repository (`gh --repo <owner-slug>`). The supervisor root has no remote, so `gh` run from it resolves nothing.                                                                                                                                                                    |
| **datasources**                    | The available datasource tools come from the **session project's** selection. A supervisor that declares `datasources: []` has none — the owner's selection must be resolved explicitly, and a query must still name the datasource it targets.                                                                                                 |
| **devteam**                        | Every plan task, implementation step and review names its owning project. Commits and PRs are per owner; a single changeset never spans two repositories.                                                                                                                                                                                       |
| **dev / makefile, shell-strategy** | `make`, test runners and container commands run from the **owner's** directory and against the **owner's** container. The supervisor's Makefile, if any, is not the project's.                                                                                                                                                                  |

### Tier 2 — tools that take a path nobody passes

| Module                                                          | Contract                                                                                                                                                                                           |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **codebase-memory / codebase-index**                            | Index and query **one project at a time**, using the owner path. An index root that does not cover the owner is a configuration problem to surface, not to work around by indexing the supervisor. |
| **explore / create-project-report**                             | A project description describes **one project**. In a supervisor, generate the owner's description on demand; do not write a child's description into the supervisor's vault.                      |
| **forensics, docs/use-case-map, docs/impact-diagram, refactor** | The repo / project-root argument is the **owner** derived from the files in play. `forensics` takes `<repo>`; the diagram tools and `refactor` take `--project-root`.                              |
| **k8s, tree, search-code**                                      | Path arguments are resolved inside the **owner**; a `--changed`/diff mode runs with `git -C <owner>`.                                                                                              |
| **memory work folders**                                         | A work item that concerns one project lives in that project's `work/` folder; only cross-project coordination work lives in the supervisor's.                                                      |

### Tier 3 — unaffected

`guards` (global, path-matched), `auto-recover` (session-scoped), `format-*`
(operate on given paths), `agent-communication`, `list-projects` (already lists
the registry), module lifecycle scripts (`init`, `reset`, `up`, `reinit`).

## Worktrees in a supervisor

The supervisor root is a container for independent sibling repositories — often with no commits
of its own. `worktree.sh create` refuses a supervisor root regardless of its history, and refuses
a repository with no commits, instead of failing halfway through. The rule is:

```bash
owner="$(devbot tool project-for-path "$file" --json | jq -r .path)"
bash src/agentic/git/tools/worktree.sh create feat/thing --project "$owner"
```

## Testing

Each code change that implements a contract above carries a test:

- the resolver: owner selection, longest-prefix, unregistered path, project-first
  config resolution;
- the worktree: `--project` targets the given repo, and a repository with no
  commits is refused with a `FATAL:`.

Instruction-only contracts are stated in the module's skill file. The documentation pages of the
modules named in the tables above — git, github, datasources, devteam, dev, codebase-memory,
codebase-index, explore, forensics, docs, refactor, k8s, tree and memory — link back to this page.
Modules outside those tables are unaffected and do not carry the contract.

## See also

- [Configuration — `supervisor`](/configuration#supervisor)
- [Memory](/modules/agentic/memory) — the read/write scoping this document extends
- [Git worktrees](/modules/agentic/git) — worktree creation and teardown
