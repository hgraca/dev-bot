---
date: 2026-09-24
keywords: ["rector", "configuration", "only", "php-l"]
trigger-on: ["rector-multiple-rules-one-config", "rector-only-repeat"]
---

## Two configured rules in one Rector config do not compose — run one rule per invocation

Registering two rules in a single `rector.php` and expecting both to fire does not
work. With a usages rule (`RenameFunctionRector`) and a declaration-renaming rule
registered together, the run renamed the declaration and **left every call site
untouched** — and the behaviour was identical with the rules in either order, so
it is not ordering. The mechanism fits the evidence: the declaration rename
invalidates the reflection a usages rule resolves calls through, so the second
rule silently finds nothing. Repeating `--only` does not help either — the CLI
keeps only the last value, so `--only A --only B` applies just `B`. The fix is
structural: render one single-rule config per step and invoke Rector once per
rule. Two related traps on the same command: a config error is reported as stdout
`{"fatal_errors": [...]}` with exit 1 and must be surfaced explicitly, and a rule
configuration that never matches fails **silently** (zero changed files), so a
plan that exits clean is not proof the rule applied. Because generated config is
code, validate it — `php -l` inside the container — since substring assertions
happily accept unbalanced parentheses that make the config unparseable.
