---
date: 2026-11-03
keywords: ["devbot", "format-tools", "prettierignore", "devbot_dir", "format-yml"]
aliases: ["format hook stopped reindenting", "agent workspace exempt from ignore", "prettierignore respected"]
supersedes: ["devbot/20261103142000-02-format-yml-hook-rewrites-whole-yaml.md"]
---

## The format-* tools now honour a project's .prettierignore, except in the agent workspace

Shipped in GET-E/dev-bot#50: the three format tools no longer pin `--ignore-path /dev/null`. `prettier_gate.prettier_ignore_args(target)` walks up from the target for `.prettierignore` — falling back to `/dev/null` where the project declares none — and pins it per file, so a project that scopes prettier narrowly is no longer reformatted behind its back; the 195-line reindent of a one-line workflow edit cannot recur. `.gitignore` is still not consulted, which keeps a gitignored path formattable.

The agent workspace stays exempt: `in_agent_workspace` resolves `devbot_dir` project-first, then the effective global config (honouring `DEV_BOT_GLOBAL_CONFIG`), then `.agents`, matching `_devbot_get_project_dir`, and compares the target against each ancestor so a nested `devbot_dir` such as `.config/devbot` is recognised. Batch runs are partitioned by ignore file as well as config, because one `--ignore-path` covers a whole invocation.

This reaches every project on merge: they all symlink their tool paths into this repo's `src/`.
