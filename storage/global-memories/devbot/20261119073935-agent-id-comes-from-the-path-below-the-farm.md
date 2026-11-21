---
date: 2026-11-19
keywords: ["devbot", "agent-registry", "opencode", "claudecode", "prompt-less"]
aliases: ["devbot/devbot", "shallow agent persona", "missing system prompt", "agent farm layout", "flat agent farm"]
trigger-on: ["devbot-agent-wiring", "devbot-harness-agent-load"]
see: ["devbot/20261114131203-agent-identifiers-are-lowercase.md", "devbot/20261013114033-module-skill-harness-name-vs-frontmatter.md"]
---

## An agent's registered id comes from its path below the farm, not from its file existing

opencode 2.x derives an agent id from the path below `.opencode/agents` (a symlink to `.agents/agents`), so a farm that links the module directory — `.agents/agents/devbot` → `src/agentic/devbot/agents/`, holding `devbot.md` — registers the id `devbot/devbot`. `default_agent: "devbot"` then matches nothing and the host serves an agent with **no prompt at all**: no error, no log line, no session-start protocol, no scout, no workflow selection, no terminal markers. opencode v1 reads the frontmatter `name:` instead, so the module layout was healthy there — that split is why the defect sat unnoticed across harness versions. The fix (dev-bot PR [#127](https://github.com/GET-e/dev-bot/pull/127)) links one file per agent at its frontmatter name (`.agents/agents/devbot.md`), while an external module keeps its per-module namespace (`.agents/agents/addyosmani` → `addyosmani/<agent>`). Command ids follow the same split: v1 reads the frontmatter `name:`, claudecode derives `<dir>:<file>` and v2 `/dir/file` from the path — a path can therefore invoke correctly while its `name:` metadata is wrong.

Suspect this rather than a broken install when every capability works but the persona behaves generically. Verify from two sides: `ls -l .opencode/agents` one level deep (the id is the path), and the id the host logs — `agent=<id>` on v1's `message=created` / `message=stream` lines under `${XDG_DATA_HOME:-$HOME/.local/share}/opencode/log/`, which must read `devbot`, never `devbot/devbot`.
