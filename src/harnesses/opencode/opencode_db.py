#!/usr/bin/env python3
"""Locate opencode's SQLite database.

Single source for the DB path, shared by the stats adapter and the DB prune so
the two cannot diverge. opencode resolves its data dir as
``$XDG_DATA_HOME || ~/.local/share``.
"""

import os


def resolve_db_path(explicit=None):
    if explicit:
        return explicit
    env = os.environ.get("OPENCODE_DB_PATH")
    if env:
        return env
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data_home, "opencode", "opencode.db")
