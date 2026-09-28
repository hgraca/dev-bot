---
date: 2026-09-29
keywords: ["shell", "flock", "fd", "detached", "set-e"]
trigger-on: ["bash-detached-child", "flock-inherited-fd"]
---

## A detached child inherits the parent's flock — close the fd before backgrounding

flock locks live on the open file description, so a child forked while the parent holds the lock keeps that lock alive until _every_ copy of the fd is closed. A `cmd & disown` issued from inside a locked section therefore pins the lock after the parent exits, stalling the next process that waits on it (verified: with fd 200 flocked, a backgrounded child holding fd 200 kept the lock; closing it in the child freed the lock the moment the parent exited). Close the descriptors inside the child before it does any work: `( exec 200>&- 210>&-; ... ) &`. Two related facts: `exec N>&-` on an fd that was never opened is a silent success even under `set -e`, and closing the fd in the child does **not** release the parent's own lock — the parent still holds it until it exits.
