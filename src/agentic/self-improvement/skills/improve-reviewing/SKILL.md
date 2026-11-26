---
name: devbot:improve-reviewing
description: "Use at wrap-up, when the session ran a code review loop, to turn the findings our reviewer missed into a pull request that improves what the reviewer catches."
---

# Skill: Improve Reviewing from External Feedback

A review loop on the session's pull request — Copilot's, or any reviewer that is not our own
`@reviewer` — is the only evidence we get of what the reviewer still cannot see. This skill turns
that evidence into a change in the toolkit: a pull request against the dev-bot repository that makes
the reviewer catch those issues before a pull request exists.

Three rules make it useful rather than noisy:

- **Generic, never one project's incident.** The gap is a check the reviewer does not perform. Write
  the change as that generalized check, and keep every project, product, customer and consumer
  repository name out of it — including the pull-request body. A rule shaped around one codebase
  misleads the reviewer in the next one.
- **Unattended in the finish flow, one go-ahead standalone.** The finish flow runs without prompts:
  draft and commit every gap, then push and open or update the standing pull request directly; the
  pull request's review is where a suggestion is approved, modified or dropped. Only a standalone
  invocation ("make the reviewer catch what this review caught") asks once before publishing.
- **One standing pull request.** Every session's gaps go to the same titled pull request; a second one
  splits the review and the history of the reviewer's growth across two places.

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

Paths are relative to the dev-bot repository root. The standing pull request also carries a change to
a review-loop skill — `review-loop`, `gh-create-pr` or `gh-review-loop` — when the gap is in how a loop runs, because
that is the same evidence read one step earlier. Anything else is out of scope: anything not about
reviewing stays out of both files, and a gap belonging to any other skill is raised as a follow-up,
not landed here.

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
folds each fixup! into its target so the commits no longer name the gap either. So collect from:

- the review bodies and the top-level comments: `gh pr view <pr> --json reviews,comments`
- the inline threads: `gh api repos/<owner>/<repo>/pulls/<pr>/comments`
- the fixup! commits still present, which `devbot:review-loop` writes one per finding

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
# The standing pull request this skill appends to, on whatever branch it sits.
gh pr list --state open --limit 200 --json number,url,headRefName,title \
  --jq '.[] | select(.title == "chore(improve-reviews): improve review skill")'
```

The standing lookup prints nothing when there is no such pull request: an empty answer means "none",
not that the query was wrong. Set the limit: `gh pr list` pages at 30 by default, and a standing pull
request beyond that page would read as "none" and invite the twin this rule forbids. When it prints
more than one, do not guess and do not open a third — list them and stop, naming the collision in the
wrap-up report; two open pull requests under that title is a state only the human can resolve, and the
finish flow does not wait for that answer. Match the title exactly in `--jq`, never through `--search`.

`worktree.sh path` looks like the probe and is not: it exits `FATAL` for a branch with no worktree,
which is the ordinary first run. `list` is the probe.

Read the pull request state first — it decides whether the branch may be continued at all — then what
the checkout holds:

| Pull request     | Local state               | What to do                                                                                                                                                                           |
| ---------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| the standing one | any                       | append to it: work on its `<headRefName>` — reuse the worktree `worktree.sh list` shows, else attach it as the next row does — and skip `create`; this session opens no pull request |
| open             | a worktree for the branch | work there — never `create`                                                                                                                                                          |
| open             | the branch, no worktree   | attach it, then continue: `git worktree add "$dir/worktrees/chore-<slug>" chore/<slug>`, fetching `origin/chore/<slug>` first when only the remote has it                            |
| merged or closed | any                       | that gap is closed: a new slug and a new branch, never a revival — the stale worktree and branch are `devbot:reconcile-work`'s                                                       |
| none             | a worktree or branch      | a run whose pull request was declined: continue it, or take a new slug if it was abandoned                                                                                           |
| none             | nothing                   | `bash src/agentic/git/tools/worktree.sh create chore/<slug>`                                                                                                                         |

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

### 5. Final pass over the changed files

The gaps are fixed; the file they landed in may not read as one document yet. Before publishing,
re-read **every file the change touched** end to end — not the diff — and remove what the
accumulation left behind:

- **Inconsistencies** — a rule the new check now contradicts, a term used two ways, a count or a
  cross-reference that no longer matches.
- **Redundancies** — the same property asserted twice in different words; keep the stronger
  statement and delete the other.
- **Duplications** — a check that repeats one already in the file; fold the new detail into the
  existing check instead of adding a second number.
- **Ambiguities** — a predicate a reader can read two ways, an unstated scope, a term used before it
  is defined.

Renumber whatever moved and keep the numbering contiguous: a list with a gap reads as a lost rule.
**Keep every property** — a pass that deletes a check to tidy the file has broken the skill, and that
is worse than the repetition it removed.

### 6. Publish the pull request

Commit each gap atomically with a Conventional Commit (`devbot:git-commits`), the final pass
included. In the finish flow, publish directly — the wrap-up is unattended: push the branch and open
or update the standing pull request without asking. On a standalone invocation, present the result as
one line per gap — the generalized check, the target file, and the change in a clause — and ask once
whether to **push and publish**; on a refusal, leave the commits on the local branch, name the branch
and the worktree, and stop there.

The pull request always carries this title:

```text
chore(improve-reviews): improve review skill
```

It does not restate the gaps and is not composed from the commits: it is the standing home for this
kind of change, so a later session finds the open one instead of opening a twin. Step 3 already
answered which of the two cases applies:

- **No standing pull request open** — push the branch (`bash src/agentic/git/tools/worktree.sh push
chore/<slug>` from `$root`, so the tool resolves the repository it acts on) and open the pull
  request with `devbot:gh-create-pr`, which owns the body rules, using the fixed title above.
- **One open** — do **not** open a second: push the branch step 3 put you on
  (`bash src/agentic/git/tools/worktree.sh push <headRefName>` from `$root`) so the standing pull
  request grows and its review stays in one place.

Never merge it. Its review belongs to the human: the next session that touches the dev-bot project
picks up whatever is still unresolved.

### 7. Report

Report the pull request URL and what it would catch, and say that the rules take effect once merged.
Count the standing pull request's commits (`gh pr view <pr> --json commits --jq '.commits | length'`);
when the count is **greater than 10**, report the number and recommend merging it before it grows
further. When nothing survived step 2's filter, say so in one line and stop: an unchanged reviewer is
a valid outcome.

## MUST

- Read both target files before drafting a change.
- Keep every rule generic — no project, product, customer or consumer-repository name in the change or in the pull-request body.
- Route each gap by kind: behaviour → `reviewer.md`, inspection → `review-implementation/SKILL.md`.
- Preserve the existing structure, heading hierarchy and numbering of the target files.
- Draft only changes that address a finding the session actually produced.
- Publish without asking when the finish flow invokes the skill: push and open or update the standing pull request directly; ask once only on a standalone invocation.
- Run the final pass over every touched file before publishing, and keep every property it is tempted
  to delete.
- Title the pull request `chore(improve-reviews): improve review skill`, and append to that open
  standing pull request instead of opening a second.
- Report a standing pull request that carries more than 10 commits, and recommend merging it.

## MUST NOT

- Add checks that duplicate what the target files already cover.
- Remove or weaken an existing check or rule.
- Put inspection content (checks, issue types) in `reviewer.md`, or behavioural rules in
  `review-implementation/SKILL.md`.
- Touch production code, non-reviewer agents or skills, or files with "no-vcs" in the name.
- Merge the pull request, or commit the change anywhere but its own worktree branch — or the open
  standing pull request's branch, when that is where step 3 put you.
- Compose the pull-request title from the gaps, or open a second standing pull request.
- Write memory notes: the finish flow's memory capture has already run, and it stays the last write
  to the vault.
