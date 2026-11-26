#!/usr/bin/env python3
"""deploy-wait — wait for a GitHub Actions deploy run to appear and finish.

Accepts a run id or a workflow plus a ref; polls until the run completes, then
prints one digest. Exit codes are the result, so a caller never parses it:

    0  the run succeeded
    3  the run did not succeed (failed, cancelled, skipped, timed out)
    4  the timeout expired (no run appeared, or it never finished)
    1  runtime error from gh
    2  usage error

A run may be a number, `#number`, `owner/repo#number` or a run URL; a URL's
repository is used when `--repo` is absent. Without a run, `--workflow` needs
`--branch` or `--commit`: the run is selected by the branch tip or that commit,
so a run belonging to another deployment is never taken.

By default the wait is for a run newer than any existing one at the call, so a
repeated deployment of the same commit waits for its own run rather than
reporting the previous verdict; `--last` reports the newest existing run.

Usage:
    deploy-wait.py 1234567
    deploy-wait.py https://github.com/GET-E/core/actions/runs/1234567
    deploy-wait.py --workflow deploy-staging.yml --branch main
    deploy-wait.py --workflow deploy-staging.yml --commit abc1234 --timeout 3600
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from urllib.parse import quote

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_USAGE = 2
EXIT_FAILED = 3
EXIT_TIMEOUT = 4

RUN_FIELDS = (
    "databaseId,status,conclusion,workflowName,headBranch,headSha,event,"
    "createdAt,startedAt,updatedAt,url,displayTitle"
)

RUN_URL_RE = re.compile(
    r"^https?://[^/]+/(?P<slug>[^/]+/[^/]+)/actions/runs/(?P<num>\d+)(?:[/?#].*)?$"
)
RUN_SHORT_RE = re.compile(r"^(?:(?P<slug>[^/\s#]+/[^/\s#]+))?#?(?P<num>\d+)$")


class GhError(Exception):
    """A GitHub call failed; distinct from a run that has no data yet."""


def gh(args: list[str], timeout: int = 60) -> tuple[str, int, str]:
    """Run gh; return (stdout, returncode, stderr). Never raises."""
    try:
        result = subprocess.run(
            ["gh", *args], capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip(), result.returncode, result.stderr.strip()
    except FileNotFoundError:
        return "", 1, "gh not found"
    except subprocess.TimeoutExpired:
        return "", 1, f"gh timed out after {timeout}s"


def parse_run(value: str) -> tuple[str, str | None]:
    """(number, owner/repo or None) from 123, #123, owner/repo#123 or a run URL."""
    text = value.strip()
    for pattern in (RUN_URL_RE, RUN_SHORT_RE):
        match = pattern.match(text)
        if match:
            return match.group("num"), match.group("slug")
    raise ValueError(text)


def resolve_repo(explicit: str | None) -> str:
    if explicit:
        return explicit
    out, rc, err = gh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"])
    if rc != 0 or not out:
        raise GhError(f"cannot resolve the repository: {err or out}")
    return out


def branch_tip(repo: str, branch: str) -> str:
    """The branch's current commit — the one this deployment must be for."""
    out, rc, err = gh(
        ["api", f"repos/{repo}/commits/{quote(branch, safe='')}", "--jq", ".sha"]
    )
    if rc != 0 or not out:
        raise GhError(err or f"cannot resolve the tip of {branch}")
    return out.splitlines()[-1].strip()


def resolve_commit(repo: str, commit: str) -> str:
    """The full SHA for a prefix — the run filter needs the whole one."""
    out, rc, err = gh(
        ["api", f"repos/{repo}/commits/{quote(commit, safe='')}", "--jq", ".sha"]
    )
    if rc != 0 or not out:
        raise GhError(err or f"cannot resolve commit {commit}")
    return out.splitlines()[-1].strip()


def run_by_id(repo: str, number: str, timeout: int = 60) -> dict:
    out, rc, err = gh(["run", "view", number, "--repo", repo, "--json", RUN_FIELDS], timeout)
    if rc != 0:
        raise GhError(err or out or f"gh run view {number} failed")
    try:
        return json.loads(out)
    except ValueError:
        raise GhError(err or "gh run view returned no JSON")


def list_runs(
    repo: str,
    workflow: str,
    branch: str | None,
    commit: str | None = None,
    timeout: int = 60,
) -> list[dict]:
    args = [
        "run",
        "list",
        "--repo",
        repo,
        "--workflow",
        workflow,
        "--limit",
        "50",
        "--json",
        RUN_FIELDS,
    ]
    if branch:
        args += ["--branch", branch]
    # A busy workflow can hide the run past the page; filter upstream.
    if commit:
        args += ["--commit", commit]
    out, rc, err = gh(args, timeout)
    if rc != 0:
        raise GhError(err or out or "gh run list failed")
    try:
        rows = json.loads(out)
    except ValueError:
        raise GhError(err or "gh run list returned no JSON")
    return rows if isinstance(rows, list) else []


def timestamp(value: object) -> datetime | None:
    if not value or not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def pin(rows: list[dict], commit: str | None, tip: str | None) -> list[dict]:
    if commit:
        return [
            row for row in rows if (row.get("headSha") or "").startswith(commit)
        ]
    if tip:
        return [row for row in rows if (row.get("headSha") or "") == tip]
    return rows


def pick_run(
    rows: list[dict],
    commit: str | None,
    tip: str | None,
    baseline: int,
    last: bool = False,
) -> dict | None:
    """The newest run this wait is for, or None while it is absent.

    `baseline` is the newest run that already existed: a run at or below it is a
    previous deployment, so a rerun waits for its own. `--last` returns the
    newest existing one instead.
    """
    rows = pin(rows, commit, tip)
    if last:
        return max(rows, key=lambda row: row.get("databaseId") or 0) if rows else None
    newer = [row for row in rows if (row.get("databaseId") or 0) > baseline]
    if not newer:
        return None
    return max(newer, key=lambda row: row.get("databaseId") or 0)


def failing_jobs(repo: str, number: object) -> list[dict]:
    """Jobs that did not succeed on a failed run, for the digest."""
    if number in (None, ""):
        return []
    out, rc, _ = gh(["run", "view", str(number), "--repo", repo, "--json", "jobs"], timeout=120)
    if rc != 0 or not out:
        return []
    try:
        rows = json.loads(out).get("jobs") or []
    except (ValueError, AttributeError):
        return []
    return [
        row
        for row in rows
        if (row.get("conclusion") or "").lower()
        not in ("success", "neutral", "skipped", "")
    ]


def elapsed(run: dict) -> str:
    start = timestamp(run.get("startedAt"))
    end = timestamp(run.get("updatedAt"))
    if not start or not end:
        return ""
    seconds = max(0, int((end - start).total_seconds()))
    return f"{seconds // 60}m {seconds % 60}s"


def remaining(deadline: float) -> int:
    """Seconds left, at least one — a gh call must not outlive the wait."""
    return max(1, int(deadline - time.monotonic()))


def render(
    repo: str,
    workflow: str | None,
    run: dict | None,
    failed: list[dict],
    code: int,
    timeout: int,
) -> str:
    if run:
        lines = [
            f"## Deploy run #{run.get('databaseId')} — {run.get('displayTitle') or ''}",
            "",
            f"- repository: `{repo}`",
            f"- workflow: {run.get('workflowName') or '?'}",
            f"- event: {run.get('event') or '?'}, branch: `{run.get('headBranch') or '?'}`",
            f"- commit: `{(run.get('headSha') or '')[:8]}`",
            f"- status: {run.get('status') or '?'}"
            + (f" ({run.get('conclusion')})" if run.get("conclusion") else ""),
        ]
        took = elapsed(run) if run.get("status") == "completed" else ""
        if took:
            lines.append(f"- took: {took}")
        lines.append(f"- url: {run.get('url') or ''}")
        lines.append("")
        if code == EXIT_TIMEOUT:
            lines += [f"_still running after {timeout}s_", ""]
    else:
        lines = [
            f"## Deploy run — {workflow or '?'}",
            "",
            f"- repository: `{repo}`",
            f"- no run matched within {timeout}s",
            "- if the newest run predates the call, pass --last",
            "",
        ]
    if failed:
        lines += ["### Failing jobs", ""]
        for row in failed:
            lines.append(f"- `{row.get('name', '?')}` — {row.get('conclusion', '?')}")
        lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Wait for a deploy run to finish")
    parser.add_argument("run", nargs="?", help="run id, #id, owner/repo#id or a run URL")
    parser.add_argument("--repo", default=None, help="owner/name (default: current repo)")
    parser.add_argument(
        "--workflow", default=None, help="deploy workflow file or name to wait on"
    )
    parser.add_argument("--branch", default=None, help="only runs on this branch")
    parser.add_argument("--commit", default=None, help="only runs for this commit SHA")
    parser.add_argument(
        "--last",
        action="store_true",
        help="report the newest existing run instead of waiting for a new one",
    )
    parser.add_argument("--timeout", type=int, default=1800, help="seconds to wait (default 1800)")
    parser.add_argument("--interval", type=int, default=30, help="poll seconds (default 30)")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    args = parser.parse_args(argv)

    if args.run and args.workflow:
        print("ERROR: give a run id or --workflow, not both", file=sys.stderr)
        return EXIT_USAGE
    if not args.run and not args.workflow:
        print("ERROR: give a run id or --workflow", file=sys.stderr)
        return EXIT_USAGE
    if args.workflow and not (args.branch or args.commit):
        print(
            "ERROR: --workflow needs --branch or --commit to name the deploy",
            file=sys.stderr,
        )
        return EXIT_USAGE
    if args.run and (args.branch or args.commit or args.last):
        print(
            "ERROR: --branch/--commit/--last apply to --workflow, not a run id",
            file=sys.stderr,
        )
        return EXIT_USAGE
    if args.interval < 1 or args.timeout < 1:
        print("ERROR: --interval and --timeout must be positive", file=sys.stderr)
        return EXIT_USAGE

    number: str | None = None
    slug: str | None = None
    if args.run:
        try:
            number, slug = parse_run(args.run)
        except ValueError:
            print(
                f"ERROR: {args.run!r} is not a deploy run — give a run id, #id, "
                "owner/repo#id or a run URL",
                file=sys.stderr,
            )
            return EXIT_USAGE

    try:
        repo = resolve_repo(args.repo or slug)
        commit = resolve_commit(repo, args.commit) if args.commit else None
        tip = branch_tip(repo, args.branch) if args.branch and not commit else None
    except GhError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR

    deadline = time.monotonic() + args.timeout
    waits = 0
    current: dict | None = None
    selected = number
    baseline = 0
    expired = False
    if not selected:
        try:
            prior = pin(
                list_runs(
                    repo,
                    args.workflow,
                    args.branch,
                    commit or tip,
                    min(60, remaining(deadline)),
                ),
                commit,
                tip,
            )
        except GhError as exc:
            if time.monotonic() < deadline:
                print(f"ERROR: {exc}", file=sys.stderr)
                return EXIT_ERROR
            expired = True
            prior = []
        baseline = max((row.get("databaseId") or 0) for row in prior) if prior else 0

    while not expired:
        try:
            if selected:
                current = run_by_id(repo, selected, min(60, remaining(deadline)))
            else:
                current = pick_run(
                    list_runs(
                        repo,
                        args.workflow,
                        args.branch,
                        commit or tip,
                        min(60, remaining(deadline)),
                    ),
                    commit,
                    tip,
                    baseline,
                    args.last,
                )
                if current:
                    selected = str(current.get("databaseId"))
        except GhError as exc:
            if time.monotonic() >= deadline:
                code = EXIT_TIMEOUT
                break
            print(f"ERROR: {exc}", file=sys.stderr)
            return EXIT_ERROR

        if current and current.get("status") == "completed":
            code = EXIT_OK if (current.get("conclusion") or "") == "success" else EXIT_FAILED
            break
        if time.monotonic() >= deadline:
            code = EXIT_TIMEOUT
            break
        waits += 1
        time.sleep(min(args.interval, max(1, int(deadline - time.monotonic()))))
    else:
        code = EXIT_TIMEOUT

    failed = failing_jobs(repo, current.get("databaseId")) if current and code == EXIT_FAILED else []

    if args.json:
        outcome = {EXIT_OK: "success", EXIT_FAILED: "failed", EXIT_TIMEOUT: "timeout"}[code]
        print(
            json.dumps(
                {
                    "status": outcome,
                    "repository": repo,
                    "workflow": (current or {}).get("workflowName") or args.workflow,
                    "run": {
                        "id": current.get("databaseId"),
                        "status": current.get("status"),
                        "conclusion": current.get("conclusion"),
                        "branch": current.get("headBranch"),
                        "commit": current.get("headSha"),
                        "url": current.get("url"),
                    }
                    if current
                    else None,
                    "failed_jobs": [
                        {"name": row.get("name"), "conclusion": row.get("conclusion")}
                        for row in failed
                    ],
                    "waits": waits,
                },
                indent=2,
            )
        )
    else:
        print(render(repo, args.workflow, current, failed, code, args.timeout))
        print(f"_{waits} poll(s)_")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
