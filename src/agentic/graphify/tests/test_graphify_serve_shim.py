#!/usr/bin/env python3
"""Unit tests for graphify-serve-shim's readiness helpers.

The MCP wrapper itself is exercised by BATS; these tests pin the decisions it
uses: placeholder detection, worktree seeding, disabled scope, and status.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
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


class ProjectResolutionTest(unittest.TestCase):
    """A polyrepo session must be able to query a child project's graph."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.devbot = self.root / "dev-bot"
        self.devbot.mkdir()
        self.child = self.root / "core"
        (self.child / "app").mkdir(parents=True)
        write_graph(self.child / "graphify-out" / "graph.json", 2)
        config = self.devbot / ".devbot.global.jsonc"
        config.write_text(
            json.dumps({"projects": [str(self.root), str(self.child)]}), encoding="utf-8"
        )
        self._old_env = shim.os.environ.get("DEVBOT_ROOT")
        shim.os.environ["DEVBOT_ROOT"] = str(self.devbot)

    def tearDown(self) -> None:
        if self._old_env is None:
            shim.os.environ.pop("DEVBOT_ROOT", None)
        else:
            shim.os.environ["DEVBOT_ROOT"] = self._old_env
        self.tmp.cleanup()

    def test_resolves_a_file_inside_a_child_project(self):
        resolved = shim._resolve_project_graph(str(self.child / "app" / "Thing.php"))
        self.assertEqual(resolved, self.child / "graphify-out" / "graph.json")

    def test_resolves_the_child_root_itself(self):
        resolved = shim._resolve_project_graph(str(self.child))
        self.assertEqual(resolved, self.child / "graphify-out" / "graph.json")

    def test_unregistered_path_yields_none(self):
        outside = Path(tempfile.mkdtemp(dir="/tmp")) / "x"
        self.assertIsNone(shim._resolve_project_graph(str(outside)))

    def test_empty_or_missing_argument_keeps_the_default_graph(self):
        default = self.root / "graphify-out" / "graph.json"
        self.assertEqual(shim._graph_for(None, default), default)
        self.assertEqual(shim._graph_for("", default), default)
        self.assertEqual(shim._graph_for(str(self.root / "nope"), default), default)

    def test_project_argument_selects_the_child_graph(self):
        default = self.root / "graphify-out" / "graph.json"
        selected = shim._graph_for(str(self.child), default)
        self.assertEqual(selected, self.child / "graphify-out" / "graph.json")


class StalenessTest(unittest.TestCase):
    """An unrecorded or matching HEAD is fresh; a moved HEAD is stale."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.project = Path(self.tmp.name) / "proj"
        (self.project / "graphify-out").mkdir(parents=True)
        self.record = self.project / "graphify-out" / ".graphify-head"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_no_record_and_no_graph_is_not_stale(self):
        self.assertFalse(shim._stale(self.project))

    def test_a_graph_without_a_marker_needs_one_bootstrap_build(self):
        """A child graph predating the marker would otherwise stay stale
        forever: only the session graph gets a launch-time update."""
        write_graph(self.project / "graphify-out" / "graph.json", 2)
        shim._stale_cache.clear()
        self.assertTrue(shim._stale(self.project))

    def test_stale_without_git_repo_degrades_to_false(self):
        # No .git: HEAD is unknown, so the graph is never condemned as stale.
        self.record.write_text("deadbeef", encoding="utf-8")
        self.assertFalse(shim._stale(self.project))

    def test_a_stale_verdict_is_not_cached(self):
        """A build is running after this answer — caching it would keep
        reporting stale and start another build once the TTL lapsed."""
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        subprocess.run(
            ["git", "-C", str(self.project), "-c", "user.email=t@t", "-c", "user.name=t",
             "commit", "-q", "--allow-empty", "-m", "x"],
            check=True,
        )
        self.record.write_text("0" * 40, encoding="utf-8")
        shim._stale_cache.clear()
        self.assertTrue(shim._stale(self.project))
        self.assertNotIn(str(self.project), shim._stale_cache)

    def test_matching_head_is_fresh(self):
        head = shim._head(self.project)
        if not head:
            self.skipTest("not inside a git repository")
        self.record.write_text(head, encoding="utf-8")
        self.assertFalse(shim._stale(self.project))


if __name__ == "__main__":
    unittest.main()
