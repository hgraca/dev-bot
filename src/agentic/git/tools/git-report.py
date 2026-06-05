#!/usr/bin/env python3
"""git-report — snapshot current git state and output Markdown.

Captures: current branch, default branch (local + remote), recent commits,
working-tree status, staged diff (summary + full), and commits unique to the
current branch.

Usage:
  python3 git-report.py
  python3 git-report.py --log-count 20
"""

import argparse
import json
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


def collect(log_count: int) -> dict:
    """Collect all git state into a structured dict."""
    # Ensure origin/HEAD is resolved (best-effort, ignore failure)
    run(["git", "remote", "set-head", "origin", "--auto"])

    current_branch, _ = run(["git", "branch", "--show-current"])
    default_branch, rc = run(
        ["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"]
    )
    if rc != 0:
        default_branch = "(unknown — run: git remote set-head origin --auto)"
        default_branch_local = "(unknown)"
    else:
        default_branch_local = (
            default_branch.split("/", 1)[1] if "/" in default_branch else default_branch
        )

    recent_commits, _ = run(["git", "log", "--oneline", f"-{log_count}"])
    status, _ = run(["git", "status"])
    staged_stat, _ = run(["git", "diff", "--staged", "--stat"])
    staged_diff, _ = run(["git", "diff", "--staged"])

    unique_commits = ""
    if "unknown" not in default_branch:
        unique_commits, urc = run(
            ["git", "log", "--oneline", f"{default_branch_local}..HEAD"]
        )
        if urc != 0:
            unique_commits, _ = run(
                ["git", "log", "--oneline", f"{default_branch}..HEAD"]
            )

    fsck_out, _ = run(["git", "fsck", "--full"])
    fsck_missing = "\n".join(
        line for line in fsck_out.splitlines() if "missing" in line
    )

    return {
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
        "--format",
        choices=["markdown", "json"],
        default="markdown",
        help=argparse.SUPPRESS,  # hidden — bash wrapper always passes markdown
    )
    args = parser.parse_args()

    data = collect(args.log_count)

    if args.format == "json":
        print(json.dumps({"status": "ok", **data}, indent=2))
    else:
        print(render_markdown(data))


if __name__ == "__main__":
    main()
