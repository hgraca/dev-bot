---
name: find-automation-candidates
description: "Use when the recurring command chains an agent types should be turned into scripts. Triggers on 'find automation candidates', 'what can we automate', 'which commands deserve a script', 'mine the session history', 'what do I keep typing'."
---

# Find automation candidates

Measure what an agent actually types across its sessions, and decide which
recurring chains deserve to become one command. The measurement is deterministic
and the script does all of it; the judgement is yours and the script deliberately
does not attempt it.

The chain of reasoning that makes the output usable: **frequency × cost −
irreducible arguments = whether a script pays**. Each part has a way to get it
wrong, listed under [Gotchas](#gotchas).

## When to apply

- Someone asks what to automate, script, or wrap.
- A workflow feels repetitive and you want evidence rather than a hunch.
- After a process change, to check whether the chain it targeted is gone.

Not for: a single session's history (just read it), or deciding _how_ to build
the script once a candidate is agreed.

## What the count covers

`--sessions N` means the newest N **root** sessions counting back from now.
Subagent sessions are folded into their parent. The current store is read first;
when it holds fewer than N roots, the legacy table tops up the shortfall, newest
first — so an install that predates the store change still produces a full
window. Each session's tool calls are read from whichever store recorded them, so
an older session contributes real commands rather than nothing.

## Procedure

1. **Run the miner.** Default is the newest 1000 root sessions:

   ```bash
   python3 <skill-base-dir>/scripts/mine-commands.py --sessions 500
   ```

   It writes a report directory (default
   `.agents/memory/thinking/<timestamp>-find-automation-candidates/`) and prints
   the top candidates. Pass `--out` to write somewhere specific and `--stage
extract|mine|evaluate` to re-run one stage against an existing report.

2. **Read the three tables in order** — `index.md` (what was covered, and how
   many sessions came from the legacy store), `sequences.md` (frequency: _sessions_
   is support, _runs_ is occurrences), `candidates.md` (priced: _chars/run_,
   _saved/session_, _turns freed_).

3. **Judge** each family of variants with the rules below. An n-gram is a
   fragment: `A → B → C` and `B → C → D` are the same workflow seen through two
   windows, so group them before deciding anything.

4. **Write the report** to `<out>/report.md` in the template below, ranked by
   est. token savings per 100 sessions, and tell the user the absolute path.

## Judgement rules

**Split overhead from content first.** This is the decisive question, and it is
not visible in any column. If the characters carry _information the agent must
supply anyway_ — file paths, a commit message, a heredoc's file body — a wrapper
saves almost nothing and adds a layer. If the characters are _furniture_ — a
cluster path, a poll-sleep-retry cycle, a `| tail -6` wrapper — a script removes
them entirely. A candidate is only worth building when the variable part is small
or known in advance.

**Support beats unit cost.** A chain saving 1,400 tokens in 9 sessions is worth
less than one saving 300 in 40. Rank on est. token savings per 100 sessions, and say the
breadth and the intensity out loud rather than a single score.

**Turns beat tokens.** Every command is one round trip: the call, its result, and
the reasoning around it. `turns freed` is usually the stronger argument and it is
what makes long chains (`gh api → sleep → gh api`) so expensive — each poll is a
full turn for nothing.

**Prefer extending a tool the agent already reaches for** over adding a new one.
Check its usage in the report's vocabulary before proposing a new command; a
wrapper nobody invokes saves nothing.

**Decline explicitly.** One command that is already a single call, or a chain
whose members are interactive by nature (reading files named by the previous
output), is not a candidate. Say so with the reason — a declined row is a result, but it belongs under _Not
worth a script_, never in the candidate table.

## The report is a file

Write the report to **`<out>/report.md`**, beside the measurement it came from —
`<out>` being the report directory the miner printed. It is a deliverable, not a
chat message: the user keeps it, forwards it, and acts on it later, so chat gets
a summary and the file gets the report.

After writing it, **tell the user the absolute path**. A report the user cannot
find is a report that was not delivered.

```markdown
# Automation candidates — <N> sessions

<one line: how many roots were available, how many were examined, where the rest came from>

Columns: % of sessions is breadth; runs/session is intensity; est. token
savings/run is the dominant chain's measured figure; est. token savings per 100
sessions is their product and the sort key. Measured on command text only — the
real cost is higher.

| # | candidate | replaces | % of sessions | runs/session | est. token savings/run | est. token savings per 100 sessions |

## 1. <candidate> — <one-line intent>

**Replaces:** <the chain, as measured>
**Evidence:** <breadth, intensity, per-run saving>
**Intent:** <what the command should do — inputs, output, exit behaviour, and
why the chain costs what it does. Two to four sentences: enough for someone to
decide whether to build it and to know what "done" looks like.>

<repeat 2..10>

## Not worth a script

| chain | why not |

## Different fix — not a script

<patterns whose cost is content or correctness, and what actually fixes them>
```

Every candidate the table ranks gets its own **Intent** section — the table says
what is expensive, the section says what to build. An intent that only restates
the chain has not said anything: name the inputs, the output shape, the failure
behaviour.

## Gotchas

These are the mistakes that silently produce plausible, wrong rankings. All are
already handled by `mine-commands.py`; they are listed so you can spot them when
reading output, and so nobody "simplifies" them away.

- **A pipeline is one command.** Splitting on `|` reports `grep → head` as a
  workflow. Split only on `&&`, `||`, `;` — and only outside quotes, or a Python
  one-liner's own semicolons become commands.
- **Filtering tools out of a flat list invents adjacency.** `sed`, `edit`, `sed`
  filtered to shell symbols reads as `sed → sed`. A chain must be consecutive,
  with nothing (tool call included) in between — hence runs, not filters.
- **A heredoc body is not a command.** It is a file write; tokenising its content
  manufactures symbols out of prose.
- **Subshells and control structures are opaque.** `$(...)` content is not the
  outer command's verb, and a `for` loop is already a script.
- **Migrated 1.x sessions keep their tool calls in `part` rows**, not in the v2
  message stream, where they were flattened into text. Reading the stream for
  those loses every command.
- **`execute` (code mode) hides its inner calls.** Anything done through it is
  invisible to this report, so its subjects are undercounts.

## Re-measuring

A shipped script is verified by re-running the miner and comparing that symbol's
count per session before and after — not by feel.

```bash
python3 <skill-base-dir>/scripts/mine-commands.py --sessions 500 --stage all
```

Compare `sequences.md` support for the chain the script replaced. It should drop;
if it does not, the script is not being used or the chain was never the problem.
