---
name: devbot:gh-create-repo
description: Create a GitHub repository with a README-only first commit and default-branch ruleset protection
---

Create a GitHub repository, following the `devbot:gh-create-repo` skill.

Repository name: $1

If no name is given, ask for one before proceeding. Also confirm the owner, visibility, and
description — never guess them.

## Steps

1. Confirm with the user, in one round: **owner** (personal account or organisation such as `GET-E`),
   **name**, **visibility** (default private), and a one-line **description**.
2. Create the repository following the skill's Step 2:

   ```
   gh repo create <owner>/<name> <--private|--public|--internal> --add-readme --description "<description>"
   ```

   Use the visibility and description confirmed in step 1, and nothing else — no `--gitignore`, no
   `--license`.

3. Ask which override policy the repository should carry — `pull-request` (default: a PR is required,
   but it may be merged without the approval or green checks), `always` (direct pushes allowed), or
   `none`. Never default this silently.
4. Show the plan before changing anything:

   ```
   devbot tool gh-configure-repo <owner>/<name> --bypass <policy>
   ```

   That is a dry run and writes nothing. Wait for the user to approve the plan.

5. Apply the approved plan:

   ```
   devbot tool gh-configure-repo <owner>/<name> --apply --bypass <policy>
   ```

6. Report the repository URL, the ruleset summary, and state explicitly that required status checks
   stay pending until CI has run once (they can then be added with `--required-check`).

## Must not

- Push application code, a license, or a `.gitignore` — the first commit is the README and nothing else.
- Hand-build a ruleset payload or invent a numeric `RepositoryRole` actor id — `gh-configure-repo` owns
  both and verifies the applied role against the API.
