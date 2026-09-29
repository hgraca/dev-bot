---
date: 2026-09-29
keywords: ["devbot", "bats", "bats-support", "test-runner", "module-tests"]
---

# A module's BATS suite fails without `BATS_LIB_PATH`, and its Python suite without `PYTHONPATH`

Running a module's tests directly fails for a reason that looks like a broken test rather than a missing environment:

```
bats src/agentic/<module>/tests/*.bats
# Could not find library 'bats-support' relative to test file or in BATS_LIB_PATH
```

Every test errors in `setup()`, because `bats-support`/`bats-assert` are installed globally by npm while BATS searches only the test file's own directory by default. The `Makefile`'s test target sets the path (`BATS_LIB_PATH="$(npm root -g)" bats -r src/ bin/`), and `make test` is the supported entry point.

To scope one module and stay fast:

```bash
cd src/agentic/<module>
BATS_LIB_PATH="$(npm root -g)" bats tests/*.bats
PYTHONPATH=lib python3 -m unittest discover -s tests -p 'test_*.py'
```

The Python half needs the same nudge for the same reason: a module's `test_*.py` files import sibling `lib/` modules, which they resolve by inserting `lib/` into `sys.path` themselves — so an LSP reporting `Import "x" could not be resolved` on those files is a false positive, and `discover` must be run from the module root with `PYTHONPATH=lib`.
