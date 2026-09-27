#!/usr/bin/env python3
"""szz — link a bug-fixing commit to the commit that introduced the faulty lines.

A simplified SZZ (Śliwerski et al.): for each fix/hotfix commit, blame the lines
the fix *removed* (i.e. the pre-fix source) at the fix's parent revision, and take
the commit blamed for most of them as the inducing commit. It is a heuristic with
known false positives and negatives, reported as a process signal — never a
verdict about a person.
"""

from __future__ import annotations

import datetime
import re
import subprocess

from commitparse import FIX_TYPES

_HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@")


def _git(repo: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def _is_sha(token: str) -> bool:
    return len(token) == 40 and all(char in "0123456789abcdef" for char in token)


def removed_ranges(repo: str, commit: str) -> dict:
    """Per pre-image path, the line ranges (start, length) the commit changed.

    Uses the *old* path so a rename or deletion still resolves at the parent, and
    disables path quoting so non-ASCII names survive. ``+++``/``---`` are only
    treated as headers outside a hunk, so an added line beginning with ``+++`` is
    not mistaken for a file.
    """
    proc = _git(repo, "-c", "core.quotePath=false", "show", "--format=", "--unified=0", "--no-color", "-M", commit)
    if proc.returncode != 0:
        return {}

    ranges = {}
    old_path = None
    current = None
    in_hunk = False

    for line in proc.stdout.splitlines():
        if line.startswith("diff --git "):
            old_path = None
            current = None
            in_hunk = False
            continue
        if not in_hunk and line.startswith("--- "):
            value = line[4:].strip()
            old_path = None if value == "/dev/null" else (value[2:] if value.startswith("a/") else value)
            continue
        if not in_hunk and line.startswith("+++ "):
            value = line[4:].strip()
            new_path = None if value == "/dev/null" else (value[2:] if value.startswith("b/") else value)
            current = old_path if old_path is not None else new_path
            if current is not None:
                ranges.setdefault(current, [])
            continue

        match = _HUNK.match(line)
        if match:
            in_hunk = True
            if current is not None:
                length = int(match.group(2)) if match.group(2) is not None else 1
                if length > 0:
                    ranges[current].append((int(match.group(1)), length))

    return ranges


def blame_origins(repo: str, rev: str, path: str, start: int, end: int) -> dict:
    """Count blamed lines per commit for a range at ``rev`` (empty on failure)."""
    proc = _git(repo, "blame", "--line-porcelain", "-L", "%d,%d" % (start, end), rev, "--", path)
    if proc.returncode != 0:
        return {}
    counts = {}
    for line in proc.stdout.splitlines():
        token = line.split(" ", 1)[0]
        if _is_sha(token):
            counts[token] = counts.get(token, 0) + 1
    return counts


def _seconds_between(start: str, end: str):
    try:
        first = datetime.datetime.fromisoformat(start)
        second = datetime.datetime.fromisoformat(end)
    except (ValueError, TypeError):
        return None
    return int((second - first).total_seconds())


def link_defects(repo: str, commits: list) -> list:
    """One defect link per fix commit — the inducing commit with the most blame."""
    by_hash = {commit["hash"]: commit for commit in commits}
    links = []

    for commit in commits:
        if commit.get("type") not in FIX_TYPES:
            continue
        fix_hash = commit["hash"]
        parent = _git(repo, "rev-parse", fix_hash + "^").stdout.strip()
        if not parent:
            continue

        best = None
        for path, ranges in removed_ranges(repo, fix_hash).items():
            for start, length in ranges:
                counts = blame_origins(repo, parent, path, start, start + length - 1)
                if not counts:
                    continue
                inducing = max(counts, key=lambda sha: counts[sha])
                if best is None or counts[inducing] > best["matched_lines"]:
                    origin = by_hash.get(inducing)
                    best = {
                        "fix_hash": fix_hash,
                        "fix_type": commit.get("type"),
                        "fix_author": commit.get("author_email", ""),
                        "inducing_hash": inducing,
                        "inducing_author": origin.get("author_email", "") if origin else "",
                        "delta_seconds": _seconds_between(origin["date"], commit["date"]) if origin else None,
                        "matched_lines": counts[inducing],
                    }

        if best is not None:
            links.append(best)

    return links
