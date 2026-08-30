---
name: devbot:remember-session
description: "Unified memory capture — the sole storage trigger besides checkpoints. Scans the session for new learnings, routes findings to latent/ notes, promotes thinking/ drafts. Use this skill when the primary agent finishes (finish-flow confirmation) or whenever the user says 'wrap up', 'wrapping up', 'let's wrap', 'remember this session', or 'remember this'."
---

# Remember Session

**Primary memory storage mechanism**. All session learnings flow through this skill.

**Triggers:** the primary agent's finish-flow confirmation (see `devbot:agent-communication`), or the user says "wrap up", "wrapping up", "let's wrap", "remember this session", "remember this" (produces report)

# MUST

- **Load the `devbot:memory-management` context skill once, first**: Before step 1, invoke `skill("memory-management")` exactly once. Do not invoke it again during steps 1–4. This provides the canonical frontmatter schema and routing rules for the entire execution.
- **Silent execution**: Emit ZERO narrative text on finish-flow captures. No "Nothing to capture", "Captured X", or any status narration. Tool calls only. Only exception: manual "wrap up" trigger produces report described at end of this skill.
- **No skill-tag echoes**: Do not emit `<skill>remember-session</skill>` markers as narrative text. Either invoke `skill` tool once (loads skill content) or run steps directly — never both.
- **No headers, no preambles, no recaps**: Do not write heading like "## Capture" or closing line like "Captured 1 gotcha". End response immediately after the last tool call completes.

## 1. Identify what happened

**When triggered by the finish flow or manually** ("wrap up", "capture session", or the agent's finish confirmation), scan the session for new content since the last capture. The last capture timestamp (if any) is provided in the trigger prompt — use it directly to determine what's new. If no timestamp is provided, process from session start.

Look for:

- **Decisions made** — architectural choices, product direction, human stakeholder answers
- **Patterns discovered** — approaches that worked and should be repeated
- **Gotchas hit** — bugs, traps, constraints, false assumptions
- **Work completed** — issue folders touched, tasks finished
- **Rules given** — new rules or constraints from stakeholder

Also check `.agents/memory/thinking/` for scratch files from this session.

**If nothing worth capturing**: exit immediately. Skip steps 2-4.

## 2. Route to latent notes

For each finding, **check duplicates first** before writing:

- Extract 2–3 representative keywords from the finding (the same keywords you'd use in the frontmatter)
- Query using `search-memories` with those keywords: `search-memories --query "<keywords>" --max-results 5`
- Review results: if an existing entry covers the same learning (same topic + same conclusion), skip it — it's already in the vault
- If no match or a different topic, proceed to write the new file

Create new files using the frontmatter schema and routing table from the already-loaded `devbot:memory-management` skill (section 2 and section 6):

| Finding                                         | Destination                          | Format                                                                                                                                            |
| ----------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Product decision, stakeholder answer, new rule  | `memory/latent/PDRs/`                | New file per item, decision + rationale                                                                                                           |
| Architecture/technical decision                 | `memory/latent/ADRs/`                | New file per item, decision + rationale                                                                                                           |
| Lesson reusable across projects (tech-specific) | `memory/latent/global/<technology>/` | New file per item, lesson + context + scope. Pick most specific bucket from classification table in `devbot:memory-management` skill (section 2). |
| Lesson specific to this project                 | `memory/latent/learnings/`           | New file per item, lesson + context + scope                                                                                                       |

**Quality gate**: Only save entries that are specific, actionable, and include context. Generic observations ("be careful with X") not worth saving.

### Gotcha entries

When the finding is a non-obvious trap, constraint, or recurring bug:

**When to apply**: Tool/API behaves unexpectedly due to undocumented constraints. Fix took multiple attempts because root cause was non-obvious. Configuration, platform, or environment quirk caused silent failure. Pattern that looks correct actually breaks in specific context.

**Template**:

```markdown
---
date: YYYY-MM-DD
keywords: ["keyword1", "keyword2"]   <- 1-5 focused terms; bucket name first
---

## <Short descriptive title>

<What went wrong, why non-obvious, context where it occurs. Include fix or workaround. File paths, commands, or code if helpful.>
```

**Quality criteria**: Reproducible problem + fix/workaround. Specific ("BSD sed requires empty backup arg" not "sed works differently on macOS"). Include _why_ — future agents need mechanism.

**Do NOT use for**: Decisions (route to PDRs/ADRs instead). General lessons without a concrete trap.

## 3. Promote or discard thinking notes

Follow thinking/ lifecycle rules in `devbot:memory-management` skill (section 7):

- Contains reusable lesson → promote to latent/, then delete
- Completed work → delete
- Still live WIP → keep

## 4. Commit memory files (if tracked)

Memory files under `.agents/memory/` are tracked **only when `commit_memory: true`** is set in `.devbot.project.jsonc` (the default is `false`, in which case `memory/init.sh` ignores the vault — `.agents/memory` lands in `.git/info/exclude`). **Check reality before committing**: read `commit_memory` from the project config AND run `git check-ignore <file>` on a captured file — if either says ignored, skip the commit (the files stay local; nothing to fix). A pre-existing `.gitignore` blanket rule (e.g. `.agents/**`) can shadow the surgical excludes even with `commit_memory: true` — `git check-ignore` catches that too. Only when the file is genuinely trackable, commit:

- **Fixup commits only** — attach each new/changed memory file to the commit where the captured insight happened, using `git commit --fixup=<orig-hash>` (see `devbot:git-fixup-commits`). One fixup per distinct originating commit.
- **Never push** — commits only; the human decides when to push.
- **Keep capture as the final action** — make these commits the final action and write no further memory files afterward, so the capture stays a one-shot operation.
