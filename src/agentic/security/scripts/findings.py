#!/usr/bin/env python3
"""Findings store and gate for the security module.

The store is one JSON object per line, mirroring the record `devbot:security-findings`
defines. The gate reads a unified diff and answers whether the change touches a known
finding — on its own lines, elsewhere in a changed file, or in a calling file.

Contract, mirroring the way a merge gate is read:

  exit 0  PASS    every check ran and nothing known intersects the change
  exit 1  REVIEW  something needs attention (or a check could not run)
  exit 2  BLOCK   an open High/Critical finding sits on the changed lines
  exit 3  usage error

The gate fails closed: a missing store, an unparseable store or an empty change set each
yield REVIEW, never PASS. PASS means "every check ran and found nothing", not "secure".
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

REQUIRED = ("id", "title", "severity", "status", "tier")
SEVERITIES = ("Critical", "High", "Medium", "Low", "Informational")
STATUSES = ("open", "confirmed", "mitigated", "false_positive", "accepted_risk")
TIERS = ("read-in-source", "observed", "reproduced")
# A finding in one of these states still describes the code, so the gate reads it.
OPEN_STATES = ("open", "confirmed")
# Only these earn a BLOCK; the rest are a reason to look, not to stop.
BLOCKING_SEVERITIES = ("Critical", "High")
# A hunk boundary moves when lines above it are added, so a finding one or two
# lines outside a hunk still belongs to it.
LINE_SLACK = 2

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
NEW_FILE = re.compile(r"^\+\+\+ b/(.+)$")

DEFAULT_STORE = os.path.join(".agents", "memory", "latent", "security", "findings.jsonl")


class StoreError(Exception):
    """The store exists but cannot be trusted."""


def repo_root(start: str) -> str:
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=start, capture_output=True, text=True, check=False,
    )
    if out.returncode != 0:
        raise SystemExit("ERROR: not inside a git repository")
    return out.stdout.strip()


def git(args: list[str], cwd: str) -> str:
    out = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=False)
    return out.stdout if out.returncode == 0 else ""


def store_path(args) -> str:
    if args.store:
        return args.store
    env = os.environ.get("SEC_FINDINGS_STORE")
    if env:
        return env
    return os.path.join(repo_root(os.getcwd()), DEFAULT_STORE)


def load(path: str):
    """Return the records, or None when the store does not exist."""
    if not os.path.exists(path):
        return None
    records = []
    with open(path, encoding="utf-8") as fh:
        for number, line in enumerate(fh, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise StoreError(f"{path}:{number}: {exc}") from exc
            if not isinstance(record, dict):
                raise StoreError(f"{path}:{number}: not an object")
            records.append(record)
    return records


def problems_with(record: dict) -> list[str]:
    found = [f"missing {key}" for key in REQUIRED if not record.get(key)]
    if record.get("severity") and record["severity"] not in SEVERITIES:
        found.append(f"severity {record['severity']!r} is not one of {', '.join(SEVERITIES)}")
    if record.get("status") and record["status"] not in STATUSES:
        found.append(f"status {record['status']!r} is not one of {', '.join(STATUSES)}")
    if record.get("tier") and record["tier"] not in TIERS:
        found.append(f"tier {record['tier']!r} is not one of {', '.join(TIERS)}")
    location = record.get("location") or {}
    if location and not location.get("file"):
        found.append("location present without a file")
    cvss = record.get("cvss")
    if cvss and re.search(r"CVSS:v?3\.1", str(cvss)):
        found.append("cvss carries a superseded 3.1 vector")
    return found


def cmd_check(args, path: str, records) -> int:
    if records is None:
        print(f"REVIEW: no findings store at {path}")
        return 1
    failures = 0
    for record in records:
        for problem in problems_with(record):
            print(f"  {record.get('id', '<no id>')}: {problem}")
            failures += 1
    counted = {state: 0 for state in STATUSES}
    for record in records:
        counted[record.get("status", "open")] = counted.get(record.get("status", "open"), 0) + 1
    summary = ", ".join(f"{state} {count}" for state, count in counted.items() if count)
    print(f"{len(records)} record(s){' — ' + summary if summary else ''}")
    if failures:
        print(f"ERROR: {failures} problem(s) in {path}")
        return 1
    return 0


def cmd_add(args, path: str) -> int:
    raw = sys.stdin.read().strip()
    if not raw:
        print("ERROR: add reads one JSON object on stdin", file=sys.stderr)
        return 3
    try:
        record = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 3
    found = problems_with(record)
    if found:
        for problem in found:
            print(f"ERROR: {problem}", file=sys.stderr)
        return 2
    existing = load(path) or []
    if any(item.get("id") == record["id"] for item in existing):
        print(f"ERROR: {record['id']} already in the store", file=sys.stderr)
        return 2
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, sort_keys=True) + "\n")
    print(f"recorded {record['id']}")
    return 0


def cmd_list(args, path: str, records) -> int:
    if records is None:
        print(f"REVIEW: no findings store at {path}")
        return 1
    selected = records
    if args.file:
        wanted = args.file.rstrip("/")
        selected = [r for r in selected if (r.get("location") or {}).get("file") == wanted]
    if args.status:
        selected = [r for r in selected if r.get("status") in args.status]
    if args.severity:
        selected = [r for r in selected if r.get("severity") in args.severity]
    if args.json:
        for record in selected:
            print(json.dumps(record, sort_keys=True))
        return 0
    if not selected:
        print("no matching findings")
        return 0
    for record in selected:
        location = record.get("location") or {}
        where = location.get("file", "")
        if location.get("line"):
            where += f":{location['line']}"
        print(f"{record['id']}  {record['severity']:<13} {record['status']:<14} {where}")
    return 0


def last_commit_for(repo: str, file: str) -> str:
    return git(["log", "-1", "--format=%H", "--", file], repo).strip()


def is_stale(repo: str, record: dict) -> bool:
    """A verdict older than the file it describes is not trustworthy."""
    discovered = (record.get("discovered") or "").strip()
    location = record.get("location") or {}
    file = location.get("file")
    if not discovered or not file:
        return False
    current = last_commit_for(repo, file)
    if not current:
        return False
    return not current.startswith(discovered[: len(discovered)]) and not discovered.startswith(
        current[:7]
    )


def cmd_stale(args, path: str, records) -> int:
    if records is None:
        print(f"REVIEW: no findings store at {path}")
        return 1
    repo = repo_root(args.repo or os.getcwd())
    stale = 0
    for record in records:
        if record.get("status") not in OPEN_STATES:
            continue
        if is_stale(repo, record):
            stale += 1
            location = record.get("location") or {}
            print(f"stale  {record['id']}  {location.get('file', '')} (discovered {record['discovered']})")
    if not stale:
        print("no stale findings")
        return 0
    print(f"\n{stale} finding(s) predate their file — re-discover before trusting the verdict")
    return 0


def parse_diff(text: str) -> dict[str, list[tuple[int, int]]]:
    changed: dict[str, list[tuple[int, int]]] = {}
    current = None
    for line in text.splitlines():
        new = NEW_FILE.match(line)
        if new:
            current = new.group(1)
            changed.setdefault(current, [])
            continue
        if line.startswith("+++ /dev/null"):
            current = None
            continue
        hunk = HUNK.match(line)
        if hunk and current:
            start = int(hunk.group(1))
            length = int(hunk.group(2)) if hunk.group(2) is not None else 1
            if length > 0:
                changed[current].append((start, start + length - 1))
    return {file: spans for file, spans in changed.items() if spans}


def calls_symbol(repo: str, file: str, symbol: str) -> bool:
    path = os.path.join(repo, file)
    if not os.path.isfile(path):
        return False
    name = symbol.split("::")[-1]
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return False
    pattern = rf"(?:->|::|\b){re.escape(name)}\s*\("
    return re.search(pattern, text) is not None


def classify(repo: str, record: dict, changed: dict[str, list[tuple[int, int]]]) -> str | None:
    location = record.get("location") or {}
    file = location.get("file")
    line = location.get("line")
    if file and file in changed:
        if line and any(start - LINE_SLACK <= line <= end + LINE_SLACK for start, end in changed[file]):
            return "direct"
        return "unrelated_in_file"
    symbol = location.get("symbol")
    if symbol:
        for path in changed:
            if path != file and calls_symbol(repo, path, symbol):
                return "caller_radius"
    return None


def cmd_gate(args, path: str) -> int:
    repo = repo_root(args.repo or os.getcwd())

    if args.base:
        text = git(["diff", "--unified=0", f"{args.base}...HEAD"], repo)
    else:
        text = sys.stdin.read()

    changed = parse_diff(text)
    if not changed:
        print("REVIEW: empty change set — nothing was checked")
        return 1

    try:
        records = load(path)
    except StoreError as exc:
        print(f"REVIEW: store cannot be read — {exc}")
        return 1
    if records is None:
        print(f"REVIEW: no findings store at {path} — nothing to gate against")
        return 1

    matched = []
    for record in records:
        if record.get("status") not in OPEN_STATES:
            continue
        relationship = classify(repo, record, changed)
        if not relationship:
            continue
        stale = is_stale(repo, record)
        matched.append((record, relationship, stale))

    blocking = [
        item for item in matched
        if item[1] == "direct"
        and item[0].get("severity") in BLOCKING_SEVERITIES
        and not item[2]
    ]

    if matched:
        print("findings touching this change:")
        for record, relationship, stale in matched:
            flag = " (stale)" if stale else ""
            print(f"  {record['id']}  {record['severity']:<13} {relationship}{flag}  {record['title']}")

    if blocking:
        print("\nBLOCK: an open High/Critical finding sits on the changed lines")
        return 2
    if matched:
        stale_high = [i for i in matched if i[2] and i[0].get("severity") in BLOCKING_SEVERITIES]
        if stale_high:
            print("\nREVIEW: a High/Critical finding is stale — re-discover it before trusting the verdict")
        else:
            print("\nREVIEW: known findings touch this change, in a changed file or a calling file")
        return 1

    print(f"PASS: {len(records)} record(s) checked against {len(changed)} changed file(s)")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="findings", description=__doc__.splitlines()[0])
    parser.add_argument("--store", help="path to findings.jsonl (default: the project vault)")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("check", help="validate the store and summarise it")
    sub.add_parser("add", help="append one record read as JSON on stdin")
    stale = sub.add_parser("stale", help="list findings that predate the file they describe")
    stale.add_argument("--repo", help="repository root (default: cwd)")

    listing = sub.add_parser("list", help="query the store")
    listing.add_argument("--file")
    listing.add_argument("--status", nargs="+", choices=STATUSES)
    listing.add_argument("--severity", nargs="+", choices=SEVERITIES)
    listing.add_argument("--json", action="store_true")

    gate = sub.add_parser("gate", help="PASS/REVIEW/BLOCK a diff against the store")
    gate.add_argument("--base", help="compare <base>...HEAD instead of reading stdin")
    gate.add_argument("--repo", help="repository root (default: cwd)")

    args = parser.parse_args(argv)
    path = store_path(args)

    if args.command == "check":
        return cmd_check(args, path, load_wrapped(path))
    if args.command == "add":
        return cmd_add(args, path)
    if args.command == "stale":
        return cmd_stale(args, path, load_wrapped(path))
    if args.command == "list":
        return cmd_list(args, path, load_wrapped(path))
    if args.command == "gate":
        return cmd_gate(args, path)
    return 3


def load_wrapped(path: str):
    try:
        return load(path)
    except StoreError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return None


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
