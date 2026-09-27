#!/usr/bin/env python3
"""trends — sample a repository over time to see complexity growth (A9).

Historical complexity needs the code as it was, so this samples one revision per
interval (the last commit in each month/quarter) and inspects a detached git
worktree at each. Expensive by design; opt in with `mine --trends`.
"""

from __future__ import annotations

import datetime
import subprocess


def _git(repo: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def _bucket(date: str, interval: str) -> str:
    try:
        parsed = datetime.datetime.fromisoformat(date)
    except (ValueError, TypeError):
        return date
    if interval == "quarter":
        return "%04d-Q%d" % (parsed.year, (parsed.month - 1) // 3 + 1)
    if interval == "year":
        return "%04d" % parsed.year
    return "%04d-%02d" % (parsed.year, parsed.month)


def sample_revisions(repo: str, interval: str = "month") -> list:
    """The last commit of each interval bucket, in order — a trend's timeline."""
    proc = _git(repo, "log", "--reverse", "--format=%H\t%aI")
    buckets = {}
    order = []
    for line in proc.stdout.splitlines():
        if "\t" not in line:
            continue
        revision, date = line.split("\t", 1)
        key = _bucket(date, interval)
        if key not in buckets:
            order.append(key)
        buckets[key] = {"revision": revision, "date": date}
    return [buckets[key] for key in order]


def add_worktree(repo: str, revision: str, path: str) -> bool:
    proc = _git(repo, "worktree", "add", "--detach", "--force", path, revision)
    return proc.returncode == 0


def remove_worktree(repo: str, path: str) -> None:
    _git(repo, "worktree", "remove", "--force", path)
    _git(repo, "worktree", "prune")
