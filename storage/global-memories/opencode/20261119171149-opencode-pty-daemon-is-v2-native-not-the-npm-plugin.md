---
date: 2026-11-19
keywords: ["opencode", "opencode-pty", "pty-daemon", "process-layout"]
aliases: ["opencode pty daemon", "pty plugin vs native", "why is opencode-pty running", "opencode background pty"]
trigger-on: ["opencode-pty-daemon", "opencode-process-tree"]
---

## `opencode-pty` under v2 is the runtime's own bundled daemon, not the npm plugin

Under OpenCode v2 (seen on 2.3.0) the shared background service spawns a child `opencode-pty daemon --runtime-dir ~/.local/state/opencode/pty --name <uuid>`, executed from `~/.cache/opencode/bin/opencode-pty/<version>-<contenthash>/` — the runtime's content-hashed cache for native sidecar binaries (the same tree that holds downloaded LSPs such as `vscode-eslint`). It is bundled into the v2 binary itself, not installed from npm: `strings ~/.opencode/v2/opencode` shows the embedded `/$bunfs/root/opencode-pty-*.` payload plus its IPC error strings (`opencode-pty frame too large`, `unexpected opencode-pty response`), and the daemon self-reports a version npm never published (`opencode-pty 0.5.2 (protocol 8)`) while npm `opencode-pty` latest is 0.4.0. That npm package is a different artifact — the **V1 plugin** the dev-bot V1 harness pins at `opencode-pty@0.3.6` and the v2 dist deliberately omits, because its builds depend on the V1 SDK (`@opencode-ai/plugin ^1.3.13`) and V1 plugin implementations do not run on a v2 host. Practical consequences: the expected v2 process layout is **one** `opencode serve --service` + **one** `opencode-pty daemon` (owned by that service and shared by every TUI) + **N** `opencode2` TUI clients; the daemon appears in no config file and is not config-driven, so do not try to enable, version-pin, or "fix" it through configuration, and do not conclude from its name that a V1 plugin is installed. A second `opencode` process in the list is something else — check its argv before assuming a duplicate server.
