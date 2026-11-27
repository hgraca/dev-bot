---
date: 2026-11-27
keywords: ["shell", "rc file", "brace balance", "awk", "function removal"]
---

## Removing a function from a user's shell rc: balance braces, never match the first `}`

A tool that replaces a hand-written shell function in `~/.bashrc` / `~/.zshrc` must delimit the
definition by counting braces, not by looking for a line that starts with `}`. Four idiomatic shapes
defeat the line heuristic and make the removal eat the rest of the file: `f() { …; };`, `f() { …; } # why`,
an indented closing brace, and a body holding its own `{ … }` block. The mirror case leaves an unmatched
`}` behind, which is a syntax error in the rc it just edited.

Count `{`/`}` with quoted text and trailing comments stripped (a `#` inside quotes is data; a `#` after
whitespace or `;` starts a comment), and refuse the edit when the depth never returns to zero rather than
deleting to EOF. Validate the candidate with `bash -n` (or `zsh -n`) for the target file before writing,
and edit a copy so a failed render cannot leave the function stripped and nothing in its place. A
pre-existing syntax error in the file must be reported as such, not blamed on the edit.
