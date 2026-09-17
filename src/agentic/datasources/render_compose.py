#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/render_compose.py
# Render the datasource gateway's docker-compose.yml from the catalogue.
#
# Internal helper — never a primary entry point. datasources/render.sh runs it.
#
# The compose file is rendered rather than shipped because the gateway must
# receive every env var the declared datasources reference, and those names are
# dynamic: they come from .devbot.global.jsonc, and compose has no "pass the
# whole environment" form. Only NAMES are written into the file — the values
# are interpolated by compose from the environment `devbot up` builds, so no
# credential is ever written to disk.
#
# Usage:
#     render_compose.py <template-path> < catalogue.json > docker-compose.yml
# =============================================================================

import json
import sys
from typing import NoReturn

from render_tools_yaml import effective_env_names, load_catalogue

# Replaced by the env var name list. Kept on a single line so the substitution
# is a plain string replace and survives any formatter re-indenting the rest.
MARKER = "__DATASOURCE_ENV__"


def fail(message: str) -> NoReturn:
    sys.stderr.write(f"ERROR: {message}\n")
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        fail("usage: render_compose.py <template-path>")

    template_path = sys.argv[1]
    catalogue = load_catalogue(sys.stdin.read())

    try:
        with open(template_path, encoding="utf-8") as handle:
            template = handle.read()
    except OSError as exc:
        fail(f"cannot read template {template_path}: {exc}")

    if MARKER not in template:
        fail(f"template {template_path} does not contain {MARKER}")

    names = effective_env_names(catalogue)
    sys.stdout.write(template.replace(MARKER, json.dumps(names)))


if __name__ == "__main__":
    main()
