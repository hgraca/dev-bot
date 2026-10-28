---
date: 2026-10-28
keywords: ["prettier", "format-hooks", "format-md", "format-json", "format-yml", "biome"]
see: ["ADRs/20260926180002-format-hooks-gate-on-declared-prettier.md"]
---

## The `format-*` hooks fall back to dev-bot's default prettier config

The `format-md`/`format-json`/`format-yml` hooks install into every project dev-bot scaffolds, so
they meet projects that never adopted prettier. ADR
`20260926180002-format-hooks-gate-on-declared-prettier.md` made them run only where the project
declares prettier, which left such a project's files unformatted and turned a `--check` run into
exit 2 with "no prettier config" — a gate that cannot verify, reported as a failure.

A run now always formats. It uses the project's own configuration when it declares one — a
`.prettierrc*`, a `prettier.config.*`, or a `prettier` key in `package.json`, resolved upward from
the target — and dev-bot's shipped `src/_shared/prettier.default.json` when it does not. The shipped
file is currently `{}`, i.e. prettier's own defaults; it exists so dev-bot has one place to pin
settings that apply everywhere.

Resolution differs by run shape. A single-file run resolves `--config` from that file. A directory
batch is split by configuration: the files whose project declares prettier go to prettier in one
invocation without the flag (their own config resolves), the rest in a second invocation with
dev-bot's default. One `--config` applies to the whole invocation, so a single pass would either
override a nested project's settings — leaving `--check` red straight after a successful write — or
drop dev-bot's defaults for the files that declare none. `--force` on `format-json` is kept as an
accepted no-op for callers written against the old gate (`devbot reinit`/`up`). Pipe mode is
unchanged: there is no project to consult.

Accepted trade-off: a project formatted by something else (Biome, say) that declares no prettier
config is now formatted by prettier — the regression the old gate was introduced to prevent. The
opt-out is disabling the module (`"format-md": false` under `modules` in `.devbot.project.jsonc`);
a project that wants different settings declares a prettier config, which wins over the fallback
apart from the parser, print width and ignore path the tools pin on the command line.
