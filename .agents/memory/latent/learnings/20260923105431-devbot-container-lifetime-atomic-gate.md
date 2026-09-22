---
date: 2026-09-23
keywords: ["devbot", "session-registry", "docker", "flock"]
---

# dev-bot container lifetime: the gate must be atomic with the removal

dev-bot containers are install-level — every module's services live in ONE compose project (`devbot`) shared by every harness on the machine — so removal is gated on the session registry at `storage/run/sessions/`: **remove iff the live session count is 0**. Getting that gate right has three non-obvious requirements, each of which fails silently if missed.

## The probe and the removal must share one critical section

A gate that reads `_devbot_live_session_count` and then removes is check-then-act: a session registering in the window has its containers deleted underneath it. `bin/down.sh` takes the registry lock (`_devbot_lock_wait` on the sessions _directory_ — `flock` works on a dir fd, so no lock file is left behind) and **holds it across the whole teardown**, module down-scripts included.

## The registering side must take the same lock

Locking only on the teardown side closes nothing. `_devbot_session_register` also takes the directory lock while it publishes its session file — then either the teardown sees the file (count >= 1, aborts) or it finishes first and the new session's containers start after the removal, which is harmless.

## A child invoked from inside the lock must be told not to re-lock it

`_devbot_session_release` runs the teardown while still holding the lock, so `_devbot_session_teardown` passes `_DEVBOT_REGISTRY_LOCK_HELD=1` to `bin/down.sh`. Without it, down.sh opens the same directory and blocks forever on an flock it can never acquire: a second process does not share the parent's open file description, so the quiet "the lock is held" case and mutual deadlock look identical.

`_run_service_scripts --all` exists for the same reason at a different layer: removal must run module `down.sh` scripts even for DISABLED modules, because a module disabled in this project may still own a non-compose container (playwright's labelled `docker run` orphans), and a disabled module's compose is excluded from `up`'s selected set — so no other collection point exists.
