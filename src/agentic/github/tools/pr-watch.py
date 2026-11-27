#!/usr/bin/env python3
"""pr-watch — drive the Copilot review cycle for one pull request.

Requests the Copilot review, polls the checks and the reviews until a review
with findings appears, the checks settle, or the timeout expires, then prints one
digest. Replaces the hand-typed `gh api` / `sleep` cycle.

Exit codes are the result, so a caller never has to parse the digest:

    0  a review arrived with nothing to address
    3  a required check failed, ignoring a fixup guard
    4  the timeout expired with no review
    5  a review arrived with findings
    6  --until green only: the required checks pass and the PR is mergeable
    1  runtime error from gh
    2  usage error

`--json` reports the outcome as `state`, and repeats it as `status` in the
spelling it had before the rename, for callers written against that.

A landed review's findings are read from the review, not from its body: Copilot
writes a body every time, an approval included. 5 is a change request, line
comments, or a body that does not claim "no open issues"; 0 is an approval, a
review reporting no open issues, or an acknowledgement.

`--until green` waits on the merge gate alone: it never requests a review and
never reads one. It returns 6 only when every check the base branch declares
required is green and the pull request is mergeable. The declaration comes from
the branch protection and the rulesets, not from `gh pr checks --required`, which
lists only the contexts that already exist: a required check that has not started
is therefore waited for, not assumed green. A pull request with no declared check
never reports green — a vacuous gate is not evidence — and neither does one whose
declaration cannot be read. A missing approval, an unresolved thread or a change
request does not hold it back — that gate is the human's. A draft, a conflict, a
stale base or an uncomputed merge state does. A failed declared check still ends
it with 3, named in the digest, within one `--interval`.

A required check whose name contains `fixup` is red by design until the branch
is squashed, so it never produces exit 3. `--ignore-check NAME` adds another
check that may be red by design (repeatable); every ignored check is named in
the digest.

The pull request may be given as a number, `#number`, `owner/repo#number` or a
PR URL; a URL's repository is used when `--repo` is absent.

Usage:
    pr-watch.py 172
    pr-watch.py https://github.com/GET-E/dev-bot/pull/172 --timeout 600
    pr-watch.py 172 --repo GET-E/dev-bot --interval 30
    pr-watch.py 172 --no-request --json
    pr-watch.py 172 --no-request --ignore-check deploy-check
    pr-watch.py 172 --until green
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import subprocess
import sys
import time
from urllib.parse import quote

EXIT_REVIEW = 0
EXIT_ERROR = 1
EXIT_USAGE = 2
EXIT_CHECKS_FAILED = 3
EXIT_TIMEOUT = 4
EXIT_REVIEW_FAILED = 5
EXIT_ALL_GREEN = 6

# mergeable alone does not say whether the merge would be accepted: a branch
# behind its base, in conflict, still a draft, or still being computed is not
# ready. BLOCKED is deliberate — a missing approval or an unresolved thread is
# the human's gate, not a check the tool can wait out.
UNREADY_STATES = {"UNKNOWN", "DIRTY", "CONFLICTING", "BEHIND", "DRAFT"}

# Copilot attaches a body to every review, approvals included, so a body is not
# a finding. It reports its own counts instead, and Read trusts them. The word
# boundary keeps "10 open issues" from matching the zero.
NO_ISSUES_RE = re.compile(r"\bno open issues?\b|\b0 open issues?\b", re.I)
OPEN_ISSUES_RE = re.compile(r"\b[1-9]\d*\s+open issues?\b", re.I)
MISSED_ISSUES_RE = re.compile(r"\b[1-9]\d*\s+previously missed issues?\b", re.I)

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
    fields = "number,state,isDraft,reviewDecision,headRefName,baseRefName,title,url"
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
    beyond the first page. A dismissed or still-pending review is not a verdict
    on the current head, so neither can end the wait.
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
        # A pending or dismissed review is not a verdict on this head.
        if (entry.get("state") or "").upper() in ("PENDING", "DISMISSED"):
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
    a round that did land. A failed read raises: reporting "no comments" during
    an outage would call an addressed pull request clean.
    """
    if review_id in (None, ""):
        return False
    out, rc, err = gh(
        [
            "api",
            "--paginate",
            f"repos/{repo}/pulls/{number}/comments",
            "--jq",
            f".[] | select(.pull_request_review_id == {review_id}) | .id",
        ],
        timeout=120,
    )
    if rc != 0:
        raise GhError(err or "gh api review comments failed")
    return bool(out.strip())


def bucket_of(rows: list[dict]) -> str:
    buckets = {
        "pass" if (row.get("bucket") or "").lower() == "skipping" else (row.get("bucket") or "").lower()
        for row in rows
    }
    if "fail" in buckets or "cancel" in buckets:
        return "fail"
    if "pending" in buckets:
        return "pending"
    if "pass" in buckets:
        return "pass"
    return "none"


def merge_ready(repo: str, number: str) -> tuple[bool, str]:
    """Whether GitHub would accept the merge now — the second gate leg.

    Green checks against a branch that is behind its base, in conflict, still a
    draft, or whose merge state GitHub has not computed yet are not mergeable.
    Returns the state as well, so a timeout can say which leg was short.
    """
    out, rc, err = gh(
        [
            "pr",
            "view",
            number,
            "--repo",
            repo,
            "--json",
            "isDraft,mergeable,mergeStateStatus",
        ]
    )
    if rc != 0 or not out:
        raise GhError(err or "gh pr view mergeable failed")
    try:
        data = json.loads(out)
    except ValueError:
        raise GhError("gh pr view returned no JSON")
    draft = bool(data.get("isDraft"))
    mergeable = (data.get("mergeable") or "").upper()
    state = (data.get("mergeStateStatus") or "UNKNOWN").upper()
    ready = not draft and mergeable == "MERGEABLE" and state not in UNREADY_STATES
    label = "draft" if draft else state
    return ready, f"{label} (mergeable: {mergeable or 'UNKNOWN'})"


def review_has_findings(repo: str, number: str, review: dict | None) -> bool:
    """Whether a landed review leaves something to address.

    Copilot writes a body every time, an approval included, so the body alone
    cannot be the signal: the review's state, its threads and its own
    "no open issues" claim are what separate a clean round from a finding one.
    Threads are read first — an approval can still carry line comments.
    """
    if review is None:
        return False
    if (review.get("state") or "").upper() == "CHANGES_REQUESTED":
        return True
    if review_has_comments(repo, number, review.get("id")):
        return True
    body = (review.get("body") or "").strip()
    if not body:
        return False  # an acknowledgement, not a review with findings
    # Its own counts outrank its state: an approval that reports issues is not
    # a clean round.
    if OPEN_ISSUES_RE.search(body) or MISSED_ISSUES_RE.search(body):
        return True
    if (review.get("state") or "").upper() == "APPROVED":
        return False
    return not NO_ISSUES_RE.search(body)


def is_ignored(row: dict, names: list[str]) -> bool:
    """A fixup guard is red by design until the squash, so it cannot block."""
    name = (row.get("name") or "").strip().casefold()
    return name in {entry.strip().casefold() for entry in names} or "fixup" in name


def _ruleset_applies(entry: dict, branch: str, default_branch: str) -> bool:
    """Whether a repository ruleset enforces on this branch.

    Only active branch rulesets count; a rule for another ref would otherwise
    demand a check this branch will never run. Over-matching waits, which is
    safe; under-matching would report a gate it never proved.
    """
    if (entry.get("enforcement") or "active").lower() != "active":
        return False
    if (entry.get("target") or "branch").lower() != "branch":
        return False
    conditions = ((entry.get("conditions") or {}).get("ref_name") or {})
    include = conditions.get("include") or []
    exclude = conditions.get("exclude") or []

    def matches(patterns: list[str]) -> bool:
        for pattern in patterns:
            # GitHub's ref tokens, not globs: a pattern the matcher read as a
            # literal would silently drop a ruleset that does apply.
            if pattern == "~ALL":
                return True
            if pattern == "~DEFAULT_BRANCH":
                if not default_branch or branch == default_branch:
                    return True
                continue
            for candidate in (f"refs/heads/{branch}", branch):
                if fnmatch.fnmatch(candidate, pattern):
                    return True
        return False

    if exclude and matches(exclude):
        return False
    return not include or matches(include)


def declared_required(repo: str, branch: str) -> set[str] | None:
    """The check contexts the base branch requires, or None when unknown.

    `gh pr checks --required` only lists contexts that already exist, so a
    required check that has not been created yet is invisible there — a fresh
    push looks green. Classic protection and the repository's rulesets are the
    declaration. None means "could not tell", which must keep the caller
    waiting rather than let it report a green it cannot prove.

    Organisation rulesets are not read: listing them needs the `admin:org`
    scope, which the session token does not carry. A check required only by an
    org ruleset is therefore invisible until it reports — the boundary of what
    this gate can prove.
    """
    if not branch:
        return None
    names: set[str] = set()
    known = False

    # The pull request's repository, not the checkout's: --repo may point
    # elsewhere, and ~DEFAULT_BRANCH then resolves against the wrong branch.
    default_branch, rc, _ = gh(
        ["repo", "view", repo, "--json", "defaultBranchRef", "-q", ".defaultBranchRef.name"],
        timeout=60,
    )
    if rc != 0:
        default_branch = ""

    encoded = quote(branch, safe="")
    out, rc, _ = gh(
        ["api", f"repos/{repo}/branches/{encoded}/protection/required_status_checks"],
        timeout=60,
    )
    if rc == 0:
        try:
            data = json.loads(out)
        except ValueError:
            return None
        names.update(data.get("contexts") or ())
        names.update(
            entry.get("context") for entry in data.get("checks") or [] if entry.get("context")
        )
        known = True

    # --paginate runs the jq filter per page, so the listing arrives as one
    # object per line; a single unpaginated page would miss later rulesets.
    listed, rc, _ = gh(
        ["api", "--paginate", f"repos/{repo}/rulesets", "--jq", ".[]"], timeout=120
    )
    if rc != 0:
        # An unreadable listing is not an empty one: the declaration is unknown.
        return None
    known = True
    entries: list[dict] = []
    for line in listed.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except ValueError:
            return None

    for entry in entries:
        if not _ruleset_applies(entry, branch, default_branch.strip()):
            continue
        rule_id = entry.get("id")
        if rule_id is None:
            continue
        detail, rc, _ = gh(["api", f"repos/{repo}/rulesets/{rule_id}"], timeout=60)
        if rc != 0:
            return None
        try:
            rules = json.loads(detail).get("rules") or []
        except ValueError:
            return None
        for rule in rules:
            if rule.get("type") != "required_status_checks":
                continue
            params = rule.get("parameters") or {}
            for check in params.get("required_status_checks") or []:
                if check.get("context"):
                    names.add(check["context"])
    return names if known else None


def gate(repo: str, number: str, ignore: list[str]) -> tuple[str, list[dict], list[dict]]:
    """The required checks — the merge gate — minus the ignored ones.

    A failing optional check is not a merge blocker, so the exit code has to come
    from this set, not from every check on the pull request.
    """
    out, rc, err = gh(
        ["pr", "checks", number, "--repo", repo, "--required", "--json", "name,state,bucket"]
    )
    if not out:
        # A repository that gates on no check raises here. There is then
        # nothing to wait for: the gate stays unknown, never green.
        message = (err or "").lower()
        if "no required checks" in message:
            # Nothing to wait for, and nothing that can turn green: a vacuous
            # gate is not evidence the pull request is ready to merge.
            return "none", [], []
        # Nothing printed and nothing raised: unknown, but the caller may fall
        # back. Runs not registered yet are the same kind of unknown.
        if not rc or "no checks reported" in message:
            return "", [], []
        # Anything else is a failed query. Falling back here would silently
        # reclassify optional checks as the merge gate.
        raise GhError(err or "gh pr checks --required failed")
    try:
        rows = json.loads(out)
    except ValueError:
        # Unparseable output is a failed query, not an empty gate: falling back
        # would silently reclassify optional checks as the merge gate.
        raise GhError("gh pr checks --required returned no JSON")
    active: list[dict] = []
    ignored: list[dict] = []
    for row in rows:
        (ignored if is_ignored(row, ignore) else active).append(row)
    if not rows:
        # An empty required set is no gate at all: it must not read as a pass.
        return "none", [], []
    # Every required check ignored leaves nothing to fail: the gate is satisfied.
    return (bucket_of(active) if active else "pass"), active, ignored


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
    return bucket_of(rows), rows


def render(
    repo: str,
    state: dict,
    review: dict | None,
    bucket: str,
    rows: list[dict],
    ignored: list[dict],
    required: list[dict],
    outcome: str,
    merge: str = "",
    gate: str = "",
) -> str:
    lines = [
        f"## PR #{state.get('number')} — {state.get('title', '')}",
        "",
        f"- repository: `{repo}`",
        f"- branch: `{state.get('headRefName', '')}`",
        f"- outcome: {outcome}",
        f"- state: {state.get('state', '')}"
        + (" (draft)" if state.get("isDraft") else "")
        + f", review decision: {state.get('reviewDecision') or 'none'}",
        f"- checks: {bucket}"
        + (f" ({len(rows)} checks)" if rows else ""),
    ]
    if merge:
        lines.append(f"- merge state: {merge}")
    if gate and gate != bucket:
        label = "none reported" if gate == "none" else gate
        lines.append(f"- required checks: {label}")
    lines.append("")
    if review:
        body = (review.get("body") or "").strip()
        lines += [
            f"### Latest review — {review.get('user', '?')} ({review.get('state', '?')})",
            "",
        ]
        lines.append(body[:2000] if body else "_(no body — likely a review request, not findings)_")
        lines.append("")
    if ignored:
        lines += ["### Ignored checks", ""]
        for row in ignored:
            lines.append(f"- `{row.get('name', '?')}` — {row.get('state', '?')}")
        lines.append("")
    ignored_names = {row.get("name") for row in ignored}
    failed = [
        row
        for row in rows
        if (row.get("bucket") or "").lower() in ("fail", "cancel")
        and row.get("name") not in ignored_names
    ]
    seen = {row.get("name") for row in failed}
    failed += [
        row
        for row in required
        if (row.get("bucket") or "").lower() in ("fail", "cancel")
        and row.get("name") not in seen
    ]
    # A red check outside the gate is not a failure of the pull request, and
    # listing it under Failing checks beside an all-green outcome misleads.
    required_names = {row.get("name") for row in required}
    blocking_fails = [row for row in failed if row.get("name") in required_names]
    optional_fails = [row for row in failed if row.get("name") not in required_names]
    for heading, group in (
        ("### Failing checks", blocking_fails),
        ("### Failing optional checks", optional_fails),
    ):
        if not group:
            continue
        lines += [heading, ""]
        for row in group:
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
    parser.add_argument(
        "--until",
        choices=["review", "green"],
        default="review",
        help="wait for a review (default) or for the merge gate to be green",
    )
    parser.add_argument(
        "--ignore-check",
        action="append",
        default=[],
        metavar="NAME",
        help="required check that may be red by design (repeatable)",
    )
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

    requested = (
        "review: skipped"
        if args.until == "green" or args.no_request
        else request_review(repo, args.number)
    )
    if "failed" in requested or "not queued" in requested:
        # The request is the whole point of this call; polling without it would
        # end in the timeout instead of the documented runtime error.
        print(f"ERROR: {requested}", file=sys.stderr)
        return EXIT_ERROR
    green = args.until == "green"
    # Only a review newer than this cursor belongs to this round — and the head
    # is the later bound, so a request from a previous head cannot satisfy it.
    # --until green reads no reviews, so it needs no cursor.
    cursor = (
        ""
        if green
        else max(review_requested_at(repo, args.number), head_committed_at(repo, args.number))
    )
    deadline = time.monotonic() + args.timeout
    waits = 0
    review: dict | None = None
    ignored: list[dict] = []
    required: list[dict] = []
    merge_state = ""
    # The declaration does not change during a wait, so it is read once.
    declared = declared_required(repo, state.get("baseRefName") or "") if green else None
    try:
        bucket, rows = checks(repo, args.number)
    except GhError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return EXIT_ERROR

    while True:
        if not green:
            try:
                review = latest_review(repo, args.number, cursor)
            except GhError as exc:
                print(f"ERROR: {exc}", file=sys.stderr)
                return EXIT_ERROR
        try:
            state = pr_state(repo, args.number)  # refreshed: render() must not show the initial one
        except SystemExit as exc:
            print(str(exc), file=sys.stderr)
            return EXIT_ERROR
        try:
            bucket, rows = checks(repo, args.number)
        except GhError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return EXIT_ERROR

        # The gate is read before the findings break so the digest and JSON name
        # an ignored guard even when the review landed on this poll.
        try:
            blocking, required, ignored = gate(repo, args.number, args.ignore_check)
        except GhError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return EXIT_ERROR
        # No fallback to the overall set: exit 3 comes from the required checks
        # alone, so an unknown gate fails nothing and the wait continues.

        if green:
            # Both legs of the merge gate: the checks the base branch declares,
            # then the pull request's own readiness. --required alone cannot be
            # the gate: it omits a required check that has not started yet.
            if blocking == "fail":
                code = EXIT_CHECKS_FAILED
                break
            try:
                ready, merge = merge_ready(repo, args.number)
            except GhError as exc:
                print(f"ERROR: {exc}", file=sys.stderr)
                return EXIT_ERROR
            merge_state = merge
            if declared:
                # Ignore by declared name: an exempt check that has not
                # started yet is absent from `ignored` and would never pass.
                gated = {
                    name for name in declared if not is_ignored({"name": name}, args.ignore_check)
                }
                seen = {(row.get("name") or ""): (row.get("bucket") or "").lower() for row in rows}
                if any(seen.get(name) in ("fail", "cancel") for name in gated):
                    code = EXIT_CHECKS_FAILED
                    break
                if ready and all(seen.get(name) in ("pass", "skipping") for name in gated):
                    code = EXIT_ALL_GREEN
                    break
        else:
            try:
                findings = review_has_findings(repo, args.number, review)
            except GhError as exc:
                print(f"ERROR: {exc}", file=sys.stderr)
                return EXIT_ERROR
            if findings:
                code = EXIT_REVIEW_FAILED
                break
            if review:
                code = EXIT_REVIEW
                break
            if blocking == "fail":
                code = EXIT_CHECKS_FAILED
                break
        if time.monotonic() >= deadline:
            code = EXIT_TIMEOUT
            break
        waits += 1
        time.sleep(min(args.interval, max(1, int(deadline - time.monotonic()))))

    outcome = {
        EXIT_REVIEW: "review",
        EXIT_REVIEW_FAILED: "review-failed",
        EXIT_CHECKS_FAILED: "check-failed",
        EXIT_ALL_GREEN: "all-green",
        EXIT_TIMEOUT: "timeout",
    }[code]
    # status is the pre-rename field: it keeps the spellings it always had.
    legacy = {EXIT_REVIEW: "review", EXIT_CHECKS_FAILED: "checks_failed", EXIT_TIMEOUT: "timeout"}
    if args.json:
        print(
            json.dumps(
                {
                    "state": outcome,
                    "status": legacy.get(code, outcome),
                    "repository": repo,
                    "pr": args.number,
                    "request": requested,
                    "waits": waits,
                    "checks": bucket,
                    "merge_state": merge_state or None,
                    "ignored_checks": [row.get("name") for row in ignored],
                    "review": review,
                },
                indent=2,
            )
        )
    else:
        print(
            render(
                repo,
                state,
                review,
                bucket,
                rows,
                ignored,
                required,
                outcome,
                merge_state,
                blocking,
            )
        )
        print(f"_{requested}; {waits} poll(s)_")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
