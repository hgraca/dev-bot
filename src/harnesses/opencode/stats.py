#!/usr/bin/env python3
"""opencode stats adapter for ``devbot stats``.

Reads the opencode SQLite database read-only, aggregates tool usage and
MCP-server usage over a time window, and prints the canonical ``devbot stats``
JSON (schema v1) on stdout. The contract is documented in ``docs/harnesses.md``.

Cost/tokens are recorded per assistant step (``step-finish`` parts), not per
tool call, so a step's cost is split evenly across the tools that step invoked
— an estimate, hence ``cost_kind: estimated``.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sqlite3
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, "..", "..", "_shared")))
from opencode_db import resolve_db_path  # noqa: E402
from read_jsonc import load_jsonc  # noqa: E402
from stats_args import (  # noqa: E402
    bash_value,
    is_sensitive_name,
    mask_argv,
    tool_arg_value,
)

DB_PATH = resolve_db_path()

# Config files that may declare an `mcp` block, relative to a project dir.
_CONFIG_NAMES = (
    "opencode.jsonc",
    "opencode.json",
    ".opencode/opencode.json",
    ".opencode/opencode.jsonc",
)

# Tools whose arguments we aggregate, mapped to the input key holding the value.
# Overrides only — every other tool falls back to _GENERIC_ARG_KEYS, so an MCP
# server added tomorrow is aggregated without touching this file.
_ARG_KEYS = {"bash": "command", "skill": "name", "grep": "pattern", "glob": "pattern"}
# pty_spawn is a shell channel too, but has no single input key: its executable
# and argument array are rejoined in _arg_value.
_PTY_TOOLS = ("pty_spawn",)
# First key holding a non-empty string wins. Ordered most-meaningful first: MCP
# servers each define their own schema (query, sql, jql, searchContext, …), so a
# fixed per-tool map would rot with every server added.
_GENERIC_ARG_KEYS = (
    "query",
    "sql",
    "jql",
    "searchContext",
    "command",
    "url",
    "filePath",
    "path",
    "endpoint",
    "pattern",
    "metricName",
    "description",
    "name",
)
_ARG_TOP = 20


def _arg_value(tool: str, input_obj) -> str:
    if not isinstance(input_obj, dict):
        return ""
    if tool == "bash":
        # `bash_value` keeps only the first two tokens, but the second can be a
        # credential (`export TOKEN=…`) — run it through the same safe helper.
        return tool_arg_value(bash_value(input_obj.get("command")))
    if tool == "pty_spawn":
        # A PTY invocation arrives split: the executable in `command`, the rest
        # in `args`. Rejoin them so the value matches the bash shape.
        rest = input_obj.get("args")
        parts = [str(input_obj.get("command") or "")]
        if isinstance(rest, list):
            parts += [str(value) for value in rest]
        return tool_arg_value(bash_value(" ".join(parts).strip()))
    if tool in _ARG_KEYS:
        return tool_arg_value(input_obj.get(_ARG_KEYS[tool]))
    for key in _GENERIC_ARG_KEYS:
        value = input_obj.get(key)
        if isinstance(value, str) and value.strip():
            return tool_arg_value(value)
    # devbot-tools wrap their CLI shape: a positional list under `args`. Without
    # this the busiest MCP tool of all (search-memories) aggregates nothing.
    for key in ("args", "argv"):
        parts = input_obj.get(key)
        if isinstance(parts, list):
            text = mask_argv([p for p in parts if isinstance(p, (str, int, float))])
            if text.strip():
                return tool_arg_value(text)
    # Unknown schema: take the first non-empty string, then give up. This keeps
    # a brand-new MCP tool represented instead of silently absent.
    for key, value in input_obj.items():
        if not (isinstance(value, str) and value.strip()):
            continue
        # An unknown schema carries no tell in the value; the field name is the
        # only signal that `{"password": "…"}` is a credential.
        if is_sensitive_name(key):
            return f"{key} ***"
        return tool_arg_value(value)
    return ""


def known_servers(project_dirs):
    """MCP server names declared by the opencode config of each project dir."""
    servers: set[str] = set()
    for directory in project_dirs:
        for name in _CONFIG_NAMES:
            path = os.path.join(directory, name)
            if not os.path.isfile(path):
                continue
            try:
                servers |= set((load_jsonc(path).get("mcp") or {}).keys())
            except Exception:
                pass
        for path in glob.glob(os.path.join(directory, ".opencode", "*.mcp.json")):
            try:
                servers |= set(load_jsonc(path).keys())
            except Exception:
                pass
    return servers


def classify(tool, servers):
    """Return (server, short_tool_name) if `tool` belongs to a known server."""
    for server in servers:  # longest names first — see main()
        if tool == server or tool.startswith(server + "_"):
            return server, tool[len(server) + 1 :]
    return None, None


def gather(cutoff_ms, project_dir, db_path):
    """Aggregate sessions in the window; ``project_dir=None`` means every project."""
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        if project_dir is None:
            dirs = [r[0] for r in conn.execute(
                "SELECT DISTINCT directory FROM session WHERE time_created >= ?", (cutoff_ms,)
            )]
        else:
            dirs = [project_dir]
        servers = sorted(known_servers(dirs), key=len, reverse=True)

        sql = (
            "SELECT p.session_id, "
            "json_extract(p.data,'$.type'), json_extract(p.data,'$.tool'), "
            "json_extract(p.data,'$.cost'), json_extract(p.data,'$.tokens'), "
            "json_extract(p.data,'$.state.input') "
            "FROM part p JOIN session s ON s.id = p.session_id "
            "WHERE p.time_created >= ? "
            "AND json_extract(p.data,'$.type') IN ('tool','step-finish')"
        )
        params = [cutoff_ms]
        if project_dir is not None:
            sql += " AND s.directory = ?"
            params.append(project_dir)
        sql += " ORDER BY p.session_id, p.time_created, p.id"

        counts = Counter()
        tokens = defaultdict(float)
        costs = defaultdict(float)
        # Any tool row may contribute, so the set grows as tools appear.
        arg_counts: dict[str, Counter] = defaultdict(Counter)

        current_tools: list[str] = []
        last_session = None
        for session_id, kind, tool, cost, tok, input_json in conn.execute(sql, params):
            if session_id != last_session:
                current_tools = []
                last_session = session_id
            if kind == "tool":
                if tool:
                    counts[tool] += 1
                    current_tools.append(tool)
                    if input_json:
                        try:
                            input_obj = json.loads(input_json)
                        except ValueError:
                            input_obj = None
                        value = _arg_value(tool, input_obj)
                        if value:
                            arg_counts[tool][value] += 1
            elif kind == "step-finish":
                n = len(current_tools)
                if n:
                    total_tokens = 0
                    if tok:
                        try:
                            total_tokens = json.loads(tok).get("total") or 0
                        except (ValueError, TypeError):
                            total_tokens = 0
                    step_cost = cost or 0.0
                    for name in current_tools:
                        tokens[name] += total_tokens / n
                        costs[name] += step_cost / n
                current_tools = []
    finally:
        conn.close()

    # MCP aggregation.
    server_count = Counter()
    server_tokens = defaultdict(float)
    server_cost = defaultdict(float)
    server_tools = defaultdict(Counter)
    server_tool_tokens = defaultdict(lambda: defaultdict(float))
    server_tool_cost = defaultdict(lambda: defaultdict(float))

    tools = []
    for name, count in counts.most_common():
        tools.append({
            "name": name,
            "count": count,
            "tokens": int(round(tokens[name])),
            "cost": round(costs[name], 6),
        })
        server, short = classify(name, servers)
        if server:
            server_count[server] += count
            server_tokens[server] += tokens[name]
            server_cost[server] += costs[name]
            server_tools[server][short] += count
            server_tool_tokens[server][short] += tokens[name]
            server_tool_cost[server][short] += costs[name]

    mcp_servers = []
    for server, count in server_count.most_common():
        mcp_servers.append({
            "server": server,
            "count": count,
            "tokens": int(round(server_tokens[server])),
            "cost": round(server_cost[server], 6),
            "tools": [
                {
                    "name": short,
                    "count": c,
                    "tokens": int(round(server_tool_tokens[server][short])),
                    "cost": round(server_tool_cost[server][short], 6),
                }
                for short, c in server_tools[server].most_common()
            ],
        })

    tool_arguments = {
        tool: [{"value": value, "count": count} for value, count in counter.most_common(_ARG_TOP)]
        for tool, counter in sorted(arg_counts.items())
        if counter
    }

    return tools, mcp_servers, tool_arguments


def main() -> int:
    parser = argparse.ArgumentParser(description="opencode stats adapter")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--all", action="store_true", dest="scope_all")
    parser.add_argument("--project", default=None,
                        help="restrict the report to this project directory (default: all projects)")
    args = parser.parse_args()

    if args.days < 1:
        print(f"ERROR: --days must be a positive integer (got {args.days})", file=sys.stderr)
        return 1
    if args.project and args.scope_all:
        print("ERROR: --project and --all are mutually exclusive", file=sys.stderr)
        return 1
    if not os.path.isfile(DB_PATH):
        print(f"ERROR: opencode database not found at {DB_PATH}", file=sys.stderr)
        return 1

    cutoff_ms = int((time.time() - args.days * 86400) * 1000)
    project_dir = args.project

    try:
        tools, mcp_servers, tool_arguments = gather(cutoff_ms, project_dir, DB_PATH)
    except sqlite3.Error as exc:
        print(f"ERROR: failed to read opencode database: {exc}", file=sys.stderr)
        return 1

    data = {
        "schema": 1,
        "harness": "opencode",
        "days": args.days,
        "scope": "all" if project_dir is None else "current",
        "scope_label": "all projects" if project_dir is None else project_dir,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "cost_kind": "estimated",
        "tools": tools,
        "mcp_servers": mcp_servers,
        "tool_arguments": tool_arguments,
    }
    json.dump(data, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
