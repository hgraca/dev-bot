---
date: 2026-10-23
keywords: ["shell", "patsub_replacement", "bash-5.2"]
aliases: ["parameter expansion ampersand", "bash replacement ampersand"]
trigger-on: ["bash-string-escaping", "html-entity-escaping"]
---

## Bash 5.2 expands `&` in a pattern-substitution replacement to the matched text

`${var//pattern/replacement}` gained `patsub_replacement` in bash 5.2: an unescaped `&` in the replacement is replaced with the text that matched `pattern`. So `${name//</&lt;}` does not produce `&lt;` — it produces `<lt;`, and `${name//>/&gt;}` produces `>gt;`. Scripts that escape HTML/Slack entities this way silently corrupt their output on newer runners while working on bash 5.1 and older, which makes it a version-dependent, hard-to-see bug.
