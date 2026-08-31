---
date: 2026-04-28
keywords: ["opencode", "tool"]
---

## M-TOOL-069: remote-opencode stores config at ~/.remote-opencode/ and manages its own setup

Migrated Discord integration from opencode-chat-bridge (Docker/ACP) to remote-opencode (host npm/HTTP API). remote-opencode has its own interactive setup wizard (`remote-opencode setup`) that writes `config.json` and `data.json` to `~/.remote-opencode/`.
When integrating a tool that manages its own configuration, don't duplicate its setup in your install scripts. Install the package, check if it's already configured, and guide the user to run the tool's native setup. This avoids config format coupling and is future-proof.
