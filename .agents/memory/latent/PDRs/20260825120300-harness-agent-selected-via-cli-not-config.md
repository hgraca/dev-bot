---
date: 2026-08-25
keywords: ["devbot", "harness", "agent"]
---

## Harness agent is chosen via CLI at launch, not baked into config

Starting devbot always launches the configured harness as the DevBot agent via the CLI flag `--agent DevBot` in each harness's `start.sh`. The claudecode generated config no longer sets `"agent": "DevBot"` (removed from `init.sh`), so launching `claude` directly does not force DevBot. opencode keeps `default_agent: "DevBot"` in its config by explicit stakeholder choice, with the start.sh flag as a belt-and-braces guarantee. Principle: agent selection lives at launch time, so direct harness usage is free of the DevBot default where the user wants otherwise.
