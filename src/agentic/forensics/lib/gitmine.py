#!/usr/bin/env python3
"""gitmine — language-agnostic git history miner for the forensics module.

Commands:
  log    commits (author, date, message, churn) + per-commit file changes
  blame  per-line author attribution for a single file

Output is canonical JSON. Nothing language-specific happens here: this is the
evidence layer every analysis is built on.
"""

from __future__ import annotations

import datetime
import json
import os
import subprocess
import sys

FIELD = "\x1f"
RECORD = "\x1e"


def _git(repo: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def _is_repo(repo: str) -> bool:
    proc = _git(repo, "rev-parse", "--is-inside-work-tree")
    return proc.returncode == 0 and proc.stdout.strip() == "true"


def _head(repo: str) -> str:
    proc = _git(repo, "rev-parse", "HEAD")
    return proc.stdout.strip() if proc.returncode == 0 else ""


def toplevel(repo: str) -> str:
    """The repository root for a path (empty string if not a repo)."""
    proc = _git(repo, "rev-parse", "--show-toplevel")
    return proc.stdout.strip() if proc.returncode == 0 else ""


def tags(repo: str) -> list:
    """Tags in creation order as {tag, date} — the release-cadence evidence."""
    proc = _git(
        repo,
        "for-each-ref",
        "--sort=creatordate",
        "--format=%(refname:short)\t%(creatordate:iso-strict)",
        "refs/tags",
    )
    result = []
    for line in proc.stdout.splitlines():
        if "\t" not in line:
            continue
        tag, date = line.split("\t", 1)
        result.append({"tag": tag.strip(), "date": date.strip()})
    return result


def _range_args(since, until) -> list:
    args = []
    if since:
        args += ["--since", since]
    if until:
        args += ["--until", until]
    return args


def _parse_numstat_z(raw: bytes) -> list:
    """Parse ``git log --numstat -z`` bytes into change rows.

    ``-z`` is NUL-delimited and never C-quotes a path, so non-ASCII and special
    filenames survive. Tokens are ``\\x1e<sha>`` for a commit header, then per
    entry ``added\\tdeleted\\t<path>`` — or, for a rename, an empty path followed
    by the old and new paths as their own NUL tokens.
    """
    record = RECORD.encode()
    tokens = raw.split(b"\x00")
    changes = []
    commit = ""
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token.startswith(record):
            commit = token[len(record):].decode("ascii", "replace").strip()
            index += 1
            continue
        if not token:
            index += 1
            continue
        if token.startswith(b"\n"):
            token = token[1:]
        parts = token.split(b"\t")
        if len(parts) < 3:
            index += 1
            continue

        added_raw, deleted_raw = parts[0], parts[1]
        path_raw = b"\t".join(parts[2:])
        if path_raw == b"":
            old_raw = tokens[index + 1] if index + 1 < len(tokens) else b""
            new_raw = tokens[index + 2] if index + 2 < len(tokens) else b""
            changes.append(
                {
                    "commit_hash": commit,
                    "path": os.fsdecode(new_raw),
                    "added": int(added_raw) if added_raw.isdigit() else 0,
                    "deleted": int(deleted_raw) if deleted_raw.isdigit() else 0,
                    "is_rename": True,
                    "old_path": os.fsdecode(old_raw),
                }
            )
            index += 3
        else:
            changes.append(
                {
                    "commit_hash": commit,
                    "path": os.fsdecode(path_raw),
                    "added": int(added_raw) if added_raw.isdigit() else 0,
                    "deleted": int(deleted_raw) if deleted_raw.isdigit() else 0,
                    "is_rename": False,
                    "old_path": "",
                }
            )
            index += 1
    return changes


def mine_commits(repo: str, since=None, until=None) -> list:
    fmt = RECORD + FIELD.join(["%H", "%an", "%ae", "%aI", "%B"]) + FIELD
    proc = _git(repo, "log", "--format=" + fmt, *_range_args(since, until))
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "git log failed")

    commits = []
    for chunk in proc.stdout.split(RECORD):
        if not chunk.strip():
            continue
        parts = chunk.split(FIELD)
        if len(parts) < 5:
            continue
        commits.append(
            {
                "hash": parts[0],
                "author_name": parts[1],
                "author_email": parts[2],
                "date": parts[3],
                "message": parts[4].rstrip("\n"),
                "files_changed": 0,
                "lines_added": 0,
                "lines_deleted": 0,
            }
        )
    return commits


def mine_changes(repo: str, since=None, until=None) -> list:
    fmt = RECORD + "%H"
    proc = subprocess.run(
        ["git", "-C", repo, "log", "-M", "--numstat", "-z", "--format=" + fmt, *_range_args(since, until)],
        capture_output=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace").strip() or "git log --numstat failed")
    return _parse_numstat_z(proc.stdout)


def mine_log(repo: str, since=None, until=None) -> dict:
    commits = mine_commits(repo, since, until)
    changes = mine_changes(repo, since, until)

    by_hash = {commit["hash"]: commit for commit in commits}
    for change in changes:
        commit = by_hash.get(change["commit_hash"])
        if commit is None:
            continue
        commit["files_changed"] += 1
        commit["lines_added"] += change["added"]
        commit["lines_deleted"] += change["deleted"]

    return {
        "ok": True,
        "repo": os.path.abspath(repo),
        "head": _head(repo),
        "since": since,
        "until": until,
        "commits": commits,
        "changes": changes,
    }


def _iso_utc(epoch: str) -> str:
    try:
        return datetime.datetime.fromtimestamp(int(epoch), datetime.timezone.utc).isoformat()
    except (ValueError, TypeError):
        return ""


def mine_blame(repo: str, path: str) -> dict:
    proc = _git(repo, "blame", "--line-porcelain", "--", path)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "git blame failed")

    lines = []
    current = None
    for raw in proc.stdout.split("\n"):
        if not raw:
            continue

        if raw.startswith("\t"):
            if current is not None:
                lines.append(current)
                current = None
            continue

        if raw.startswith("author "):
            if current is not None:
                current["author_name"] = raw[len("author "):]
            continue
        if raw.startswith("author-mail "):
            if current is not None:
                current["author_email"] = raw[len("author-mail "):].strip("<>")
            continue
        if raw.startswith("author-time "):
            if current is not None:
                current["date"] = _iso_utc(raw[len("author-time "):])
            continue

        header = raw.split(" ")
        if len(header) >= 3 and len(header[0]) == 40 and all(c in "0123456789abcdef" for c in header[0]):
            current = {"line": int(header[2]), "hash": header[0], "author_name": "", "author_email": "", "date": ""}

    return {"ok": True, "repo": os.path.abspath(repo), "file": path, "lines": lines}


def _parse_opts(argv: list) -> dict:
    opts = {}
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg.startswith("--"):
            if index + 1 < len(argv) and not argv[index + 1].startswith("--"):
                opts[arg[2:]] = argv[index + 1]
                index += 2
            else:
                opts[arg[2:]] = True
                index += 1
        else:
            index += 1
    return opts


def main(argv: list) -> int:
    if argv and argv[0] in ("--help", "-h"):
        print("Usage: gitmine.py <log|blame> --repo <path> [--since <d>] [--until <d>] [--file <path>]")
        return 0

    if not argv:
        print("ERROR: no command", file=sys.stderr)
        return 2

    command, rest = argv[0], argv[1:]
    opts = _parse_opts(rest)

    repo = opts.get("repo")
    if not isinstance(repo, str) or not repo:
        print("ERROR: --repo is required", file=sys.stderr)
        return 2
    if not _is_repo(repo):
        print("ERROR: not a git repository: %s" % repo, file=sys.stderr)
        return 1

    try:
        if command == "log":
            doc = mine_log(repo, opts.get("since"), opts.get("until"))
        elif command == "blame":
            path = opts.get("file")
            if not isinstance(path, str) or not path:
                print("ERROR: --file is required for blame", file=sys.stderr)
                return 2
            doc = mine_blame(repo, path)
        else:
            print("ERROR: unknown command '%s'" % command, file=sys.stderr)
            return 2
    except RuntimeError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1

    print(json.dumps(doc, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
