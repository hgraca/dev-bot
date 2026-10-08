#!/usr/bin/env python3
"""Resolve a path to the registered devbot project that contains it.

Reads the `projects` array from a global config (default
<DEV_BOT_ROOT>/.devbot.global.jsonc) and prints the longest registered project
path that contains the given path. When no registered project contains it, the
script prints the --default directory (resolved) when one is given, else
nothing.

Because registered project paths can be prefixes of one another (/a/b and
/a/b/c), the longest match wins; and a match requires a path-component
boundary, so /a/b never matches /a/bc.

Usage:
  resolve_project.py <path> [--config <global.jsonc>] [--default <dir>]

Exit codes: 0 always (a missing/unreadable config fails open to --default).
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from read_jsonc import load_jsonc  # noqa: E402


def _default_config() -> str:
    root = os.environ.get("DEV_BOT_ROOT") or os.path.abspath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    )
    return os.path.join(root, ".devbot.global.jsonc")


def resolve_project(target: str, projects: list) -> str:
    """Return the longest registered project path containing `target`, else ""."""
    t = os.path.realpath(target)
    best = ""
    best_len = -1
    for project in projects:
        if not isinstance(project, str) or not project:
            continue
        p = os.path.realpath(project)
        if (t == p or t.startswith(p + os.sep)) and len(p) > best_len:
            best = project
            best_len = len(p)
    return best


def load_projects(config_path: str) -> list[str]:
    """Load the `projects` array; a missing/unreadable config yields []."""
    try:
        data = load_jsonc(config_path)
    except Exception:
        return []
    if not isinstance(data, dict):
        return []
    projects = data.get("projects", [])
    return projects if isinstance(projects, list) else []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="Path to resolve to a registered project")
    parser.add_argument(
        "--config",
        default="",
        help="Global config holding the projects array (default: <DEV_BOT_ROOT>/.devbot.global.jsonc)",
    )
    parser.add_argument(
        "--default",
        default="",
        help="Printed (resolved) when no registered project contains the path",
    )
    args = parser.parse_args(argv)

    projects = load_projects(args.config or _default_config())
    match = resolve_project(args.path, projects)
    if match:
        print(match)
    elif args.default:
        print(os.path.realpath(args.default))
    else:
        print("")
    return 0


if __name__ == "__main__":
    sys.exit(main())
