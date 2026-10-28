---
title: "GitHub"
description: "Create a repository, open a pull request from a branch or work one locally, and scaffold a GitHub Pages docs site."
commands: ["gh-create-repo", "gh-address-review", "gh-make-review", "gh-create-pr"]
skills: ["gh-create-repo", "gh-create-pr", "gh-pages"]
tools: ["gh-configure-repo"]
---

Create a repository, open a pull request from a branch, or pull one down and work on it locally —
review its changeset, or address the comments it already has.

## What it does

- **`gh-create-repo`** — creates a repository with a README-only first commit, then protects the default
  branch with a ruleset: a mandatory pull request, with a bypass policy the caller chooses. Merged
  head branches are deleted on merge.
- **`gh-create-pr`** — opens a pull request from a branch onto the default branch.
- **`gh-make-review`** — checks out a PR and code-reviews its changeset locally.
- **`gh-address-review`** — reads a PR's review comments and addresses them locally.
- **`gh-pages`** — scaffolds a Jekyll documentation site deployed to GitHub Pages: a project site, or
  the org-level umbrella that indexes every project's docs site.

`gh-configure-repo` resets a repository that already exists to the same standard: the pull-request and
merge settings, merged-branch cleanup, and one default-branch ruleset that carries the status checks
already in force. Legacy classic protection is kept unless `--remove-classic-protection` is passed —
removing it is what lets the ruleset's override take effect. It is a dry run by default, writes only
with `--apply`, and is idempotent.

`gh-create-repo`, `gh-configure-repo` and `gh-create-pr` are the module's writes to GitHub: creating a
repository and its ruleset, reconfiguring an existing one, and creating a pull request plus the
`git push -u origin <branch>` a never-pushed branch needs. The review commands keep their output local
— no replies, comments or resolutions are ever posted back.

## Configuration

Needs the `gh` CLI and `jq`, authenticated on the machine; the module's lifecycle scripts install and
update both. No project configuration is required.

## See also

- [Supervisor sessions](/supervisor-sessions) — how this module scopes itself to the owning project
- [Git](/modules/agentic/git) — the commit and history skills these commands lean on
- [Self-improvement](/modules/agentic/self-improvement) — improving what the reviewer catches
