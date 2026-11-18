#!/usr/bin/env python3
"""opencode-v2 stats adapter for ``devbot stats``.

Reads the shared opencode SQLite database read-only and prints the canonical
``devbot stats`` JSON (schema v1) on stdout.

V2 difference: 1.x recorded assistant steps in ``message``/``part``, while 2.x
writes ``session_v2`` plus one ``session_message`` row per entry. Tool calls are
``content`` entries of ``type == "tool"``:

    {"type": "tool", "id": "call_…", "name": "shell",
     "state": {"status": "completed", "input": {"command": "…"},
               "content": [{"type": "text", "text": "…"}], "metadata": {…}}}

Cost and tokens are recorded per assistant message, not per tool call, so a
message's cost is split evenly across the tools it invoked — an estimate, hence
``cost_kind: estimated``.

MCP calls are attributed by tool name: a 2.x host names them
``<server>_<tool>``, and the servers are the ones each session directory's
opencode config declares (``mcp.servers``, a v1-shaped ``mcp`` map, or
``.opencode/*.mcp.json``). Calls made through the code-mode ``execute`` tool are
recorded only as ``execute``, so they carry no server name and cannot be
attributed — the adapter reports what the database actually recorded rather than
a hardcoded empty list (audit-02 F-2).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sqlite3
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, "..", "..", "_shared")))
from opencode_db import resolve_db_path  # noqa: E402
from read_jsonc import load_jsonc  # noqa: E402

# Config files that may declare MCP servers, relative to a project directory.
_CONFIG_NAMES = (
    "opencode.jsonc",
    "opencode.json",
    ".opencode/opencode.json",
    ".opencode/opencode.jsonc",
)


def _cutoff_ms(days: int) -> int:
    return int((time.time() - days * 86400) * 1000)


def known_servers(project_dirs: list[str]) -> list[str]:
    """MCP server names declared by each project's opencode config.

    V2 nests them under ``mcp.servers`` (with ``disabled`` inverted); a v1-shaped
    ``mcp`` map is accepted too, so one adapter reads either. Dynamic manifests
    under ``.opencode/*.mcp.json`` contribute server names as well — entries
    whose value is not an object (e.g. ``mcp.dynamic.json``'s ``prefixes``) are
    ignored. Every declared server counts, enabled or not: this is name
    attribution for calls the database recorded, not an enablement report.
    """
    servers: set[str] = set()
    for directory in project_dirs:
        for name in _CONFIG_NAMES:
            path = os.path.join(directory, name)
            if not os.path.isfile(path):
                continue
            try:
                data = load_jsonc(path)
            except Exception:
                continue
            mcp = data.get("mcp") or {}
            block = mcp.get("servers") if isinstance(mcp.get("servers"), dict) else mcp
            if isinstance(block, dict):
                servers |= {
                    key for key, value in block.items() if isinstance(value, dict)
                }
        for path in glob.glob(os.path.join(directory, ".opencode", "*.mcp.json")):
            try:
                data = load_jsonc(path)
            except Exception:
                continue
            if isinstance(data, dict):
                servers |= {
                    key for key, value in data.items() if isinstance(value, dict)
                }
    # Longest first so a server whose name prefixes another still wins.
    return sorted(servers, key=len, reverse=True)


def classify(tool: str, servers: list[str]) -> tuple[str | None, str]:
    """``<server>_<tool>`` (v2) → (server, short tool); native tools → (None, "").

    A v2 host exposes MCP tools as ``<server>_<tool>``. ``.`` and ``/`` are
    accepted too: the separator is a host detail, while the server names come
    from the project's own config, so matching is anchored on a known name and
    never guesses a split.

    An exact name match is deliberately **not** an MCP call: v2 has native tools
    whose name equals a server's (``websearch`` is both the built-in search tool
    and a configured MCP server), and counting it would invent MCP usage.
    """
    for server in servers:
        for sep in ("_", ".", "/"):
            if tool.startswith(server + sep):
                return server, tool[len(server) + 1 :]
    return None, ""


def _iter_messages(con: sqlite3.Connection, session_ids: list[str]):
    if not session_ids:
        return
    placeholders = ",".join("?" for _ in session_ids)
    query = (
        f"select session_id, type, data from session_message "
        f"where session_id in ({placeholders}) order by seq"
    )
    for session_id, kind, data in con.execute(query, session_ids):
        try:
            yield session_id, kind, json.loads(data)
        except (TypeError, ValueError):
            continue


def collect(db_path: str, days: int, project_dir: str | None) -> dict:
    cutoff = _cutoff_ms(days)
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        # session_v2 also holds 1.x rows (it is the shared modern table), so the
        # version prefix is what keeps this adapter reporting 2.x usage only.
        if project_dir:
            rows = con.execute(
                "select id, directory from session_v2 "
                "where time_updated >= ? and directory = ?"
                " and (version like '2.%' or version like '0.0.0--%')",
                (cutoff, project_dir),
            ).fetchall()
        else:
            rows = con.execute(
                "select id, directory from session_v2 where time_updated >= ?"
                " and (version like '2.%' or version like '0.0.0--%')",
                (cutoff,),
            ).fetchall()
        session_ids = [r[0] for r in rows]
        directories = sorted({r[1] for r in rows if r[1]})
        # A session's directory decides which server names its MCP calls may
        # carry. Classifying merged totals against the union of every selected
        # project let one project's server name claim another project's tool.
        dir_by_session = {r[0]: r[1] for r in rows if r[1]}
        servers_by_dir = {d: known_servers([d]) for d in directories}
        servers_by_name: dict[str, dict] = {}

        tools: dict[str, dict] = defaultdict(
            lambda: {"name": "", "count": 0, "tokens": 0.0, "cost": 0.0, "durations": []}
        )
        messages = 0

        for session_id, kind, data in _iter_messages(con, session_ids):
            if kind != "assistant":
                continue
            messages += 1
            content = data.get("content") or []
            calls = [c for c in content if isinstance(c, dict) and c.get("type") == "tool"]
            if not calls:
                continue

            tokens = data.get("tokens") or {}
            total_tokens = (
                (tokens.get("input") or 0)
                + (tokens.get("output") or 0)
                + (tokens.get("reasoning") or 0)
                + ((tokens.get("cache") or {}).get("read") or 0)
                + ((tokens.get("cache") or {}).get("write") or 0)
            )
            cost = data.get("cost") or 0
            share_tokens = total_tokens / len(calls)
            share_cost = cost / len(calls)

            session_servers = servers_by_dir.get(dir_by_session.get(session_id, ""), [])
            for call in calls:
                name = call.get("name") or "unknown"
                entry = tools[name]
                entry["name"] = name
                entry["count"] += 1
                entry["tokens"] += share_tokens
                entry["cost"] += share_cost
                server, short = classify(name, session_servers)
                if server:
                    bucket = servers_by_name.setdefault(
                        server,
                        {"server": server, "count": 0, "tokens": 0.0, "cost": 0.0, "tools": {}},
                    )
                    bucket["count"] += 1
                    bucket["tokens"] += share_tokens
                    bucket["cost"] += share_cost
                    tool_bucket = bucket["tools"].setdefault(
                        short, {"name": short, "count": 0, "tokens": 0.0, "cost": 0.0}
                    )
                    tool_bucket["count"] += 1
                    tool_bucket["tokens"] += share_tokens
                    tool_bucket["cost"] += share_cost
                state = call.get("state") or {}
                timing = (call.get("time") or {})
                started = timing.get("start")
                finished = timing.get("end")
                if isinstance(started, (int, float)) and isinstance(finished, (int, float)):
                    entry["durations"].append((finished - started) / 1000.0)

        rendered = []
        for entry in tools.values():
            durations = entry.pop("durations")
            rendered.append(
                {
                    "name": entry["name"],
                    "count": entry["count"],
                    "uses": entry["count"],
                    "avg": round(sum(durations) / len(durations), 1) if durations else None,
                    "tokens": round(entry["tokens"]),
                    "cost": round(entry["cost"], 6),
                }
            )
        rendered.sort(key=lambda t: t["count"], reverse=True)

        # MCP aggregation happened per call above, so the totals were split
        # against the session's own project config rather than a global union.
        mcp_servers = []
        for bucket in sorted(
            servers_by_name.values(), key=lambda b: b["count"], reverse=True
        ):
            mcp_servers.append(
                {
                    "server": bucket["server"],
                    "count": bucket["count"],
                    "tokens": round(bucket["tokens"]),
                    "cost": round(bucket["cost"], 6),
                    "tools": [
                        {
                            "name": tool["name"],
                            "count": tool["count"],
                            "tokens": round(tool["tokens"]),
                            "cost": round(tool["cost"], 6),
                        }
                        for tool in sorted(
                            bucket["tools"].values(),
                            key=lambda t: t["count"],
                            reverse=True,
                        )
                    ],
                }
            )

        return {
            "schema": 1,
            "harness": "opencode-v2",
            "days": days,
            "scope": "current" if project_dir else "all",
            "scope_label": project_dir or "all projects",
            "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "cost_kind": "estimated",
            "sessions": len(session_ids),
            "messages": messages,
            "tools": rendered,
            "mcp_servers": mcp_servers,
        }
    finally:
        con.close()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="opencode-v2 stats adapter")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--all", action="store_true", help="every project, not just this one")
    parser.add_argument("--project", default=None, help="project directory to report on")
    args = parser.parse_args(argv)

    db_path = resolve_db_path()
    if not db_path or not os.path.exists(db_path):
        print(f"ERROR: opencode database not found ({db_path})", file=sys.stderr)
        return 1

    project_dir = None if args.all else (args.project or os.getcwd())
    print(json.dumps(collect(db_path, args.days, project_dir)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
