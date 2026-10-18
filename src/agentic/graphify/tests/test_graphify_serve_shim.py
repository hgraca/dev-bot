#!/usr/bin/env python3
"""Unit tests for graphify-serve-shim's readiness helpers.

The MCP wrapper itself is exercised by BATS; these tests pin the decisions it
uses: placeholder detection, worktree seeding, disabled scope, and status.
"""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "graphify-serve-shim.py"
spec = importlib.util.spec_from_file_location("graphify_serve_shim", MODULE_PATH)
assert spec is not None and spec.loader is not None
shim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shim)


def write_graph(path: Path, nodes: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "directed": True,
                "multigraph": False,
                "graph": {},
                "nodes": [{"id": f"n{i}", "label": f"node {i}"} for i in range(nodes)],
                "links": [],
            }
        ),
        encoding="utf-8",
    )


class ReadinessTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.project = self.root / "worktree"
        self.graph = self.project / "graphify-out" / "graph.json"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_placeholder_has_no_nodes(self):
        self.graph.parent.mkdir(parents=True)
        self.graph.write_text(shim.PLACEHOLDER, encoding="utf-8")
        self.assertEqual(shim._nodes(self.graph), 0)

    def test_populated_graph_is_ready(self):
        write_graph(self.graph, 2)
        self.assertEqual(shim._nodes(self.graph), 2)
        state, _ = shim._status(self.project, self.graph)
        self.assertEqual(state, "ready")

    def test_empty_graph_is_not_ready(self):
        self.graph.parent.mkdir(parents=True)
        self.graph.write_text(shim.PLACEHOLDER, encoding="utf-8")
        state, reason = shim._status(self.project, self.graph)
        self.assertIn(state, {"empty", "failed", "building"})
        self.assertTrue(reason)

    def test_disabled_scope(self):
        self.project.mkdir(parents=True)
        (self.project / ".graphifyignore").write_text("/*\n", encoding="utf-8")
        self.assertTrue(shim._indexing_disabled(self.project))

    def test_source_scope_is_not_disabled(self):
        self.project.mkdir(parents=True)
        (self.project / ".graphifyignore").write_text("/*\n!src\n", encoding="utf-8")
        self.assertFalse(shim._indexing_disabled(self.project))

    def test_live_build_pid_means_building(self):
        self.graph.parent.mkdir(parents=True)
        self.graph.write_text(shim.PLACEHOLDER, encoding="utf-8")
        (self.project / "graphify-out").mkdir(parents=True, exist_ok=True)
        (self.project / "graphify-out" / ".graphify-update.pid").write_text(
            str(__import__("os").getpid()), encoding="utf-8"
        )
        state, _ = shim._status(self.project, self.graph)
        self.assertEqual(state, "building")

    def test_failed_build_log_is_reported(self):
        self.graph.parent.mkdir(parents=True)
        self.graph.write_text(shim.PLACEHOLDER, encoding="utf-8")
        (self.project / "graphify-out" / ".graphify-update.log").write_text(
            "start\nfinished (exit 1)\n", encoding="utf-8"
        )
        state, reason = shim._status(self.project, self.graph)
        self.assertEqual(state, "failed")
        self.assertIn(".graphify-update.log", reason)

    def test_seeds_an_empty_worktree_from_main(self):
        main = self.root / "main"
        write_graph(main / "graphify-out" / "graph.json", 3)
        self.graph.parent.mkdir(parents=True)
        self.graph.write_text(shim.PLACEHOLDER, encoding="utf-8")

        self.assertTrue(shim._seed_from_main(self.project, self.graph, main_root=main))
        self.assertEqual(shim._nodes(self.graph), 3)

    def test_does_not_seed_when_worktree_already_has_nodes(self):
        main = self.root / "main"
        write_graph(main / "graphify-out" / "graph.json", 3)
        write_graph(self.graph, 1)
        self.assertFalse(shim._seed_from_main(self.project, self.graph, main_root=main))
        self.assertEqual(shim._nodes(self.graph), 1)


if __name__ == "__main__":
    unittest.main()
