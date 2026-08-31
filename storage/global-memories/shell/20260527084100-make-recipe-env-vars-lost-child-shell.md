---
date: 2026-05-27
keywords: ["shell", "make", "makefile", "env", "envsubst"]
---

## Make recipe env vars lost: each recipe line runs in a separate shell

GNU Make recipe lines and sub-make `$(MAKE)` invocations each run in a **separate shell process**. You cannot source `.env.prod` (or any shell script) in a prerequisite target and expect exported variables to be available to subsequent recipe lines or sub-make calls. When the child shell exits, all exported variables are lost.

The fix is Make-native variable assignment at parse time using `$(shell ...)`, guarded by `$(wildcard ...)` for file existence:

```makefile
ifneq ($(wildcard .env.prod),)
  MY_VAR := $(shell grep -E '^MY_VAR=' .env.prod | tail -1 | sed 's/^[^=]*=//')
endif
```

Then reference as `$(MY_VAR)` in recipes (single `$`). Pass to `envsubst` by prefixing the recipe line with `MY_VAR=$(MY_VAR)` — this sets the env var for that single command's subprocess.

Do NOT use `export` inside recipe/prerequisite targets expecting vars to flow to other targets. Keep a validation-only prerequisite target (e.g., `_load-env-prod`) that checks the file exists and vars are present, but do not rely on it for variable propagation.
