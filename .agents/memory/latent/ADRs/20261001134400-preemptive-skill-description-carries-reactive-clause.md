---
date: 2026-10-01
keywords: ["skill-description", "skills", "create-skill", "trigger", "preemptive"]
supersedes: ["ADRs/20260923120000-skill-descriptions-carry-the-trigger-only.md"]
---

## A preemptive skill description carries the reactive clause too

A `SKILL.md` frontmatter `description` still states **when to reach for the skill — never what it
does**, and is still composed of up to three ordered pieces (see ADR
`20260923120000-skill-descriptions-carry-the-trigger-only`). This ADR narrows one clause of that
record: for a **preemptively-loaded** skill, piece 2 (`Use when <the situation that calls for this
skill>.`) is **required**, not skippable.

The preemptive form is therefore `Load at session start in every project under <project signal>.`
**followed by** `Use when <situation>.`, with the optional `Triggers on '…', '…'.` still last:

```
Load at session start in every project under git. Use when making a commit or wording its message.
```

The reason is the palette entry. `Load at session start …` states when the skill loads — a property
of the harness, not of the user's task — so on its own it tells the agent nothing about the situation
the always-loaded skill answers. The `Use when …` half supplies that. `devbot:git-commits` and
`devbot:software-development` now carry it, alongside `devbot:agent-communication`, which already
did.

Two consequences:

- The ~72-char ideal applies **per imperative clause** — the `Load …` clause and the `Use when …`
  clause are each about one terminal line. It remains an ideal, not a budget (the 400-byte test is
  the only enforced limit), and literal trigger phrases remain excluded from it.
- Reactive skills are unchanged: a lone `Use when …` (plus optional triggers) is still complete.

`devbot:create-skill` §"Writing effective descriptions" is updated to match and remains the single
source of truth for the convention.
