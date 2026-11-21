---
date: 2026-11-20
keywords: ["shell", "bash", "symlink", "testing"]
aliases: ["[ -e ] on a dangling symlink", "test passes vacuously", "broken link reads as absent"]
trigger-on: ["symlink-prune-test"]
---

## `[ -e ]` is false for a dangling symlink, so a prune test can pass without the prune

A test that deletes a link's target and then asserts `[ ! -e "$link" ]` proves nothing: `-e` follows
the link, and a dangling symlink reports as absent whether or not the link itself still exists. The
assertion passes with the pruning code removed — it is green for entirely the wrong reason, and green
is the one outcome nobody investigates. Assert on the **link** (`[ -L ]`, `readlink`, `test -h`), or
assert both: `! [ -L ] && ! [ -e ]`. The same shape bites anywhere a test distinguishes "removed" from
"now unresolvable": `find -type l` vs `-type f`, `os.path.exists` vs `os.path.lexists` in Python,
`fs.existsSync` vs `lstat` in Node. The reliable control is to delete the behaviour and confirm the
test reddens — a vacuous test is invisible in any suite that is passing.
