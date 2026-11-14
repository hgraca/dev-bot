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
"""
from __future__ import annotations

import argparse
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


def _cutoff_ms(days: int) -> int:
    return int((time.time() - days * 86400) * 1000)


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
                "select id from session_v2 "
                "where time_updated >= ? and directory = ?"
                " and (version like '2.%' or version like '0.0.0--%')",
                (cutoff, project_dir),
            ).fetchall()
        else:
            rows = con.execute(
                "select id from session_v2 where time_updated >= ?"
                " and (version like '2.%' or version like '0.0.0--%')",
                (cutoff,),
            ).fetchall()
        session_ids = [r[0] for r in rows]

        tools: dict[str, dict] = defaultdict(
            lambda: {"name": "", "count": 0, "tokens": 0.0, "cost": 0.0, "durations": []}
        )
        messages = 0

        for _session_id, kind, data in _iter_messages(con, session_ids):
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

            for call in calls:
                name = call.get("name") or "unknown"
                entry = tools[name]
                entry["name"] = name
                entry["count"] += 1
                entry["tokens"] += share_tokens
                entry["cost"] += share_cost
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
            "mcp_servers": [],
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
