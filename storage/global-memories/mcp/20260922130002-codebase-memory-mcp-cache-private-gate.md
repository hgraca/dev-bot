---
date: 2026-09-22
keywords: ["mcp", "codebase-memory-mcp", "cache-dir", "permissions"]
trigger-on: ["codebase-memory-mcp-start-failure", "cbm-daemon-could-not-start", "codebase-memory-cache-private"]
---

## codebase-memory-mcp's private-directory gate, and why it fails silently

`codebase-memory-mcp` refuses to start unless its cache directory passes a private-directory check, and the failure is easy to misdiagnose because the daemon's own stderr is swallowed — the visible symptom is only `CBM daemon could not start within 30000 ms`, or, when the server itself fails first, `exact executable identity could not be verified (cache-private)`. The requirements, extracted from the 0.10.8 binary: the cache directory must be owned by the euid, mode `0700`, with no extended ACL; and its **containing** directory must be owned by the euid, not world-writable, and carry no allow-ACL — `daemon.private_dir_group_writable_ancestor` names the offender ("the directory CONTAINING '<x>' is not a usable private-directory parent"). Only the immediate parent is checked, so a root-owned `/tmp` is fine as a further ancestor, and `0770` parents pass — only `0777` fails. Root is **not** exempt: the check is strictly owner == euid, so a root process fails on a non-root-owned cache exactly as a non-root process fails on a root-owned one. The server also calls `chmod 0700` on the cache directory **unconditionally on every start** (verified via ctime, and it is what makes the Docker-Desktop-virtiofs bind-mount trap self-sustaining), and no flag or environment variable relaxes any of it. `XDG_CACHE_HOME` is ignored; **`CBM_CACHE_DIR`** sets the cache root directly and is the supported way to relocate the store.
