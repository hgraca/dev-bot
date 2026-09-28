#!/usr/bin/env python3
"""GitHub pull-request source adapter for the forensics module.

Verbs: ``meta`` (declare the adapter), ``doctor`` (is ``gh`` available and
authenticated?) and ``fetch`` (read a window on stdin, emit merged PRs).

All GitHub access goes through the machine's authenticated ``gh`` CLI — no token
handling here — and a merged PR's commit count comes from the GraphQL
``commits.totalCount`` field, so one paginated query covers a window without a
per-PR call.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

SOURCE = "github"
CAPABILITIES = ["pull-requests"]

_QUERY = """query($q: String!, $cursor: String) {
  search(query: $q, type: ISSUE, first: 100, after: $cursor) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number
        author { login }
        createdAt
        mergedAt
        additions
        deletions
        changedFiles
        url
        commits { totalCount }
      }
    }
  }
}"""

_SLUG_RE = re.compile(r"[:/]([^/:]+/[^/:]+)$")


def _gh() -> str:
    return os.environ.get("FORENSICS_GH", "gh")


def _run(args: list) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True)


def repo_slug(project: str) -> str:
    """The ``owner/repo`` slug from the project's ``origin`` remote."""
    proc = _run(["git", "-C", project, "remote", "get-url", "origin"])
    url = (proc.stdout or "").strip()
    match = _SLUG_RE.search(url)
    if not match:
        raise RuntimeError("cannot resolve a GitHub slug from remote '%s'" % url)
    slug = match.group(1)
    return slug[:-4] if slug.endswith(".git") else slug


def _date(value) -> str:
    """The ``YYYY-MM-DD`` part of an ISO-8601 timestamp."""
    raw = str(value or "").strip()[:10]
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", raw):
        raise RuntimeError("not a date: %r" % (value,))
    return raw


def _shape(node: dict) -> dict:
    author = node.get("author") or {}
    commits = node.get("commits") or {}
    return {
        "number": node.get("number"),
        "author": author.get("login") or "",
        "created_at": node.get("createdAt") or "",
        "merged_at": node.get("mergedAt") or "",
        "commits": commits.get("totalCount") or 0,
        "added": node.get("additions") or 0,
        "deleted": node.get("deletions") or 0,
        "changed_files": node.get("changedFiles") or 0,
        "url": node.get("url") or "",
    }


def search_merged(slug: str, since: str, until: str) -> list:
    """Every PR merged in ``[since, until]`` for the slug, across all pages."""
    query = "repo:%s is:pr is:merged merged:%s..%s" % (slug, since, until)
    prs = []
    cursor = None
    while True:
        args = [_gh(), "api", "graphql", "-f", "query=" + _QUERY, "-f", "q=" + query]
        if cursor:
            args += ["-f", "cursor=" + cursor]
        try:
            proc = _run(args)
        except OSError as exc:
            raise RuntimeError("cannot run %s: %s" % (_gh(), exc))
        if proc.returncode != 0:
            raise RuntimeError((proc.stderr or "gh api graphql failed").strip())
        try:
            doc = json.loads(proc.stdout)
        except ValueError:
            raise RuntimeError("gh returned non-JSON")
        page = (doc.get("data") or {}).get("search") or {}
        for node in page.get("nodes") or []:
            prs.append(_shape(node))
        info = page.get("pageInfo") or {}
        if not info.get("hasNextPage"):
            break
        cursor = info.get("endCursor")
        if not cursor:
            break
    return prs


def cmd_meta(argv: list) -> int:
    print(json.dumps({"source": SOURCE, "capabilities": CAPABILITIES}))
    return 0


def cmd_doctor(argv: list) -> int:
    binary = _gh()
    path = shutil.which(binary)
    if not path:
        print(json.dumps({"ok": False, "source": SOURCE, "error": "gh not found (%s)" % binary}))
        return 0
    version = ""
    proc = _run([binary, "--version"])
    if proc.returncode == 0 and proc.stdout:
        version = proc.stdout.splitlines()[0].strip()
    authenticated = _run([binary, "auth", "status"]).returncode == 0
    doc = {"ok": authenticated, "source": SOURCE, "engine": {"via": "host", "path": path, "version": version}}
    if not authenticated:
        doc["error"] = "gh is not authenticated"
    print(json.dumps(doc))
    return 0


def cmd_fetch(argv: list) -> int:
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        print(json.dumps({"ok": False, "error": "invalid JSON on stdin"}))
        return 1
    try:
        slug = repo_slug(payload.get("project") or ".")
        since = _date(payload.get("since"))
        until = _date(payload.get("until"))
        prs = search_merged(slug, since, until)
    except RuntimeError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    print(json.dumps({"ok": True, "pull_requests": prs, "errors": []}))
    return 0


_HANDLERS = {"meta": cmd_meta, "doctor": cmd_doctor, "fetch": cmd_fetch}


def main(argv: list) -> int:
    if not argv:
        print("ERROR: no verb", file=sys.stderr)
        return 2
    handler = _HANDLERS.get(argv[0])
    if handler is None:
        print("ERROR: unknown verb '%s'" % argv[0], file=sys.stderr)
        return 2
    return handler(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
