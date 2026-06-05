---
name: prune-memories
description: "Prune the memory vault: remove stale/superseded entries, merge complementary notes into single actionable files, rewrite incomplete entries. Use this skill whenever the vault has grown noisy, after major project milestones, or when 'prune memories' or /prune-memories is invoked."
---

# Prune Memories

Reduce vault noise: delete stale entries, merge complementary notes, rewrite incomplete ones. Produce report of every change.

## When to Apply

- User says "prune memories", "clean up memories", or invokes `/prune-memories`
- Vault noisy after many sessions
- Major project milestone — old decisions superseded

## Before Starting

Load `memory-management` skill once. Provides frontmatter schema, routing table, quality criteria used throughout.

## Procedure

### Step 1 — Inventory

**Scope**: by default, inventory `latent/ADRs/`, `latent/PDRs/`, `latent/learnings/`, and `thinking/`. Only include `latent/global/` when user explicitly requests it (e.g. "prune global memories", "include global", "prune everything").

List all files in the active scope and `thinking/`.

Read each file. Build working map:

```
file path | topic summary | date | keywords | status (keep / stale / merge-candidate / incomplete)
```

### Step 2 — Identify stale / superseded entries

Mark file **stale** when:

- Newer file in same folder covers same topic with updated info
- Decision or lesson explicitly reversed or replaced
- Content refers to tool, pattern, or convention no longer used

For each stale file: note which newer file supersedes it.

### Step 3 — Identify merge candidates

Mark files **merge-candidates** when:

- Cover same topic from complementary angles (e.g. two gotchas about same tool, two ADRs about same subsystem)
- Merging produces single note more complete and actionable than either alone
- Share ≥ 2 keywords and bodies do not contradict

Group merge candidates by topic.

### Step 4 — Identify incomplete entries

Mark file **incomplete** when:

- Body is single vague sentence with no actionable guidance
- Rationale missing (ADRs/PDRs)
- Says "be careful with X" without explaining what to do instead
- Frontmatter missing required fields (`date`, `keywords`)

### Step 5 — Execute changes

Order: delete stale → merge groups → rewrite incomplete.

#### 5a. Delete stale files

For each stale file:

1. Confirm superseding file exists and covers same ground
2. Delete stale file
3. Log: `DELETED <path> — superseded by <superseding-path>`

#### 5b. Merge groups

For each merge group:

1. Choose canonical destination (newest file in group, or new file if none fits)
2. Write merged content: combine bodies into one coherent paragraph (or multiple `##` sections for `learnings/`), union `keywords` (max 5, most specific first), keep newest `date`
3. Delete source files merged in
4. Log: `MERGED <source1>, <source2> → <destination>`

#### 5c. Rewrite incomplete entries

For each incomplete file:

1. Rewrite body — specific, actionable: what, why, how to apply
2. Add missing frontmatter fields\
3. Log: `REWRITTEN <path> — reason: <what was missing>`

### Step 6 — Thinking/ hygiene

Apply `memory-management` skill section 7:

- Reusable lesson → promote to `latent/`, delete draft
- Completed work → delete
- Live WIP → keep; rename if not descriptive
- Flag files older than 7 days for user review

### Step 7 — Report

```
## Memory Prune Report — YYYY-MM-DD

### Deleted (stale/superseded)
- <path> — superseded by <path>

### Merged
- <source1>, <source2> → <destination>

### Rewritten (incomplete)
- <path> — <what was fixed>

### Thinking/ promoted
- <path> → <latent destination>

### Thinking/ deleted
- <path>

### No change
<n> files reviewed, no action needed.
```

If no changes: say so explicitly.

## Quality Rules (every written/merged/rewritten file)

- Specific not generic — "Always pass `--no-interaction` to Artisan" not "Be careful with CLI"
- Self-contained — future agents understand _why_ without reading other files
- One `##` heading + one prose paragraph for `ADRs/`, `PDRs/`, `global/<tech>/`
- Multiple `##` sections allowed for `learnings/`
- No scaffolding lines (`- **Status**: ACTIVE`, `- **Scope**: ...`) in body
- `keywords`: 1–5 focused terms, most specific first
