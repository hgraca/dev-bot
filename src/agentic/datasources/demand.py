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
# Internal helper — never a primary entry point.
#
# Usage:
#     demand.py --names  [name...] < catalogue.json   # demanded sidecar names
#     demand.py --filter [name...] < catalogue.json   # catalogue with the
#                                                      # undemanded sidecars gone
# =============================================================================

import json
import sys
from typing import NoReturn

from render_tools_yaml import is_sidecar, load_catalogue


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


def main():
    args = sys.argv[1:]
    if not args:
        _fail("usage: demand.py --names|--filter [name...]  (catalogue on stdin)")

    mode, names = args[0], args[1:]
    catalogue = load_catalogue(sys.stdin.read())

    if mode == "--names":
        for name in sorted(demanded_sidecars(catalogue, [names])):
            print(name)
    elif mode == "--filter":
        print(json.dumps(filter_demanded_sidecars(catalogue, [names])))
    else:
        _fail(f"unknown mode '{mode}' (expected --names or --filter)")


if __name__ == "__main__":
    main()
