---
name: devbot:refactor
description: "Use when refactoring a PHP, Python or TypeScript symbol: rename, move, extract, inline, encapsulate, add-parameter, remove-parameter, remove-unused, privatize, promote-readonly. Triggers on 'rename this', 'extract this method', 'inline this', 'move this file', 'make this readonly'."
---

# Refactor

Deterministic, reference-aware refactoring in PHP, Python and TypeScript. The
edit is delegated to the language's own engine — Rector (PHP), rope (Python),
ts-morph (TypeScript) — so there is **no language model in the edit path**.

**Dry run by default**: nothing is written unless `--apply` is passed.

## Invoking it

The refactor tool is a plain CLI, not an MCP tool — run it through the shell:

```bash
devbot tool refactor <op> [options]
```

`<op>` is the refactoring (the table below). The language is inferred from
`--file`, or from an op only one language declares — so `--lang` is usually
unnecessary. Run `devbot tool refactor --help` for the live option list.

| Option             | Meaning                                                 |
| ------------------ | ------------------------------------------------------- |
| `--file <path>`    | the file declaring the symbol — also picks the language |
| `--lang <lang>`    | force a language plugin (`php`, `py`, `ts`)             |
| `--kind <kind>`    | variant/declaration kind when an op offers several      |
| `--class <name>`   | class the symbol lives in (ops on members)              |
| `--from <old>`     | current name (aliases: `--method`, `--property`)        |
| `--to <new>`       | new name (or destination, for a move)                   |
| `--namespace <ns>` | namespace, for ops on free functions/constants          |
| `--start`, `--end` | the range an extract op lifts (`line` or `line:col`)    |
| `--index <n>`      | parameter position (the signature ops)                  |
| `--default <x>`    | default expression for an added parameter               |
| `--apply`          | write the change (default: plan only)                   |
| `--json`           | emit the raw response as JSON                           |
| `--force`          | proceed despite a dirty working tree                    |

`--apply` refuses to run when the working tree has uncommitted changes to
**tracked** files, unless `--force`. Untracked files are ignored.

A plan ends with a **Risk** line — `rename`, `cleanup` or `signature` — the class
of change the op makes. A `signature` op can break callers, so back it with your
own tests before applying.

## Operations

`--kind` is needed only when an op offers several variants; a single-variant op
is chosen automatically, and a rename infers `method`/`property` from
`--method`/`--property`.

| refactor           | languages   | description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------ | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rename`           | php, py, ts | Renames a symbol and every genuine reference. php `--kind`: method, static-method, property, annotation, function, constant, class, class-constant, string (`class` also moves the file to match). ts takes `--kind` as a declaration kind (class, interface, function, type, enum, variable, method, property); py and ts accept `--file` to pick between a name declared in several places, and without either an ambiguous name is refused, not guessed. A name held in a string is reported, never rewritten (php, py). |
| `move`             | php, py, ts | Relocates a unit and repoints what refers to it. `--kind class` (php) changes a class's namespace and file; `--kind module` (py) moves a module and rewrites its importers; `--kind file` (ts) moves a source file and rewrites relative importers (a tsconfig alias is reported, not rewritten); `--kind member` (ts) moves a static member to another class and repoints its call sites; an instance member is refused, its receiver needing an owner the tool cannot supply.                                             |
| `extract`          | py          | Lifts the selected region into a new name: `--kind method` makes a method, `--kind variable` a local. Select the region with `--start`/`--end` (`line` or `line:col`, 1-based, inclusive).                                                                                                                                                                                                                                                                                                                                  |
| `inline`           | py          | Folds a definition into its callers and deletes it. An inlined f-string can emit nested quotes only Python 3.12+ parses (PEP 701).                                                                                                                                                                                                                                                                                                                                                                                          |
| `encapsulate`      | py          | Adds accessors around a field, making the field private. Refuses a field another class shares.                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `add-parameter`    | py          | Appends a parameter at `--index` (1-based); `--default` sets its default. The index is used verbatim, so a defaulted parameter before a non-defaulted one is a syntax error.                                                                                                                                                                                                                                                                                                                                                |
| `remove-parameter` | py          | Removes the parameter at `--index`. The body is untouched, so a name still used there becomes a `NameError`.                                                                                                                                                                                                                                                                                                                                                                                                                |
| `remove-unused`    | php, py, ts | Deletes what nothing references. php `--kind`: method, property, class-constant, constructor-param, promoted-property. py `--kind import` drops unused imports. ts `--kind local` / `--kind param` drop an unused local or a parameter no call site supplies; ts leaves an underscore-named binding, a loop binding, a destructuring pattern and an initialiser with possible side effects. Decided from the language's own reference set, so a dynamic access — a computed key, a string index, `eval` — reads as unused.  |
| `privatize`        | php, py, ts | Narrows visibility where nothing outside the unit needs it. php `--kind` method/property/constant, on a final class. py privatises a module-internal name, refusing one used outside its module. ts narrows public members the compiler sees no outside reference to — keeping a get/set pair together, leaving `protected` members, and keeping a member a subclass uses.                                                                                                                                                  |
| `promote-readonly` | ts          | Adds `readonly` to a property the constructor is the only thing to assign. Refuses an apply that would compile to an error.                                                                                                                                                                                                                                                                                                                                                                                                 |

## Limits

- **Dynamic references are invisible** to static analysis: string callables,
  `__call`, container bindings, variable method names. A rename reports quoted
  occurrences (`string_references`) rather than losing them silently, and an
  apply reports what no rule reached — a doc-block mention as
  `unrewritten_references`, a residual call site as `remaining_changes`.
- **The PHP scope is the project's composer source roots.** Only the directories
  `composer.json` declares under `autoload` and `autoload-dev` are searched;
  `vendor/` never is. A project that maps `tests/` in `autoload-dev` has its test
  doubles and call sites renamed alongside `src/`. Without a `composer.json` the
  old `app/` + `src/` fallback applies.
- **PHP `--class` is resolved, and an empty result is stated.** A bare class name
  is resolved to its fully-qualified name; a run that changed nothing carries a
  `notice` explaining why (an unresolved class, or a name that matched nowhere),
  and the exit stays 0 — this is feedback, not a failure.
- **The tool does not run your tests.** Only your suite can prove a rename is
  right in your project's terms — run it after applying.
- **An apply costs a second pass.** The self-verification doubles the runtime;
  set `REFACTOR_SKIP_VERIFY=1` on a large project.
- **The TypeScript whole-project sweeps grow with the project.** `privatize`
  and `promote-readonly` resolve references for every member of every class, so
  pass `--class` (or `--file`) to bound a run.

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

- [Refactor tool reference](/modules/agentic/refactor) — engine policy and the
  plugin contract for adding another language.
