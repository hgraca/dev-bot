---
title: "Refactor"
description: "Deterministic, reference-aware refactoring of PHP, Python and TypeScript symbols."
skills: ["refactor"]
tools: ["refactor"]
---

Renames, moves or restructures a symbol and updates every genuine reference, via
the language's own engine — Rector for PHP, rope for Python, ts-morph for
TypeScript. The edit path is deterministic: the engine decides what changes, not
a language model.

Dry run by default. `--apply` is the only thing that writes.

## Invoking it

The tool is a plain CLI. Agents are pointed at it by the `devbot:refactor`
skill; a human runs the same thing:

```bash
devbot tool refactor <op> [options]
```

`<op>` is the refactoring (the table below). The language plugin is chosen from
`--file`'s extension, else from an op only one language declares; `--lang` forces
one. `devbot tool refactor --help` prints the live option list.

## Operations

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

## Engine policy

Two sources of Rector, in order:

1. **The project's own `vendor/bin/rector`.** Preferred: it is the version the
   project actually runs, with the project's `vendor/autoload.php`. The GET-e PHP
   projects ship Rector already, so this is the normal path.
2. **A pinned scoped install** in the dev-bot scratch dir, for projects without
   Rector. Provisioned with `plugin.sh provision` (Composer is Rector's official
   distribution channel).

There is deliberately **no phar**: upstream abandoned that distribution because it
broke on absolute paths and Docker mounts, which is exactly this tool's setup.

The project's own `rector.php` is never applied. It registers rule sets (Laravel,
PHPUnit, Carbon, PHP upgrade) and running them would rewrite unrelated code.
Instead the tool renders a config holding **exactly one rule**, and pins it with
`--only`. The run also passes `--clear-cache`, because PHPStan's per-file result
cache can otherwise let a warm cache mask drift.

### Scope

The search and the rewrite cover the directories `composer.json` declares under
`autoload` and `autoload-dev` (PSR-4/PSR-0 and classmap directories), falling
back to `app/` + `src/` when it declares none. `vendor/` is never a root — which
is why the scope is derived from composer rather than taken as the mount root. A
project that maps `tests/` in `autoload-dev` therefore has its test doubles and
call sites renamed alongside `src/`; before, the scope was the literal
`app/` + `src/` and those files were silently left behind.

Python and TypeScript use engines provisioned into the shared scratch dir
(`storage/refactor/{py,ts}`) — rope and ts-morph respectively. `--image`
overrides the PHP engine's container image; the Python and TypeScript engines
take `REFACTOR_PYTHON_IMAGE` / `REFACTOR_NODE_IMAGE`.

## Adding a language

The core is language-agnostic. It discovers `langs/*/plugin.sh`, reads each
plugin's `meta`, and dispatches `plan` / `apply` with a JSON request on stdin and
a JSON response on stdout. **Adding a language means adding a directory** — no
change to the core.

`meta` declares the language's canonical operations and, for each, the native op
a `--kind` selects:

```json
{
  "lang": "php",
  "extensions": [".php"],
  "ops": ["rename", "move", "remove-unused", "privatize"],
  "map": {
    "rename": { "method": "rename-method", "class": "rename-class" },
    "move": { "class": "move-class" }
  },
  "requires": { "rename-method": ["class", "from", "to"] },
  "risks": { "rename-method": "rename" }
}
```

| Field      | Meaning                                                           |
| ---------- | ----------------------------------------------------------------- |
| `ops`      | the canonical operations this language supports                   |
| `map`      | `canonical -> {kind -> native op}`; `"*"` passes any kind through |
| `requires` | per **native** op, the request fields it needs                    |
| `risks`    | per **native** op, how much the change needs backing by tests     |

An op absent from `map` does not exist in that language — `promote-readonly` is
TypeScript-only, `extract` Python-only. A language declaring a `*` key accepts
any kind and forwards it (TypeScript reads `kind` as a declaration kind).

| Subcommand  | Contract                                                      |
| ----------- | ------------------------------------------------------------- |
| `meta`      | the descriptor above                                          |
| `doctor`    | resolved engine, PHP version, container image (diagnostics)   |
| `provision` | install the pinned engine for languages that need one         |
| `plan`      | read a request on stdin, write a JSON plan, change nothing    |
| `apply`     | read a request on stdin, perform the change, write the result |

Request: `{"op", "class", "from", "to", "apply", "image", "namespace", "file", "kind", "start", "end", "index", "default"}`.
Response: `{"ok", "engine", "applied", "summary", "files", "warnings", "error", "notice", "string_references", "unrewritten_references", "remaining_changes", "file_move"}`.

`REFACTOR_LANGS_DIR` relocates the plugin directory (used by the test suite to
prove additivity).

## Risk class

The report names a **risk class** per op, because the tool never runs your tests
and how much your suite must back the change depends on the op:

| Class       | Meaning                                                           |
| ----------- | ----------------------------------------------------------------- |
| `rename`    | behaviour preserving — the symbol keeps its role                  |
| `extract`   | moves a block or expression into a new name; behaviour preserving |
| `inline`    | folds a definition into its callers and deletes it                |
| `cleanup`   | deletes dead code or tightens visibility; safe for correct code   |
| `signature` | changes a callable's signature or a type — **can break callers**  |
| `move`      | relocates a module and rewrites the imports that point at it      |

## Limits

- **Dynamic references are invisible** to static analysis: string callables,
  `__call`, container bindings and variable method names are not renamed.
  `string_references` reports quoted occurrences of the old name,
  `unrewritten_references` reports what an apply left outside strings (a
  doc-block mention), and `remaining_changes` reports what a rename could not
  reach.
- **PHP `--class` is resolved, and an empty result is stated.** A bare class name
  is resolved to its fully-qualified name; a run that changed nothing carries a
  `notice` explaining why (an unresolved class, or a name that matched nowhere).
  The exit stays 0 — this is feedback, not a failure.
- **Signature ops do not validate the result** — position the index and check
  the diff.
- **`rename-string` matches on the bare name** for global constants, because
  Rector's rule rejects a qualified key.
- **A TypeScript op sees only what the compiler resolves.** A member or binding
  reached dynamically reads as unused and is not reported; `promote-readonly` is
  stricter and refuses an apply that would introduce a compiler error.
- **`move-file` does not rewrite a non-relative specifier.** A tsconfig `paths`
  or `baseUrl` alias resolves to the moved file but is left as it is — reported in
  `warnings`.
- **The tool does not run tests**, by design. Run your own suite after applying.

## Configuration

No project configuration is required.

## See also

- [Tools](/tools) — the full tool index
- [Codebase Memory](/modules/agentic/codebase-memory) — structural lookup used to plan
  larger refactors
