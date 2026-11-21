#!/usr/bin/env python3
"""docker-exec — run a command in the project's container without naming it.

The corpus showed `docker exec transfers-app-1 <command>` chains: the container
name is discovered once, then retyped for every follow-up command. This resolves
it from the compose project instead — by service name, or the only running
container — and execs there.

Exit codes: 0 the command ran and succeeded, its own exit code otherwise,
2 usage, 3 no or ambiguous target.

Usage:
    docker-exec.py php artisan migrate
    docker-exec.py --service app composer install
    docker-exec.py --path /srv/project --list
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

EXIT_USAGE = 2
EXIT_NO_TARGET = 3


def docker(args: list[str], cwd: str | None = None) -> tuple[str, int, str]:
    try:
        result = subprocess.run(
            ["docker", *args], capture_output=True, text=True, timeout=120, cwd=cwd
        )
        return result.stdout.strip(), result.returncode, result.stderr.strip()
    except FileNotFoundError:
        return "", 1, "docker not found"
    except subprocess.TimeoutExpired:
        return "", 1, "docker timed out"


def running_containers(cwd: str | None) -> list[dict]:
    """Compose containers for the project, running ones first."""
    out, rc, err = docker(
        ["compose", "ps", "--format", "json", "--all"], cwd=cwd
    )
    if rc != 0:
        raise SystemExit(f"FATAL: cannot list compose containers: {err or out}")
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        rows.append(
            {
                "name": entry.get("Name") or entry.get("Names") or "",
                "service": entry.get("Service") or "",
                "state": (entry.get("State") or "").lower(),
            }
        )
    return rows


def pick(rows: list[dict], service: str | None) -> dict:
    candidates = [row for row in rows if row["name"]]
    if service:
        matched = [row for row in candidates if row["service"] == service]
        if not matched:
            available = ", ".join(sorted({row["service"] for row in candidates})) or "none"
            raise SystemExit(
                f"ERROR: no container for service {service!r} (services: {available})"
            )
        candidates = matched
    # Only a running container can be exec'd into; falling back to a stopped one
    # reports a docker failure instead of the documented no-target condition.
    pool = [row for row in candidates if "running" in row["state"]]
    if not pool:
        raise SystemExit("ERROR: no running container for this project")
    if len(pool) > 1:
        names = ", ".join(f"{row['name']} ({row['service']})" for row in pool)
        raise SystemExit(
            f"ERROR: several containers match — pass --service. Candidates: {names}"
        )
    return pool[0]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Run a command in the project container")
    # REMAINDER, not "*": the command's own flags (-v, -e, --force) are not this
    # tool's options, and argparse would reject them as unknown.
    parser.add_argument(
        "command", nargs=argparse.REMAINDER, help="command and arguments to run"
    )
    parser.add_argument("--service", default=None, help="compose service name")
    parser.add_argument("--path", default=None, help="project directory (default: cwd)")
    parser.add_argument("--list", action="store_true", help="list containers and exit")
    parser.add_argument(
        "--no-tty", action="store_true", help="never allocate a TTY (default: only when attached)"
    )
    args = parser.parse_args(argv)

    rows = running_containers(args.path)

    if args.list:
        if not rows:
            print("_(no compose containers)_")
            return 0
        for row in rows:
            print(f"{row['name']}\t{row['service'] or '-'}\t{row['state'] or '-'}")
        return 0

    if not args.command:
        print("ERROR: no command given", file=sys.stderr)
        return EXIT_USAGE

    try:
        target = pick(rows, args.service)
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_NO_TARGET

    flags = [] if args.no_tty else ["-i"] if not sys.stdin.isatty() else ["-i", "-t"]
    try:
        result = subprocess.run(["docker", "exec", *flags, target["name"], *args.command])
    except FileNotFoundError:
        print("FATAL: docker not found", file=sys.stderr)
        return 1
    return result.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
