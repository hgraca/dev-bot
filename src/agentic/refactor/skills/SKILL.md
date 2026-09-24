---
name: devbot:refactor
description: "Use when renaming a PHP or TypeScript symbol across a codebase and updating every call site, or when asking what to refactor. Triggers on 'rename this method', 'rename everywhere', 'what should I refactor'."
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
  [--class <FQCN>] [--from <old> | --method <old> | --property <old>] [--namespace <ns>] \
  --to <new> [--apply] [--json] [--force]
```

- `--apply` writes the change. Without it you get a plan and the tree is untouched.
- Refuses `--apply` when the working tree has uncommitted changes to **tracked**
  files, unless `--force`. Untracked files are ignored.
- `--json` emits the response as JSON; the default is a short markdown report.

## Ops

| op                      | what it renames                              | Rector rule                   |
| ----------------------- | -------------------------------------------- | ----------------------------- |
| `rename-method`         | the declaration + instance calls             | `RenameMethodRector`          |
| `rename-static-method`  | the declaration + static calls               | `RenameMethodRector`          |
| `rename-annotation`     | a docblock annotation on a class             | `RenameAnnotationRector`      |
| `rename-property`       | the declaration + accesses                   | `RenamePropertyRector`        |
| `rename-function`       | a free function: declaration + calls         | `RenameFunctionRector`        |
| `rename-class`          | the declaration + references + the file move | `RenameClassRector`           |
| `rename-string`         | string literals (no declaration exists)      | `RenameStringRector`          |
| `rename-class-constant` | a class constant: declaration + fetches      | `RenameClassConstFetchRector` |
| `move-class`            | a class's namespace + its file (name kept)   | `RenameClassRector`           |
| `rename-constant`       | a global constant: declaration + uses        | `RenameConstantRector`        |

### Languages

`--lang` selects the plugin. The core knows **no op names** — it discovers
`langs/<lang>/plugin.sh` and validates against whatever that plugin declares — so
adding a language is additive.

| lang  | ops                                                  | engine                        |
| ----- | ---------------------------------------------------- | ----------------------------- |
| `php` | the ops above                                        | Rector, in a PHP container    |
| `py`  | `rename-symbol` (`--from`/`--to`, optional `--file`) | rope, in a Python container   |
| `ts`  | `rename-symbol` (`--from`/`--to`, optional `--file`) | ts-morph, in a Node container |

The TypeScript plugin needs a one-time `bash langs/ts/plugin.sh provision`
(npm installs ts-morph into the shared scratch dir; `langs/py/plugin.sh provision` does the same for rope); `doctor` reports whether it
is present. ts-morph resolves the symbol through the TypeScript compiler, so one
run renames the declaration and every reference — no per-rule steps.

## Cleanup ops

These take no `--from`/`--to`: they run across the whole scope and change
whatever they find. **Read the plan before applying** — they are not targeted at
one symbol.

| op                                      | what it does                                                | Rector rule                              |
| --------------------------------------- | ----------------------------------------------------------- | ---------------------------------------- |
| `remove-unused-private-methods`         | deletes private methods nothing calls                       | `RemoveUnusedPrivateMethodRector`        |
| `remove-unused-private-properties`      | deletes private properties nothing reads                    | `RemoveUnusedPrivatePropertyRector`      |
| `privatize-final-class-methods`         | tightens `public`/`protected` to `private` on final classes | `PrivatizeFinalClassMethodRector`        |
| `privatize-final-class-constants`       | tightens `protected` to `private` on final classes          | `PrivatizeFinalClassConstantRector`      |
| `remove-unused-private-class-constants` | deletes class constants nothing reads                       | `RemoveUnusedPrivateClassConstantRector` |
| `remove-unused-constructor-params`      | deletes constructor parameters nothing uses                 | `RemoveUnusedConstructorParamRector`     |
| `remove-unused-promoted-properties`     | deletes promoted properties nothing reads                   | `RemoveUnusedPromotedPropertyRector`     |
| `privatize-final-class-properties`      | tightens `protected` to `private` on final classes          | `PrivatizeFinalClassPropertyRector`      |

`rename-class` additionally **moves the file** (`Widget.php` → `Gadget.php`):
Rector rewrites the declaration and the references but moves no files, and a
PSR-4 autoloader keys on the file name.

## Limits

- **Dynamic references are invisible** to static analysis: string callables
  (`[$obj, 'method']`), `__call`, container bindings, and variable method names
  are not renamed. Read the plan before applying.
- **The tool does not run your tests.** Run them yourself after applying — only
  your suite can prove the rename is right in your project's terms.
- The target project's own `vendor/bin/rector` is preferred (right version, right
  autoload). Otherwise a pinned Rector is installed into the dev-bot scratch dir.

## Refactor candidates (advisory)

When the question is _what_ to refactor rather than _how_, query the codebase
graph (`codebase-memory`). These properties have no equivalent in the rename
tools, and the queries below are validated against a real index.

**Hotspots** — complexity, plus the hidden loops it misses:

```cypher
MATCH (f:Function)
WHERE f.complexity >= 10 OR f.transitive_loop_depth >= 2
RETURN f.qualified_name AS qn, f.complexity, f.transitive_loop_depth AS loop_depth,
       f.linear_scan_in_loop AS scans, f.param_count AS params
ORDER BY complexity DESC, loop_depth DESC LIMIT 20
```

`transitive_loop_depth` is the worst-case nested-loop degree _propagated along
call edges_, so it catches a quadratic helper reached from a loop — a shape
`loop_depth` alone reports as linear. `linear_scan_in_loop` counts
`find`/`contains`-style scans inside a loop: the O(n²) neither number shows.
`param_count >= 5` is a separate, cheap signal.

**Dead code** — nothing calls it:

```cypher
MATCH (f:Function)
WHERE f.is_entry_point = false AND NOT EXISTS { (f)<-[:CALLS]-() }
RETURN f.qualified_name AS qn, f.file_path AS file LIMIT 50
```

**Caveats — the graph cannot replace reading the code:**

- Call edges are partly heuristic (`suffix_match`). Only the type-aware subset is
  trustworthy, which is why the graph never drives an edit here.
- Filter the results: vendored templates, test fixtures and generated files are
  uncalled by design. The first real run returned a Composer test template.
- Cohesion and layering come from `code_communities` and `get_architecture`, not
  from Cypher.

Report candidates as a ranked list, each with the metric that flagged it. The
advisory report is the deliverable here — not an edit.

## See also

- [Refactor tool reference](/tools/refactor) — engine policy and the plugin
  contract for adding another language.
