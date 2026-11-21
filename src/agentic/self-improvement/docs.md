---
title: "Self-improvement"
description: "Meta-optimization — authoring skills, agents and modules, plus retrospectives and instruction tuning."
commands: ["find-automation-candidates", "improve-reviewing"]
# prettier-ignore
skills: ["address-retrospective", "create-agent", "create-claudecode-tool", "create-command", "create-devbot-module", "create-opencode-tool", "create-skill", "find-automation-candidates", "grade-tools", "improve-implementation", "improve-planning", "improve-reviewing", "make-retrospective", "optimize-instructions"]
---

The toolkit's tools for improving itself: everything needed to author or revise a dev-bot capability, and to turn a finished task into a process improvement.

## What it does

- **Authoring** — `create-skill`, `create-agent`, `create-devbot-module`, `create-opencode-tool`, `create-claudecode-tool` and `create-command` carry the conventions for each artifact type.
- **Retrospectives** — `make-retrospective` assesses a completed task or iteration; `address-retrospective` acts on what it found.
- **Process improvement** — `improve-planning`, `improve-reviewing` and `improve-implementation` trace a quality gap back to the instruction that caused it; `improve-reviewing` turns the issues a code review loop caught into a pull request against the dev-bot repository, so the reviewer catches them before the next pull request exists.
- **Automation discovery** — `find-automation-candidates` measures the command chains the agent actually types across its sessions and ranks the ones worth a script; the command runs the analysis for a given number of sessions.
- **Instruction quality** — `optimize-instructions` rewrites agent instruction files; `grade-tools` records how well each tool performed so a weak tool can be found and fixed.

## Configuration

No project configuration is required.

## See also

- [Create a module](/create-a-module) — module anatomy and lifecycle
- [DevTeam](/modules/agentic/devteam) — the workflows these skills improve
