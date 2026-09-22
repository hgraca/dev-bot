---
date: 2026-09-22
keywords: ["skill-tool", "git-changelog", "release-notes", "staleness"]
---

# The skill tool can serve skill content that disagrees with the file on disk

While cutting release 1.5.3 the `skill` tool returned a `devbot:git-changelog` body whose output contract said the release file is `release.v<MAJOR>-<MINOR>.no-vcs.md`, while the canonical file — `.agents/skills/devbot/git/git-changelog/SKILL.md`, a symlink into `src/agentic/git/skills/git-changelog/SKILL.md`, line 14 — says `release.v<VERSION>.no-vcs.md` with the full version. The canonical file was right (the repo already carries `release.v1-5-2.no-vcs.md`), and following the served text would have produced a wrong artifact name, most visibly for the four-part unstable scheme where truncating to MAJOR-MINOR collides across patch releases. The mechanism was not determined: the path resolves correctly, so the served copy looked stale rather than misrouted, and the served text also lacked the four-part paragraph the canonical file carries. Mitigation until it is understood: when a skill string becomes an artifact name, a filename, or a command argument, verify it against the file on disk instead of acting on the served body. Treat a served skill body as guidance, not as the current source of truth.
