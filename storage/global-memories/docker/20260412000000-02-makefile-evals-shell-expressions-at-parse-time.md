---
date: 2026-04-12
keywords: ["docker"]
---

## Makefile evals shell expressions at parse time

Lines like `IS_DOCKER := $(shell ./scripts/is-in-docker.sh)` are evaluated when `make` parses the Makefile, not when a target runs. A missing script causes an error on every `make` invocation, even for unrelated targets. Fix: keep such helper scripts in version control even if trivial.
