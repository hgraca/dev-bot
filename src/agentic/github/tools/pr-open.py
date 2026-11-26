#!/usr/bin/env python3
"""pr-open — push the branch, open the pull request, assign it, request the review.

The commands that always happen together in the corpus: `git push -u origin
<branch>`, `gh pr create --title … --body-file …`, `gh pr edit --add-assignee`,
then the GraphQL mutation that requests the Copilot review. This does them in
one call and prints the pull request URL.

`--type` is the finish flow's publisher: it fixes the standing title, the
repository the pull request belongs to and (for the memory streams) the body, so
publishing a memory or a review improvement is one deterministic call. A typed
call never requests a review, and never opens a second standing pull request —
it appends to the branch's own, and refuses rather than guessing when a standing
one sits on another branch.

Of the steps after the push, only the creation is fatal: the PR is what the
caller cannot reconstruct, so a failed assignment or review request is reported
at the end instead of losing it.

Exit codes: 0 opened (or already open) with every requested step done,
1 git/gh failure or a step that did not register, 2 usage.

Usage:
    pr-open.py --title "feat(x): do the thing" --body-file /tmp/body.md
    pr-open.py --title "..." --body-file body.md --base main --assignee @me --no-review
    pr-open.py --type global-memories --cwd /path/to/worktree
    pr-open.py --type review-improvement --body-file /tmp/body.md --cwd /path
    pr-open.py --type proj-memories --cwd /path --remote upstream
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_USAGE = 2

COPILOT_USER = "copilot-pull-request-reviewer%5Bbot%5D"
COPILOT_LOGIN = "Copilot"
MUTATION = (
    "mutation($pr: ID!, $bot: ID!) { requestReviews(input: "
    "{pullRequestId: $pr, botIds: [$bot]}) { clientMutationId } }"
)

# repo: "project" = the checkout given to --cwd, "dev-bot" = the toolkit's own.
TYPES = {
    "proj-memories": {
        "title": "chore(agents): commit memories and lessons learned",
        "repo": "project",
        "body": (
            "Problems:\n"
            "- session memories stay on a local branch no one reviews\n"
            "\n"
            "Solutions:\n"
            "- publish the vault notes from the project that owns them\n"
            "- keep one reviewable pull request per repository\n"
        ),
    },
    "global-memories": {
        "title": "chore(global-memories): commit global memories and lessons learned",
        "repo": "dev-bot",
        "body": (
            "Problems:\n"
            "- global lessons accumulate untracked in the toolkit\n"
            "\n"
            "Solutions:\n"
            "- collect the global store's notes in one reviewable pull request\n"
        ),
    },
    "review-improvement": {
        "title": "chore(improve-reviews): improve review skill",
        "repo": "dev-bot",
        "body": None,
    },
}


WORKDIR: str | None = None


def run(cmd: list[str], timeout: int = 180, cwd: str | None = None) -> tuple[str, int, str]:
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd or WORKDIR
        )
        return result.stdout.strip(), result.returncode, result.stderr.strip()
    except FileNotFoundError:
        return "", 1, f"{cmd[0]} not found"
    except subprocess.TimeoutExpired:
        return "", 1, f"{cmd[0]} timed out"


def current_branch() -> str:
    """The attached branch, or empty when the checkout is detached."""
    out, rc, err = run(["git", "branch", "--show-current"])
    if rc != 0:
        raise SystemExit(f"FATAL: cannot read the current branch: {err or out}")
    return out


def repo_slug(directory: str | None = None) -> str:
    out, rc, err = run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"], cwd=directory
    )
    if rc != 0 or not out:
        raise SystemExit(f"FATAL: cannot resolve the repository: {err or out}")
    return out


def dev_bot_slug() -> str:
    """The toolkit's repository, so a global stream never lands in a project."""
    root = Path(os.environ.get("DEV_BOT_ROOT") or Path(__file__).resolve().parents[4])
    if not (root / ".git").exists():
        raise SystemExit(f"FATAL: {root} is not the dev-bot checkout: set DEV_BOT_ROOT")
    return repo_slug(str(root))


def default_branch(repo: str) -> str:
    out, rc, err = run(
        ["gh", "repo", "view", repo, "--json", "defaultBranchRef", "-q", ".defaultBranchRef.name"]
    )
    if rc != 0 or not out:
        raise SystemExit(f"FATAL: cannot read {repo}'s default branch: {err or out}")
    return out


def remote_identity(remote: str, push: bool = False) -> str:
    """host/owner/name a remote points at — the host is part of the identity."""
    # --all: a remote may carry several pushurls, and git push fans out to all.
    args = ["git", "remote", "get-url", "--all"] + (["--push"] if push else []) + [remote]
    out, rc, err = run(args)
    urls = [line for line in out.splitlines() if line.strip()]
    if rc != 0 or not urls:
        raise SystemExit(f"FATAL: cannot read the {remote} remote: {err or out}")
    if len(urls) > 1:
        raise SystemExit(f"FATAL: {remote} pushes to {len(urls)} repositories: {', '.join(urls)}")
    url = urls[0].strip().rstrip("/")
    if url.endswith(".git"):
        url = url[:-4]
    if "://" in url:
        authority, _, path = url.split("://", 1)[1].partition("/")
        host = authority.split("@")[-1]
    else:
        host, _, path = url.partition(":")  # scp-like: git@host:owner/repo
        host = host.split("@")[-1]
    return f"{host.lower()}/{path.lower()}"


def repo_identity(repo: str) -> str:
    """host/owner/name of a repository, as GitHub reports its own URL."""
    out, rc, err = run(["gh", "repo", "view", repo, "--json", "url", "-q", ".url"])
    if rc != 0 or not out:
        raise SystemExit(f"FATAL: cannot read {repo}'s URL: {err or out}")
    parsed = urlparse(out)
    return f"{(parsed.hostname or '').lower()}/{parsed.path.strip('/').lower()}"


def ensure_pushed(branch: str, remote: str, publishing_head: bool) -> str:
    """Push with upstream set, or report it is already there."""
    head, hrc, _ = run(["git", "rev-parse", "HEAD"])
    tip, trc, _ = run(["git", "rev-parse", "--verify", "--quiet", f"{remote}/{branch}"])
    if hrc == 0 and trc == 0 and head == tip:
        return "already up to date"
    # A detached worktree has no branch to set an upstream on.
    if publishing_head:
        args = ["git", "push", "-u", remote, branch]
    else:
        args = ["git", "push", remote, f"HEAD:{branch}"]
    out, rc, err = run(args)
    if rc != 0:
        raise SystemExit(f"FATAL: push failed: {err or out}")
    return "pushed"


def open_prs_for_branch(repo: str | None, branch: str) -> list[dict[str, str]]:
    """Every open pull request whose head is this branch — a branch can have many."""
    args = ["gh", "pr", "list", "--head", branch, "--state", "open"]
    if repo:
        args += ["--repo", repo]
    args += ["--json", "number,title,url", "--jq", ".[] | [.number, .title, .url] | @tsv"]
    out, rc, err = run(args)
    if rc != 0:
        raise SystemExit(f"FATAL: cannot list the pull requests: {err or out}")
    rows = []
    for line in out.splitlines():
        if line.strip():
            number, title, url = line.split("\t")
            rows.append({"number": number, "title": title, "url": url})
    return rows


def standing_prs(repo: str, title: str) -> list[dict[str, str]]:
    """Every open pull request carrying the stream's standing title."""
    out, rc, err = run(
        [
            "gh",
            "pr",
            "list",
            "--repo",
            repo,
            "--state",
            "open",
            "--limit",
            "200",
            "--json",
            "number,headRefName,title,url",
            "--jq",
            f'.[] | select(.title == "{title}") | [.number, .headRefName, .url] | @tsv',
        ],
        timeout=120,
    )
    if rc != 0:
        raise SystemExit(f"FATAL: cannot list the standing pull requests: {err or out}")
    rows = []
    for line in out.splitlines():
        if line.strip():
            number, head, url = line.split("\t")
            rows.append({"number": number, "head": head, "url": url})
    return rows


def create_pr(
    title: str,
    body_file: str | None,
    base: str | None,
    draft: bool,
    body: str | None = None,
    repo: str | None = None,
    head: str | None = None,
) -> str:
    args = ["gh", "pr", "create", "--title", title]
    if body_file:
        args += ["--body-file", body_file]
    elif body:
        args += ["--body", body]
    if base:
        args += ["--base", base]
    if head:
        args += ["--head", head]
    if repo:
        args += ["--repo", repo]
    if draft:
        args.append("--draft")
    out, rc, err = run(args)
    if rc != 0:
        raise SystemExit(f"FATAL: gh pr create failed: {err or out}")
    return out.splitlines()[-1].strip() if out else ""


def assign(url: str, login: str) -> str:
    """Add an assignee, unless that login is already on the pull request."""
    target = login
    if login == "@me":
        target, _, _ = run(["gh", "api", "user", "--jq", ".login"])
    current, _, _ = run(
        ["gh", "pr", "view", url, "--json", "assignees", "--jq", ".assignees[].login"]
    )
    if target and target in current.splitlines():
        return "already assigned"
    out, rc, err = run(["gh", "pr", "edit", url, "--add-assignee", login])
    if rc != 0:
        return f"failed ({err or out})"
    return "assigned"


def head_committed_at(number: str, repo: str) -> str:
    """When the PR's head commit was authored — the freshness bound for a request."""
    out, rc, _ = run(
        ["gh", "pr", "view", number, "--repo", repo, "--json", "commits", "--jq", ".[-1].committedDate"],
        timeout=120,
    )
    return out if rc == 0 else ""


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
    # A request stays in the timeline forever; only one newer than the current
    # head proves this head was queued.
    requested = timeline_requested(repo, number)
    head_at = head_committed_at(number, repo)
    if requested and head_at and requested >= head_at:
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


def target_repo(spec: dict, override: str | None) -> str:
    """The repository the pull request belongs to."""
    if override:
        return override
    return dev_bot_slug() if spec["repo"] == "dev-bot" else repo_slug()


def publish_typed(args: argparse.Namespace, branch: str, publishing_head: bool) -> int:
    """Push and open or append the stream's one standing pull request."""
    spec = TYPES[args.type]
    title = spec["title"]
    repo = target_repo(spec, args.repo)
    target = repo_identity(repo)
    pushed_to = remote_identity(args.remote, push=True)
    if pushed_to != target:
        print(
            f"FATAL: {args.remote} is {pushed_to}, but a {args.type} pull request belongs to {target}",
            file=sys.stderr,
        )
        return EXIT_FAIL

    if branch == default_branch(repo):
        print(f"FATAL: {branch} is {repo}'s default branch; publish a branch", file=sys.stderr)
        return EXIT_FAIL

    # Nothing is pushed until the branch is known to be this stream's own: a
    # mistaken checkout must not add commits to a stranger's pull request.
    heads = open_prs_for_branch(repo, branch)
    current = heads[0] if heads else None
    strangers = [item for item in heads if item["title"] != title]
    if strangers:
        print(
            f"FATAL: {strangers[0]['url']} already heads {branch} for another purpose",
            file=sys.stderr,
        )
        return EXIT_FAIL
    if len(heads) > 1:
        print(
            f"FATAL: {len(heads)} open pull requests head {branch}: "
            + ", ".join(item["url"] for item in heads),
            file=sys.stderr,
        )
        return EXIT_FAIL

    standing = standing_prs(repo, title)
    if len(standing) > 1:
        print(
            "FATAL: more than one standing pull request carries that title; "
            + ", ".join(item["url"] for item in standing),
            file=sys.stderr,
        )
        return EXIT_FAIL
    if standing and not current:
        print(
            f"FATAL: {standing[0]['url']} is the standing pull request, on branch "
            f"{standing[0]['head']}; commit there instead of opening a second",
            file=sys.stderr,
        )
        return EXIT_FAIL

    pushed = ensure_pushed(branch, args.remote, publishing_head)

    body, twins = "unchanged", []
    if current:
        note, url = "appended", current["url"]
        if args.body_file:
            print("WARN: the standing pull request keeps its own body", file=sys.stderr)
    else:
        url = create_pr(
            title,
            args.body_file,
            args.base,
            args.draft,
            body=spec["body"],
            repo=repo,
            head=branch,
        )
        note, body = "opened", "created"
        # Two sessions can both read "none"; the twin is found, not hidden.
        twins = [item["url"] for item in standing_prs(repo, title) if item["url"] != url]
        for twin in twins:
            print(f"WARN: a second standing pull request appeared: {twin}", file=sys.stderr)

    print(
        json.dumps(
            {
                "type": args.type,
                "branch": branch,
                "remote": args.remote,
                "repo": repo,
                "push": pushed,
                "pr": note,
                "url": url,
                "body": body,
                "twins": twins,
                "review": "skipped",
            },
            indent=2,
        )
    )
    return EXIT_OK


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Push, open a pull request, assign it, request the review")
    parser.add_argument("--title", default=None, help="the pull request title; forbidden with --type")
    parser.add_argument("--type", choices=sorted(TYPES), default=None,
                        help="publish a finish-flow stream: its title, repository and body are fixed")
    parser.add_argument("--body-file", default=None)
    parser.add_argument("--base", default=None)
    parser.add_argument("--draft", action="store_true")
    parser.add_argument("--assignee", default=None, help="login to assign, @me for yourself")
    parser.add_argument("--no-review", action="store_true", help="skip the Copilot request")
    parser.add_argument("--remote", default="origin", help="the remote to push to (default: origin)")
    parser.add_argument("--repo", default=None, help="owner/name the pull request belongs to")
    parser.add_argument("--branch", default=None, help="the branch to publish; needed on a detached HEAD")
    parser.add_argument("--cwd", default=None, help="the checkout to act on; required with --type")
    args = parser.parse_args(argv)

    if args.type and args.title is not None:
        print("ERROR: --type carries its own title", file=sys.stderr)
        return EXIT_USAGE
    if not args.type and not args.title:
        print("ERROR: one of --title or --type is required", file=sys.stderr)
        return EXIT_USAGE
    if args.type and TYPES[args.type]["body"] is None and not args.body_file:
        print(f"ERROR: a {args.type} pull request needs --body-file", file=sys.stderr)
        return EXIT_USAGE
    if args.type and args.assignee:
        print("ERROR: a standing pull request is assigned by hand", file=sys.stderr)
        return EXIT_USAGE
    if args.type and args.draft:
        print("ERROR: a standing pull request is never a draft", file=sys.stderr)
        return EXIT_USAGE
    if args.type and not args.cwd:
        print("ERROR: --type needs --cwd <checkout>", file=sys.stderr)
        return EXIT_USAGE

    global WORKDIR
    if args.cwd:
        if not os.path.isdir(args.cwd):
            print(f"ERROR: --cwd {args.cwd} is not a directory", file=sys.stderr)
            return EXIT_USAGE
        WORKDIR = os.path.abspath(args.cwd)

    if args.body_file:
        if WORKDIR and not os.path.isabs(args.body_file):
            args.body_file = os.path.join(WORKDIR, args.body_file)
        try:
            with open(args.body_file, encoding="utf-8") as handle:
                if not handle.read().strip():
                    print("ERROR: body file is empty", file=sys.stderr)
                    return EXIT_USAGE
        except OSError as exc:
            print(f"ERROR: cannot read body file: {exc}", file=sys.stderr)
            return EXIT_USAGE

    attached = current_branch()
    branch = args.branch or attached
    if not branch:
        print("ERROR: the checkout is detached: pass --branch <name>", file=sys.stderr)
        return EXIT_USAGE

    publishing_head = attached == branch
    if args.type:
        return publish_typed(args, branch, publishing_head)

    pushed = ensure_pushed(branch, args.remote, publishing_head)

    heads = open_prs_for_branch(args.repo, branch)
    current = heads[0] if heads else None
    if current:
        url = current["url"]
        note = "already open"
    else:
        url = create_pr(
            args.title,
            args.body_file,
            args.base,
            args.draft,
            repo=args.repo,
            head=args.branch,
        )
        note = "opened"

    assigned = assign(url, args.assignee) if args.assignee else "skipped"
    review = "skipped" if args.no_review else request_review(url)
    print(
        json.dumps(
            {
                "branch": branch,
                "push": pushed,
                "pr": note,
                "url": url,
                "assignee": assigned,
                "review": review,
            },
            indent=2,
        )
    )
    # PR exists either way; a step that did not
    # register still fails the exit code.
    failures = []
    if args.assignee and assigned not in ("assigned", "already assigned"):
        failures.append(f"the assignee was not added: {assigned}")
    if not args.no_review and review not in ("requested", "already requested", "skipped"):
        failures.append(f"the Copilot review did not register: {review}")
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    return EXIT_FAIL if failures else EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
