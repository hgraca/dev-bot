---
name: devbot:git-commits
description: "Load at session start in every project under git."
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

A commit that solves nothing has no reason to exist, and a body that only restates the diff is
noise. Keep each bullet to a single idea, and keep it under 72 characters so it reads unwrapped in a
terminal.

```text
fix(api): retry idempotent requests on 503

Problems:
- gateway returns 503 during its rolling deploys
- users saw failed checkouts as a result

Solutions:
- retry twice with backoff on idempotent calls
- exclude non-idempotent calls deliberately
```

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
explicit approval, and on a protected or shared branch prefer a normal follow-up commit.

## Routing

| Doing this                                                                 | Read                              |
| -------------------------------------------------------------------------- | --------------------------------- |
| Writing a message, type taxonomy, footers, breaking changes, ticket IDs    | `devbot:git-conventional-commits` |
| Deciding what belongs in each commit, splitting, ordering, branch creation | `devbot:git-atomic-commits`       |
| Correcting a commit unique to the branch (`--fixup`, autosquash)           | `devbot:git-fixup-commits`        |
| Partial staging, stash isolation, splitting a made commit, reflog recovery | `devbot:git-advanced-operations`  |
| Producing a release file from the branch's commits                         | `devbot:git-changelog`            |
