#!/usr/bin/env python3
"""git-report — snapshot current git state and output Markdown.

Captures: current branch, default branch (local + remote), recent commits,
working-tree status, staged diff (summary + full), and commits unique to the
current branch.

Usage:
  python3 git-report.py
  python3 git-report.py --log-count 20
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys


def run(cmd: list[str], cwd: str | None = None) -> tuple[str, int]:
    """Run a shell command, return (stdout, returncode). Never raises."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            cwd=cwd,
        )
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "(timeout)", 1
    except FileNotFoundError:
        return "(git not found)", 1


def collect(log_count: int, cwd: str | None = None) -> dict:
    """Collect all git state into a structured dict."""
    # Ensure origin/HEAD is resolved (best-effort, ignore failure)
    run(["git", "remote", "set-head", "origin", "--auto"], cwd=cwd)

    repo_root, repo_rc = run(["git", "rev-parse", "--show-toplevel"], cwd=cwd)
    if repo_rc != 0:
        repo_root = os.path.abspath(cwd) if cwd else os.getcwd()

    current_branch, _ = run(["git", "branch", "--show-current"], cwd=cwd)
    # Distinguish "no origin remote at all" from "origin exists but HEAD isn't
    # set": the set-head remediation below can only work when origin exists, so
    # the fallback message must differ (audit-19 incidental NOTE — suggesting a
    # command that was already run and cannot succeed is dead advice).
    _, origin_rc = run(["git", "remote", "get-url", "origin"], cwd=cwd)
    default_branch, rc = run(
        ["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd=cwd
    )
    if rc != 0:
        if origin_rc != 0:
            # No origin remote at all — the only meaningful "default branch" is
            # the current one (HEAD). Report it instead of a bare "(unknown)"
            # so the report stays useful on remote-less repos and the
            # unique-commit logic below has a real base (audit-35 NOTE).
            default_branch = "(unknown — no remote configured)"
            default_branch_local = current_branch or "(unknown)"
        else:
            default_branch_local = "(unknown)"
            default_branch = "(unknown — run: git remote set-head origin --auto)"
    else:
        default_branch_local = (
            default_branch.split("/", 1)[1] if "/" in default_branch else default_branch
        )

    recent_commits, _ = run(["git", "log", "--oneline", f"-{log_count}"], cwd=cwd)
    status, _ = run(["git", "status"], cwd=cwd)
    staged_stat, _ = run(["git", "diff", "--staged", "--stat"], cwd=cwd)
    staged_diff, _ = run(["git", "diff", "--staged"], cwd=cwd)

    unique_commits = ""
    if default_branch_local not in ("", "(unknown)"):
        unique_commits, urc = run(
            ["git", "log", "--oneline", f"{default_branch_local}..HEAD"], cwd=cwd
        )
        if urc != 0 and "unknown" not in default_branch:
            unique_commits, _ = run(
                ["git", "log", "--oneline", f"{default_branch}..HEAD"], cwd=cwd
            )

    # --connectivity-only walks reachability from refs (fast) and still reports
    # missing objects, which is the corruption we care about. --full additionally
    # re-verifies every object's SHA and scans unreachable objects — far slower,
    # and unnecessary for detecting missing objects.
    fsck_out, _ = run(["git", "fsck", "--connectivity-only"], cwd=cwd)
    fsck_missing = "\n".join(
        line for line in fsck_out.splitlines() if "missing" in line
    )

    return {
        "repository": repo_root,
        "current_branch": current_branch,
        "default_branch": default_branch,
        "default_branch_local": default_branch_local,
        "recent_commits": recent_commits,
        "status": status,
        "staged_stat": staged_stat,
        "staged_diff": staged_diff,
        "unique_commits": unique_commits,
        "fsck_missing": fsck_missing,
    }


def render_markdown(data: dict) -> str:
    """Render collected git state as a markdown report."""
    lines = []

    lines.append("## Git Report")
    lines.append("")
    lines.append(f"**Repository:** `{data['repository']}`  ")
    lines.append(f"**Current branch:** `{data['current_branch']}`  ")
    lines.append(f"**Default branch:** `{data['default_branch_local']}`")
    lines.append(f"**Default remote branch:** `{data['default_branch']}`")
    lines.append("")

    lines.append("### Recent Commits")
    lines.append("")
    if data["recent_commits"]:
        for line in data["recent_commits"].splitlines():
            lines.append(f"- {line}")
    else:
        lines.append("_(no commits)_")
    lines.append("")

    lines.append("### Status")
    lines.append("")
    lines.append("```")
    lines.append(data["status"] or "(clean)")
    lines.append("```")
    lines.append("")

    lines.append("### Staged Changes (summary)")
    lines.append("")
    if data["staged_stat"]:
        lines.append("```")
        lines.append(data["staged_stat"])
        lines.append("```")
    else:
        lines.append("_(nothing staged)_")
    lines.append("")

    lines.append("### Staged Changes (full diff)")
    lines.append("")
    if data["staged_diff"]:
        lines.append("```diff")
        lines.append(data["staged_diff"])
        lines.append("```")
    else:
        lines.append("_(nothing staged)_")
    lines.append("")

    lines.append("### Commits Unique to Current Branch")
    lines.append("")
    if data["unique_commits"]:
        for line in data["unique_commits"].splitlines():
            lines.append(f"- {line}")
    else:
        lines.append("_(none — branch is up to date or default branch unknown)_")
    lines.append("")

    lines.append("### Index Integrity (fsck missing objects)")
    lines.append("")
    if data["fsck_missing"]:
        lines.append("```")
        lines.append(data["fsck_missing"])
        lines.append("```")
    else:
        lines.append("_(no missing objects — index clean)_")

    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="git-report tool")
    parser.add_argument(
        "--log-count",
        type=int,
        default=10,
        help="Number of recent commits to show (default: 10)",
    )
    parser.add_argument(
        "--cwd",
        default=None,
        help="Repository directory to inspect (default: the current directory)",
    )
    parser.add_argument(
        "--format",
        choices=["markdown", "json"],
        default="markdown",
        help=argparse.SUPPRESS,  # hidden — bash wrapper always passes markdown
    )
    args = parser.parse_args()

    if args.cwd is not None:
        if not os.path.isdir(args.cwd):
            print(f"ERROR: --cwd is not a directory: {args.cwd}", file=sys.stderr)
            raise SystemExit(2)
        _, repo_rc = run(["git", "rev-parse", "--show-toplevel"], cwd=args.cwd)
        if repo_rc != 0:
            print(f"ERROR: --cwd is not a git repository: {args.cwd}", file=sys.stderr)
            raise SystemExit(2)

    data = collect(args.log_count, cwd=args.cwd)

    if args.format == "json":
        print(json.dumps({"status": "ok", **data}, indent=2))
    else:
        print(render_markdown(data))


if __name__ == "__main__":
    main()
