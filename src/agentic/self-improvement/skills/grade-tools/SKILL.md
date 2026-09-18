---
name: devbot:grade-tools
description: "Records per-session tool quality into .agents/logs/tools-grades.csv: one graded row per run, 0-5 per MCP server/skill, notes flagging substitutes and limitations. Use this skill whenever the primary agent finishes a session, right after devbot:remember-session — and on 'wrap up', 'grade tools', or 'remember this session' — even if the user does not ask for it."
---

# Grade Tools

Every row feeds the tool-roster decisions: keep, remove, substitute, or improve an MCP server or a
skill — especially our own `devbot-tools`, which is graded per tool for exactly that reason. A grade
without the reasoning behind it cannot drive that decision, so the `notes` column carries the _why_.

## When to Apply

- **Primary trigger**: the finish flow (see `devbot:agent-communication`), immediately after
  `devbot:remember-session` and before `[FINISHED]`.
- The user says "wrap up", "grade tools", "how did the tools do", or "remember this session".
- Any time the agent wants to record tool quality for a completed slice of work.

## MUST

- **Silent on the finish flow**: emit ZERO narrative text — no status line, no "graded N tools".
  The script call is the only visible effect.
- **Always add a row**, even when the slice used no MCP server or skill (all-zero grades, note says so).
- **Grade the slice in isolation**: only work since the previous `tools-grades` row in this session.
  A tool used earlier but not in this slice is `0`.
- **Never hand-edit the CSV** — the script owns column order, the `-NN` id, and quoting.
- **Never commit the CSV** — it lives under `.agents/logs/`, which is gitignored.

## Procedure

### Step 1 — Determine the slice

If no `tools-grades` row exists for this session yet, the slice is the whole session so far;
otherwise it is the work done since the previous row (the trigger prompt usually marks it). Grade
that slice only.

### Step 2 — Enumerate the tools used in the slice

| What you used                   | Flag                        | Column written            |
| ------------------------------- | --------------------------- | ------------------------- |
| An MCP server                   | `--mcp <server>=<grade>`    | `mcp:<server>`            |
| One of the `devbot-tools` tools | `--mcp-tool <tool>=<grade>` | `mcp:devbot-tools:<tool>` |
| A skill                         | `--skill <name>=<grade>`    | `skill:<name>`            |

List only tools actually invoked. Built-in tools (`bash`, `edit`, `read`, `grep`, `task`, …) are out
of scope — this matrix covers MCP servers and skills only.

### Step 3 — Grade each tool

| Grade | Meaning                                                         | Note it needs                          |
| ----- | --------------------------------------------------------------- | -------------------------------------- |
| 0     | Not used in this slice (only ever written for existing columns) | —                                      |
| 1     | Used, but the outcome was not relevant to the task              | Tool limitation, or config/usage issue |
| 2     | Used, marginal / redundant — another tool covered the need      | Which tool made it redundant           |
| 3     | Used, helpful, but a substitute existed                         | Which tool could have substituted      |
| 4     | Used, significant contribution; hard to replace                 | —                                      |
| 5     | Critical; the task was very likely impossible without it        | —                                      |

### Step 4 — Write the notes

The notes column is the point of the matrix. For every grade that carries a signal, say which of the
three it is:

- **A tool limitation** — "returned no hits on a symbol that exists; its index excludes symlinked dirs".
- **A configuration / usage issue** — "empty result was because the index had not been built, not a tool limit".
- **An improvement / removal signal** — "`tree` adds little over `glob` here — candidate to drop".

Name concrete substitutes for a `3` and redundant authors for a `2`.

### Step 5 — Append the row

Run the script from the project root (the harness prints this skill's base directory):

```bash
python3 <skill-base-dir>/scripts/record-grades.py \
  --notes "<why, naming any substitute or limitation>" \
  --mcp <server>=<grade> \
  --mcp-tool <tool>=<grade> \
  --skill <name>=<grade>
```

The script reads `$DEV_BOT_SESSION_ID`, resolves the next `<session-id>-NN` id, adds any new tool
column (backfilling earlier rows with `0`), and rewrites `.agents/logs/tools-grades.csv` atomically.

If it prints `WARN: DEV_BOT_SESSION_ID is not set`, the harness did not export the session id — the
row is grouped under `unknown` until opencode is restarted with the shell.env hook loaded.

## MUST NOT

- Do not narrate on the finish flow — the capture is silent, like `devbot:remember-session`.
- Do not invent tools that were not used, or grade the whole session when only a slice is new.
- Do not bypass the script to edit the CSV directly.
