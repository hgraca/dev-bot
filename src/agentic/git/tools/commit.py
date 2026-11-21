#!/usr/bin/env python3
"""commit — stage the named paths and commit, in one call.

The corpus showed `git add <paths> → git commit` in 29% of sessions: two calls
for one act, with the path list typed once and the message the caller's input
either way. This stages exactly the paths given (never `-A`, never `.`) and
commits, optionally as a fixup against an earlier commit.

Exit codes: 0 committed, 1 git failed, 2 usage.

Usage:
    commit.py --message-file /tmp/msg.txt src/a.py src/b.py
    commit.py -m "fix: tidy the retry loop" -- src/a.py
    commit.py --fixup 3a3b3313 src/a.py
"""

from __future__ import annotations

import argparse
import subprocess
import sys

EXIT_OK = 0
EXIT_GIT = 1
EXIT_USAGE = 2


def git(args: list[str], cwd: str | None = None) -> tuple[str, int, str]:
    try:
        result = subprocess.run(
            ["git", *args], capture_output=True, text=True, timeout=120, cwd=cwd
        )
        return result.stdout.strip(), result.returncode, result.stderr.strip()
    except FileNotFoundError:
        return "", 1, "git not found"
    except subprocess.TimeoutExpired:
        return "", 1, "git timed out"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Stage named paths and commit")
    parser.add_argument("paths", nargs="+", help="paths to stage (never -A)")
    parser.add_argument("--message-file", default=None, help="file holding the message")
    parser.add_argument("-m", "--message", default=None, help="commit message inline")
    parser.add_argument("--fixup", default=None, help="record a fixup for this commit")
    parser.add_argument("--cwd", default=None, help="repository directory")
    args = parser.parse_args(argv)

    if args.fixup and (args.message_file or args.message):
        print("ERROR: --fixup writes its own message; drop -m and --message-file", file=sys.stderr)
        return EXIT_USAGE
    if not args.fixup and bool(args.message_file) == bool(args.message):
        print("ERROR: give exactly one of --message-file or -m", file=sys.stderr)
        return EXIT_USAGE
    if args.message_file:
        try:
            with open(args.message_file, encoding="utf-8") as handle:
                if not handle.read().strip():
                    print("ERROR: message file is empty", file=sys.stderr)
                    return EXIT_USAGE
        except OSError as exc:
            print(f"ERROR: cannot read message file: {exc}", file=sys.stderr)
            return EXIT_USAGE

    _, rc, err = git(["add", "--", *args.paths], cwd=args.cwd)
    if rc != 0:
        print(f"ERROR: git add failed: {err}", file=sys.stderr)
        return EXIT_GIT

    if args.fixup:
        commit_args = ["commit", "--fixup", args.fixup]
    elif args.message_file:
        commit_args = ["commit", "-F", args.message_file]
    else:
        commit_args = ["commit", "-m", args.message]
    # The pathspec keeps any foreign staged entry out of this commit.
    out, rc, err = git([*commit_args, "--", *args.paths], cwd=args.cwd)
    if rc != 0:
        print(f"ERROR: git commit failed: {err or out}", file=sys.stderr)
        return EXIT_GIT

    sha, _, _ = git(["rev-parse", "--short", "HEAD"], cwd=args.cwd)
    subject, _, _ = git(["log", "-1", "--format=%s"], cwd=args.cwd)
    print(f"{sha} {subject}")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
