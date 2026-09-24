---
layout: page
title: Refactor
description: Deterministic, agent-callable renaming of PHP symbols.
nav_section: docs
---

Renames a PHP symbol and updates every genuine reference, via Rector. The edit
path is deterministic — the engine decides what changes, not a language model.

Dry run by default. `--apply` is the only thing that writes.

## Usage

```
devbot-tools_refactor --lang php --op <op> \
  [--class <FQCN>] [--from <old> | --method <old> | --property <old>] [--namespace <ns>] \
  --to <new> [--apply] [--json] [--force]
```

| Op                     | Renames                                      |
| ---------------------- | -------------------------------------------- |
| `rename-method`        | the declaration + instance calls             |
| `rename-static-method` | the declaration + static calls               |
| `rename-annotation`    | a docblock annotation on a class             |
| `rename-property`      | the declaration + accesses                   |
| `rename-function`      | a free function: declaration + calls         |
| `rename-class`         | the declaration + references + the file move |
| `rename-constant`      | a global constant: declaration + uses        |

### Cleanup ops

No `--from`/`--to`: these run across the whole scope and change whatever they
find, so **read the plan before applying**.

| Op                                 | What it does                                       |
| ---------------------------------- | -------------------------------------------------- |
| `remove-unused-private-methods`    | deletes private methods nothing calls              |
| `remove-unused-private-properties` | deletes private properties nothing reads           |
| `privatize-final-class-properties` | tightens `protected` to `private` on final classes |

`rename-class` also **moves the file** to match the class name.

Ops on **classes and free functions** need the symbol's namespace, because
Rector resolves those by fully-qualified name. Pass `--namespace` or let the
tool derive it from the declaration under `app/` or `src/`; it errors rather
than guesses when the declaration is missing or ambiguous. **Constants** are
matched by bare name instead, so they need no namespace.

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
