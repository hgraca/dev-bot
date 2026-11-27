---
date: 2026-11-26
keywords: ["opencode", "shell-tool", "enospc", "disk-full"]
aliases: ["shell tool unusable", "No space left on device", "FileSystem.makeDirectory"]
---

## The shell tool dies when the filesystem holding the opencode data dir is full

The `shell` tool creates `<data-dir>/shell/<sessionID>/sh_*.out` and writes every command's stdout there before/while executing, so a full filesystem takes out the whole channel — every call fails, including `true`, with `failed to open output file …: No space left on device (os error 28)`. Once that session directory has been removed (e.g. by clearing `shell/*`), the failure changes shape to an opaque `Unknown: FileSystem.makeDirectory (<session dir>)`, which names no cause and tells the agent nothing. Nothing on the agent side unblocks it: `write` cannot create files on the full filesystem either (it fails as a bare "Unable to write <path>"), and truncating existing scratch files frees nothing in practice because those `.out` files are usually 0 bytes. Do not retry the tool in a loop and do not treat the `makeDirectory` wording as a permissions bug — free space from outside the harness and re-test with one cheap command.
