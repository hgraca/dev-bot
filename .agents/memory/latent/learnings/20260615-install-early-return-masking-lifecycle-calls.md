---
date: 2026-06-15
keywords: ["devbot", "install.sh", "lifecycle", "idempotency"]
---

# install.sh early-return idempotency guard masks post-install lifecycle calls

The canonical `install.sh` pattern uses a `command -v <binary> &>/dev/null` check at the top of `main()`, which `return 0`s immediately when the binary is already installed. This guards the binary install block. However, when adding post-install lifecycle steps (plugin wiring, storage setup, suppression logic) that should run on every invocation (not just first install), placing them after the early return means they never execute on re-installs. Fix: restructure `main()` so the idempotency check guards only the binary-install section, not the entire function. Common pattern: restructure to `if ! command -v <binary>; then <install>; else <skip>; fi`, then unconditionally call lifecycle steps after the conditional. This ensures idempotent re-installs still refresh runtime artifacts.
