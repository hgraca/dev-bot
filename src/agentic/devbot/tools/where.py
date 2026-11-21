#!/usr/bin/env python3
"""where — resolve the project context once.

A polyrepo session opens by asking "which project am I in, and what rules apply
here" — `project-for-path`, then `project-memory`, sometimes `project-for-path`
again for a second key. This answers all of it in one call: the owning project,
its type and registration, the workflow in force, commit_memory, devbot_dir,
datasources, where the memory lives, and which memory files are active.

Exit codes: 0 resolved, 1 the resolver failed, 2 usage.

Usage:
    where.py                 # the current directory
    where.py /path/to/child  # resolve another path
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_USAGE = 2


def resolver_path() -> str:
    """Locate the project-for-path tool next to this script's tree."""
    override = os.environ.get("PROJECT_FOR_PATH")
    if override:
        return override
    here = pathlib.Path(__file__).resolve()
    # src/agentic/devbot/tools/where.py -> src/tools/devbot-cli/tools/...
    candidate = here.parents[3] / "tools" / "devbot-cli" / "tools" / "project-for-path.mcp.sh"
    return str(candidate)


def resolve(path: str) -> dict:
    resolver = resolver_path()
    if not os.path.exists(resolver):
        raise SystemExit(f"FATAL: project-for-path tool not found at {resolver}")
    try:
        result = subprocess.run(
            ["bash", resolver, path, "--json"],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        raise SystemExit("FATAL: project-for-path timed out")
    if result.returncode != 0:
        raise SystemExit(
            f"FATAL: project-for-path failed ({result.returncode}): "
            f"{result.stderr.strip() or result.stdout.strip()}"
        )
    try:
        return json.loads(result.stdout)
    except ValueError:
        raise SystemExit("FATAL: project-for-path did not return JSON")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Resolve the project context in one call")
    parser.add_argument("path", nargs="?", default=".", help="path to resolve (default: .)")
    args = parser.parse_args(argv)

    if not os.path.exists(args.path):
        print(f"ERROR: path does not exist: {args.path}", file=sys.stderr)
        return EXIT_USAGE

    project = resolve(args.path)
    config = project.get("config") or {}
    devbot_dir = config.get("devbot_dir") or ".agents"
    root = pathlib.Path(project["path"])
    memory_dir = root / devbot_dir / "memory" / "active"
    active = (
        sorted(str(p.relative_to(memory_dir)) for p in memory_dir.glob("**/*.md"))
        if memory_dir.is_dir()
        else []
    )

    print(
        json.dumps(
            {
                "project": project.get("name"),
                "path": str(root),
                "type": project.get("type"),
                "registered": project.get("registered"),
                "workflow": config.get("workflow") or "(default)",
                "commit_memory": config.get("commit_memory"),
                "devbot_dir": devbot_dir,
                "datasources": config.get("datasources") or [],
                "memory_dir": str(memory_dir),
                "memory_files": active,
            },
            indent=2,
        )
    )
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
