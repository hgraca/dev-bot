#!/usr/bin/env python3
"""claudecode stats adapter for ``devbot stats``.

Claude Code has no stats command, so this adapter parses the session
transcripts under ``<CLAUDE_PROJECTS_DIR>/<slug>/**/*.jsonl`` (default
``~/.claude/projects``) — including subagent transcripts — aggregates tool usage
and MCP-server usage over a time window, and prints the canonical
``devbot stats`` JSON (schema v1) on stdout.

Claude Code writes one JSONL line per content block of an assistant response,
repeating the message id and ``usage`` on every line, so lines are grouped by
message id: the usage is taken once and split evenly across that message's
``tool_use`` blocks. Transcripts carry no cost data, so ``cost`` is always null
and ``cost_kind`` is null.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, "..", "..", "_shared")))
from stats_args import bash_value  # noqa: E402

PROJECTS_DIR = os.environ.get(
    "CLAUDE_PROJECTS_DIR", os.path.expanduser("~/.claude/projects")
)

_USAGE_KEYS = (
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
)

# Claude Code tool name → canonical argument tool name, and its input key.
_ARG_TOOLS = {"Bash": "bash", "Skill": "skill", "Grep": "grep", "Glob": "glob"}
_ARG_KEYS = {"bash": "command", "skill": "skill", "grep": "pattern", "glob": "pattern"}
_ARG_TOP = 20


def _arg_value(tool: str, input_obj) -> str:
    canonical = _ARG_TOOLS[tool]
    if not isinstance(input_obj, dict):
        return ""
    if canonical == "bash":
        return bash_value(input_obj.get("command"))
    value = input_obj.get(_ARG_KEYS[canonical])
    if value is None and canonical == "skill":
        value = input_obj.get("name")
    return str(value or "")


def parse_ts(raw):
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def classify(tool):
    """mcp__<server>__<tool> → (server, short_tool); native tools → (None, None)."""
    if not tool.startswith("mcp__"):
        return None, None
    parts = tool.split("__")
    if len(parts) < 3 or not parts[1]:
        return None, None
    return parts[1], "__".join(parts[2:])


def transcript_files(scope_all, cwd):
    if scope_all:
        pattern = os.path.join(PROJECTS_DIR, "*", "**", "*.jsonl")
    else:
        pattern = os.path.join(PROJECTS_DIR, cwd.replace("/", "-"), "**", "*.jsonl")
    return sorted(glob.glob(pattern, recursive=True))


def gather(paths, cutoff):
    # Group lines by assistant message. Claude Code emits one line per content
    # block, repeating the message id and usage on each line, so grouping takes
    # the usage once and collects every tool_use of the message. Keying on the
    # message id also de-duplicates a message that appears in more than one
    # transcript file (e.g. a subagent transcript).
    messages = {}
    for path in paths:
        try:
            fh = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if obj.get("type") != "assistant":
                    continue
                message = obj.get("message") or {}
                content = message.get("content")
                if not isinstance(content, list):
                    continue
                calls = [
                    (part.get("name"), part.get("input"))
                    for part in content
                    if isinstance(part, dict)
                    and part.get("type") == "tool_use"
                    and part.get("name")
                ]
                if not calls:
                    continue
                key = message.get("id") or obj.get("requestId") or obj.get("uuid")
                if key is None:
                    continue
                entry = messages.get(key)
                if entry is None:
                    entry = {
                        "tools": [],
                        "usage": message.get("usage") or {},
                        "ts": parse_ts(obj.get("timestamp")),
                    }
                    messages[key] = entry
                entry["tools"].extend(calls)

    counts = Counter()
    tokens = defaultdict(float)
    arg_counts = {tool: Counter() for tool in _ARG_TOOLS.values()}

    for entry in messages.values():
        ts = entry["ts"]
        if ts is not None and ts < cutoff:
            continue
        calls = entry["tools"]
        total = sum(int(entry["usage"].get(k) or 0) for k in _USAGE_KEYS)
        share = total / len(calls)
        for name, input_obj in calls:
            counts[name] += 1
            tokens[name] += share
            if name in _ARG_TOOLS:
                value = _arg_value(name, input_obj)
                if value:
                    arg_counts[_ARG_TOOLS[name]][value] += 1

    tools = []
    server_count = Counter()
    server_tokens = defaultdict(float)
    server_tools = defaultdict(Counter)
    server_tool_tokens = defaultdict(lambda: defaultdict(float))

    for name, count in counts.most_common():
        tok = int(round(tokens[name]))
        tools.append({"name": name, "count": count, "tokens": tok, "cost": None})
        server, short = classify(name)
        if server:
            server_count[server] += count
            server_tokens[server] += tokens[name]
            server_tools[server][short] += count
            server_tool_tokens[server][short] += tokens[name]

    mcp_servers = []
    for server, count in server_count.most_common():
        mcp_servers.append({
            "server": server,
            "count": count,
            "tokens": int(round(server_tokens[server])),
            "cost": None,
            "tools": [
                {
                    "name": short,
                    "count": c,
                    "tokens": int(round(server_tool_tokens[server][short])),
                    "cost": None,
                }
                for short, c in server_tools[server].most_common()
            ],
        })

    tool_arguments = {
        tool: [{"value": value, "count": count} for value, count in arg_counts[tool].most_common(_ARG_TOP)]
        for tool in _ARG_TOOLS.values()
        if arg_counts[tool]
    }

    return tools, mcp_servers, tool_arguments


def main() -> int:
    parser = argparse.ArgumentParser(description="claudecode stats adapter")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--all", action="store_true", dest="scope_all")
    args = parser.parse_args()

    if args.days < 1:
        print(f"ERROR: --days must be a positive integer (got {args.days})", file=sys.stderr)
        return 1

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    cwd = os.getcwd()

    tools, mcp_servers, tool_arguments = gather(transcript_files(args.scope_all, cwd), cutoff)

    data = {
        "schema": 1,
        "harness": "claudecode",
        "days": args.days,
        "scope": "all" if args.scope_all else "current",
        "scope_label": "all projects" if args.scope_all else cwd,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "cost_kind": None,
        "tools": tools,
        "mcp_servers": mcp_servers,
        "tool_arguments": tool_arguments,
    }
    json.dump(data, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
