---
date: 2026-10-01
keywords: ["refactor", "php", "scope", "composer", "rector"]
see: ["ADRs/20260923201723-prefer-project-own-engine-over-pinned-global.md"]
---

## The refactor tool's PHP scope derives from composer autoload, not a hardcoded root list

The PHP plugin used to pass Rector a literal `app/` + `src/` root list. That silently
excluded every other root a project declares — above all `autoload-dev`'s `tests/`, so a
rename that should sweep a library's test doubles and call sites left them behind while
reporting success. Scope is now derived from `composer.json`: the directories in
`autoload` and `autoload-dev` (PSR-4/PSR-0/classmap), normalised and contained to the
project, with `vendor/` never a root and `app/` + `src/` as the fallback when composer
declares none. The rejected alternatives were hardcoding `tests/` alongside `app`/`src`
(still wrong for any other layout) and an opt-in `--include-tests` flag (the hazard is
the caller not knowing to pass it). The same list is threaded to the plugin's own
scanners via `request.roots`, so declaration lookup, namespace resolution and the
reference scans walk exactly the directories Rector does.
