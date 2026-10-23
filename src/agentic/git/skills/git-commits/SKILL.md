---
name: devbot:git-commits
description: "Load at session start in every project under git. Use when making a commit or wording its message."
---

# Git Commits

The rules that apply to every commit in a repository under git. This is the shared core; the
technique-specific skills build on it — see [Routing](#routing) at the end.

## Commit message anatomy

```text
<type>(<scope>)!: <description>

Problems:
- <what was wrong, missing, or at risk — ≤72 chars>
- <what was wrong, missing, or at risk — ≤72 chars>

Solutions:
- <what this commit does about it — ≤72 chars>
- <what this commit does about it — ≤72 chars>

[optional footers]
```

The `<type>(<scope>)` taxonomy, the version impact of each type, footers, and breaking-change
notation live in `devbot:git-conventional-commits` — this skill defines the skeleton they fill in.

## Message checklist (MUST)

Check every message against this list before the commit is made. A rule that is not checked is a
rule that gets skipped, and a message is read far more often than it is written:

- Subject: imperative, lowercase start, no trailing period, ≤72 characters.
- Body: `Problems:` and `Solutions:`, each with at least one bullet.
- Every bullet: one idea, ≤72 characters, so it reads unwrapped in a terminal.
- No paragraph body — not even one explaining the why. That reasoning belongs
  in the bullets; any prose body is a defect, not a style choice.
- Exempt from this list: `Merge`/`Revert` as git writes them, and the
  `fixup!`/`amend!`/`squash!` markers as `git commit --fixup`/`--squash` writes
  them. Git writes their subject and body, so neither the subject rules nor the
  two-list form apply. A marker prefix you type yourself is not an exemption.

The sections below explain each rule in full; this list is the gate they exist to enforce.

## Subject

- Imperative mood — "add", not "added" or "adds".
- Lowercase start, no trailing period.
- At most 72 characters.
- Say what changed and why it matters — not which files moved.

```text
feat(auth): add OAuth2 support                    <- good
feat(auth): Added OAuth2 Support.                 <- wrong mood, capitalized, period
feat(auth): update auth.ts and config.ts          <- describes files, not the change
fix: stuff                                        <- says nothing
```

## Body — the why, not the how

The diff already shows the _how_: which lines changed and in what order. Restating it in the message
duplicates what `git show` prints better. What the diff cannot tell a future reader is _why_ the
change was made — the problem that prompted it, and the constraint the solution had to respect.
That is what the body carries.

State it as two lists:

- **Problems** — what was wrong, missing, or at risk. One bullet per distinct problem, ≤72 chars.
- **Solutions** — what the commit does about each one. One bullet per solution, ≤72 chars.

A commit that solves nothing has no reason to exist. The reasoning has a home too: the `Problems:`
bullet that names the problem, and the `Solutions:` bullet that says what changes — not a paragraph
above the lists. Keep each bullet to a single idea, and keep it under 72 characters so it reads
unwrapped in a terminal.

```text
fix(api): retry idempotent requests on 503

Problems:
- gateway returns 503 during its rolling deploys
- users saw failed checkouts as a result

Solutions:
- retry twice with backoff on idempotent calls
- exclude non-idempotent calls deliberately
```

The only messages outside this form are the ones git writes itself: `Merge`, `Revert`, and the
`fixup!`/`amend!`/`squash!` markers — their subject and body are git's, so neither rule set applies
to them. Writing a marker prefix by hand does not opt a message out. See
[Message checklist](#message-checklist-must).

**The why belongs here, not in code comments.** A comment explaining why a line exists, what
workaround it encodes, or what would break without it is a commit-description line that ended up in
the wrong file: invisible to `git log`, rotting in place, and duplicating a message the body could
carry once. Leave the code to say what it does, and reserve in-code comments for the 1–2 lines of
non-obvious mechanics a reader cannot infer — see the Comments rules in `devbot:software-development`.

## Rewriting history (MUST)

Anything that rewrites history — `rebase`, `commit --amend`, `reset` — is safe on commits that exist
only on your machine, and dangerous on shared ones. Check before rewriting:

```bash
git branch -r --contains <sha>        # empty output means not pushed anywhere
git log --oneline @{upstream}..HEAD   # the range that is yours alone
```

If the commit is on a remote, rewriting forces every collaborator to reset or force-pull. Get
explicit approval. When the target commit is already reachable from the default branch — or from
another branch or repository — prefer a normal follow-up commit: that is the shared history this rule
protects.

Creating a fixup commit is **not** rewriting — it only adds a commit, so it is safe on a pushed
feature branch and needs no approval, including a branch with an open pull request. The rewrite is
the squash that folds it in; on a pull-request branch that squash is the expected pre-merge step, and
the human publishes it with `git push --force-with-lease` — the guards module blocks force-pushes for
the agent (see `devbot:git-fixup-commits`).

## Committing from a worktree (MUST)

When the project follows the `worktrees` workflow (the default), commit from a linked git
worktree, never from the main checkout — except the finish flow's memory commits, which are normal
commits made on the main checkout's local default branch (`devbot:remember-session`). Before the first edit, confirm the workflow is in use —
`worktree.sh enabled` — in a `supervisor: true` session pass `--project <owner>` after resolving the
owner, since the tool refuses a supervisor root — exits `1` when the project follows another workflow
(e.g. `"workflow": "trunk"`), in which case commit where that workflow directs: the **owning project's** main
checkout (in a `supervisor: true` session, `git -C <owner>`; otherwise the current one). Exit `2`
means the configured workflow is unknown — stop and ask. Otherwise check where you are: `git rev-parse --git-dir --git-common-dir` printing the **same** path means you are in
the main checkout and must isolate the work first:

```bash
bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create <branch>
```

The worktree is cut from `origin/<default>` under `<devbot_dir>/worktrees/<slug>`; all edits use
its absolute path and all git commands run with `-C <worktree>`. The full policy — the tool's
subcommands, the opt-out, and the finish flow — is `devbot:git-worktrees`.

In a `supervisor: true` project the repository is the **owning project** of the files in the
commit (`devbot tool project-for-path <file>`), never the supervisor root. Create the worktree
with `--project <owner>`; after that, run edits and commits with `git -C <worktree>`, and reserve
`git -C <owner>` for owner-scoped commands (worktree creation, merge, remove). A commit never
spans two repositories.

## Committing in a shared main checkout (MUST)

When the user explicitly approves committing in the main checkout (see `devbot:git-worktrees`), the
index may already hold another agent's staged work. Never commit bare — pass the same paths you
staged:

```bash
git add <your-file> [<your-file>…]
git commit -m "<message>" -- <your-file> [<your-file>…]
git show --stat HEAD   # must list only your files
```

The pathspec leaves every other index entry untouched. If `git show --stat` lists a file you did not
change, stop and surface it — never "fix" or discard another agent's staged work.

## Routing

| Doing this                                                                 | Read                              |
| -------------------------------------------------------------------------- | --------------------------------- |
| Writing a message, type taxonomy, footers, breaking changes, ticket IDs    | `devbot:git-conventional-commits` |
| Deciding what belongs in each commit, splitting, and ordering              | `devbot:git-atomic-commits`       |
| Correcting a commit unique to the branch (`--fixup`, autosquash)           | `devbot:git-fixup-commits`        |
| Partial staging, stash isolation, splitting a made commit, reflog recovery | `devbot:git-advanced-operations`  |
| Creating a task branch and isolating its commits in a worktree             | `devbot:git-worktrees`            |
| Producing a release file from the branch's commits                         | `devbot:git-changelog`            |
