---
date: 2026-11-11
keywords: ["shell", "bash", "functions"]
aliases: ["dotted function name", "migration_up-1.15.0"]
---

## Bash allows dots in function names only with the `function` keyword

`function migration_up-1.15.0 { ...; }` (unquoted, `function` keyword form) defines a function whose name contains dots; `migration_up-1.15.0() { ...; }` is a syntax error, and `function "migration_up-1.15.0"` fails with "not a valid identifier". The dotted name is still discoverable with `compgen -A function` or `declare -F "migration_up-1.15.0"` and callable through a variable (`fn=migration_up-1.15.0; "$fn" arg`). Hyphens work in all three forms. This is the trick behind version-named migration functions; if a tool (shellcheck, an editor, a framework) rejects the dotted form, fall back to underscores in the identifier and document the version mapping.
