---
date: 2026-10-02
keywords: ["graphify", "graphifyignore", "negation", "scoping", "update"]
aliases: ["leading-slash negation", "re-include src", "index nothing"]
supersedes: ["graphify/20260515000000-01-graphify-update-path-arg-controls-output-dir-not-just-scope.md"]
---

## graphify `.graphifyignore` negations must be bare (`!src`, not `!/src`)

graphify's ignore parser (installed 0.8.35, `detect._parse_gitignore_line`) does not anchor a
leading-slash negation the way git does: a `!/src` line re-includes **nothing**, so a scope
block of `/*` + `!/src` silently indexes zero files — and `graphify update .` then exits
non-zero with "No code files found" instead of writing an empty graph. The bare form works:
`/*` + `!src` (+ `!app` when both exist) indexes only root `src`/`app`; gitignore
parent-exclusion still keeps nested `vendor/*/src` out. Always confirm a new scope pattern
with a real `graphify update . --no-cluster` on a throwaway fixture before trusting it.
