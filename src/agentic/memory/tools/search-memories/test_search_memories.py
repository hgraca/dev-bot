#!/usr/bin/env python3
"""Unit tests for search-memories.py.

Tests core logic without requiring a real QMD index: YAML frontmatter
stripping, output formatting, devbot root resolution, and argument handling.

Usage:
    python3 -m pytest test_search_memories.py -v
    python3 test_search_memories.py          # runs via unittest
"""

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

# Import search-memories.py (hyphenated filename) via importlib
_MODULE_PATH = Path(__file__).resolve().parent / "search-memories.py"
_spec = importlib.util.spec_from_file_location("search_memories", _MODULE_PATH)
assert _spec is not None, f"Could not load spec for {_MODULE_PATH}"
assert _spec.loader is not None, f"No loader for {_MODULE_PATH}"
_search_memories = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_search_memories)

find_devbot_root = _search_memories.find_devbot_root
strip_yaml_frontmatter = _search_memories.strip_yaml_frontmatter
format_markdown = _search_memories.format_markdown
format_json = _search_memories.format_json
resolve_collection = _search_memories.resolve_collection
search_qmd = _search_memories.search_qmd


# ---------------------------------------------------------------------------
# strip_yaml_frontmatter
# ---------------------------------------------------------------------------


class TestStripYamlFrontmatter(unittest.TestCase):
    def test_no_frontmatter(self):
        content = "# Just a heading\n\nSome text."
        self.assertEqual(strip_yaml_frontmatter(content), content)

    def test_frontmatter_at_start(self):
        content = "---\ntitle: Test\ndate: 2024-01-01\n---\n\n# Heading\n\nBody text."
        result = strip_yaml_frontmatter(content)
        self.assertNotIn("---", result)
        self.assertIn("# Heading", result)
        self.assertIn("Body text.", result)

    def test_frontmatter_only(self):
        content = "---\ntitle: Only Frontmatter\n---\n"
        result = strip_yaml_frontmatter(content)
        self.assertEqual(result, "")

    def test_frontmatter_with_empty_lines_after(self):
        content = "---\ntitle: Test\n---\n\n\n\nContent here."
        result = strip_yaml_frontmatter(content)
        self.assertIn("Content here.", result)

    def test_triple_dash_in_body_not_frontmatter(self):
        """Content with --- in body but not as frontmatter delimiters."""
        content = "Not frontmatter\n---\nSome divider\n---\nMore text."
        result = strip_yaml_frontmatter(content)
        self.assertEqual(result, content)

    def test_double_dash_not_frontmatter(self):
        content = "--\ntitle: not yaml\n--\n\nBody"
        result = strip_yaml_frontmatter(content)
        self.assertEqual(result, content)

    def test_frontmatter_with_tags(self):
        content = "---\ntags: [bootstrap, session, memory]\ndescription: Memory skill guide\n---\n\n# Memory Skill\n\nContent."
        result = strip_yaml_frontmatter(content)
        self.assertIn("# Memory Skill", result)
        self.assertNotIn("tags:", result)

    def test_empty_string(self):
        self.assertEqual(strip_yaml_frontmatter(""), "")

    def test_only_opening_dashes(self):
        """Content starting with --- but no closing ---."""
        content = "---\npartial frontmatter\nNo closing delimiter."
        result = strip_yaml_frontmatter(content)
        # Should return as-is because no closing ---
        self.assertEqual(result, content)


# ---------------------------------------------------------------------------
# format_markdown / format_json
# ---------------------------------------------------------------------------


class TestOutputFormatting(unittest.TestCase):
    def test_format_markdown_empty(self):
        result = format_markdown([])
        self.assertIn("_No memory vault matches found._", result)

    def test_format_markdown_with__body(self):
        """When _body is already attached, no fetch needed."""
        results = [
            {"file": "qmd://notes/test1.md", "_body": "## Test Note\n\nHello world."},
            {"file": "qmd://notes/test2.md", "_body": "## Another Note\n\nMore content."},
        ]
        output = format_markdown(results)
        self.assertIn("## Test Note", output)
        self.assertIn("Hello world.", output)
        self.assertIn("## Another Note", output)
        self.assertIn("More content.", output)
        self.assertIn("---", output)  # separator between entries

    def test_format_markdown_fetch_error(self):
        """When _body is missing, falls back to fetch_file_body."""
        with patch.object(_search_memories, "fetch_file_body", return_value=(None, "mock error")):
            results = [{"file": "qmd://missing/file.md"}]
            output = format_markdown(results)
            self.assertIn("_Error reading file", output)
            self.assertIn("mock error", output)

    def test_format_json_empty(self):
        result = format_json([])
        self.assertEqual(result, {"memories": []})

    def test_format_json_with__body(self):
        results = [
            {"file": "qmd://notes/a.md", "_body": "Content A"},
            {"file": "qmd://notes/b.md", "_body": "Content B"},
        ]
        result = format_json(results)
        self.assertEqual(result, {"memories": ["Content A", "Content B"]})


# ---------------------------------------------------------------------------
# find_devbot_root
# ---------------------------------------------------------------------------


class TestFindDevbotRoot(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tmpdir.name)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_finds_root_by_src_agentic_memory(self):
        """When src/agentic/memory exists, returns that parent."""
        modules_dir = self.root / "src" / "agentic" / "memory"
        modules_dir.mkdir(parents=True)

        # Start from deep inside a tool dir
        start = self.root / "src" / "agentic" / "memory" / "tools" / "search-memories"
        start.mkdir(parents=True)

        result = find_devbot_root(start)
        self.assertEqual(result.resolve(), self.root.resolve())

    def test_falls_back_to_start_when_not_found(self):
        """When src/agentic/modules doesn't exist, returns start.resolve()."""
        start = self.root / "some" / "random" / "dir"
        start.mkdir(parents=True)

        result = find_devbot_root(start)
        self.assertEqual(result, start.resolve())

    def test_walks_up_to_10_levels(self):
        """Walk up from deeply nested directory."""
        modules_dir = self.root / "src" / "agentic" / "memory"
        modules_dir.mkdir(parents=True)

        # 8 levels deep
        start = self.root / "a" / "b" / "c" / "d" / "e" / "f" / "g" / "h"
        start.mkdir(parents=True)

        result = find_devbot_root(start)
        self.assertEqual(result.resolve(), self.root.resolve())

    def test_walks_up_exactly_10_and_stops(self):
        """After 10 levels, falls back to start even if root exists further up."""
        # Create root at level 12, start at level 0 — won't find it
        modules_dir = self.root / "a" / "b" / "c" / "d" / "e" / "f" / "g" / "h" / "i" / "j" / "k"
        real_root = modules_dir.parent  # has src/agentic/memory 11 levels up from start
        (real_root / "src" / "agentic" / "memory").mkdir(parents=True)

        start = self.root
        result = find_devbot_root(start)
        # Should walk up 10 levels but not reach real_root (11 levels up)
        self.assertEqual(result, start.resolve())


# ---------------------------------------------------------------------------
# resolve_collection
# ---------------------------------------------------------------------------


class TestResolveCollection(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tmpdir.name)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_reads_from_devbot_project_jsonc(self):
        cfg = self.root / ".devbot.project.jsonc"
        cfg.write_text('{"project_name": "my-cool-project"}')

        result = resolve_collection(self.root)
        self.assertEqual(result, "my-cool-project")

    def test_strips_jsonc_comments(self):
        cfg = self.root / ".devbot.project.jsonc"
        cfg.write_text("""{
            // This is a comment
            "project_name": "commented-project"
        }""")

        result = resolve_collection(self.root)
        self.assertEqual(result, "commented-project")

    def test_falls_back_to_dir_basename_when_file_missing(self):
        # Mirrors qmd/init.sh: PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
        result = resolve_collection(self.root)
        self.assertEqual(result, self.root.name)

    def test_falls_back_when_file_is_invalid_json(self):
        cfg = self.root / ".devbot.project.jsonc"
        cfg.write_text("not valid json {{{")

        result = resolve_collection(self.root)
        self.assertEqual(result, self.root.name)

    def test_falls_back_when_no_project_name_key(self):
        # Regression (audit-32/33): a .devbot.project.jsonc without project_name
        # must resolve to the project dir basename — the collection qmd/init.sh
        # actually registers — not a hardcoded "devbot" collection that never
        # exists ("Collection not found: devbot").
        cfg = self.root / ".devbot.project.jsonc"
        cfg.write_text('{"harness": "opencode", "modules": {}}')

        result = resolve_collection(self.root)
        self.assertEqual(result, self.root.name)

    def test_falls_back_when_project_name_empty(self):
        # qmd/init.sh treats an empty project_name as missing ("${VAR:-fallback}");
        # resolve_collection must agree, not return "" (which would break qmd -c "").
        cfg = self.root / ".devbot.project.jsonc"
        cfg.write_text('{"project_name": ""}')

        result = resolve_collection(self.root)
        self.assertEqual(result, self.root.name)


# ---------------------------------------------------------------------------
# search_qmd (mock qmd CLI)
# ---------------------------------------------------------------------------


class TestSearchQmd(unittest.TestCase):
    def test_merges_and_deduplicates_results(self):
        """Results from multiple queries are merged and deduplicated by file URI."""
        mock_stdout_1 = json.dumps({
            "results": [
                {"docid": "1", "score": 0.9, "file": "qmd://notes/a.md", "title": "A", "snippet": "..."},
                {"docid": "2", "score": 0.7, "file": "qmd://notes/b.md", "title": "B", "snippet": "..."},
            ]
        })
        mock_stdout_2 = json.dumps({
            "results": [
                {"docid": "2", "score": 0.8, "file": "qmd://notes/b.md", "title": "B", "snippet": "dup"},
                {"docid": "3", "score": 0.5, "file": "qmd://notes/c.md", "title": "C", "snippet": "..."},
            ]
        })

        with patch.object(_search_memories, "run_qmd_cli") as mock_run:
            mock_run.side_effect = [
                (mock_stdout_1, None),
                (mock_stdout_2, None),
                (mock_stdout_1, None),  # global collection for query 1
                (mock_stdout_2, None),  # global collection for query 2
            ]
            results, err = search_qmd(["q1", "q2"], "test-collection", 10)

        self.assertIsNone(err)
        # Should have 3 unique files: a, b, c (b was deduplicated)
        files = [r["file"] for r in results]
        self.assertEqual(len(files), 3)
        self.assertIn("qmd://notes/a.md", files)
        self.assertIn("qmd://notes/b.md", files)
        self.assertIn("qmd://notes/c.md", files)

    def test_sorts_by_score_descending(self):
        """Results sorted by score, highest first."""
        mock_stdout = json.dumps({
            "results": [
                {"docid": "1", "score": 0.3, "file": "qmd://low.md", "title": "L", "snippet": "..."},
                {"docid": "2", "score": 0.9, "file": "qmd://high.md", "title": "H", "snippet": "..."},
                {"docid": "3", "score": 0.6, "file": "qmd://mid.md", "title": "M", "snippet": "..."},
            ]
        })

        with patch.object(_search_memories, "run_qmd_cli") as mock_run:
            mock_run.side_effect = [(mock_stdout, None), (mock_stdout, None)]
            results, _ = search_qmd(["q1"], "col", 10)

        scores = [r["score"] for r in results]
        self.assertEqual(scores, [0.9, 0.6, 0.3])

    def test_limits_to_max_results(self):
        """Results are capped at max_results."""
        mock_stdout = json.dumps({
            "results": [
                {"docid": str(i), "score": 1.0 - i * 0.1, "file": f"qmd://{i}.md", "title": f"T{i}", "snippet": "..."}
                for i in range(20)
            ]
        })

        with patch.object(_search_memories, "run_qmd_cli") as mock_run:
            mock_run.side_effect = [(mock_stdout, None), (mock_stdout, None)]
            results, _ = search_qmd(["q1"], "col", 5)

        self.assertEqual(len(results), 5)

    def test_handles_list_format(self):
        """QMD may return a list instead of dict with results key."""
        mock_stdout = json.dumps([
            {"docid": "1", "score": 0.5, "file": "qmd://x.md", "title": "X", "snippet": "..."},
        ])

        with patch.object(_search_memories, "run_qmd_cli") as mock_run:
            mock_run.side_effect = [(mock_stdout, None), (mock_stdout, None)]
            results, _ = search_qmd(["q1"], "col", 10)

        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["file"], "qmd://x.md")

    def test_returns_error_on_qmd_failure(self):
        with patch.object(_search_memories, "run_qmd_cli", return_value=(None, "qmd crashed")):
            results, err = search_qmd(["q1"], "col", 10)

        self.assertIsNone(results)
        self.assertIn("qmd crashed", err)

    def test_handles_invalid_json_output(self):
        with patch.object(_search_memories, "run_qmd_cli", return_value=("not json at all", None)):
            results, err = search_qmd(["q1"], "col", 10)

        self.assertIsNone(results)
        self.assertIn("Failed to parse qmd output", err)

    def test_skips_files_with_empty_uri(self):
        """Results with empty 'file' field are skipped."""
        mock_stdout = json.dumps({
            "results": [
                {"docid": "1", "score": 0.5, "file": "", "title": "E", "snippet": "..."},
                {"docid": "2", "score": 0.9, "file": "qmd://good.md", "title": "G", "snippet": "..."},
            ]
        })

        with patch.object(_search_memories, "run_qmd_cli") as mock_run:
            mock_run.side_effect = [(mock_stdout, None), (mock_stdout, None)]
            results, _ = search_qmd(["q1"], "col", 10)

        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["file"], "qmd://good.md")

    def test_always_searches_global_collection(self):
        """Even when a specific collection is given, global is also searched."""
        with patch.object(_search_memories, "run_qmd_cli") as mock_run:
            mock_run.return_value = ("[]", None)  # empty array
            search_qmd(["q1"], "myproject", 10)

        # One call per query, but the cmd should include both -c flags
        self.assertEqual(mock_run.call_count, 1)
        cmd = mock_run.call_args[0][0]
        self.assertIn("-c", cmd)
        self.assertIn("myproject", cmd)
        self.assertIn("dev-bot-global", cmd)

    def test_uses_bm25_keyword_search(self):
        """search-memories uses `qmd search` (BM25) — not the GPU/LLM semantic route."""
        with patch.object(_search_memories, "run_qmd_cli", return_value=("[]", None)) as mock_run:
            search_qmd(["q1"], "col", 10)

        cmd = mock_run.call_args[0][0]
        self.assertEqual(cmd[0], "search")


# ---------------------------------------------------------------------------
# _qmd_env
# ---------------------------------------------------------------------------


class TestQmdEnv(unittest.TestCase):
    def test_strips_xdg_cache_home(self):
        """XDG_CACHE_HOME is removed so prod searches the default qmd index."""
        with patch.dict(os.environ, {"XDG_CACHE_HOME": "/tmp/somewhere"}):
            env = _search_memories._qmd_env()
        self.assertNotIn("XDG_CACHE_HOME", env)

    def test_override_forwards_isolated_index(self):
        """SEARCH_MEMORIES_XDG_CACHE_HOME is forwarded as XDG_CACHE_HOME (test isolation)."""
        with patch.dict(
            os.environ,
            {"XDG_CACHE_HOME": "/tmp/prod", "SEARCH_MEMORIES_XDG_CACHE_HOME": "/tmp/isolated"},
        ):
            env = _search_memories._qmd_env()
        self.assertEqual(env.get("XDG_CACHE_HOME"), "/tmp/isolated")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    unittest.main()
