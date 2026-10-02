---
date: 2026-10-02
keywords: ["devbot", "agent-communication", "status-marker", "WAITING_FOR_PTY", "single-source"]
---

# agent-communication status markers: the skill table is the single source of truth

The canonical terminal-marker set used by every agent lives only in the "Canonical Status Markers" table of `src/agentic/agent-communication/skills/SKILL.md`. The executable validator `tools/agent-communication.mcp.sh` still hard-codes `MARKER_RE` (it cannot parse markdown), so the skill is the documentation source of truth and a drift-guard test keeps the two in sync: `tests/agent-communication_tool_tests.bats` parses the skill's marker table and asserts the validator accepts every marker in it. Adding or renaming a marker therefore means editing the skill table **and** the regex — the test fails otherwise.

Current markers: `[FINISHED]`, `[BLOCKED]`, `[NEEDS_INPUT]`, `[PARTIAL]` are work-terminal; `[WAITING_FOR_PTY]` is a turn-ender — the agent pauses mid-work to await a PTY process (`sleep`, build, or test spawned with `notifyOnExit`) and resumes automatically on its exit notification, deliberately distinct from `[PARTIAL]`'s incomplete stall. Agent instruction files (`devbot.md`, `teamlead.md`), `optimize-instructions`, the module `docs.md` and `active/project.md` no longer repeat the list — they point to the skill; a full-list enumeration anywhere else is a drift bug. Note the validator regex is unanchored grep over the whole message, so `[BLOCKED] reason` validates; only the convention places the marker on its own line.
