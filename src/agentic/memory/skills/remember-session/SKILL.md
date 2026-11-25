---
name: devbot:remember-session
description: "Use when a session ends or the user asks to capture it. Triggers on 'wrap up', 'remember this session', 'let's wrap'."
---

# Remember Session

**Primary memory storage mechanism**. All session learnings flow through this skill.

**Triggers:** the primary agent's finish-flow confirmation (see `devbot:agent-communication`), or the user says "wrap up", "wrapping up", "let's wrap", "remember this session", "remember this" (produces report)

# MUST

- **Load the `devbot:memory-management` context skill once, first**: Before step 1, invoke `skill("memory-management")` exactly once. Do not invoke it again during steps 1–4. This provides the canonical frontmatter schema and routing rules for the entire execution.
- **Silent execution**: Emit ZERO narrative text on finish-flow captures. No "Nothing to capture", "Captured X", or any status narration. Tool calls only. The pull request URLs `devbot:commit-memories` returns are the one exception — list them as data, with no commentary. A manual "wrap up" trigger may additionally produce the report described at the end of this skill.
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

**Polyrepo sessions** — in a project with `workspace.type: "polyrepo"`, route each
finding by the files it concerns (see `devbot:memory-management` §2
"Polyrepo sessions"): a finding about a child project's file → that child's
vault; cross-project / org-wide → the polyrepo's vault; tech-generic →
`latent/global/<tech>/`. Dedup-check with `search-memories --focus "<path>"`
so the owning project's vault is in scope.

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

## 3. Promote thinking notes

Promote the lasting value out of this session's `thinking/` files into `latent/`, following `devbot:memory-management` (section 7).

Deletion is not yours: `devbot:reconcile-work` removes every `thinking/` file this session created, so leave the files in place here and let the one owner do the removal.

## 4. Publish the captured files

Memory files are published through a pull request, never committed to the local default branch: load
`devbot:commit-memories` and follow it once, after the capture has written its notes. It groups the
files this capture created or modified by the repository that owns them — the owning project for vault
notes, the dev-bot repository for the global store — applies the `commit_memory` and `git check-ignore`
gates, commits them on a branch, pushes the branch, and opens or appends each group's standing pull
request — `chore(agents): commit memories and lessons learned` for vault notes and
`chore(global-memories): commit global memories and lessons learned` for the global store. It is
unattended in the finish flow: no permission prompt, no confirmation round. `devbot:commit-memories`
carries every publishing rule; this step only hands it the files. The URLs it returns are the wrap-up
report's memory lines.

**Polyrepo sessions** — a note's repository is its **owning project's**, never the polyrepo's. Pass
every note with the owner resolved (`devbot tool project-for-path <file>`), and let the child's own
`commit_memory` gate its vault notes; a global lesson still goes to the dev-bot store's repository. A
non-git owner is skipped with a **notice** line in its `.agents/logs/memory-index.log` — no warning,
no failure.

**Keep the memory capture as the final memory action** — write no memory files after this step, so the
capture stays a one-shot operation. The finish flow then runs `devbot:grade-tools` (tool quality),
`devbot:reconcile-work` (work-folder and worktree housekeeping) and, when the session ran a code review
loop, `devbot:improve-reviewing` (reviewer improvement) — none of them writes memory notes.
