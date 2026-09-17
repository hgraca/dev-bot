---
date: 2026-09-17
keywords: ["mcp", "reset", "refresh-modules", "reinit"]
see: ["ADRs/20260917212754-hybrid-mcp-declared-not-sniffed.md"]
---

# Dropping a stale MCP entry is only safe if init can re-register it

reset.sh's `REFRESH_MODULES` loop removes a module's stale `opencode.jsonc` entry so init.sh can re-register it from the canonical manifest. That is a two-step contract, and the second step has conditions that are easy to break: registration is skip-if-exists, and `bin/init.sh` refuses to register a server it judges docker-only when no docker daemon is reachable.

The `e7e7cd40` playwright repin broke that contract invisibly. The docker-only guard keyed on the literal `npx -y @playwright/mcp`; the repin removed that string from the manifest, so playwright was judged docker-only. Nothing was visible while the stale-but-working entry just sat there — refresh is what exposed it. Adding playwright to `REFRESH_MODULES` (`8cf7b905`) made reset drop the entry, turning the latent misclassification into a real loss: on a daemon-less host it would be removed and never re-registered (fixed in `e1337fd4`).

Rule: before adding a module to `REFRESH_MODULES`, confirm init will actually re-register it on every supported host — walk the registration guards, not just the merge path. And when a refresh-list module's entry never refreshes in a consumer project (observability's playwright sat stale), inspect the registration half before the refresh half. Note also that refreshing is not free of side effects: an entry that is not the last key in the `mcp` map is re-appended at the end, so the refreshing reinit reorders keys once.
