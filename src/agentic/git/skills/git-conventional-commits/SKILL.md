---
name: git-conventional-commits
description: Write commit messages in Conventional Commits format — the "type(scope) then description" convention, plus bodies, footers, and breaking-change notation. Use whenever a commit message needs writing or reviewing, when the user asks about commit message format, prefixes, types, scopes, "how should I word this commit", "what prefix do I use", "is this message right", or mentions semantic versioning driven by commit messages. Also use when about to write any commit message in a repository whose existing history follows this convention, even if the user did not mention the format.
---

# Conventional Commits

A commit message format that makes history scannable and can drive automated versioning and changelogs.

## Structure

```
<type>(<scope>)<!>: <description>

[optional body]

[optional footer(s)]
```

Only `<type>` and `<description>` are required. The `!` marks a breaking change.

```
feat(auth): add OAuth2 support
fix: handle null response from /users
refactor(utils)!: drop callback API from date helpers
```

## Types

| Type       | Use for                                                    | Version impact |
| ---------- | ---------------------------------------------------------- | -------------- |
| `feat`     | New feature for the user                                   | MINOR          |
| `fix`      | Bug fix for the user                                       | PATCH          |
| `docs`     | Documentation only                                         | —              |
| `style`    | Formatting, whitespace, semicolons; no code meaning change | —              |
| `refactor` | Restructuring that neither fixes a bug nor adds a feature  | —              |
| `perf`     | Performance improvement                                    | PATCH          |
| `test`     | Adding or correcting tests                                 | —              |
| `build`    | Build system or external dependencies                      | —              |
| `ci`       | CI configuration and scripts                               | —              |
| `chore`    | Anything else not touching src or tests                    | —              |
| `revert`   | Reverts a previous commit                                  | —              |

Anything marked `!` or carrying a `BREAKING CHANGE:` footer is MAJOR regardless of type.

Choose the type by the _user-visible effect_, not the size of the diff. A one-character change that fixes wrong behaviour is `fix`; a 500-line reorganization that changes nothing observable is `refactor`.

## Scope

The scope names the part of the codebase affected — a module, package, or subsystem. Keep it a single lowercase noun and stay consistent with existing history:

```bash
git log --format='%s' -50 | sed -n 's/^[a-z]*(\([^)]*\)).*/\1/p' | sort | uniq -c | sort -rn
```

That lists the scopes already in use, which matters more than any external convention. Omit the scope when a change is genuinely global or when the repo doesn't use scopes.

```
feat(auth): add OAuth2 support
fix(api): handle null response from /users
docs(readme): add installation instructions
refactor(utils): extract date formatting
test(cart): add checkout flow tests
```

## Description

The description is the subject line after the colon:

- Imperative mood — "add", not "added" or "adds". It should complete the sentence "this commit will _____".
- Lowercase start, no trailing period.
- Aim for a subject line under ~72 characters total.
- Say what changed and why it matters, not which files moved.

```
feat(auth): add OAuth2 support                    <- good
feat(auth): Added OAuth2 Support.                 <- wrong mood, capitalized, period
feat(auth): update auth.ts and config.ts          <- describes files, not the change
fix: stuff                                        <- says nothing
```

If the description needs "and", the commit probably needs splitting — see the atomic-commits skill.

## Body

Add a body when the _why_ isn't obvious from the subject. Separate it from the subject with a blank line, wrap around 72 characters, and explain the reasoning and any consequences rather than restating the diff:

```
fix(api): retry idempotent requests on 503

The upstream gateway returns 503 during its rolling deploys, which
surfaced to users as failed checkouts. Retry twice with backoff for
requests we know are safe to repeat.

Non-idempotent calls are deliberately excluded.
```

## Footers

Footers go last, one per line, as `Token: value`:

```
Refs: #142
Reviewed-by: Alex Kim
Co-authored-by: Sam Patel <sam@example.com>
BREAKING CHANGE: config.timeout is now milliseconds, not seconds
```

Many hosts auto-close issues from `Closes: #142` or `Fixes: #142`. Check the project's convention before relying on it.

## Breaking changes

Two ways to mark one, and they can be combined:

```
feat(api)!: require auth token on all endpoints
```

```
feat(api): require auth token on all endpoints

BREAKING CHANGE: unauthenticated requests now return 401 instead of
falling back to the anonymous role. Callers must send Authorization.
```

The `!` is the scannable signal; the footer is where the migration path goes. For anything a downstream consumer must act on, write the footer — `!` alone tells them something broke but not what to do.

## Checking a message against project history

Before writing, match what the repo already does:

```bash
git log --format='%s' -30                    # existing subject style
git log --format='%s' -200 | sed -n 's/^\([a-z]*\)[(:!].*/\1/p' \
  | sort | uniq -c | sort -rn                # types in use
ls .commitlintrc* commitlint.config.* 2>/dev/null   # enforced rules, if any
cat .gitmessage 2>/dev/null                  # project template
```

If the repo has a commitlint config, it is authoritative over this skill — read it and follow it.
If the history plainly doesn't use Conventional Commits, match the local style instead of imposing this one;
mention the option rather than silently switching formats.

## Ticket IDs

Some projects prefix the subject with a ticket ID instead of the conventional type — e.g. `POS-666: add user authentication`.
When a task carries a ticket ID, use it as the subject prefix; when there is no ticket, use plain Conventional Commits.
Check existing history to confirm the repo's ticket-prefix format before assuming one.

## Related skills

- **atomic-commits** — deciding what belongs in each commit before writing its message
- **fixup-commits** — replacing a wrong message on an earlier commit via `--fixup=reword:`
- **advanced-operations** — rewording messages across a range of commits
