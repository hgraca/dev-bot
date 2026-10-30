---
date: 2026-10-30
keywords: ["shell", "make", "make-n", "recursive-make", "hermetic-tests"]
aliases: ["make dry run side effects", "make -n touches cluster", "MAKEFLAGS n check"]
trigger-on: ["convention-test-renders-make-target", "make-n-dry-run"]
---

## `make -n` still runs recipe lines that contain $(MAKE)

`make -n <target>` prints commands without executing them, with one exception: a recipe line that
contains `$(MAKE)` is executed so make can recurse. The nested make inherits `-n` and only prints,
but any shell logic wrapped around that line runs for real — so a "static" convention test that
renders a target with `make -n` can touch a live system. Rendering an `otel-gateway-deploy` target
this way executed a `signoz-token-bootstrap` branch that ran `kubectl` against the current context
before the nested dry run printed anything. Keep such tests hermetic by reading the recipe text from
the makefiles instead of invoking make (extract the target block with awk: start at `^target:`, stop
at the next line that begins in column 0), or guard the recipe's side effects on `-n` being absent
from `MAKEFLAGS`.
