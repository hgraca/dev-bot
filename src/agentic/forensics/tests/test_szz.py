#!/usr/bin/env python3
"""Unit tests for lib/szz.py — linking a fix to the commit that induced it."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import commitparse  # noqa: E402
import gitmine  # noqa: E402
import szz  # noqa: E402


def _git(repo, *args, env=None):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, env=env)


class InducingAuthorTests(unittest.TestCase):
    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="forensics-szz-")
        self.addCleanup(shutil.rmtree, self.repo, True)
        _git(self.repo, "init", "-q")
        _git(self.repo, "config", "user.name", "Alice")
        _git(self.repo, "config", "user.email", "alice@example.com")
        _git(self.repo, "config", "commit.gpgsign", "false")

    def _write_and_commit(self, path, content, message, author=None, author_date=None, committer_date=None):
        with open(os.path.join(self.repo, path), "w", encoding="utf-8") as handle:
            handle.write(content)
        _git(self.repo, "add", "-A")
        args = ["commit", "-q", "-m", message]
        if author:
            args += ["--author", author]
        env = dict(os.environ)
        if author_date:
            env["GIT_AUTHOR_DATE"] = author_date
        if committer_date:
            env["GIT_COMMITTER_DATE"] = committer_date
        _git(self.repo, *args, env=env)

    def _fixes(self):
        """The fix commits only — as if the window had mined just those."""
        commits = commitparse.enrich(gitmine.mine_commits(self.repo))
        return [commit for commit in commits if commit["type"] == "fix"]

    def test_inducing_author_resolves_when_the_origin_is_outside_the_mined_set(self):
        self._write_and_commit("calc.py", "a = 1\nb = 2\nc = 3\n", "feat: add the calculation", "Bob <bob@example.com>")
        inducing = _git(self.repo, "rev-parse", "HEAD").stdout.strip()
        self._write_and_commit("calc.py", "a = 1\nb = 20\nc = 3\n", "fix: correct the calculation")

        links = szz.link_defects(self.repo, self._fixes())

        self.assertEqual(len(links), 1, links)
        self.assertEqual(links[0]["inducing_hash"], inducing)
        self.assertEqual(links[0]["inducing_author"], "bob@example.com")
        self.assertIsNotNone(links[0]["delta_seconds"], links[0])

    def test_time_to_fix_uses_committer_dates_so_a_rebase_cannot_go_negative(self):
        # A rebased pair: the fix is *authored* before the line it removes, so an
        # author-date delta is negative, while the committer dates stay ordered.
        self._write_and_commit(
            "calc.py",
            "a = 1\nb = 2\nc = 3\n",
            "feat: add the calculation",
            author="Bob <bob@example.com>",
            author_date="2020-01-02T10:00:00+00:00",
            committer_date="2026-09-20T10:00:00+00:00",
        )
        self._write_and_commit(
            "calc.py",
            "a = 1\nb = 20\nc = 3\n",
            "fix: correct the calculation",
            author_date="2020-01-01T10:00:00+00:00",
            committer_date="2026-09-22T10:00:00+00:00",
        )

        links = szz.link_defects(self.repo, self._fixes())

        self.assertEqual(len(links), 1, links)
        self.assertEqual(links[0]["delta_seconds"], 2 * 24 * 3600, links[0])


if __name__ == "__main__":
    unittest.main()
