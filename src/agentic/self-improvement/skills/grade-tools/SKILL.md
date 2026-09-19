---
name: devbot:grade-tools
description: "Records per-session tool quality into <DEV_BOT_ROOT>/.agents/logs/tools-grades.csv: one project-tagged row per run, 0-5 per MCP server/skill, multi-line notes explaining every 1-3 grade. Use this skill whenever the primary agent finishes a session, right after devbot:remember-session — and on 'wrap up', 'grade tools', or 'remember this session' — even if the user does not ask for it."
---

# Grade Tools

Every row feeds the tool-roster decisions: keep, remove, substitute, or improve an MCP server or a
skill — especially our own `devbot-tools`, which is graded per tool for exactly that reason. A grade
without the reasoning behind it cannot drive that decision, so the `notes` column carries the _why_.

The CSV is **install-level, not per-project**: rows from every project land in one file at
`<DEV_BOT_ROOT>/.agents/logs/tools-grades.csv`, each row tagged with the `project` it came from, so
tool quality accumulates across the whole workspace instead of fragmenting into one file per consumer.
`devbot stats` reads this matrix back, reporting each tool's average grade and the reasons behind its
poor (1–3) ratings.

## When to Apply

- **Primary trigger**: the finish flow (see `devbot:agent-communication`), immediately after
  `devbot:remember-session` and before `[FINISHED]`.
- The user says "wrap up", "grade tools", "how did the tools do", or "remember this session".
- Any time the agent wants to record tool quality for a completed slice of work.

## MUST

- **Silent on the finish flow**: emit ZERO narrative text — no status line, no "graded N tools".
  The script call is the only visible effect.
- **Always add a row**, even when the slice used no MCP server or skill (all-zero grades, note says so).
- **Grade the slice in isolation**: only work since the previous row for _this project_ in this
  session. A tool used earlier but not in this slice is `0`.
- **Explain every `1`, `2` and `3`** in the notes, naming the tool. Those grades mean "used, but
  something was wrong with it", and that something is the entire signal. The script rejects the row
  otherwise.
- **Write the notes as several lines, not one long line.** A single line is unreadable once the CSV
  is opened in a spreadsheet. One line per tool, blank line between blocks of related tools.
- **Close the notes with the tools you did not reach for** — the unused alternative is the one signal a
  grade cannot carry, and where improvement and removal candidates come from.
- **Run the script from the project root** so the `project` column is right, or pass `--project-root`.
- **Never hand-edit the CSV** — the script owns column order, the `-NN` id, and quoting.
- **Never commit the CSV** — it lives under devbot's own `.agents/logs/`, which is gitignored, and it
  spans every project, so it belongs to none of them.

## Procedure

### Step 1 — Determine the slice

Resolve the session id and its last row:

1. Read the session id from the shell: `echo "$DEV_BOT_SESSION_ID"` — if it is empty, the session id is `unknown`.
2. Read `<DEV_BOT_ROOT>/.agents/logs/tools-grades.csv` and take the highest row id starting with `<session-id>-`.

If no such row exists, the slice is the whole session so far. Otherwise the slice is the work done
after that row. Grade that slice only.

### Step 2 — Enumerate the tools used in the slice

| What you used                   | Flag                        | Column written            |
| ------------------------------- | --------------------------- | ------------------------- |
| An MCP server                   | `--mcp <server>=<grade>`    | `mcp:<server>`            |
| One of the `devbot-tools` tools | `--mcp-tool <tool>=<grade>` | `mcp:devbot-tools:<tool>` |
| A skill                         | `--skill <name>=<grade>`    | `skill:<name>`            |

List only tools actually invoked. Built-in tools (`bash`, `edit`, `read`, `grep`, `task`, …) are out
of scope — this matrix covers MCP servers and skills only.

`project` is not a tool: it is written automatically from the working directory (see Step 5).

### Step 3 — Grade each tool

| Grade | Meaning                                                                   | Note it needs                            |
| ----- | ------------------------------------------------------------------------- | ---------------------------------------- |
| 0     | Not used in this slice (only ever written for existing columns)           | —                                        |
| 1     | Used, but the outcome was not relevant to the task                        | Tool limitation, or config/usage issue   |
| 2     | Used, marginal / redundant — another tool covered the need                | Which tool made it redundant             |
| 3     | Used, helpful — a replacement you would actually have reached for existed | Which replacement could have substituted |
| 4     | Used, significant contribution; hard to replace                           | —                                        |
| 5     | Critical — without it the outcome would have been materially wrong        | —                                        |

A `1`, `2` or `3` must name its tool in the notes — that is exactly what the script checks for. `0`,
`4` and `5` need no explanation.

**The two boundaries people call lazily.** They decide most rows, so pin them:

- **3 vs 4 — "a substitute existed."** A replacement counts only if you would actually have reached for
  it in that session, with no extra setup. Almost anything _can_ be replaced by something; that is not a 3. `format-md` sits at 3 beside `npx prettier --write`; a tool whose result the session depended on
  does not.
- **5 vs 4 — "critical."** Reserve 5 for tools whose absence would have made the outcome materially
  _wrong_ rather than merely less tidy: a commit that sweeps in a colleague's uncommitted work, a
  behaviour change shipped on manual evidence. A tool that kept the work organised but still correct is
  a 4.

**A flat row is an unexamined row.** When five or more tools are graded and none lands below 4, re-read
them before writing. A session in which every tool was excellent is rare; the likelier cause is that the
weakest one was never identified. Find it, and give it the grade it earned.

### Step 4 — Write the notes

The notes column is the point of the matrix, and a human reads it in a spreadsheet — so write several
lines, not one. Name each graded tool and say which of the three signals it carries:

- **A tool limitation** — "returned no hits on a symbol that exists; its index excludes symlinked dirs".
- **A configuration / usage issue** — "empty result was because the index had not been built, not a tool limit".
- **An improvement / removal signal** — "`tree` adds little over `glob` here — candidate to drop".

Name concrete substitutes for a `3` and redundant authors for a `2`. For a `1`-`3` the script matches
the tool's **short name** — the last colon-separated segment — so `skill:devbot:makefile` is satisfied
by mentioning `makefile`, and `mcp:devbot-tools:format-md` by mentioning `format-md`. Matching is
case-insensitive.

**Close the notes with the tools you did NOT reach for.** The matrix carries a grade only for tools that
were used, so the most useful signal of all has nowhere else to live: "used `bash git` for ~15
operations and never touched `git-report`" is an improvement or removal candidate that no grade can
express. One line, naming what fitted the slice and went unused, and what it would have covered.

### Step 5 — Append the row

Run the script **from the project root**, with the notes as one multi-line argument. `$'…'` is the
reliable shell form for embedding real line breaks:

```bash
python3 <skill-base-dir>/scripts/record-grades.py \
  --notes $'graphify: marginal, grep covered the same ground\ncodebase-memory: grep substituted\n\nmakefile: its container targets do not apply to this repo; the Makefile itself covered running the suite\n\nsignoz: critical, the only verification path left' \
  --mcp graphify=2 \
  --mcp-tool format-md=4 \
  --skill devbot:makefile=3
```

The `project` column is derived from the working directory as `<parent folder>/<folder>` — run from
`/home/me/Get-e/positioning-activities` and the row records `Get-e/positioning-activities`. Pass
`--project-root DIR` to override it (or when invoking from anywhere else).

The script resolves the install root from `$DEV_BOT_ROOT`, falling back to walking up from its own
(real) location. It reads `$DEV_BOT_SESSION_ID`, resolves the next `<session-id>-NN` id, adds any new
tool column (backfilling earlier rows with `0`), and rewrites the shared CSV atomically. Pass
`--devbot-root DIR` to override the install root deliberately.

If it prints `WARN: DEV_BOT_SESSION_ID is not set`, the harness did not export the session id, and the
row is grouped under `unknown`. The shell.env hook supplies that variable, so a session started before
the hook was (re)loaded will not have it — restart opencode to pick it up.

## MUST NOT

- Do not narrate on the finish flow — the capture is silent, like `devbot:remember-session`.
- Do not invent tools that were not used, or grade the whole session when only a slice is new.
- Do not bypass the script to edit the CSV directly.
