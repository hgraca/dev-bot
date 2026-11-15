---
date: 2026-11-15
keywords: ["devbot", "harness", "shell", "module-init"]
aliases: ["_devbot_harness_dirs one line", "while read gets both dirs", "harness dir helper splits"]
---

# `_devbot_harness_dirs` prints both directories on one line — split it, do not `read` a word

`_devbot_harness_dirs` prints `.opencode .claude` as a **single** line, meant for word splitting. A consumer written as `while read -r harness_dir; do … done < <(_devbot_harness_dirs)` assigns the whole line to the variable, so every path becomes `<project>/.opencode .claude/...` and the loop silently does nothing — no error, no output, the cleanup just never happens. Use `read -r -a dirs <<< "$(_devbot_harness_dirs)"` then `for dir in "${dirs[@]}"`, or `for dir in $(_devbot_harness_dirs)` with an intentional-split comment. `_devbot_harness_dir` (singular) prints one directory for the selected harness; `_devbot_harness_platform` prints that harness's own CLI name (`opencode`/`claude`) for a third-party installer's `--platform`. A module that needs to clean up after a previous harness must sweep `_devbot_harness_dirs`; only writes are scoped to the selected one.
