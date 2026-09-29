#!/usr/bin/env python3
"""Unit tests for the composition-root filter in lib/analyse.structural."""

from __future__ import annotations

import os
import sqlite3
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import analyse  # noqa: E402
import store  # noqa: E402


def _store():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    store.init(conn)
    return conn


def _unit(conn, path, name, ca, ce, cbo):
    conn.execute(
        "INSERT INTO units(path, name, kind, ca, ce, cbo) VALUES (?, ?, 'class', ?, ?, ?)",
        (path, name, ca, ce, cbo),
    )


class WiringFilterTests(unittest.TestCase):
    def test_composition_roots_are_excluded_from_structural_coupling(self):
        conn = _store()
        _unit(conn, "app/Providers/AppServiceProvider.php", "AppServiceProvider", 0, 256, 256)
        _unit(conn, "app/Models/Laravel/User.php", "User", 21, 26, 26)

        paths = [row["path"] for row in analyse.structural(conn)]

        self.assertNotIn("app/Providers/AppServiceProvider.php", paths, paths)
        self.assertIn("app/Models/Laravel/User.php", paths, paths)


if __name__ == "__main__":
    unittest.main()
