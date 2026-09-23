---
name: devbot:refactor
description: "Use when renaming a PHP method, static method or property across a codebase and updating every call site. Triggers on 'rename this method', 'rename everywhere'."
---

# Refactor

Deterministic, agent-callable refactoring. Renames a PHP symbol and updates every
genuine reference — **no LLM in the edit path**. Dry run by default: nothing is
written unless you pass `--apply`.

The edit is delegated to the PHP ecosystem's own engine (Rector), run in a PHP
container against the project. The tool resolves the engine, renders a config
holding exactly one rename rule, runs it, and reports what changed.

## When to Use

| Situation                                             | Do this                                |
| ----------------------------------------------------- | -------------------------------------- |
| Rename a method and all its call sites                | `--op rename-method`                   |
| Rename a static method (declaration + calls)          | `--op rename-static-method`            |
| Rename a property (declaration + accesses)            | `--op rename-property`                 |
| See what a rename would touch before committing to it | run without `--apply` (the default)    |
| Confirm the symbol exists and where it is declared    | run the tool's `doctor` via the plugin |

## Contract

```
devbot-tools_refactor --lang php --op <op> \
  [--class <FQCN>] [--method <old> | --property <old>] \
  --to <new> [--apply] [--json] [--force]
```

- `--apply` writes the change. Without it you get a plan and the tree is untouched.
- Refuses `--apply` when the working tree has uncommitted changes to **tracked**
  files, unless `--force`. Untracked files are ignored.
- `--json` emits the response as JSON; the default is a short markdown report.

## Ops

| op                     | what it renames                  | Rector rule            |
| ---------------------- | -------------------------------- | ---------------------- |
| `rename-method`        | the declaration + instance calls | `RenameMethodRector`   |
| `rename-static-method` | the declaration + static calls   | `RenameMethodRector`   |
| `rename-property`      | the declaration + accesses       | `RenamePropertyRector` |

`rename-class` is **not supported yet**. Rector's `RenameClassRector` rewrites
references but leaves the class declaration and the PSR-4 filename behind, which
would emit broken code.

## Limits

- **Dynamic references are invisible** to static analysis: string callables
  (`[$obj, 'method']`), `__call`, container bindings, and variable method names
  are not renamed. Read the plan before applying.
- **The tool does not run your tests.** Run them yourself after applying — only
  your suite can prove the rename is right in your project's terms.
- The target project's own `vendor/bin/rector` is preferred (right version, right
  autoload). Otherwise a pinned Rector is installed into the dev-bot scratch dir.

## See also

- [Refactor tool reference](/tools/refactor) — engine policy and the plugin
  contract for adding another language.
