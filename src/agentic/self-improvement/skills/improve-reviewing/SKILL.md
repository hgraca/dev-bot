---
name: devbot:improve-reviewing
description: "Use at wrap-up, when the session ran a code review loop, to turn the findings our reviewer missed into a pull request that improves what the reviewer catches."
---

# Skill: Improve Reviewing from External Feedback

A review loop on the session's pull request — Copilot's, or any reviewer that is not our own
`@reviewer` — is the only evidence we get of what the reviewer still cannot see. This skill turns
that evidence into a change in the toolkit: a pull request against the dev-bot repository that makes
the reviewer catch those issues before a pull request exists.

Two rules make it useful rather than noisy:

- **Generic, never one project's incident.** The gap is a check the reviewer does not perform. Write
  the change as that generalized check, and keep every project, product, customer and consumer
  repository name out of it — including the pull-request body. A rule shaped around one codebase
  misleads the reviewer in the next one.
- **One go-ahead to publish, none per suggestion.** The human confirmed the session's work is
  finished — not that a pull request should be opened against the toolkit repository. Draft and commit
  every gap first, then ask once whether to push and open it. Once the pull request exists, its review
  is where a suggestion is approved, modified or dropped.

## When to Apply

- **Primary trigger**: the finish flow (see `devbot:agent-communication`), after
  `devbot:reconcile-work`, **only when the session ran an external review loop**.
- The user asks to make the reviewer catch what an external review caught.

An **external review loop** is the pull request's own loop with a reviewer that is not us — Copilot,
a human, another tool — whose findings this skill can read. Our own `@reviewer` pass before the pull
request exists is not one: it has no `@reviewer`-independent findings to learn from, and this skill
skips it. With no such loop there is no evidence of a gap, and a speculative rule makes the reviewer
worse, not better.

## Improvements land in two files

| Improvement kind                                                                                  | Target                                                      |
| ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| reviewer **behaviour** — workflow, tone, behavioural MUST/MUST NOT rules, skill references        | `src/agentic/devteam/agents/reviewer.md`                    |
| What the reviewer **inspects and flags** — checks, issue types, finding patterns, report template | `src/agentic/devteam/skills/review-implementation/SKILL.md` |

Paths are relative to the dev-bot repository root. Anything that is not about reviewing stays out of
both files; a gap that belongs to another reviewer-referenced skill is raised as a follow-up, not
landed here.

## Procedure

### 1. Locate the dev-bot repository

The target is the installed toolkit's own checkout, not the project the session worked in:

```bash
root="$DEV_BOT_ROOT"
git -C "$root" remote get-url origin        # the repository the pull request is opened against
```

When `DEV_BOT_ROOT` is empty, resolve this skill's directory **physically** before walking up: the
path the harness reports is a farm link, so `pwd -P` is what leads into the dev-bot checkout.

```bash
dir="$(cd "<this skill's base directory>" && pwd -P)"
while [ "$dir" != "/" ] && [ ! -d "$dir/src/agentic" ]; do dir="$(dirname "$dir")"; done
root="$dir"
```

If neither route yields a directory holding `src/agentic/`, stop and ask the user where the dev-bot
checkout is — never guess, and never work in the current project instead. Likewise, when `gh` cannot
push to or open a pull request against that repository, stop and report it: this step needs no other
credential.

### 2. Collect the findings

Read them from the session before it is gone — the whole review conversation on the pull request(s) it
worked, not only its inline threads. A body-only finding leaves no thread, and the wrap-up squash
folds each `fixup!` into its target so the commits no longer name the gap either. So collect from:

- the review bodies and the top-level comments: `gh pr view <pr> --json reviews,comments`
- the inline threads: `gh api repos/<owner>/<repo>/pulls/<pr>/comments`
- the `fixup!` commits still present, which `devbot:gh-review-loop` writes one per line finding

For each finding capture what was flagged, its category (correctness, security, performance,
architecture, testing, style), whether it took a code change, and whether our reviewer should have
caught it.

Keep only findings where our reviewer **should** have caught it **and** does not already cover it —
check that second part against `reviewer.md` and `review-implementation/SKILL.md`, never from memory.

### 3. Assess progress before cutting anything

Gaps recur across sessions by definition, so never assume a fresh start. Everything below runs
**from `$root`**: `worktree.sh` resolves the repository from the working directory, and wrap-up
normally runs in the consumer project.

```bash
cd "$root"
dir="$(devbot tool project-for-path "$root" --key devbot_dir)"   # configured worktree root
bash src/agentic/git/tools/worktree.sh list                       # "<path> <branch>" per worktree
git rev-parse --verify --quiet refs/heads/chore/<slug>
git rev-parse --verify --quiet refs/remotes/origin/chore/<slug>
gh pr list --head chore/<slug> --state all --json number,url,state
```

`worktree.sh path` looks like the probe and is not: it exits `FATAL` for a branch with no worktree,
which is the ordinary first run. `list` is the probe.

Read the pull request state first — it decides whether the branch may be continued at all — then what
the checkout holds:

| Pull request     | Local state               | What to do                                                                                                                                                |
| ---------------- | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| open             | a worktree for the branch | work there — never `create`                                                                                                                               |
| open             | the branch, no worktree   | attach it, then continue: `git worktree add "$dir/worktrees/chore-<slug>" chore/<slug>`, fetching `origin/chore/<slug>` first when only the remote has it |
| merged or closed | any                       | that gap is closed: a new slug and a new branch, never a revival — the stale worktree and branch are `devbot:reconcile-work`'s                            |
| none             | a worktree or branch      | a run whose pull request was declined: continue it, or take a new slug if it was abandoned                                                                |
| none             | nothing                   | `bash src/agentic/git/tools/worktree.sh create chore/<slug>`                                                                                              |

`create` refuses an existing branch or path, which is why every other row avoids it. The attach path
uses the project's configured worktree root — a hard-coded `.agents` is wrong for a project that
renamed it — and `<slug>` in it is the branch with `/` written as `-`, the tool's own convention.

Then edit only absolute paths under the worktree, with every git command run as `git -C <worktree>`.

Agents and skills are symlinked into the running harness from the main checkout, so a worktree commit
takes effect only once it is merged — say so in the hand-back rather than implying the running
session already reviews differently.

### 4. Draft the change

Read both target files first, then write the smallest change that would have caught the finding:

- **New check** — add it to `review-implementation/SKILL.md` under `## Recurring issue types`:
  `### Generic` when it applies to any stack, `### Technology-specific → #### <technology>` when it
  does not. Follow the existing shape — a numbered heading, the checks, and the property the code
  must satisfy.
- **Strengthened check** — extend the existing section with the verification step that was missing.
- **Behaviour rule** — add it to `reviewer.md` only when it governs how the reviewer works or
  reports; what it inspects belongs in the skill.

State the property to verify, not the incident that revealed it. One gap, one change: two findings
that reduce to the same check are one check.

### 5. Ask once, then open the pull request

Commit each gap atomically with a Conventional Commit (`devbot:git-commits`). Then present the result
as one line per gap — the generalized check, the target file, and the change in a clause — and ask
once whether to **push and open the pull request**. On a refusal, leave the commits on the local
branch, name the branch and the worktree, and stop there.

With the go-ahead, push it — from `$root`, `bash src/agentic/git/tools/worktree.sh push chore/<slug>`, so
the tool resolves the repository it acts on — and open it with `devbot:gh-create-pr`, which owns the
title and body rules — including its exception for a pull request that does not belong to the
session's project's work, which this one is. Never merge it. Its review belongs to the human: the
next session that touches the dev-bot project picks up whatever is still unresolved.

### 6. Report

Report the pull request URL and what it would catch, and say that the rules take effect once merged.
When nothing survived step 2's filter, say so in one line and stop: an unchanged reviewer is a valid
outcome.

## MUST

- Read both target files before drafting a change.
- Keep every rule generic — no project, product, customer or consumer-repository name in the change or in the pull-request body.
- Route each gap by kind: behaviour → `reviewer.md`, inspection → `review-implementation/SKILL.md`.
- Preserve the existing structure, heading hierarchy and numbering of the target files.
- Draft only changes that address a finding the session actually produced.
- Ask once before publishing, and leave the commits local when the answer is no.

## MUST NOT

- Add checks that duplicate what the target files already cover.
- Remove or weaken an existing check or rule.
- Put inspection content (checks, issue types) in `reviewer.md`, or behavioural rules in
  `review-implementation/SKILL.md`.
- Touch production code, non-reviewer agents or skills, or files with "no-vcs" in the name.
- Merge the pull request, or commit the change anywhere but its own worktree branch.
- Write memory notes: the finish flow's memory capture has already run, and it stays the last write
  to the vault.
