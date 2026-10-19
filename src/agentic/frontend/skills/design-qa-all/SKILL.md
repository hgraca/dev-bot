---
name: devbot:design-qa-all
description: "Use when running design QA across every mapped entry in design-map.json — all entries, only the changed ones, or one. Triggers on 'design QA all', 'check every mapped page', 'design QA before the PR'."
---

# Design QA (batch)

Run the `devbot:design-qa` check for entries in `design-map.json` and write one report. This skill is
**report-only**: never pass `--fix` and never edit source files. The only file it writes is
`design-qa-report.md`.

Keep the main context small. Every entry runs in its own subagent, and only the compact result comes
back.

## When to Apply

- The `design-qa-all` command asks for a batch run.
- The user asks to check every mapped page, or every page the branch changed, before a PR.

## Inputs

```text
[--changed-only [--base <branch>]] [--only <id>]
```

## 1. Select entries

Read `design-map.json` from the repo root. If it's missing, stop and say so.

| Arguments                          | Entries                                                                  |
| ---------------------------------- | ------------------------------------------------------------------------ |
| none                               | all entries                                                              |
| `--only <id>`                      | the entry with that `id`; if none matches, stop and list the closest ids |
| `--changed-only [--base <branch>]` | entries affected by changes vs the base branch, see below                |

### --changed-only

1. Find the changed files with the shell. Don't run `git fetch`; use what's local. The base is
   `--base`, else `project.baseBranch`, else `origin/HEAD`, else `main`. Set `project.baseBranch` to
   the repository's **integration branch** — the one PRs target, which is not always `main`; the
   remote default can otherwise select a far larger changeset than the branch actually carries.

   ```bash
   BASE=<branch>
   REF=$(git rev-parse --verify -q origin/$BASE || git rev-parse --verify -q $BASE)
   MB=$(git merge-base "$REF" HEAD)
   [ -n "$MB" ] || { echo "ERROR: no common ancestor with $BASE (shallow checkout?) — fetch the base history and re-run" >&2; exit 1; }
   { git diff --name-only "$MB"...HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
   ```

   - If `REF` is empty, stop and say the base branch wasn't found.
   - If `MB` is empty, stop with an actionable error before collecting paths — an empty merge base
     turns the diff into `...HEAD`, which silently compares HEAD with itself.
   - If there are no changed files, report "No changes vs <base>" and stop.

2. **Direct matches.** An entry is affected if any changed file matches any of its `sourcePaths`. Match
   the patterns like this:
   - `**` matches any path, including `/`;
   - `*` matches anything except `/`;
   - a plain path matches exactly.

3. **Shared code.** For each changed file under a `project.sharedRoots` directory:
   - resolve the import specifiers that can reach it before matching: relative paths against the
     importer's directory, the project's configured path aliases, and folder index files (an import of
     `./PrimaryButton` and of `components/buttons` must both resolve to
     `components/buttons/PrimaryButton.tsx`);
   - grep `project.sourceRoot` for every file whose resolved specifier is the changed file, then repeat
     once for those importers, so the search goes 2 levels deep;
   - an entry is affected if any importer matches its `sourcePaths`.

   Mark these entries as "via `<shared file>`". Skip this step when `project.sharedRoots` is absent or
   empty.

4. **Global styling.** If any file in `project.globalStyleFiles` changed, every entry is affected. Mark
   them as "via global styles". Skip this step when the list is absent or empty.

5. If the selection is empty, report which files changed and that no mapped entry covers them, then
   stop.

## 2. Skip what can't run

Don't run these entries; list each under **Skipped** with its reason:

| Condition                                                           | Reason                    |
| ------------------------------------------------------------------- | ------------------------- |
| `url` still contains a route parameter (`:id`, `:userId`, `:uuid`…) | `needs a concrete URL`    |
| `type` is `component` and has no `url`                              | `no page to render it on` |

## 3. Preflight (once)

1. **App is up:**

   ```bash
   PREFLIGHT_ROUTE="<project.preflightRoute, default \"/\">"
   PREFLIGHT_URL="${baseUrl%/}${PREFLIGHT_ROUTE}"
   curl -s -o /dev/null -w "%{http_code}" "$PREFLIGHT_URL"
   ```

   Treat any **2xx or 3xx** as up; the initial response is what counts, so do not follow redirects (a redirect to an authentication endpoint may itself answer 401/403). If the result is
   not 2xx/3xx, stop and tell the user to start the local app. Point `project.preflightRoute` at a
   route that answers without authentication — the root or the first `project.publicRoutes` entry.

2. **Order.** Sort the remaining entries by `userType` (public first, then the order in
   `project.userTypes`), so entries for the same user run together.

## 4. Run each entry in a subagent

Run the subagents **one at a time**, never in parallel, because all of them share the single Playwright
browser. Use the harness's task tool with the generic subagent (`general` on opencode,
`general-purpose` on claudecode), which has the Figma and Playwright MCP tools. Start one subagent per
entry, covering all its viewports, so Figma is fetched only once. Give it this prompt:

```text
You are running a design QA check. Load the `devbot:design-qa` skill and follow it exactly, with these inputs:

- figma-link: <entry.figma>
- url: <entry.url resolved against baseUrl: an absolute URL is used as-is; otherwise `${baseUrl%/}` + the route, with exactly one slash between them>
- viewport: <entry.viewports, else defaults.viewports, comma-separated>
- --as: <entry.userType>   (public = no login)
- design-map entry: <the entry as JSON>

Rules for this run:
- Report-only. Never edit files, never use --fix.
- Non-interactive: never ask the user anything. If you would stop to ask (state doesn't match and the entry's `state` can't fix it, not logged in as the right user, zoom can't be fixed), stop and return status "blocked" with a one-line reason. If the blocker is the session, start the reason with "login needed".
- If browser zoom is not 100%, continue and add it to observations.

Return ONLY the block below and the terminal marker. Repeat the block per viewport, starting each with "VIEWPORT: <px>"; put NOTES only in the first. End with `[FINISHED]` when done, or `[BLOCKED]` when blocked.

STATUS: done | blocked | error — <one-line reason if not done>
COUNTS: High N · Medium N · Notes N · Hardcoded N
ISSUES:
| # | Element | Property | Figma | Actual | Severity | File:line |
(every row)
NOTES:
| # | Note | Element | Status |
(omit if none)
HARDCODED:
| File:line | Value | Use token |
(omit if none)
OBSERVATIONS: at most 3 bullets
```

Don't keep the subagent's raw MCP output. Keep only the returned block, stripping its terminal marker
(`[FINISHED]` / `[BLOCKED]`) before aggregating.

If a subagent returns `blocked — login needed…`, don't run the remaining entries for that `userType`.
List them under **Skipped** with the reason `log in as <userType> in the Playwright browser and re-run`.

## 5. Write design-qa-report.md

Overwrite `design-qa-report.md` in the repo root:

```markdown
# Design QA report

- Date: <YYYY-MM-DD HH:mm>
- Branch: <git branch --show-current>
- Commit: <git rev-parse --short HEAD><" (uncommitted changes)" if git status --porcelain is not empty>
- Mode: all | only <id> | changed-only vs <base> (<N> changed files)
- Base URL: <baseUrl>

## Summary

| Entry                                                                                                                                                         | URL | User | Viewport | High | Medium | Notes | Status |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- | ---- | -------- | ---- | ------ | ----- | ------ |
| (one row per entry × viewport, ordered High desc; Status = ✅ done / ⛔ blocked: reason / ❌ error: reason; add "via <shared file>" for changed-only matches) |

**Total:** High N · Medium N across N checks.

## Details

### <entry id> — <url> @ <viewport>px as <userType>

<the subagent's ISSUES / NOTES / HARDCODED / OBSERVATIONS blocks, unchanged>

## Skipped

| Entry | Reason |
| ----- | ------ |
```

- Use repo-relative markdown links for File:line, e.g. `[X.tsx:42](path/to/X.tsx#L42)`.
- Omit the Skipped section if nothing was skipped.

## 6. Reply in chat

Print only:

- the Summary table and the totals line;
- the number of skipped entries, grouped by reason, e.g. "3 skipped: 3 need a concrete URL";
- a link to `design-qa-report.md`.

Don't repeat the details in chat.
