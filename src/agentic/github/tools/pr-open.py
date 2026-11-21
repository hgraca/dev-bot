#!/usr/bin/env python3
"""pr-open — push the branch, open the pull request, request the review.

Three commands that always happen together in the corpus: `git push -u origin
<branch>`, `gh pr create --repo … --title … --body-file …`, then the GraphQL
mutation that requests the Copilot review. This does them in one call and prints
the pull request URL.

Exit codes: 0 opened (or already open), 1 git/gh failure, 2 usage.

Usage:
    pr-open.py --title "feat(x): do the thing" --body-file /tmp/body.md
    pr-open.py --title "..." --body-file body.md --base main --no-review
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_USAGE = 2

COPILOT_USER = "copilot-pull-request-reviewer%5Bbot%5D"
COPILOT_LOGIN = "Copilot"
MUTATION = (
    "mutation($pr: ID!, $bot: ID!) { requestReviews(input: "
    "{pullRequestId: $pr, botIds: [$bot]}) { clientMutationId } }"
)


def run(cmd: list[str], timeout: int = 180) -> tuple[str, int, str]:
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip(), result.returncode, result.stderr.strip()
    except FileNotFoundError:
        return "", 1, f"{cmd[0]} not found"
    except subprocess.TimeoutExpired:
        return "", 1, f"{cmd[0]} timed out"


def current_branch() -> str:
    out, rc, err = run(["git", "branch", "--show-current"])
    if rc != 0 or not out:
        raise SystemExit(f"FATAL: cannot read the current branch: {err or out}")
    return out


def ensure_pushed(branch: str) -> str:
    """Push with upstream set, or report it is already there."""
    _, rc, _ = run(["git", "rev-parse", "--verify", "--quiet", f"origin/{branch}"])
    upstream_exists = rc == 0
    ahead, arc, _ = run(["git", "rev-list", "--count", f"origin/{branch}..HEAD"]) if upstream_exists else ("1", 0, "")
    if upstream_exists and arc == 0 and ahead == "0":
        return "already up to date"
    out, rc, err = run(["git", "push", "-u", "origin", branch])
    if rc != 0:
        raise SystemExit(f"FATAL: push failed: {err or out}")
    return "pushed"


def existing_pr(branch: str) -> str | None:
    out, rc, _ = run(["gh", "pr", "list", "--head", branch, "--state", "open", "--json", "url", "-q", ".[0].url"])
    if rc != 0 or not out:
        return None
    return out


def create_pr(title: str, body_file: str | None, base: str | None, draft: bool) -> str:
    args = ["gh", "pr", "create", "--title", title]
    if body_file:
        args += ["--body-file", body_file]
    if base:
        args += ["--base", base]
    if draft:
        args.append("--draft")
    out, rc, err = run(args)
    if rc != 0:
        raise SystemExit(f"FATAL: gh pr create failed: {err or out}")
    return out.splitlines()[-1].strip() if out else ""


def timeline_requested(repo: str, number: str) -> str:
    """When Copilot was last asked to review — the timeline is the only source,
    because the REST reviewer view never lists bot reviewers."""
    out, rc, _ = run(
        [
            "gh",
            "api",
            "--paginate",
            f"repos/{repo}/issues/{number}/timeline",
            "--jq",
            f'.[] | select(.event=="review_requested" and .requested_reviewer.login=="{COPILOT_LOGIN}") | .created_at',
        ],
        timeout=120,
    )
    if rc != 0 or not out:
        return ""
    return out.splitlines()[-1].strip()


def request_review(url: str) -> str:
    """GraphQL only — `gh pr edit --add-reviewer` registers nobody."""
    number, rrc, _ = run(["gh", "pr", "view", url, "--json", "number", "-q", ".number"])
    repo, nrc, _ = run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]
    )
    if rrc != 0 or nrc != 0:
        return "could not resolve the PR"
    if timeline_requested(repo, number):
        return "already requested"
    bot, brc, berr = run(["gh", "api", f"users/{COPILOT_USER}", "--jq", ".node_id"])
    pr_id, irc, ierr = run(["gh", "pr", "view", url, "--json", "id", "-q", ".id"])
    if brc != 0 or irc != 0:
        return f"request failed ({berr or ierr or 'could not resolve ids'})"
    _, rc, err = run(
        [
            "gh",
            "api",
            "graphql",
            "-f",
            f"query={MUTATION}",
            "-f",
            f"pr={pr_id}",
            "-f",
            f"bot={bot}",
        ]
    )
    if rc != 0:
        return f"request failed ({err})"
    time.sleep(1)
    return "requested" if timeline_requested(repo, number) else "not queued"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Push, open a pull request, request the review")
    parser.add_argument("--title", required=True)
    parser.add_argument("--body-file", default=None)
    parser.add_argument("--base", default=None)
    parser.add_argument("--draft", action="store_true")
    parser.add_argument("--no-review", action="store_true", help="skip the Copilot request")
    args = parser.parse_args(argv)

    if args.body_file:
        try:
            with open(args.body_file, encoding="utf-8") as handle:
                if not handle.read().strip():
                    print("ERROR: body file is empty", file=sys.stderr)
                    return EXIT_USAGE
        except OSError as exc:
            print(f"ERROR: cannot read body file: {exc}", file=sys.stderr)
            return EXIT_USAGE

    branch = current_branch()
    pushed = ensure_pushed(branch)

    url = existing_pr(branch)
    opened = False
    if url:
        note = "already open"
    else:
        url = create_pr(args.title, args.body_file, args.base, args.draft)
        opened = True
        note = "opened"

    review = "skipped" if args.no_review else request_review(url)
    print(
        json.dumps(
            {"branch": branch, "push": pushed, "pr": note, "url": url, "review": review},
            indent=2,
        )
    )
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
