#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/demand.py
# Which sidecars a set of project opt-in lists actually wants.
#
# A sidecar datasource (opensearch, s3) is a heavyweight container served by its
# own MCP server, so it is rendered and started only when some project opts into
# it. Two callers need the same answer from different universes — render.sh from
# the machine's configured projects, datasources/up.sh from the live sessions —
# so the rule lives here once and the two cannot drift.
#
# `demanded_sidecars` / `filter_demanded_sidecars` are the pure rule. The static
# gatherer below is the I/O edge that reads which projects exist and what they
# opt into; it is what makes the render-side universe session-independent.
#
# Internal helper — never a primary entry point.
#
# Usage:
#     demand.py --names  [name...]        < catalogue.json  # wanted sidecars
#     demand.py --filter [name...]        < catalogue.json  # catalogue, minus
#                                                           # the unwanted sidecars
#     demand.py --static-filter <global-config> [project-dir] < catalogue.json
#     demand.py --projects-names <project-dir>... < catalogue.json
# =============================================================================

import json
import os
import sys
from typing import NoReturn

_SHARED = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "_shared",
)
if _SHARED not in sys.path:
    sys.path.insert(0, _SHARED)

from read_jsonc import load_jsonc  # noqa: E402

from render_tools_yaml import is_sidecar, load_catalogue  # noqa: E402


def _fail(message: str) -> NoReturn:
    sys.stderr.write(f"ERROR: {message}\n")
    sys.exit(1)


def demanded_sidecars(catalogue: dict, optin_lists) -> set:
    """The catalogue's sidecar names that any opt-in list references.

    Only a sidecar can be demanded: a name that matches a toolbox engine is not
    a sidecar, so it is never returned.
    """
    wanted = set()
    for names in optin_lists:
        wanted.update(names)
    return {
        name
        for name, spec in catalogue.items()
        if isinstance(spec, dict) and is_sidecar(spec) and name in wanted
    }


def filter_demanded_sidecars(catalogue: dict, optin_lists) -> dict:
    """The catalogue with every undemanded sidecar removed.

    Non-sidecar entries pass through untouched — the toolbox path has its own,
    separate availability filter.
    """
    demanded = demanded_sidecars(catalogue, optin_lists)
    return {
        name: spec
        for name, spec in catalogue.items()
        if not (isinstance(spec, dict) and is_sidecar(spec)) or name in demanded
    }


def project_optins(project_dir) -> list:
    """The datasource names one project opts into.

    An absent directory, a missing config, an unreadable one, or a non-list
    `datasources` value all mean the same thing: this project wants nothing.
    """
    if not project_dir:
        return []
    path = os.path.join(project_dir, ".devbot.project.jsonc")
    if not os.path.isfile(path):
        return []
    try:
        data = load_jsonc(path)
    except Exception:
        return []
    names = data.get("datasources") if isinstance(data, dict) else None
    if not isinstance(names, list):
        return []
    return [name for name in names if isinstance(name, str)]


def static_optin_names(global_config: str, project_dir=None) -> list:
    """Every datasource a KNOWN project opts into.

    The known projects are the entries of the global config's `projects` list
    that exist on this machine, plus `project_dir` (which may have been added
    since the list was last written).
    """
    try:
        data = load_jsonc(global_config)
    except Exception:
        data = {}
    projects = data.get("projects") if isinstance(data, dict) else None
    if not isinstance(projects, list):
        projects = []

    names = []
    for path in projects:
        if isinstance(path, str) and os.path.isdir(path):
            names.extend(project_optins(path))
    names.extend(project_optins(project_dir))
    return names


def _emit(mode: str, catalogue: dict, names: list) -> None:
    # Space-joined, one line: the bash callers membership-test a name with
    # `grep -F " ${name} "`, so a per-line list would never match more than the
    # first name.
    if mode.endswith("names"):
        print(" ".join(sorted(demanded_sidecars(catalogue, [names]))))
    else:
        print(json.dumps(filter_demanded_sidecars(catalogue, [names])))


def main():
    args = sys.argv[1:]
    if not args:
        _fail("usage: demand.py --names|--filter|--static-names|--static-filter ...")

    mode = args[0]

    if mode in ("--names", "--filter"):
        _emit(mode, load_catalogue(sys.stdin.read()), args[1:])
        return

    if mode == "--static-filter":
        if len(args) < 2:
            _fail("--static-filter needs the global config path")
        catalogue = load_catalogue(sys.stdin.read())
        names = static_optin_names(args[1], args[2] if len(args) > 2 else None)
        print(json.dumps(filter_demanded_sidecars(catalogue, [names])))
        return

    if mode == "--projects-names":
        catalogue = load_catalogue(sys.stdin.read())
        names = []
        for project_dir in args[1:]:
            names.extend(project_optins(project_dir))
        _emit(mode, catalogue, names)
        return

    _fail(f"unknown mode '{mode}'")


if __name__ == "__main__":
    main()
