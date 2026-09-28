#!/usr/bin/env python3
"""trends — sample a repository over time to see complexity growth (A9).

Historical complexity needs the code as it was, so this samples one revision per
interval (the last commit in each day/week/month/quarter/year) and inspects a
detached git worktree at each. Expensive by design; opt in with `mine --trends`.

Sampling is bounded by the mining window: only revisions inside it are sampled,
and buckets key on the same date the walk filters on (committer date), so a
one-month window and a `day` interval produce a one-month daily trend.
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
    if interval == "day":
        return parsed.strftime("%Y-%m-%d")
    if interval == "week":
        return parsed.strftime("%G-W%V")
    if interval == "quarter":
        return "%04d-Q%d" % (parsed.year, (parsed.month - 1) // 3 + 1)
    if interval == "year":
        return "%04d" % parsed.year
    return "%04d-%02d" % (parsed.year, parsed.month)


def last_commit_per_bucket(entries: list, interval: str) -> list:
    """The last entry of each interval bucket, in first-appearance order.

    ``git log --reverse`` feeds these chronologically, so first-appearance order
    is chronological order.
    """
    buckets = {}
    order = []
    for entry in entries:
        key = _bucket(entry["date"], interval)
        if key not in buckets:
            order.append(key)
        buckets[key] = entry
    return [buckets[key] for key in order]


def sample_revisions(repo: str, interval: str = "month", since=None, until=None) -> list:
    """The last commit of each interval bucket inside the window — a trend's timeline."""
    args = []
    if since:
        args += ["--since", since]
    if until:
        args += ["--until", until]
    proc = _git(repo, "log", "--reverse", "--format=%H\t%cI", *args)

    entries = []
    for line in proc.stdout.splitlines():
        if "\t" not in line:
            continue
        revision, date = line.split("\t", 1)
        entries.append({"revision": revision, "date": date})
    return last_commit_per_bucket(entries, interval)


def add_worktree(repo: str, revision: str, path: str) -> bool:
    proc = _git(repo, "worktree", "add", "--detach", "--force", path, revision)
    return proc.returncode == 0


def remove_worktree(repo: str, path: str) -> None:
    _git(repo, "worktree", "remove", "--force", path)
    _git(repo, "worktree", "prune")
