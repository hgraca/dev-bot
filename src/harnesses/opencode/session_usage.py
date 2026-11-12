#!/usr/bin/env python3
"""Read the live context occupancy of one opencode session.

The ``session`` table holds cumulative totals, which say nothing about how full
the window is now. Each assistant step ends with a ``step-finish`` part whose
``tokens.total`` is that step's context size, so the latest one is the answer.
"""
from __future__ import annotations

import json
import os
import sqlite3
import sys
from urllib.parse import quote

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.normpath(os.path.join(_HERE, "..", "..", "_shared")))
from opencode_db import resolve_db_path  # noqa: E402


def _connect(path):
    return sqlite3.connect(f"file:{quote(path)}?mode=ro", uri=True)


def _session_model(row):
    try:
        meta = json.loads(row or "{}")
    except ValueError:
        return "", ""
    if not isinstance(meta, dict):
        return "", ""
    return str(meta.get("providerID") or ""), str(
        meta.get("modelID") or meta.get("id") or ""
    )


def gather(session_id, db_path=None):
    path = resolve_db_path(db_path)
    if not os.path.isfile(path):
        return {"error": "no-database", "session": session_id, "detail": path}
    try:
        conn = _connect(path)
    except sqlite3.Error as exc:
        return {"error": "no-database", "session": session_id, "detail": str(exc)}
    try:
        row = conn.execute(
            "SELECT model FROM session WHERE id = ?", (session_id,)
        ).fetchone()
        if row is None:
            return {"error": "unknown-session", "session": session_id}
        provider, model = _session_model(row[0])
        part = conn.execute(
            "SELECT data FROM part WHERE session_id = ? "
            "AND json_extract(data, '$.type') = 'step-finish' "
            "ORDER BY time_created DESC, rowid DESC LIMIT 1",
            (session_id,),
        ).fetchone()
    except sqlite3.Error as exc:
        return {"error": "no-database", "session": session_id, "detail": str(exc)}
    finally:
        conn.close()

    if part is None:
        return {"error": "no-usage", "session": session_id}
    try:
        total = int(json.loads(part[0])["tokens"]["total"])
    except (ValueError, KeyError, TypeError):
        return {"error": "no-usage", "session": session_id}
    return {
        "session": session_id,
        "provider": provider,
        "model": model,
        "context_tokens": total,
    }
