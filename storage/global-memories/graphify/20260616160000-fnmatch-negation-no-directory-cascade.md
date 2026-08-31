---
date: 2026-06-16
keywords: ["graphify", "fnmatch", "gitignore", "graphifyignore"]
---

## fnmatch negation patterns don't support gitignore directory-cascade semantics

graphify's `detect.py` uses Python's `fnmatch` for anchored pattern matching in `.graphifyignore`. The pattern `/*` matches everything (including nested paths like `app/Models/User.php`), but `!/app` only matches the literal path `app` — NOT `app/anything/else.php`. Since `fnmatch.fnmatch("app/Models/User.php", "app")` returns `False`, ALL files remain excluded after `/*` regardless of `!` negation patterns. Same bug applies to `!/src`.

**Workaround**: Do not use `/*` + `!` negation patterns in `.graphifyignore`. Instead, rely on `.gitignore` content (merged into `.graphifyignore` by the hook runner) for framework exclusions like `vendor/`, `node_modules/`. The only graphify-specific exclusion needed is `graphify-out` (its own output directory). If you need to scope graphify to specific directories, use `--include` paths instead of `!` negation.
