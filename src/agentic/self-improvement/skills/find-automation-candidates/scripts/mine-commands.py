#!/usr/bin/env python3
"""Mine the opencode session store for recurring command chains.

Reduces every tool call in a window of sessions to a verb-level symbol, mines
the contiguous chains that recur across sessions, prices the characters the
agent had to write for them, and reports the ones worth turning into a script.

Session selection: the newest ``--sessions`` root sessions (default 1000) from
``session_v2``; when the v2 table holds fewer than that, the remainder is filled
from the legacy ``session`` table, oldest-first shortfall. Tool calls are read
per session from the structured v1 ``part`` rows when they exist, otherwise from
the v2 ``session_message`` stream — mandatory for migrated 1.x sessions, whose
v2 stream flattened tool calls into prose.

Three stages, each re-runnable on its own:

    extract   write one file per session, commands only, plus index.md
    mine      n-grams over runs of consecutive shell commands -> sequences.md
    evaluate  price the sequences by measured command characters -> candidates.md

Usage:
    python3 mine-commands.py --sessions 500
    python3 mine-commands.py --stage mine --out <dir-from-a-previous-run>

Output is a report directory (default under .agents/memory/thinking/), never a
commit. Diagnostics go to stderr, the summary to stdout.
"""

import argparse
import collections
import json
import os
import pathlib
import re
import sqlite3
import sys
from datetime import datetime, timezone

DEFAULT_SESSIONS = 1000
SHELL_TOOLS = {"shell", "bash", "pty_spawn"}
CHARS_PER_TOKEN = 3.6
INVOCATION_CHARS = 40

LINE = re.compile(r"^([0-9]+)\. \[([^\]]+)\] (.*)$")
PUNCT = re.compile(r"^[|&;<>()\[\]]+$")
REDIRECT = re.compile(r"\d*(?:>>?|>&)")
CONTROL = re.compile(r"\b(?:for|while|until|case|if)\b[\s\S]*\b(?:do|then|fi|done|esac)\b")
NOISE = {"echo", "printf", "true", ":"}
LAUNCHERS = ("npm", "bun", "bunx", "npx", "pnpm", "yarn", "uv", "poetry")
MAX_TOKENS = 3
# Reads a file the agent does not yet know the name of; nothing to parameterise.
READERS = {
    "ls", "cat", "sed", "head", "tail", "grep", "find", "wc", "sort", "uniq",
    "awk", "cut", "tr", "diff", "file", "du", "df", "which", "pwd", "tree",
    "xargs", "basename", "dirname", "realpath", "stat", "md5sum", "sha256sum",
}

ARG_KEYS = (
    "command", "id", "filePath", "file_path", "path", "pattern", "url", "query",
    "description", "prompt", "content", "todos",
)


# --------------------------------------------------------------------------- db

def resolve_db_path(explicit=None):
    """$OPENCODE_DB_PATH, else the host's XDG data dir."""
    if explicit:
        return explicit
    env = os.environ.get("OPENCODE_DB_PATH")
    if env:
        return env
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data_home, "opencode", "opencode.db")


def connect(path):
    if not os.path.exists(path):
        sys.exit(f"FATAL: opencode database not found: {path}")
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def load_sessions(con):
    """Every session from both generations, keyed by id; the v2 row wins.

    A migrated 1.x session exists in both tables. The v2 row carries the newer
    metadata, and where its tool calls actually live is decided per session by
    ``has_parts``.
    """
    by_id = {}
    for src, table in (("v2", "session_v2"), ("v1", "session")):
        try:
            cur = con.execute(
                f"select id, parent_id, title, directory, time_created from {table}"
            )
        except sqlite3.OperationalError as exc:
            print(f"WARN: {table} unreadable ({exc}); skipping", file=sys.stderr)
            continue
        for sid, parent, title, directory, created in cur:
            if sid in by_id and by_id[sid]["src"] == "v2":
                continue
            by_id[sid] = {
                "id": sid,
                "parent": parent,
                "title": title or "",
                "directory": directory or "",
                "created": created,
                "src": src,
            }
    return by_id


def select_roots(by_id, limit):
    """The newest ``limit`` root sessions: v2 first, legacy table tops up."""
    roots = [row for row in by_id.values() if not row["parent"]]
    roots.sort(key=lambda row: row["created"], reverse=True)
    v2 = [row for row in roots if row["src"] == "v2"][:limit]
    if len(v2) >= limit:
        return v2[:limit]
    taken = {row["id"] for row in v2}
    v1 = [row for row in roots if row["src"] == "v1" and row["id"] not in taken]
    return v2 + v1[: limit - len(v2)]


def descendants(by_id, root_id):
    children = collections.defaultdict(list)
    for row in by_id.values():
        if row["parent"]:
            children[row["parent"]].append(row["id"])
    out, seen, stack = [], set(), [root_id]
    while stack:
        sid = stack.pop()
        if sid in seen:
            continue
        seen.add(sid)
        out.append(sid)
        stack.extend(children.get(sid, []))
    return out


def has_parts(con, session_ids):
    """Ids whose tool calls are structured v1 ``part`` rows.

    A migrated 1.x session keeps both, but its ``session_message`` stream has
    flattened the calls into text, so the parts are authoritative where they
    exist. Reading both would duplicate every call.
    """
    if not session_ids:
        return set()
    marks = ",".join("?" for _ in session_ids)
    cur = con.execute(
        f"select distinct session_id from part "
        f"where session_id in ({marks}) and json_extract(data,'$.type') = 'tool'",
        session_ids,
    )
    return {row[0] for row in cur}


def v1_events(con, session_ids):
    events = []
    if not session_ids:
        return events
    marks = ",".join("?" for _ in session_ids)
    cur = con.execute(
        f"select session_id, time_created, id, data from part "
        f"where session_id in ({marks}) and json_extract(data,'$.type') = 'tool' "
        f"order by time_created",
        session_ids,
    )
    for sid, created, pid, data in cur:
        try:
            part = json.loads(data)
        except (TypeError, ValueError):
            continue
        state = part.get("state") or {}
        events.append(
            {
                "session": sid,
                "time": created,
                "order": pid,
                "tool": part.get("tool") or "?",
                "args": state.get("input"),
                "status": state.get("status", ""),
            }
        )
    return events


def v2_events(con, session_ids):
    events = []
    if not session_ids:
        return events
    marks = ",".join("?" for _ in session_ids)
    cur = con.execute(
        f"select session_id, seq, time_created, data from session_message "
        f"where session_id in ({marks}) and type = 'assistant' order by seq",
        session_ids,
    )
    for sid, seq, created, data in cur:
        try:
            message = json.loads(data)
        except (TypeError, ValueError):
            continue
        for item in message.get("content") or []:
            if not isinstance(item, dict) or item.get("type") != "tool":
                continue
            state = item.get("state") or {}
            events.append(
                {
                    "session": sid,
                    "time": created,
                    "order": f"{seq:012d}",
                    "tool": item.get("name") or "?",
                    "args": state.get("input"),
                    "status": state.get("status", ""),
                }
            )
    return events


# ------------------------------------------------------------------ rendering

def one_line(text):
    return text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n").strip()


def arg_of(tool, args):
    if isinstance(args, str):
        return one_line(args)
    if not isinstance(args, dict):
        return ""
    # pty_spawn splits the command it runs into command + args
    if isinstance(args.get("args"), list) and args.get("command"):
        joined = " ".join([str(args["command"])] + [str(a) for a in args["args"]])
        return one_line(joined)
    for key in ARG_KEYS:
        if key in args and args[key] not in (None, "", []):
            value = args[key]
            if isinstance(value, str):
                return one_line(value)
            return one_line(json.dumps(value, ensure_ascii=False))
    return one_line(json.dumps(args, ensure_ascii=False, sort_keys=True))


# ---------------------------------------------------------------- symbolising

def mask(token):
    if re.fullmatch(r"[0-9a-fA-F]{7,}", token):
        return "<sha>"
    if "/" in token or token.startswith("~"):
        return "<path>"
    if re.fullmatch(r"\d+", token):
        return "<n>"
    if token.startswith(("$", '"', "'", "`")):
        return "<str>"
    return token


def strip_subshells(text):
    """Blank out ``$(...)`` and backtick subshells, nesting included.

    A regex cannot: the content holds parentheses of its own
    (``select(.event == ...)``), and the leftover turns
    ``since="$(gh api ...)"`` into a phantom ``api`` command.
    """
    out, i = [], 0
    while i < len(text):
        if text.startswith("$(", i):
            depth, i = 1, i + 2
            while i < len(text) and depth:
                if text[i] == "(":
                    depth += 1
                elif text[i] == ")":
                    depth -= 1
                i += 1
            out.append("<sub>")
            continue
        if text[i] == "`":
            end = text.find("`", i + 1)
            i = len(text) if end < 0 else end + 1
            out.append("<sub>")
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def split_commands(command):
    """Split on ``&&`` / ``||`` / ``;`` only outside quotes.

    A naive split cuts a Python one-liner or a commit message at its own
    semicolons and invents symbols out of the string's interior.
    """
    parts, current, quote, i = [], [], None, 0
    while i < len(command):
        char = command[i]
        if quote:
            current.append(char)
            if char == quote:
                quote = None
            i += 1
            continue
        if char in "\"'":
            quote = char
            current.append(char)
            i += 1
            continue
        two = command[i : i + 2]
        if two in ("&&", "||"):
            parts.append("".join(current))
            current = []
            i += 2
            continue
        if char == ";":
            parts.append("".join(current))
            current = []
            i += 1
            continue
        current.append(char)
        i += 1
    parts.append("".join(current))
    return parts


def shell_symbols(command):
    """Verb-level symbols for one shell command line."""
    # A control structure is already a script; shredding it on ';' would turn one
    # loop into "for f in", "do echo", "done" pseudo-commands.
    if CONTROL.search(command):
        return ["loop"]
    # A heredoc is a file write: its body is prose or code, not commands.
    if "<<" in command:
        return ["heredoc"]

    out = []
    for segment in split_commands(strip_subshells(command)):
        tokens = segment.strip().split()
        while tokens and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[0]):
            tokens.pop(0)
        if not tokens:
            continue
        program = mask(tokens.pop(0))
        if program == "cd" or program in NOISE or PUNCT.match(program):
            continue
        if program.startswith(("(", "$")):
            continue  # unparsed subshell fragment, not a program
        picked, skip_next = [program], False
        for token in tokens:
            if PUNCT.match(token) or REDIRECT.search(token):
                if "|" in token:
                    break  # past a pipe is a different program's business
                skip_next = False
                continue
            if skip_next:
                skip_next = False
                continue
            if token.startswith("-"):
                skip_next = "=" not in token
                continue
            masked = mask(token)
            if masked.startswith("<"):
                continue
            picked.append(masked)
            if len(picked) >= MAX_TOKENS and program not in LAUNCHERS:
                break
        out.append(" ".join(picked))
    return out


def session_records(path):
    """``(symbol, raw_chars)`` in call order, plus the native tool names used.

    A line yielding several symbols splits its raw length between them, so a
    sequence's characters never double-count a line.
    """
    records, tools = [], set()
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        match = LINE.match(line)
        if not match:
            continue
        tool, arg = match.group(2), match.group(3).strip()
        if tool in SHELL_TOOLS:
            symbols = shell_symbols(arg)
            if not symbols:
                continue
            share = len(arg) / len(symbols)
            records.extend((symbol, share) for symbol in symbols)
        else:
            records.append((tool, len(arg)))
            tools.add(tool)
    return records, tools


def run_records(records, tools):
    """Maximal runs of consecutive shell commands, as ``(symbol, raw_chars)``.

    Filtering native tools out of a flat list would join commands that were
    never adjacent ("sed", "edit", "sed" would read as "sed -> sed"). A chain
    counts only when nothing — tool call included — sat between its members.
    """
    runs, current = [], []
    for symbol, raw in records:
        if symbol in tools:
            if current:
                runs.append(current)
                current = []
        else:
            current.append((symbol, raw))
    if current:
        runs.append(current)
    return runs


# -------------------------------------------------------------------- mining

def mine(runsets, lo, hi):
    """n-gram -> [occurrences, set(sessions)]; support counts sessions, not runs."""
    grams = collections.defaultdict(lambda: [0, set()])
    for name, runs in runsets.items():
        for symbols in runs:
            for size in range(lo, hi + 1):
                for i in range(len(symbols) - size + 1):
                    gram = tuple(symbols[i : i + size])
                    entry = grams[gram]
                    entry[0] += 1
                    entry[1].add(name)
    return grams


def prune(grams, min_support):
    """Keep supported n-grams; drop those fully covered by a longer equal one."""
    kept = {g: v for g, v in grams.items() if len(v[1]) >= min_support and v[0] >= 2}
    redundant = set()
    for gram in sorted(kept, key=len, reverse=True):
        if gram in redundant:
            continue
        count, sessions = kept[gram]
        for size in range(2, len(gram)):
            for i in range(len(gram) - size + 1):
                sub = gram[i : i + size]
                if sub in kept and kept[sub][0] == count and kept[sub][1] == sessions:
                    redundant.add(sub)
    return {g: v for g, v in kept.items() if g not in redundant}


def occurrences(runsets, gram):
    """Every match of ``gram``: (session, [raw_chars per symbol])."""
    out, size = [], len(gram)
    for name, runs in runsets.items():
        for run in runs:
            symbols = [symbol for symbol, _ in run]
            for i in range(len(symbols) - size + 1):
                if tuple(symbols[i : i + size]) == gram:
                    out.append((name, [run[i + k][1] for k in range(size)]))
    return out


def action_symbols(gram):
    return sum(1 for symbol in gram if symbol.split()[0] not in READERS)


# -------------------------------------------------------------------- stages

def stage_extract(con, roots, out):
    by_id = load_sessions(con)
    sessions_dir = out / "sessions"
    sessions_dir.mkdir(parents=True, exist_ok=True)
    for stale in sessions_dir.glob("*.md"):
        stale.unlink()

    index = [
        "# opencode command record — session index",
        "",
        f"Root sessions: {len(roots)} (newest first, v2 first then legacy top-up)",
        "",
        "| # | session | created | tool calls | shell | sessions | title |",
        "| - | ------- | ------- | ---------- | ----- | -------- | ----- |",
    ]
    total = shell_total = 0
    for number, root in enumerate(roots, 1):
        ids = descendants(by_id, root["id"])
        parts = has_parts(con, ids)
        events = v1_events(con, sorted(parts))
        rest = [sid for sid in ids if sid not in parts]
        events += v2_events(con, rest)
        events.sort(key=lambda ev: (ev["time"], str(ev["order"])))
        total += len(events)
        shell = sum(1 for ev in events if ev["tool"] in SHELL_TOOLS)
        shell_total += shell

        stamp = datetime.fromtimestamp(root["created"] / 1000, timezone.utc)
        name = f"{number:03d}-{root['id'][-6:]}.md"
        lines = [
            f"# {root['id']}",
            f"# {stamp:%Y-%m-%d %H:%M} | {root['directory']} | {root['title'][:120]}",
            f"# sessions folded: {len(ids)} | calls from: "
            f"{'v1 parts' if parts else 'v2 messages'}",
            "",
        ]
        for position, event in enumerate(events, 1):
            suffix = "" if event["status"] in ("", "completed") else f"  [{event['status']}]"
            lines.append(f"{position}. [{event['tool']}] {arg_of(event['tool'], event['args'])}{suffix}")
        (sessions_dir / name).write_text("\n".join(lines) + "\n", encoding="utf-8")

        index.append(
            f"| {number} | [{name}](sessions/{name}) | {stamp:%Y-%m-%d %H:%M} | "
            f"{len(events)} | {shell} | {len(ids)} | {root['title'].replace('|', chr(92)+'|')[:70]} |"
        )
    index += ["", f"Total tool calls recorded: {total} ({shell_total} shell)"]
    (out / "index.md").write_text("\n".join(index) + "\n", encoding="utf-8")
    print(f"extract: {len(roots)} sessions, {total} tool calls -> {out}")
    return total


def load_runsets(out):
    records, tools = {}, set()
    for path in sorted((out / "sessions").glob("*.md")):
        recs, used = session_records(path)
        records[path.stem] = recs
        tools |= used
    return {name: run_records(recs, tools) for name, recs in records.items()}


def table(ranked, limit):
    rows = ["| # | sessions | runs | sequence |", "| - | -------- | ---- | -------- |"]
    for number, (gram, (count, sessions)) in enumerate(ranked[:limit], 1):
        rows.append(f"| {number} | {len(sessions)} | {count} | `{' → '.join(gram)}` |")
    return rows


def stage_mine(out, min_support, top, lo, hi):
    runsets = load_runsets(out)
    if not runsets:
        sys.exit(f"FATAL: no session files under {out / 'sessions'}")
    symbols = {
        name: [[s for s, _ in run] for run in runs]
        for name, runs in runsets.items()
    }
    flat = {
        name: [symbol for run in runs for symbol, _ in run]
        for name, runs in runsets.items()
    }

    # One run per session for the all-symbols view: native tools included, so the
    # run is the whole call sequence and adjacency is the real call order.
    all_grams = prune(mine({n: [syms] for n, syms in flat.items()}, lo, hi), min_support)
    all_ranked = sorted(all_grams.items(), key=lambda kv: (len(kv[1][1]), kv[1][0], len(kv[0])), reverse=True)
    run_grams = prune(mine(symbols, lo, hi), min_support)
    run_ranked = sorted(run_grams.items(), key=lambda kv: (len(kv[1][1]), kv[1][0], len(kv[0])), reverse=True)

    vocabulary = collections.Counter(symbol for syms in flat.values() for symbol in syms)
    lines = [
        "# Recurring command sequences",
        "",
        f"Sessions: {len(runsets)} · symbols: {sum(vocabulary.values())} · n-grams: "
        f"{lo}..{hi} · min session support: {min_support}",
        "",
        "Symbols are verb-level: program plus up to three meaningful words, paths, hashes "
        "and numbers masked (`<path>`, `<sha>`, `<n>`). `cd` dropped, compound lines split "
        "on `&&`/`||`/`;` outside quotes, pipelines kept whole, control structures "
        "collapsed to `loop`, heredocs to `heredoc`, subshells blanked. *sessions* is "
        "distinct-session support; *runs* is the raw occurrence count.",
        "",
        f"## All symbols — top {top}",
        "",
        "<sub>Includes native tool calls (`edit`, `read`, `execute`): mostly workflow "
        "shapes, not scriptable chains.</sub>",
        "",
    ]
    lines += table(all_ranked, top)
    lines += [
        "",
        f"## Shell commands only — top {top}",
        "",
        "<sub>Runs of *consecutive* shell commands; a native tool call ends the run, so "
        "no fabricated adjacency. This is the raw material a wrapper script replaces.</sub>",
        "",
    ]
    lines += table(run_ranked, top)
    lines += ["", "## Vocabulary (top 40)", "", "| symbol | count |", "| ------ | ----- |"]
    lines += [f"| `{sym}` | {count} |" for sym, count in vocabulary.most_common(40)]

    (out / "sequences.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out / "sequences.json").write_text(
        json.dumps(
            {
                "all": [
                    {"sequence": list(g), "sessions": len(s), "runs": c, "session_files": sorted(s)}
                    for g, (c, s) in all_ranked
                ],
                "shell_only": [
                    {"sequence": list(g), "sessions": len(s), "runs": c, "session_files": sorted(s)}
                    for g, (c, s) in run_ranked
                ],
            },
            indent=1,
        ),
        encoding="utf-8",
    )
    print(f"mine: {len(all_ranked)} sequences ({len(run_ranked)} shell-only) -> {out / 'sequences.md'}")
    return run_ranked


def stage_evaluate(out, min_support, min_actions, top, exclude=()):
    sequences_file = out / "sequences.json"
    if not sequences_file.exists():
        sys.exit(f"FATAL: {sequences_file} missing — run --stage mine first")
    ranked = json.loads(sequences_file.read_text())["shell_only"]
    runsets = load_runsets(out)

    rows = []
    total_sessions = len(list((out / "sessions").glob("*.md"))) or 1
    for entry in ranked:
        gram = tuple(entry["sequence"])
        if entry["sessions"] < min_support or action_symbols(gram) < min_actions:
            continue
        if exclude and any(symbol in exclude for symbol in gram):
            continue  # a loop is already a script; a heredoc is a file write
        hits = occurrences(runsets, gram)
        if not hits:
            continue
        chars = sum(sum(raw) for _, raw in hits)
        saved = max(0.0, chars - INVOCATION_CHARS * len(hits)) / CHARS_PER_TOKEN
        rows.append(
            {
                "sequence": gram,
                "sessions": entry["sessions"],
                "pct_sessions": round(100 * entry["sessions"] / total_sessions, 1),
                "runs": len(hits),
                "runs_per_session": round(len(hits) / entry["sessions"], 1),
                "chars_per_run": round(chars / len(hits), 1),
                "saved_tokens": round(saved),
                "saved_per_run": round(saved / len(hits), 1),
                # tokens the workflow costs per 100 sessions: breadth x intensity
                # x per-run saving; identical to 100 x total / sessions examined
                "saved_per_100": round(100 * saved / total_sessions),
                # firings x (n-1) round trips collapse into one invocation each
                "turns_freed": round(len(hits) * (1 - 1 / len(gram))),
            }
        )
    rows.sort(key=lambda row: (row["saved_per_100"], row["sessions"]), reverse=True)

    lines = [
        "# Script candidates — measured cost",
        "",
        f"Sequences with ≥{min_support} sessions and ≥{min_actions} action symbols, ranked "
        f"by est. token savings per 100 sessions. Model: command "
        f"characters ÷ {CHARS_PER_TOKEN}/token, minus a {INVOCATION_CHARS}-character "
        "invocation per run. Tool-call framing, result and reasoning turn are excluded — "
        "the real cost is higher, so treat every figure as a floor.",
        "",
        "*% sessions* is breadth (sessions it appears in ÷ sessions examined); "
        "*runs/session* is intensity (occurrences ÷ the sessions it appears in); "
        "*saved/run* is the estimate for one occurrence. Variants of one workflow "
        "overlap — group them into a family and use the dominant chain's figures "
        "rather than summing.",
        "",
        "| # | saved/100 | % sessions | sessions | runs | runs/session | chars/run | saved tokens | saved/run | turns freed | sequence |",
        "| - | ---------- | ---------- | -------- | ---- | ------------ | --------- | ------------ | --------- | ----------- | -------- |",
    ]
    for number, row in enumerate(rows[:top], 1):
        lines.append(
            f"| {number} | {row['saved_per_100']} | {row['pct_sessions']}% | "
            f"{row['sessions']} | {row['runs']} | {row['runs_per_session']} | "
            f"{row['chars_per_run']} | {row['saved_tokens']} | {row['saved_per_run']} | "
            f"{row['turns_freed']} | "
            f"`{' → '.join(row['sequence'])}` |"
        )
    lines += [
        "",
        "Verdicts are not written here on purpose: whether a chain deserves a script "
        "depends on whether it is overhead or content, who else consumes it, and whether "
        "its arguments are known in advance. Apply the skill's rules.",
    ]
    (out / "candidates.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out / "candidates.json").write_text(json.dumps(rows, indent=1), encoding="utf-8")
    print(f"evaluate: {len(rows)} priced candidates -> {out / 'candidates.md'}")
    return rows


def main(argv):
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Sessions default to %d; v2 table first, legacy table tops up." % DEFAULT_SESSIONS,
    )
    parser.add_argument("--sessions", type=int, default=DEFAULT_SESSIONS,
                        help=f"root sessions to examine, newest first (default {DEFAULT_SESSIONS})")
    parser.add_argument("--db", default=None, help="opencode database (default: $OPENCODE_DB_PATH or XDG)")
    parser.add_argument("--out", default=None,
                        help="report directory (default: .agents/memory/thinking/<ts>-find-automation-candidates)")
    parser.add_argument("--stage", choices=("all", "extract", "mine", "evaluate"), default="all")
    parser.add_argument("--min-support", type=int, default=3, help="distinct sessions (default 3)")
    parser.add_argument("--min-actions", type=int, default=2,
                        help="non-reader symbols required in a candidate (default 2)")
    parser.add_argument("--top", type=int, default=80, help="rows per table (default 80)")
    parser.add_argument("--exclude", default="heredoc,loop",
                        help="symbols never shown as candidates — already a script or a "
                             "file write (default: heredoc,loop)")
    parser.add_argument("--lo", type=int, default=2, help="smallest n-gram (default 2)")
    parser.add_argument("--hi", type=int, default=6, help="largest n-gram (default 6)")
    args = parser.parse_args(argv)

    if args.sessions < 1:
        parser.error("--sessions must be at least 1")

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    out = pathlib.Path(args.out or f".agents/memory/thinking/{stamp}-find-automation-candidates")
    out.mkdir(parents=True, exist_ok=True)

    if args.stage in ("all", "extract"):
        db = resolve_db_path(args.db)
        con = connect(db)
        try:
            roots = select_roots(load_sessions(con), args.sessions)
            if not roots:
                sys.exit(f"FATAL: no sessions found in {db}")
            v2 = sum(1 for root in roots if root["src"] == "v2")
            print(f"selected {len(roots)} root sessions ({v2} from v2, {len(roots) - v2} from v1)",
                  file=sys.stderr)
            stage_extract(con, roots, out)
        finally:
            con.close()

    if args.stage in ("all", "mine"):
        stage_mine(out, args.min_support, args.top, args.lo, args.hi)

    if args.stage in ("all", "evaluate"):
        exclude = {symbol.strip() for symbol in args.exclude.split(",") if symbol.strip()}
        rows = stage_evaluate(out, args.min_support, args.min_actions, args.top, exclude)
        print("\ntop candidates by est. token savings per 100 sessions:")
        for row in rows[:10]:
            print(f"  {row['saved_per_100']:7d}/100  {row['pct_sessions']:5.1f}% "
                  f"{row['runs_per_session']:5.1f} runs/sess {row['saved_per_run']:6.1f}/run  "
                  f"{' → '.join(row['sequence'])}")
    print(f"\nreport: {out.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
