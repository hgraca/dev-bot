---
date: 2026-10-02
keywords: ["devbot", "format-yml", "prettier", "prettierignore", "hook"]
aliases: ["file.edited hook reformats yaml", "format hook rewrites single quotes", "hook churn on dependabot.yml"]
trigger-on: ["format-yml-hook", "dependabot-yml-edit"]
---

## The format-yml hook reformats YAML even when the repo's .prettierignore excludes it

The devbot `format-yml` hook runs prettier over a YAML file after every `edit`/`write` and does **not** honour the repo's `.prettierignore`. In repos that ship a `.prettierrc` with `singleQuote: true` (observed: `core`, `portal`, `positioning-activities-portal`) editing one line of `.github/dependabot.yml` returns a **whole-file rewrite** — every double quote becomes single and values reflow. `portal` and `positioning-activities-portal` explicitly list `*.yml` in `.prettierignore` (their prettier scripts cover only `src/**/*.{ts,tsx}` and `*.json`), so the hook's output contradicts the project's own convention; the churn is invisible to the hook's success report and only `git diff` reveals it. Workaround: `git checkout -- <file>` then re-apply the change with a bash in-place edit (`perl -pi -e 's/old/new/' <file>`), which does not fire the `file.edited` hook, and confirm `git diff` is one or two lines. Same failure class as the project-local `learnings/20260924233800-format-hooks-expand-minified-content-files.md`, but cross-project and caused specifically by the ignore file being skipped.
