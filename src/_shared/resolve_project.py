#!/usr/bin/env python3
"""Resolve a path to the registered devbot project that contains it, and read a
project-first config setting.

Reads the `projects` array from a global config (default
<DEV_BOT_ROOT>/.devbot.global.jsonc) and prints the longest registered project
path that contains the given path. When no registered project contains it, the
script prints the --default directory (resolved) when one is given, else
nothing.

Because registered project paths can be prefixes of one another (/a/b and
/a/b/c), the longest match wins; and a match requires a path-component
boundary, so /a/b never matches /a/bc.

With --setting it instead prints one effective config value: the project's
.devbot.project.jsonc first, then the global config, then --default. This is
the single implementation of that precedence — `_devbot_get_config` in
functions.sh calls this script, and the Python readers (project-for-path,
project-memory, search-memories) import `resolve_setting` directly.

Usage:
  resolve_project.py <path> [--config <global.jsonc>] [--default <dir>]
  resolve_project.py --setting <name> [--section <block>]
                     [--project-root <dir>] [--config <global.jsonc>]
                     [--default <value>]

Exit codes: 0 always (a missing/unreadable config fails open to --default);
2 on a usage error.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from read_jsonc import load_jsonc  # noqa: E402

# The devbot state directory a project gets when it states none. One constant
# for every reader that needs the fallback; functions.sh carries the same
# literal because bash cannot import it.
DEFAULT_DEVBOT_DIR = ".agents"


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


def _read_key(config_path: str, name: str, section: str = ""):
    """One raw value from a config, or None when absent/unreadable.

    A malformed config is reported on stderr and treated as absent: the two
    callers (an MCP tool and a shell function) both log stderr, and a parse
    error must not read as "key missing" without a trace.
    """
    try:
        data = load_jsonc(config_path)
    except FileNotFoundError:
        return None
    except Exception as exc:  # noqa: BLE001 — a bad config must not abort a read
        print(f"WARNING: {config_path}: {exc}", file=sys.stderr)
        return None
    if section:
        data = data.get(section) if isinstance(data, dict) else None
    if not isinstance(data, dict) or name not in data:
        return None
    return data[name]


def resolve_setting(
    config_path: str,
    project_root: str,
    name: str,
    default=None,
    section: str = "",
):
    """Effective value of a config key: project first, then global, then `default`.

    The RAW value comes back — a bool stays a bool, a list a list — because
    callers disagree about what they need: `commit_memory` and `devbot_dir` are
    read as text by some and as booleans by others, and a string-only helper
    would turn `false` into `"False"` or drop it entirely.

    A project value that is an empty string falls through to the global one,
    matching the `-z` test the bash getter always used. `false` and `0` do NOT
    fall through: an explicit project `false` beating a global `true` is the
    commit_memory bug this precedence exists for.
    """
    candidates = []
    if project_root:
        candidates.append(os.path.join(project_root, ".devbot.project.jsonc"))
    if config_path:
        candidates.append(config_path)
    for candidate in candidates:
        value = _read_key(candidate, name, section)
        if value is not None and value != "":
            return value
    return default


def as_text(value) -> str:
    """Render a config value the way read_jsonc.py prints one.

    Strings print bare, everything else as JSON — so `false` stays `false` and
    a list keeps its brackets. Shell callers compare this text (`== "false"`),
    so the two readers must not disagree about the encoding.
    """
    if isinstance(value, str):
        return value
    if value is None:
        return ""
    return json.dumps(value)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "path", nargs="?", help="Path to resolve to a registered project"
    )
    parser.add_argument(
        "--config",
        default="",
        help="Global config (default: <DEV_BOT_ROOT>/.devbot.global.jsonc)",
    )
    parser.add_argument(
        "--default",
        default="",
        help="Printed when no project matches (path mode) or nothing is set (setting mode)",
    )
    parser.add_argument(
        "--setting",
        default="",
        metavar="NAME",
        help="Print this config setting instead of resolving a project",
    )
    parser.add_argument(
        "--section",
        default="",
        help="With --setting: the top-level block the key lives in (e.g. workspace)",
    )
    parser.add_argument(
        "--project-root",
        default="",
        help="With --setting: the project whose .devbot.project.jsonc wins",
    )
    args = parser.parse_args(argv)

    config_path = args.config or _default_config()

    if args.setting:
        if args.path:
            parser.error("--setting takes no path argument")
        value = resolve_setting(
            config_path,
            args.project_root,
            args.setting,
            args.default,
            args.section,
        )
        print(as_text(value))
        return 0

    if not args.path:
        parser.error("a path is required (or use --setting NAME)")

    projects = load_projects(config_path)
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
