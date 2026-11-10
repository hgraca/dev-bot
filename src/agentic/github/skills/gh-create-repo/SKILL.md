---
name: devbot:gh-create-repo
description: "Use when creating a GitHub repository. Triggers on 'create a repo', 'new repository', 'gh repo create', 'scaffold a repo'."
---

# Create Repository

Create a GitHub repository whose first commit contains a README and nothing else, then apply the
standard configuration through the `gh-configure-repo` tool. The tool owns the definition of that
standard, so this skill never hand-builds a ruleset payload — one place defines it, one place
changes it.

## When to Apply

- The `gh-create-repo` command asks for a repository to be created.
- The user asks to create, scaffold, or initialise a GitHub repository.

## Preconditions

- `gh` is installed and authenticated (`gh auth status`). If it is not, stop and say so — do not guess
  at credentials.
- `jq` is installed — `gh-configure-repo` requires it; the module's install script provisions it.
- In a polyrepo project, resolve the **owning project** (`devbot tool project-for-path <path>`)
  and run every command there.

## Procedure

Progress:

- [ ] Step 1: Confirm owner, name, visibility, description
- [ ] Step 2: Create the repository with a README-only initial commit
- [ ] Step 3: Apply the standard configuration
- [ ] Step 4: Add required status checks once CI has run

### Step 1 — Confirm the essentials

Ask in one round: **owner** (personal account or organisation such as `GET-E`), **name**,
**visibility** (default: private), and a one-line **description**. Never infer any of these from the
current directory or from a previous repository — a repo created under the wrong owner is painful to
move and may briefly leak content if it lands public.

### Step 2 — Create with a README and nothing else

```bash
gh repo create <owner>/<name> <--private|--public|--internal> --add-readme --description "<description>"
```

Pass the flag matching the visibility confirmed in Step 1 — `--private`, `--public`, or
`--internal` (organisations only). Hard-coding one silently ignores the answer.

`--add-readme` creates the default branch with exactly one commit containing `README.md`. That
initial commit is what lets the next step target a default branch — protection cannot apply to a
branch that does not exist yet.

Do **not** pass `--gitignore` or `--license`: "README only" means nothing else in the repository. Do
not `--clone` unless the user asks.

### Step 3 — Apply the standard configuration

The repository now exists, which is all `gh-configure-repo` needs. Dry run first, then apply:

```bash
devbot tool gh-configure-repo <owner>/<name>
devbot tool gh-configure-repo <owner>/<name> --apply
```

It sets, in one idempotent pass:

- pull requests enabled for all users, merge commits titled with the PR title and described with its
  body, squash merging titled with the PR title, rebase merging, suggest updating PR branches, and
  auto-merge;
- merged head branches deleted on merge;
- one `default-branch` ruleset: no force pushes, no deletion, changes only via pull request with one
  approving review and conversation resolution.

It reads back the effective rules and the override role from the API, so there is no manual
verification step here — if the configuration did not take effect, the tool fails.

**Choose the override deliberately.** Pass `--bypass` (default `pull-request`) and, if needed,
`--bypass-role` (default `write`):

| `--bypass`     | Who can skip the review and the CI                                                 |
| -------------- | ---------------------------------------------------------------------------------- |
| `pull-request` | a PR is still mandatory, but it can be merged without the approval or green checks |
| `always`       | the branch can also be pushed to directly                                          |
| `none`         | nobody — the rule is a hard gate                                                   |

Only `write`, `maintain` and `admin` can be bypass actors; GitHub rejects a role without write
permission, and the tool refuses rather than guessing.

### Step 4 — Add required status checks once CI exists

A brand-new repository has no workflows, so there is no check to require. Once the default branch has
run CI at least once, add the workflow **job name**:

```bash
devbot tool gh-configure-repo <owner>/<name> --apply --required-check "<job name>"
```

The tool merges it with any check it already carries. Do not add a context that never reports — that
leaves every pull request waiting forever.

## Gotchas

- **Rulesets layer with classic protection, and the most restrictive rule wins.** This does not arise
  for a repository the skill just created, but it does when the tool is pointed at an older repo: the
  override only takes effect once legacy classic protection is gone.
- **`--bypass none` is a hard gate.** Nobody can override it, administrators included. The tool accepts
  only `none`, `pull-request` and `always`, so there is no silent-exemption mode.
- **The override is a ceiling on enforcement, not the default path.** With a bypass in place, review
  and green CI are a convention with an audit record — do not describe such a branch as "protected
  against unreviewed merges".

## See also

- `gh-configure-repo` tool — the whole standard, and how it is applied to an existing repository
- `devbot:gh-create-pr` — opening the first pull request against the new default branch
