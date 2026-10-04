---
date: 2026-10-06
keywords: ["shell", "pkill", "process"]
trigger-on: ["pkill-self-match"]
---

## `pkill -f <pattern>` can match the very shell running it

`pkill -f` matches against full command lines — including the shell or batch that contains the literal
pattern string. So `pkill -f 'remote-debugging-port=9333'` can kill its own parent shell and silently
abort the whole command (no output, then it hangs until the tool times out). Break the literal with a
character class so the pattern does not match itself — `pkill -f 'remote-debugging-port=93[3]3'` — or
target a unique token (e.g. the `--user-data-dir` path) written so it never appears literally.
