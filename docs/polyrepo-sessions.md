---
layout: page
title: Monorepo sessions
description: The owning-project contract for monorepo sessions.
nav_section: docs
---

# Monorepo sessions

A project with `monorepo: true` runs sessions that work **across** the managed
projects registered in the global config's `projects` array. Memory already
scopes itself that way (see [`devbot:memory-management`](/modules/agentic/memory));
this document defines the same contract for every other module.

## The rule

A monorepo session has no single "current project". Before any project-scoped
action:

1. **Resolve the owning project** from the files the action concerns — never
   from the session's working directory.
2. **Read that project's config**, project-first then global
   (`commit_memory`, `workflow`, `devbot_dir`, `datasources`, `modules`).
3. **Load that project's memory** before the first read or edit of the project's
   own files — resolution and config reads are exempt — once per project per
   session: `devbot tool project-memory <owner>` (see [Loading a child's active
   memory](#loading-a-childs-active-memory)).
4. **Run repo-scoped commands in that project** (`git -C <owner>`, `gh --repo`,
   `make` from `<owner>`, containers belong to `<owner>`).
5. **Write into the owner**, not into the monorepo. A change belongs to the
   monorepo only when it spans projects or is coordination-level (plans,
   cross-repo decisions, session notes).

In a non-monorepo project the owner of every path is the project itself, so
these rules are inert and the existing single-project behaviour stands.

## Resolving the owner

```bash
devbot tool project-for-path src/foo.ts          # table
devbot tool project-for-path src/foo.ts --json   # machine-readable
```

The tool maps the path to the **longest registered project** that contains it
(path-component boundaries respected), then prints that project's name, path,
whether it is a monorepo, and the resolved `commit_memory`, `workflow`,
`devbot_dir`, `datasources` and `modules`. It exits `3` when no registered
project contains the path — treat that as "the monorepo owns it" only if the
path is genuinely workspace-level; otherwise stop and ask.

The same resolution is available in Bash as
`_devbot_resolve_project_for_path <path> [default]` and in Python as
`src/_shared/resolve_project.py`.

## Loading a child's active memory

A monorepo session auto-loads only its **own** `AGENTS.md` and
`<devbot_dir>/memory/active/**/*.md`. A child's always-on context is not in scope
until it is loaded, and a child is not otherwise reachable except through
`search-memories --focus`, which is search rather than always-on context.

```bash
devbot tool project-memory src/foo.ts     # memory of the project that owns the path
```

The tool resolves the owning project (same rule as `project-for-path`), reads its
`devbot_dir`, and prints — labelled by file and in this order — `AGENTS.md` and/or
`CLAUDE.md` when present, then `<devbot_dir>/memory/active/**/*.md` recursively in
sorted order. A symlinked memory file is still read — a project may link shared
module memory in deliberately — and is labelled with its resolved target, so the
scope statement stays accurate. It exits `3` for a path that belongs to no registered project —
there is no child memory to load, so continue with the monorepo's own — and
prints an explicit "no active memory" notice when the project has none.

Run it **once per project per session**, at the point work first reads or writes
files there — not at session start for every project, and not again for a project
already loaded. The memory it prints is scoped to that project:

- it never sets the rules for a sibling project;
- it never displaces the monorepo's own active memory for coordination work;
- it is never copied into another project's vault.

Where a child rule conflicts with the monorepo's, the child's rule wins while
the work is in that child. Subagents sent into a child are told to run the tool
themselves as their first step — a `@scout` report about the child does not stand
in for it.

## Module contracts

### Tier 1 — actions that currently target the wrong repository

| Module                             | Contract                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **git**                            | Resolve the owner's `workflow` first (`worktree.sh enabled --project <owner>`). Under `worktrees`, the worktree is created in the **owning project** and commits are made with `git -C <worktree>`; under `trunk`, no worktree or branch is created — commits go on the owner's default branch with `git -C <owner>`. Every worktree subcommand that needs a repository — `create`, `enabled`, `list`, `path`, `push`, `remove` — takes `--project <dir>`, and `create`/`enabled` refuse a monorepo root (even with commits); a repository with no commits asks for an initial commit. `git-report` takes `--cwd <dir>`. |
| **github**                         | PRs, reviews, releases and `gh` reads target the **owner's** repository (`gh --repo <owner-slug>`). The monorepo root has no remote, so `gh` run from it resolves nothing.                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **datasources**                    | The available datasource tools come from the **session project's** selection. A monorepo that declares `datasources: []` has none — the owner's selection must be resolved explicitly, and a query must still name the datasource it targets.                                                                                                                                                                                                                                                                                                                                                                            |
| **devteam**                        | Every plan task, implementation step and review names its owning project. Commits and PRs are per owner; a single changeset never spans two repositories.                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| **dev / makefile, shell-strategy** | `make`, test runners and container commands run from the **owner's** directory and against the **owner's** container. The monorepo's Makefile, if any, is not the project's.                                                                                                                                                                                                                                                                                                                                                                                                                                             |

### Tier 2 — tools that take a path nobody passes

| Module                                                          | Contract                                                                                                                                                                                         |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **codebase-memory / codebase-index**                            | Index and query **one project at a time**, using the owner path. An index root that does not cover the owner is a configuration problem to surface, not to work around by indexing the monorepo. |
| **explore / create-project-report**                             | A project description describes **one project**. In a monorepo, generate the owner's description on demand; do not write a child's description into the monorepo's vault.                        |
| **forensics, docs/use-case-map, docs/impact-diagram, refactor** | The repo / project-root argument is the **owner** derived from the files in play. `forensics` takes `<repo>`; the diagram tools and `refactor` take `--project-root`.                            |
| **k8s, tree, search-code**                                      | Path arguments are resolved inside the **owner**; a `--changed`/diff mode runs with `git -C <owner>`.                                                                                            |
| **memory work folders**                                         | A work item that concerns one project lives in that project's `work/` folder; only cross-project coordination work lives in the monorepo's.                                                      |

### Tier 3 — unaffected

`guards` (global, path-matched), `auto-recover` (session-scoped), `format-*`
(operate on given paths), `agent-communication`, `list-projects` (already lists
the registry), module lifecycle scripts (`init`, `reset`, `up`, `reinit`).

## Worktrees in a monorepo

The monorepo root is a container for independent sibling repositories — often with no commits
of its own. `worktree.sh create` refuses a monorepo root regardless of its history, and refuses
a repository with no commits, instead of failing halfway through. The rule is:

```bash
owner="$(devbot tool project-for-path "$file" --json | jq -r .path)"
bash src/agentic/git/tools/worktree.sh create feat/thing --project "$owner"
```

The same `--project` reaches every other subcommand that needs a repository, so the monorepo root
can list, locate, push and remove a child's worktrees — `push` and `remove` included. Without it
they resolve the monorepo's own repository and report `no worktree is registered for '<branch>'`;
that message means "wrong repository", not "no such worktree". `<branch>` is always the branch
name, never the worktree directory slug, and running the tool with the child's main checkout as the
working directory works as well as passing `--project`.

```bash
bash src/agentic/git/tools/worktree.sh push   feat/thing --project "$owner"
bash src/agentic/git/tools/worktree.sh remove feat/thing --project "$owner"
```

## Testing

Each code change that implements a contract above carries a test:

- the resolver: owner selection, longest-prefix, unregistered path, project-first
  config resolution;
- the memory loader: owner selection, the owner's own `devbot_dir`, `AGENTS.md`
  and `CLAUDE.md`, nested `active/` files in sorted order, an empty project and an
  unregistered path;
- the worktree: `--project` targets the given repo, and a repository with no
  commits is refused with a `FATAL:`.

Instruction-only contracts are stated in the module's skill file. The documentation pages of the
modules named in the tables above — git, github, datasources, devteam, dev, codebase-memory,
codebase-index, explore, forensics, docs, refactor, k8s, tree and memory — link back to this page.
Modules outside those tables are unaffected and do not carry the contract.

## See also

- [Configuration — `monorepo`](/configuration#monorepo)
- [Memory](/modules/agentic/memory) — the read/write scoping this document extends
- [Git worktrees](/modules/agentic/git) — worktree creation and teardown
