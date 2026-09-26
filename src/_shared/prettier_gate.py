#!/usr/bin/env python3
"""Decides whether a format-* run should proceed.

The format-* tools install into every project dev-bot scaffolds, but prettier is
not every project's formatter. Running it anyway rewrites files to a standard the
project never adopted, and fights the one it did: a Biome project's deliberately
multi-line "files" array was collapsed (breaking its own format check), and its
README gained semicolons in a JS sample that contradict its style.

So a file/directory run proceeds only when prettier is available AND the project
declares it. Pipe mode is an explicit request — there is no project to consult —
and is not gated.
"""

from __future__ import annotations

import json
import os
import shutil

# The names prettier itself resolves, plus a `prettier` key in package.json.
CONFIG_FILENAMES = (
    ".prettierrc",
    ".prettierrc.json",
    ".prettierrc.json5",
    ".prettierrc.yml",
    ".prettierrc.yaml",
    ".prettierrc.toml",
    ".prettierrc.js",
    ".prettierrc.cjs",
    ".prettierrc.mjs",
    ".prettierrc.ts",
    "prettier.config.js",
    "prettier.config.cjs",
    "prettier.config.mjs",
    "prettier.config.ts",
)


def prettier_available() -> bool:
    """Whether a run is possible at all: node and prettier both on PATH."""
    return shutil.which("node") is not None and shutil.which("prettier") is not None


def _directory_declares_prettier(directory: str) -> bool:
    for name in CONFIG_FILENAMES:
        if os.path.isfile(os.path.join(directory, name)):
            return True
    package_json = os.path.join(directory, "package.json")
    if not os.path.isfile(package_json):
        return False
    try:
        with open(package_json, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return False
    return isinstance(data, dict) and "prettier" in data


def has_prettier_config(target: str) -> bool:
    """Whether the project containing `target` declares prettier.

    Walks up from `target`'s directory, mirroring how prettier resolves its own
    configuration, so a path in a project that never declares prettier is left
    alone.
    """
    directory = os.path.abspath(target)
    if not os.path.isdir(directory):
        directory = os.path.dirname(directory)
    while True:
        if _directory_declares_prettier(directory):
            return True
        parent = os.path.dirname(directory)
        if parent == directory:
            return False
        directory = parent
