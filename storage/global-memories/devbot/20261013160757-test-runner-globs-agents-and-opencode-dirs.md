---
date: 2026-10-13
keywords: ["devbot", "vitest", "test-runner", "worktrees", "opencode"]
trigger-on: ["devbot-test-runner-directory-excludes"]
---

## A glob-based test runner picks up devbot's `.agents/` and `.opencode/` directories

In a devbot-managed repo, test runners that discover files by glob (Vitest's default
`**/*.{test,spec}.*`) also scan the devbot working state: `.agents/worktrees/<branch>/…` (linked git
worktrees — including a stale merged one) and `.opencode/**` plugin tests. Those produce phantom
failures: a full run reported "4 failed / 1 failed test" while every failure lived in an untracked
agent directory and the project's own `src/` suite was green. The gap is silent and reads as a real
regression.

Fix: add explicit excludes to the runner config, e.g. in `vitest.config.ts`:

```ts
test: { exclude: ["**/node_modules/**", "**/.agents/**", "**/.opencode/**"] }
```

A path *filter* does not help — `vitest run src/` still matches `.agents/worktrees/<branch>/src/…`
because the substring `src/` appears in the path. Exclude by directory. Diagnose by checking whether
the failing file paths start with `.agents/` or `.opencode/` before believing a regression; the same
class of pollution hits any glob-based tool (coverage, linters, snapshot writers).
