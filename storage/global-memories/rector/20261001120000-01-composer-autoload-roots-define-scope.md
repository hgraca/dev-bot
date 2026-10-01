---
date: 2026-10-01
keywords: ["rector", "composer", "withPaths", "autoload-dev", "scope"]
trigger-on: ["rector-scope", "rector-with-paths", "refactor-rename-scope"]
---

## Derive Rector's paths from composer autoload, not a hardcoded layout

A tool that renders its own Rector config and calls `withPaths()` must decide the
scope itself, and the tempting shortcut — a literal `app/` + `src/` list — silently
skips every other root the project declares. `composer.json` is the authoritative
answer: collect the directories named in `autoload` and `autoload-dev` (`psr-4`,
`psr-0`, and classmap directories), normalise each (`os.path.normpath`; reject
absolute paths, `..` escapes and anything rooted at `vendor/`), keep the ones that
exist, and fall back to `app/` + `src/` only when composer declares none. The
`autoload-dev` half is what a hardcoded list forgets, so `tests/` — a library's test
doubles and call sites — is never visited: renaming a method on an interface then
leaves its implementing test double holding the old name, a fatal error the tool
reports as success. Rector does not exclude `vendor/` by default, so the vendor
rejection is load-bearing too.
