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
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, "..", "..", "_shared")))
from read_jsonc import load_jsonc  # noqa: E402

DB_PATH = os.environ.get(
    "OPENCODE_DB_PATH", os.path.expanduser("~/.local/share/opencode/opencode.db")
)

# Config files that may declare an `mcp` block, relative to a project dir.
_CONFIG_NAMES = (
    "opencode.jsonc",
    "opencode.json",
    ".opencode/opencode.json",
    ".opencode/opencode.jsonc",
)


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


def gather(cutoff_ms, scope_all, cwd, db_path):
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        if scope_all:
            dirs = [r[0] for r in conn.execute(
                "SELECT DISTINCT directory FROM session WHERE time_created >= ?", (cutoff_ms,)
            )]
        else:
            dirs = [cwd]
        servers = sorted(known_servers(dirs), key=len, reverse=True)

        sql = (
            "SELECT p.session_id, "
            "json_extract(p.data,'$.type'), json_extract(p.data,'$.tool'), "
            "json_extract(p.data,'$.cost'), json_extract(p.data,'$.tokens') "
            "FROM part p JOIN session s ON s.id = p.session_id "
            "WHERE p.time_created >= ? "
            "AND json_extract(p.data,'$.type') IN ('tool','step-finish')"
        )
        params = [cutoff_ms]
        if not scope_all:
            sql += " AND s.directory = ?"
            params.append(cwd)
        sql += " ORDER BY p.session_id, p.time_created, p.id"

        counts = Counter()
        tokens = defaultdict(float)
        costs = defaultdict(float)

        current_tools: list[str] = []
        last_session = None
        for session_id, kind, tool, cost, tok in conn.execute(sql, params):
            if session_id != last_session:
                current_tools = []
                last_session = session_id
            if kind == "tool":
                if tool:
                    counts[tool] += 1
                    current_tools.append(tool)
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

    return servers, tools, mcp_servers


def main() -> int:
    parser = argparse.ArgumentParser(description="opencode stats adapter")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--all", action="store_true", dest="scope_all")
    args = parser.parse_args()

    if args.days < 1:
        print(f"ERROR: --days must be a positive integer (got {args.days})", file=sys.stderr)
        return 1
    if not os.path.isfile(DB_PATH):
        print(f"ERROR: opencode database not found at {DB_PATH}", file=sys.stderr)
        return 1

    cutoff_ms = int((time.time() - args.days * 86400) * 1000)
    cwd = os.getcwd()

    try:
        _, tools, mcp_servers = gather(cutoff_ms, args.scope_all, cwd, DB_PATH)
    except sqlite3.Error as exc:
        print(f"ERROR: failed to read opencode database: {exc}", file=sys.stderr)
        return 1

    data = {
        "schema": 1,
        "harness": "opencode",
        "days": args.days,
        "scope": "all" if args.scope_all else "current",
        "scope_label": "all projects" if args.scope_all else cwd,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "cost_kind": "estimated",
        "tools": tools,
        "mcp_servers": mcp_servers,
    }
    json.dump(data, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
