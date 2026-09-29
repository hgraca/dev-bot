---
date: 2026-09-29
keywords: ["opencode", "formatter", "format-md", "prettier", "hooks"]
---

# opencode's native `formatter` config is a smaller version of dev-bot's format-* hooks

opencode can drive formatters from config — the `formatter` key, with per-formatter
`command`, `extensions`, and `environment`, plus built-ins for prettier, biome and
others — which overlaps dev-bot's `format-md` / `format-json` / `format-yml`
modules. The native key is strictly smaller, and the two cannot usefully coexist:
enabling native double-formats and re-introduces the format-on-create path dev-bot
deliberately excluded (`skipOnCreate`; see the audit-47/50 note).

- **Create-skip**: dev-bot sets `skipOnCreate: true`; native formatters normalize
  on create too, which is the audit-48 corruption class.
- **Gate**: native prettier requires `prettier` as a project **dependency**;
  dev-bot gates on a prettier **config file** (`.prettierrc*`, `prettier.config.*`,
  or a `package.json` key) and installs prettier globally — a different set of
  projects gets formatted.
- **Harness**: native is opencode-only; dev-bot's hook manifests are read by both
  opencode and claudecode.
- **Tooling**: native has no manual / pipe / batch invocation; dev-bot exposes
  `format-*` as callable tools (a path, pipe mode, `prettier --write` batch).
- **Guards**: dev-bot adds the re-read guard, the rewrite-echo tracker, burst
  coalescing, and `--ignore-path /dev/null` so `.agents/**` is not skipped.
