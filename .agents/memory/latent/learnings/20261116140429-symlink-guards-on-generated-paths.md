---
date: 2026-11-16
keywords: ["devbot", "symlink", "ownership", "generated-files"]
aliases: ["write through a symlink", "symlinked manifest", "shim marker bypass"]
---

# Every dev-bot-generated path needs a symlink guard — on read and on write

A cascade of review findings all had one root: dev-bot wrote or deleted generated files by _name_, and each operation followed a symlink a user could have planted. Four distinct instances in one PR:

- `printf … > "$target"` for a runtime MCP manifest wrote **through** a link to a file outside the project (as did `cksum`/`cat` in the ownership and byte-identical checks, which silently compared the referent).
- `rm -f "$target"` retired a user's link — and the fingerprint compare read through it.
- `rm -r -f "${dir}"` in the plugin-package sweep deleted an **external** directory when `.opencode/plugins/<name>` was a symlink to it.
- `grep -qF "$marker" "${dir}index.ts"` classified a user package as dev-bot-generated when its `index.ts` was a symlink to a file containing the marker — then the sweep deleted the package.

The rule: before any read, write, `rm` or `grep` on a path dev-bot generates, `[[ -L "$path" ]] && refuse`. Do it early — before the ownership/fingerprint/marker checks, because every one of those helpers follows links. Records are no exception: a migration that `cp`s onto a record path must write a temp file and `mv` it (rename replaces the link instead of writing through it). A symlinked path is never dev-bot's, no matter what it points at.
