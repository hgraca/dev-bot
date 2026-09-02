---
date: 2026-09-02
keywords: ["devbot", "devbot.global.jsonc", "jsonc", "comments", "machine-owned"]
---

# .devbot.global.jsonc is machine-owned: CLI rewrites strip comments

`tools/module.sh` add/remove rewrite `.devbot.global.jsonc` via
`read_jsonc.py` (comment-stripping) piped into `json.dump` — any `//`
comment anywhere in the file is destroyed on the first CLI op, and untouched
keys get reformatted (byte noise, semantically identical). Verified
empirically: a `// keep me` comment is gone after the rewrite.

Treat the global config as machine-owned: it is generated from
`.devbot.global.dist.jsonc` on install and rewritten by the CLI. Keep human
annotations in `.devbot.project.jsonc` or files the CLI never rewrites.
module.sh now runs the format-json tool after every write (same convention as
install.sh / bin/up.sh) so output stays canonical and diffs stable — but
formatting cannot restore comments, which are already lost by the writer.
Reintroducing comment survival would require a comment-preserving section
editor (the namespaced-era merge script had one; it was reverted with the
namespacing).
