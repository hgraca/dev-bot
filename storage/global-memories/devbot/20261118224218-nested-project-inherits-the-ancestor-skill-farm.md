---
date: 2026-11-18
keywords: ["devbot", "nested-project", "skills", "ancestor", "skill-farm"]
trigger-on: ["opencode-v2-init", "skill-farm-wiring"]
---

## A nested dev-bot project also inherits the ancestor's whole skill farm

opencode 2.x rescans `<project>/.opencode/skills` and the same directory under every ancestor, so a dev-bot project nested inside another registers the ancestor's catalogue beside its own — the plugin note covers plugins and config, but skills are a separate surface and the host gives no diagnostic for them. Measured on dev-bot nested in its polyrepo (2026-11-18): 104 project skills, 164 from the ancestor, **101 registered twice** (both ids resolve — `git-commits` and `devbot:git-commits` point at different farms) and **63 ancestor-only** skills belonging to modules the nested project disables (`aws`, `atlassian`, `notion`, `rfp`, `frontend`). Duplicates arise because the two farms spell ids differently: a converged farm names each link `devbot:<skill>`, a stale one links the whole module dir and the host derives `<skill>`. Measure it by intersecting SKILL.md `name:` frontmatter across the two farms, not directory basenames. `opencode-v2/init.sh` now warns with the ancestor path and count (`_warn_ancestor_skill_farms`, resolving the ancestor's own `devbot_dir` rather than a hard-coded `.agents`); the only real cure is reinitialising the ancestor so both farms share one layout.
