#!/usr/bin/env python3
"""Read the live context occupancy of one opencode-v2 session.

2.x writes ``session_v2`` plus one ``session_message`` row per entry. The
assistant row carries that call's ``tokens`` — ``input``, ``output``,
``reasoning`` and ``cache.read``/``cache.write`` — so the newest assistant row
is the answer. The sum matches what 1.x recorded as a step's ``tokens.total``.
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


def _context_tokens(tokens):
    cache = tokens.get("cache") or {}
    return (
        int(tokens.get("input") or 0)
        + int(tokens.get("output") or 0)
        + int(tokens.get("reasoning") or 0)
        + int(cache.get("read") or 0)
        + int(cache.get("write") or 0)
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
            "SELECT model FROM session_v2 WHERE id = ?", (session_id,)
        ).fetchone()
        if row is None:
            return {"error": "unknown-session", "session": session_id}
        provider, model = _session_model(row[0])
        # The newest assistant row can be an in-flight step whose tokens are all
        # zero, so walk back to the most recent row that recorded usage.
        messages = conn.execute(
            "SELECT data FROM session_message WHERE session_id = ? "
            "AND type = 'assistant' ORDER BY seq DESC, rowid DESC LIMIT 25",
            (session_id,),
        ).fetchall()
    except sqlite3.Error as exc:
        return {"error": "no-database", "session": session_id, "detail": str(exc)}
    finally:
        conn.close()

    total = 0
    for (raw,) in messages:
        try:
            tokens = json.loads(raw).get("tokens") or {}
        except (ValueError, AttributeError):
            continue
        total = _context_tokens(tokens)
        if total > 0:
            break
    if total <= 0:
        return {"error": "no-usage", "session": session_id}
    return {
        "session": session_id,
        "provider": provider,
        "model": model,
        "context_tokens": total,
    }
