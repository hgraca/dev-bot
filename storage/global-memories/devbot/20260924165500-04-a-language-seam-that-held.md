---
date: 2026-09-24
keywords: ["devbot", "module", "plugin", "language-seam"]
trigger-on: ["devbot-language-plugin-seam", "refactor-tool-add-language"]
---

## A language seam that held: self-describing plugins, core knows no op names

The `refactor` module's per-language seam was designed as "a new language = a new
directory", and it held under test: adding `langs/ts/` and `langs/py/` required
**zero changes to the core**. The core discovers `langs/<lang>/plugin.sh`, runs
its `meta` subcommand and reads the JSON — `lang`, `extensions`, `ops`,
`requires` (per-op required inputs) and `risks` — then validates the caller's
arguments against *that* and dispatches `plan`/`apply` with the request JSON on
stdio. Nothing in the core names an op: a user typing `--op rename-symbol` gets
"requires --to" from the TypeScript plugin's own metadata. Two lessons worth
keeping: give each plugin a `doctor` subcommand (it made engine resolution and
version reporting testable without running a refactor at all), and be honest that
the *internals* cannot be shared — the PHP plugin must render one single-rule
Rector config per step and invoke the engine repeatedly, while ts-morph and rope
each complete a rename in one run, so the shared part is the contract, never the
mechanics.
