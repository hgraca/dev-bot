---
date: 2026-05-15
keywords: ["opencode", "plugin", "tool"]
---

## Wrapping a system CLI tool as an opencode tool: TS tool → bash wrapper → CLI

Pattern for adding a system CLI tool (e.g. `tree`, `repomix`) as an opencode tool: (1) `<tool>.ts` — exports `default tool({...})` from `@opencode-ai/plugin`, spawns the colocated `.sh` script via `Bun.spawn(["bash", script, ...args], { stdio: ["ignore","pipe","pipe"] })`, returns stdout or error string on non-zero exit; (2) `<tool>.sh` — bash wrapper that validates the CLI is installed (`command -v`), resolves paths to absolute (`cd && pwd`), and outputs markdown to stdout; (3) `src/prerequisites/<tool>/install.sh` — uses shared `header`/`skip`/`step`/`log` functions, detects macOS vs Linux, installs via Homebrew or apt; (4) `src/instructions/commands/<tool>.md` — frontmatter `agent: devbot/devbot` + one-liner invoking the tool; (5) add to `PRE_DOCKER_APPS` in `bin/install.sh`; (6) add health check section in `bin/doctor.sh` after nearest related section. The `.ts` tool NEVER calls the CLI directly — always delegates to the `.sh` wrapper. Reference: `tree-report` (commit `3d79255`), `repomix-report`. Cross-ref [[memories]] tool-wiring pattern.
