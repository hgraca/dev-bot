---
date: 2026-09-19
keywords: ["shell", "flock", "file-descriptor", "subshell", "background"]
trigger-on: ["shell-detached-background-lock", "shell-command-substitution-pipe"]
---

## A detached background child inherits open fds — locks and pipes outlive the parent

`( ... ) &` (even followed by `disown`) inherits the parent's open file descriptors, which produces two failures that look unrelated but share one cause. (1) An `exec 200>file` + `flock -n 200` taken in the parent stays held for the child's whole lifetime, so the flock is a _build-duration_ lock rather than the launch lock its comment claimed — any later `flock` on the same file blocks until the child exits (verified empirically: the lock was unobtainable while the detached child lived, and free immediately after). (2) The child also holds the stdout pipe of a `$( ... )` command substitution, so `pid=$(start_background_child)` blocks until the child exits instead of returning the pid. Fix for (2): redirect the background child's stdio (`( ... ) >/dev/null 2>&1 &`) before echoing the pid. For (1): either exploit the inheritance deliberately as a build lock, or explicitly close the fd in the child (`exec 200>&-`) if launch-only semantics are intended.
