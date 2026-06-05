---
name: git-report
description: "Return a git state snapshot: current branch, default branch, recent commits, working-tree status, staged diff, commits unique to the current branch, and index integrity check. Use this skill whenever you need to understand what has changed before committing, reviewing, or planning next steps."
---

# Git Report

Snapshots the current git state and returns a structured Markdown report. Use before committing, reviewing changes, or planning next steps.

## When to Use

| Situation                                                    | Tool                |
| ------------------------------------------------------------ | ------------------- |
| Need to understand what changed before committing            | **Git Report**      |
| Need to review staged vs unstaged changes                    | **Git Report**      |
| Need recent commit history in session context                | **Git Report**      |
| Need to check which commits are unique to the current branch | **Git Report**      |
| Need to verify git index integrity (missing objects)         | **Git Report**      |
| Need to know just the current branch name                    | Git Report          |
| Need to see a live file diff while working                   | `git diff` via Bash |

## How to Call

```
git-report
```

| Parameter     | Required | Description                                    |
| ------------- | -------- | ---------------------------------------------- |
| (none)        | —        | Default output: Markdown, 10 recent commits    |
| `--log-count` | no       | Number of recent commits to show (default: 10) |

No format parameters — output is always Markdown.

## Output Sections

| Section                              | Content                                                                             |
| ------------------------------------ | ----------------------------------------------------------------------------------- |
| **Git Report** header                | Current branch, default branch (local + remote)                                     |
| **Recent Commits**                   | `git log --oneline -<count>` output                                                 |
| **Status**                           | `git status` output                                                                 |
| **Staged Changes (summary)**         | `git diff --staged --stat` output                                                   |
| **Staged Changes (full diff)**       | `git diff --staged` output (in diff code block)                                     |
| **Commits Unique to Current Branch** | Commits on the current branch not present on the default branch (`<default>..HEAD`) |
| **Index Integrity**                  | Missing objects from `git fsck --full`                                              |

## Usage Guidelines

- Always **commit or stash** before running `git-report` — it reads the working tree as-is
- Use the default 10 commits for most sessions; increase with `--log-count` for deeper history
- The `fsck_missing` section warns about missing git objects — address only if non-empty

## Examples

```
git-report
# → Full git state report with last 10 commits

git-report --log-count 3
# → Same report, only 3 recent commits shown
```
