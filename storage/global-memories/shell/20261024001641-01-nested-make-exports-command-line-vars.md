---
date: 2026-10-24
keywords: ["shell", "make", "makeflags", "bats", "environment"]
---

## Nested make exports command-line variables into every recipe's environment

GNU make exports its command-line variables (and `MAKEFLAGS`, `MFLAGS`, `MAKELEVEL`) to the environment of every recipe process, so a test harness that shells out to `make` sees the _outer_ invocation's variables. A guard test running inside `make test-slice SLICE=2` receives `SLICE=2` and `MAKEFLAGS=… SLICE=2`; a nested `make target` called without `SLICE` silently inherits it, and the "missing argument fails" assertion can never pass. The same leak carries any `VAR=value` the outer target passed down (`BATS_FILES_FILE`, in one case), so the nested run quietly used the outer run's file list. Clear the seam: `env -u SLICE -u VAR -u MAKEFLAGS -u MFLAGS -u MAKELEVEL <command>`. `env` cannot wrap a shell function, so put `env …` _inside_ a helper — `_make_clean() { env -u … "$@"; }` called as `_make_clean env VAR=value make …`. Symptom shape: the guard passes standalone and fails only when the suite runs it under the partitioned CI job.
