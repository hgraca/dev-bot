---
date: 2026-09-24
keywords: ["makefile", "docker-wrap", "devtools", "paratest"]
trigger-on: ["devtools-makefile-docker-wrap", "make-target-runs-twice"]
---

## DevTools make targets: declare `.docker-wrap-$$@` on the dotted target, not the public alias

In the DevTools makefile layout the managed `Makefile` declares public aliases (`ut: .ut`, `stan: .stan`) while `Makefile.proj.mk` declares the container wrapper — and GNU Make **merges** prerequisites rather than replacing them. So the wrapper must go on the **dotted** target: `.ut: .docker-wrap-$$@` with the recipe in the double-dotted `..ut:` (the wrapper recurses into `..<name>` because its `$*` already carries the leading dot — mirror the working `.stan: .docker-wrap-$$@` / `..stan:` pair). Declaring `ut: .docker-wrap-$$@` instead (wrapping the public name) leaves `.ut`'s bare recipe live, so the target executes **twice**: once on the host and once in the container. The tell is a target that exits non-zero while its output says everything passed, with a **host** path in the trace — e.g. `Class "DOMDocument" not found` in ParaTest's `Util/Xml/Loader.php`, because that host PHP lacks `ext-dom` while the container's has it. Verify with `make -n <target> EXEC=echo` and compare against a known-good sibling; note `$(MAKE)` lines still execute under `-n`, so neutralise the wrapper with `EXEC=echo` to see the plan without running it.
