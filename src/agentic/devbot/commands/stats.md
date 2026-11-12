---
name: devbot:stats
description: Report what is working, what can be improved and what is broken, from the tool and MCP usage stats of the harness running this session.
---

Report on the harness that is running this session.

## 1. Detect the live harness

Read your own tool palette: opencode names MCP tools `<server>_<tool>` (e.g. `devbot-tools_*`),
claudecode names them `mcp__<server>__<tool>`. That is the harness to target — use the config
`harness` key only as a cross-check, and as the fallback when no MCP tools are exposed.

The palette shows only servers that connected, so it cannot show an enabled server that exposed no
tools. Take the enabled set from the selected harness config: `mcp` entries in `opencode.jsonc`
(`enabled` absent or true), `mcpServers` in `.mcp.json` for claudecode. A server disabled there is
out of scope, not broken.

## 2. Run the report

The detected harness is authoritative: pass it explicitly as `--harness` below, and ignore any
`--harness` the caller supplies. Translate the request (`$ARGUMENTS`) into the flags the CLI takes,
whether it arrives as `--days=7` or as "last week": a time range becomes `--days=N`, a project
becomes `--project=<dir>`, and an empty request means the defaults.

```bash
devbot stats --harness=<detected> [--days=N] [--project=<dir>]
```

Defaults are the last 30 days across every project. An argument with no flag equivalent is a
question to ask, not something to paste through.

## 3. Read the report against the run

Tool Usage and MCP Server Usage are always present. Tool Grades (quadrants, poor ratings, `Never
used`) appears only when the grade matrix has tools, and Tool Arguments only when arguments were
recorded. Read only the sections that appear — a missing one means no data, not zero use.

Then judge:

- an enabled server absent from MCP Server Usage had no calls in the window;
- an enabled server with no reachable tools in your palette is not working;
- `Never used` is a grade-matrix bucket for a tool with no grades in the window — not proof of zero
  calls, since a used but ungraded tool can land there.

## 4. Answer in three sections

Print one line naming the harness and window, then these three sections and nothing else. Under each
label, bullets only, every one a single line of at most 72 characters.

### Working well

Healthy call share, good grades, MCP servers that connect and get used.

### Can be improved

Low usage, poor or missing grades, thin argument coverage, heavy cost when the report shows a Cost
column. Enabled servers that connected but had no calls in the window. End every bullet with a
one-line suggestion: `→ <what to change>`.

### Not working at all

Enabled MCP servers with no reachable tools in your palette.
