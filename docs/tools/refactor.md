---
layout: page
title: Refactor
description: Deterministic, agent-callable refactoring of PHP, Python and TypeScript symbols.
nav_section: docs
---

Renames or restructures a symbol and updates every genuine reference, via the
language's own engine — Rector for PHP, rope for Python, ts-morph for TypeScript.
The edit path is deterministic — the engine decides what changes, not a language
model.

Dry run by default. `--apply` is the only thing that writes.

## Usage

```
devbot-tools_refactor --lang <lang> --op <op> \
  [--class <FQCN>] [--from <old> | --method <old> | --property <old>] [--namespace <ns>] \
  [--file <path>] [--start <line[:col]>] [--end <line[:col]>] \
  [--index <n>] [--default <expr>] \
  --to <new> [--apply] [--json] [--force]
```

| Op                      | Renames                                      |
| ----------------------- | -------------------------------------------- |
| `rename-method`         | the declaration + instance calls             |
| `rename-static-method`  | the declaration + static calls               |
| `rename-annotation`     | a docblock annotation on a class             |
| `rename-property`       | the declaration + accesses                   |
| `rename-function`       | a free function: declaration + calls         |
| `rename-class`          | the declaration + references + the file move |
| `rename-string`         | string literals (no declaration exists)      |
| `rename-class-constant` | a class constant: declaration + fetches      |
| `move-class`            | a class's namespace + its file (name kept)   |
| `rename-constant`       | a global constant: declaration + uses        |

### Cleanup ops

No `--from`/`--to`: these run across the whole scope and change whatever they
find, so **read the plan before applying**.

| Op                                      | What it does                                       |
| --------------------------------------- | -------------------------------------------------- |
| `remove-unused-private-methods`         | deletes private methods nothing calls              |
| `remove-unused-private-properties`      | deletes private properties nothing reads           |
| `privatize-final-class-methods`         | tightens visibility on final-class methods         |
| `privatize-final-class-constants`       | tightens visibility on final-class constants       |
| `remove-unused-private-class-constants` | deletes class constants nothing reads              |
| `remove-unused-constructor-params`      | deletes constructor parameters nothing uses        |
| `remove-unused-promoted-properties`     | deletes promoted properties nothing reads          |
| `privatize-final-class-properties`      | tightens `protected` to `private` on final classes |

`rename-class` also **moves the file** to match the class name. `move-class`
takes both names fully qualified (`--from Demo\Widget --to Demo\Frontend\Widget`)
and changes the class's namespace, its file's directory and its references — the
class name itself is unchanged. The namespace is rewritten on that one file, not
across the namespace, and the target directory is inferred from PSR-4: if the
source directory does not mirror the namespace, the file is left for you to move.

Ops on **classes and free functions** need the symbol's namespace, because
Rector resolves those by fully-qualified name. Pass `--namespace` or let the
tool derive it from the declaration under `app/` or `src/`; it errors rather
than guesses when the declaration is missing or ambiguous. **Constants** are
matched by bare name instead, so they need no namespace.

## Languages

`--lang` selects the plugin. The core knows no op names: it discovers
`langs/<lang>/plugin.sh`, reads that plugin's `meta`, and validates against it —
which is what makes a new language additive.

| Lang  | Ops             | Engine                        |
| ----- | --------------- | ----------------------------- |
| `php` | the ops above   | Rector, in a PHP container    |
| `py`  | the Python ops  | rope, in a Python container   |
| `ts`  | `rename-symbol` | ts-morph, in a Node container |

Run `bash langs/ts/plugin.sh provision` once to install the TypeScript engine into
the shared scratch dir; `doctor` reports whether it is there. ts-morph drives the
TypeScript compiler, so a single run renames the declaration and every reference —
and, unlike the PHP plugin, it needs no per-rule steps.

### Python ops

rope ships refactorings Rector has no equivalent for, so `py` adds structural ops
alongside `rename-symbol`. A region is selected by **line, optionally with a
column** (`--start 12:9 --end 12:18`) — 1-based, inclusive; a missing column reads
to the end of the line.

| Op                      | Needs                                 | Risk      |
| ----------------------- | ------------------------------------- | --------- |
| `rename-symbol`         | `--from`, `--to` (optional `--file`)  | rename    |
| `extract-method`        | `--file`, `--start`, `--end`, `--to`  | extract   |
| `extract-variable`      | `--file`, `--start`, `--end`, `--to`  | extract   |
| `inline`                | `--from` (optional `--file`)          | inline    |
| `encapsulate-field`     | `--file`, `--from`                    | cleanup   |
| `add-argument`          | `--file`, `--from`, `--to`, `--index` | signature |
| `remove-argument`       | `--file`, `--from`, `--index`         | signature |
| `move-module`           | `--file`, `--to` (a folder)           | move      |
| `remove-unused-imports` | `--file`                              | cleanup   |
| `privatise`             | `--file`, `--from`                    | cleanup   |

As for PHP, a Python rename reports quoted occurrences of the old name as
`string_references` (rope cannot rewrite a name held in a string), and an apply
verifies itself, reporting `remaining_changes` when an identifier it could not
reach is left behind.

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

## Risk class

`meta` reports a `risks` entry per op, because the tool never runs your tests and
how much your suite must back the change depends on the op:

| Class       | Meaning                                                           |
| ----------- | ----------------------------------------------------------------- |
| `rename`    | behaviour preserving — the symbol keeps its role                  |
| `extract`   | moves a block or expression into a new name; behaviour preserving |
| `inline`    | folds a definition into its callers and deletes it                |
| `cleanup`   | deletes dead code or tightens visibility; safe for correct code   |
| `signature` | changes a callable's signature or a type — **can break callers**  |
| `move`      | relocates a module and rewrites the imports that point at it      |

## Invoking it

Agents call it as `devbot-tools_refactor` (the `devbot:refactor` skill carries the
contract). It is also a plain executable, so a human can run the same thing:

```bash
bash .agents/tools/refactor.mcp.sh --lang php --op rename-method \
  --class 'App\Greeting' --method greet --to salute        # plan
bash .agents/tools/refactor.mcp.sh ... --apply             # write
```

## Container

Rector runs in a PHP container with the project mounted at `/app`. The image is
resolved in this order:

1. `--image <ref>` (explicit)
2. `REFACTOR_PHP_IMAGE` (environment)
3. the project's own `image:` from its compose file
4. `php:<php-version>-cli`

The project's own image is preferred because a generic `php` image usually lacks
the project's PHP extensions, and `vendor/composer/platform_check.php` throws at
autoload time when they are missing.

## Adding a language

The core is language-agnostic. It discovers `langs/*/plugin.sh`, reads each
plugin's `meta`, and dispatches `plan` / `apply` with a JSON request on stdin and
a JSON response on stdout. **Adding a language means adding a directory** — no
change to `refactor.ts`.

| Subcommand  | Contract                                                      |
| ----------- | ------------------------------------------------------------- |
| `meta`      | `{"lang": “…”, "extensions": […], "ops": […]}`                |
| `doctor`    | resolved engine, PHP version, container image (diagnostics)   |
| `provision` | install the pinned engine for languages that need one         |
| `plan`      | read a request on stdin, write a JSON plan, change nothing    |
| `apply`     | read a request on stdin, perform the change, write the result |

Request: `{"op", "class", "from", "to", "apply"}`. Response:
`{"ok", "engine", "applied", "summary", "files", "warnings"}`.

A new language also declares its own `ops`, so the core never needs to know which
refactorings exist.

`REFACTOR_LANGS_DIR` relocates the plugin directory (used by the test suite to
prove additivity).

## Limits

- **Dynamic references are invisible** to static analysis: string callables,
  `__call`, container bindings and variable method names are not renamed.
  `string_references` reports quoted occurrences of the old name so they are not
  lost silently, and `rename-string` can rewrite them deliberately.
- **An apply verifies itself** by re-running every step as a dry run and
  reporting `remaining_changes`. That second pass doubles the runtime, so a large
  project can set `REFACTOR_SKIP_VERIFY=1`.
- **`rename-attribute` and `rename-cast`** are not available (the attribute rule
  needs the qualified name; the cast rule is configured from enum kinds).
- **The Python plugin uses rope**, whose reference set comes from the symbol table
  rather than a type checker — ordinary code is covered, dynamic construction is
  not. `rename-symbol` refuses a name defined in several places rather than
  guessing which one, so pass `--file` to disambiguate.
- **`inline` on an f-string** can emit nested quotes (`f"Hello {"world"}"`), which
  only Python 3.12+ parses (PEP 701); do not inline such a method for an older
  target.
- **Signature ops do not validate the result.** `add-argument` inserts at
  `--index` verbatim, so a defaulted parameter placed before a non-defaulted one
  produces a syntax error — and `remove-argument` leaves the body untouched, so a
  parameter still used there becomes a `NameError`. Position the index and check
  the result.
- **`rename-constant` matches on the bare name**, because Rector's rule rejects a
  qualified key. A same-named constant in another namespace would match too.
- **`rename-annotation` re-appends the annotation**, so it can shift order
  relative to other annotations in the same docblock. Content is preserved.
- **The tool does not run tests**, by design — the target may not be a GET-e
  project and may not test the way we do. Run your own suite after applying.
- **`rename-class` moves the file** but does not rewrite `composer.json` autoload
  maps, non-PSR-4 includes, or a class referenced by string elsewhere.

## See also

- [Tools](/tools) — the full tool index
- [Codebase Memory](/tools/codebase-memory) — structural lookup used to plan
  larger refactors
