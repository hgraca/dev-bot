#!/usr/bin/env python3
"""pr-watch — drive the Copilot review cycle for one pull request.

Requests the Copilot review, polls the checks and the reviews until a review
with findings appears, the checks settle, or the timeout expires, then prints one
digest. Replaces the hand-typed `gh api` / `sleep` cycle.

Exit codes are the result, so a caller never has to parse the digest:

    0  a review arrived (or the review decision is already final)
    3  the checks failed
    4  the timeout expired with no review
    1  runtime error from gh
    2  usage error

The pull request may be given as a number, `#number`, `owner/repo#number` or a
PR URL; a URL's repository is used when `--repo` is absent.

Usage:
    pr-watch.py 172
    pr-watch.py https://github.com/GET-E/dev-bot/pull/172 --timeout 600
    pr-watch.py 172 --repo GET-E/dev-bot --interval 30
    pr-watch.py 172 --no-request --json
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time

EXIT_REVIEW = 0
EXIT_ERROR = 1
EXIT_USAGE = 2
EXIT_CHECKS_FAILED = 3
EXIT_TIMEOUT = 4

MUTATION = (
    "mutation($pr: ID!, $bot: ID!) { requestReviews(input: "
    "{pullRequestId: $pr, botIds: [$bot]}) { clientMutationId } }"
)

COPILOT_USER = "copilot-pull-request-reviewer%5Bbot%5D"
COPILOT_LOGIN = "Copilot"


class GhError(Exception):
    """A GitHub call failed; distinct from a PR that simply has no data yet."""


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


PR_URL_RE = re.compile(
    r"^https?://[^/]+/(?P<slug>[^/]+/[^/]+)/(?:pull|pulls)/(?P<num>\d+)/?(?:[?#].*)?$"
)
PR_SHORT_RE = re.compile(r"^(?:(?P<slug>[^/\s#]+/[^/\s#]+))?#?(?P<num>\d+)$")


def parse_pr(value: str) -> tuple[str, str | None]:
    """(number, owner/repo or None) from 172, #172, owner/repo#172 or a PR URL.

    Callers hand this tool whatever their own surface accepts — a number from a
    digest, a URL from a review comment — so the shape is normalised here rather
    than in every caller.
    """
    text = value.strip()
    for pattern in (PR_URL_RE, PR_SHORT_RE):
        match = pattern.match(text)
        if match:
            return match.group("num"), match.group("slug")
    raise ValueError(text)


def resolve_repo(explicit: str | None) -> str:
    if explicit:
        return explicit
    out, rc, err = gh(["repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"])
    if rc != 0 or not out:
        raise SystemExit(f"FATAL: cannot resolve the repository: {err or out}")
    return out


def pr_state(repo: str, number: str) -> dict:
    fields = "number,state,isDraft,reviewDecision,headRefName,title,url"
    out, rc, err = gh(["pr", "view", number, "--repo", repo, "--json", fields])
    if rc != 0:
        raise SystemExit(f"FATAL: cannot read PR #{number} in {repo}: {err or out}")
    return json.loads(out)


def review_requested_at(repo: str, number: str) -> str:
    """When Copilot was last asked to review, or "" when never.

    The REST `requested_reviewers` view and `--json reviewRequests` never list
    bot reviewers, so the timeline is the only honest source.
    """
    out, rc, _ = gh(
        [
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


def head_committed_at(repo: str, number: str) -> str:
    """When the PR's head commit was authored — the freshness bound for a request."""
    out, rc, _ = gh(
        ["pr", "view", number, "--repo", repo, "--json", "commits", "--jq", ".[-1].committedDate"],
        timeout=120,
    )
    return out if rc == 0 else ""


def request_review(repo: str, number: str) -> str:
    """Ask for the Copilot review. Returns a line describing what happened.

    GraphQL only: `gh pr edit --add-reviewer` reports success while registering
    nobody, and the REST request endpoint does not queue a bot reviewer either.
    """
    # An old request stays in the timeline forever. Only a request newer than
    # the current head proves this head was queued; otherwise a push would go
    # unreviewed because a previous round had asked once.
    requested = review_requested_at(repo, number)
    head_at = head_committed_at(repo, number)
    if requested and head_at and requested >= head_at:
        return "review: already requested"
    bot, rc, err = gh(["api", f"users/{COPILOT_USER}", "--jq", ".node_id"])
    if rc != 0 or not bot:
        return f"review: request failed (bot id: {err or 'not found'})"
    pr_id, rc, err = gh(["pr", "view", number, "--repo", repo, "--json", "id", "--jq", ".id"])
    if rc != 0 or not pr_id:
        return f"review: request failed (pr id: {err or 'not found'})"
    out, rc, err = gh(
        [
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
        return f"review: request failed ({err or out})"
    # The mutation's exit code is not proof the review was queued.
    time.sleep(1)
    return "review: requested" if review_requested_at(repo, number) else "review: not queued"


def latest_review(repo: str, number: str, since: str = "") -> dict | None:
    """The newest Copilot review submitted after ``since``, paginated.

    The endpoint mixes human and bot reviews and is paginated: taking the last
    entry would let a human review end the loop, and would miss a Copilot review
    beyond the first page.
    """
    out, rc, err = gh(
        [
            "api",
            "--paginate",
            f"repos/{repo}/pulls/{number}/reviews",
            "--jq",
            ".[] | {id, user: .user.login, state, submitted_at, body}",
        ],
        timeout=120,
    )
    if rc != 0:
        raise GhError(err or "gh api reviews failed")
    reviews = []
    for line in out.splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if "copilot" not in (entry.get("user") or "").lower():
            continue
        if since and (entry.get("submitted_at") or "") <= since:
            continue
        reviews.append(entry)
    if not reviews:
        return None
    return max(reviews, key=lambda entry: entry.get("submitted_at") or "")


def review_has_comments(repo: str, number: str, review_id: object) -> bool:
    """Whether a review carries line comments — findings with no body at all.

    A Copilot review can be COMMENTED with an empty body and every finding in the
    inline comments; judging arrival by the body alone waits out the timeout on
    a round that did land.
    """
    if review_id in (None, ""):
        return False
    out, rc, _ = gh(
        [
            "api",
            "--paginate",
            f"repos/{repo}/pulls/{number}/comments",
            "--jq",
            f".[] | select(.pull_request_review_id == {review_id}) | .id",
        ],
        timeout=120,
    )
    return rc == 0 and bool(out.strip())


def bucket_of(rows: list[dict]) -> str:
    buckets = {(row.get("bucket") or "").lower() for row in rows}
    if "fail" in buckets or "cancel" in buckets:
        return "fail"
    if "pending" in buckets:
        return "pending"
    if "pass" in buckets:
        return "pass"
    return "none"


def gate(repo: str, number: str) -> tuple[str, list[dict]]:
    """The required checks — the merge gate — or ("", []) when gh cannot say.

    A failing optional check is not a merge blocker, so the exit code has to come
    from this set, not from every check on the pull request.
    """
    out, rc, _ = gh(
        ["pr", "checks", number, "--repo", repo, "--required", "--json", "name,state,bucket"]
    )
    if not out:
        return "", []
    try:
        rows = json.loads(out)
    except ValueError:
        return "", []
    return bucket_of(rows), rows


def unregistered(err: str) -> bool:
    """True when gh says simply that no check run exists yet.

    Check runs are created a moment after a push, and gh calls that state an
    error. Polling is the correct answer; treating it as an outage is not.
    """
    return "no checks reported" in (err or "").lower()


def checks(repo: str, number: str) -> tuple[str, list[dict]]:
    """Return (overall bucket, rows). Overall is fail | pending | pass | none.

    A gh failure raises: reporting "none" during an outage would look like a PR
    with no checks and poll until the timeout instead of failing fast. A non-zero
    exit with parseable JSON is normal — gh returns one when checks are failing.
    """
    out, rc, err = gh(["pr", "checks", number, "--repo", repo, "--json", "name,state,bucket"])
    if not out:
        if rc != 0 and not unregistered(err):
            raise GhError(err or "gh pr checks failed")
        return "none", []
    try:
        rows = json.loads(out)
    except ValueError:
        raise GhError(err or "gh pr checks returned no JSON")
    buckets = {(row.get("bucket") or "").lower() for row in rows}
    if "fail" in buckets or "cancel" in buckets:
        return "fail", rows
    if "pending" in buckets:
        return "pending", rows
    if "pass" in buckets:
        return "pass", rows
    return "none", rows


def render(repo: str, state: dict, review: dict | None, bucket: str, rows: list[dict]) -> str:
    lines = [
        f"## PR #{state.get('number')} — {state.get('title', '')}",
        "",
        f"- repository: `{repo}`",
        f"- branch: `{state.get('headRefName', '')}`",
        f"- state: {state.get('state', '')}"
        + (" (draft)" if state.get("isDraft") else "")
        + f", review decision: {state.get('reviewDecision') or 'none'}",
        f"- checks: {bucket}"
        + (f" ({len(rows)} checks)" if rows else ""),
        "",
    ]
    if review:
        body = (review.get("body") or "").strip()
        lines += [
            f"### Latest review — {review.get('user', '?')} ({review.get('state', '?')})",
            "",
        ]
        lines.append(body[:2000] if body else "_(no body — likely a review request, not findings)_")
        lines.append("")
    failed = [
        row for row in rows if (row.get("bucket") or "").lower() in ("fail", "cancel")
    ]
    if failed:
        lines += ["### Failing checks", ""]
        for row in failed:
            lines.append(f"- `{row.get('name', '?')}` — {row.get('state', '?')}")
        lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Drive the Copilot review cycle")
    parser.add_argument("number", help="pull request number")
    parser.add_argument("--repo", default=None, help="owner/name (default: current repo)")
    parser.add_argument("--timeout", type=int, default=900, help="seconds to wait (default 900)")
    parser.add_argument("--interval", type=int, default=60, help="poll seconds (default 60)")
    parser.add_argument("--no-request", action="store_true", help="do not request a review")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    args = parser.parse_args(argv)

    try:
        number, slug = parse_pr(args.number)
    except ValueError:
        print(
            f"ERROR: {args.number!r} is not a pull request — give a number, #number, "
            "owner/repo#number or a PR URL",
            file=sys.stderr,
        )
        return EXIT_USAGE
    args.number = number
    if args.interval < 1 or args.timeout < 1:
        print("ERROR: --interval and --timeout must be positive", file=sys.stderr)
        return EXIT_USAGE

    repo = resolve_repo(args.repo or slug)
    state = pr_state(repo, args.number)
    if state.get("state") != "OPEN":
        print(f"ERROR: PR #{args.number} is {state.get('state')}, not open", file=sys.stderr)
        return EXIT_USAGE

    requested = request_review(repo, args.number) if not args.no_request else "review: skipped"
    if "failed" in requested or "not queued" in requested:
        # The request is the whole point of this call; polling without it would
        # end in the timeout instead of the documented runtime error.
        print(f"ERROR: {requested}", file=sys.stderr)
        return EXIT_ERROR
    # Only a review newer than this cursor belongs to this round — and the head
    # is the later bound, so a request from a previous head cannot satisfy it.
    cursor = max(review_requested_at(repo, args.number), head_committed_at(repo, args.number))
    deadline = time.monotonic() + args.timeout
    waits = 0
    review: dict | None = None
    try:
        bucket, rows = checks(repo, args.number)
    except GhError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR

    while True:
        try:
            review = latest_review(repo, args.number, cursor)
        except GhError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return EXIT_ERROR
        try:
            state = pr_state(repo, args.number)  # refreshed: render() must not show the initial one
            decision = (state.get("reviewDecision") or "").upper()
        except SystemExit as exc:
            print(str(exc), file=sys.stderr)
            return EXIT_ERROR
        has_findings = bool(
            review
            and (
                (review.get("body") or "").strip()
                or review_has_comments(repo, args.number, review.get("id"))
            )
        ) or decision in ("APPROVED", "CHANGES_REQUESTED")
        try:
            bucket, rows = checks(repo, args.number)
        except GhError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return EXIT_ERROR

        if has_findings:
            code = EXIT_REVIEW
            break
        # Only a required check blocks the merge; optional failures do not.
        blocking, _ = gate(repo, args.number)
        failed = blocking == "fail" if blocking else bucket == "fail"
        if failed:
            code = EXIT_CHECKS_FAILED
            break
        if time.monotonic() >= deadline:
            code = EXIT_TIMEOUT
            break
        waits += 1
        time.sleep(min(args.interval, max(1, int(deadline - time.monotonic()))))

    if args.json:
        print(
            json.dumps(
                {
                    "status": {EXIT_REVIEW: "review", EXIT_CHECKS_FAILED: "checks_failed",
                               EXIT_TIMEOUT: "timeout"}[code],
                    "repository": repo,
                    "pr": args.number,
                    "request": requested,
                    "waits": waits,
                    "checks": bucket,
                    "review": review,
                },
                indent=2,
            )
        )
    else:
        print(render(repo, state, review, bucket, rows))
        print(f"_{requested}; {waits} poll(s)_")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
