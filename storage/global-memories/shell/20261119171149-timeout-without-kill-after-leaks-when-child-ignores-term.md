---
date: 2026-11-19
keywords: ["shell", "timeout", "kill-after", "sigterm"]
aliases: ["timeout process never exits", "wedged timeout wrapper", "timeout -k", "timeout 40 still running"]
trigger-on: ["timeout-wrapper-in-scripts"]
---

## `timeout` without `-k` keeps the wrapper alive forever when the child ignores SIGTERM

`timeout 40 opencode serve --port 14097` was still in `ps` after 16 hours with its child still listening on the port. `timeout` sends SIGTERM to the child at expiry but, with no `--kill-after`, it then **blocks waiting for the child to exit**; a child that traps or ignores TERM (a server doing graceful shutdown, a process in a signal-deferred state) never exits, so the wrapper parks indefinitely and the pair becomes a permanent leak. The failure mode compounds: the wedged `timeout` itself no longer reacts usefully to a later TERM, so routine `kill` on the wrapper does nothing and both PIDs need SIGKILL. Detection: `ps` showing `timeout <N> <cmd>` whose elapsed time far exceeds `N`. Prevention: always pass `--kill-after` with a small grace period (`timeout -k 5 40 <cmd>`). Reaping a wedged pair: KILL the wrapper and the child **separately** — killing only the wrapper reparents the child to init, where it keeps holding the port.
