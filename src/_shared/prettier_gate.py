#!/usr/bin/env python3
"""Picks the prettier configuration a format-* run should use.

The format-* tools install into every project dev-bot scaffolds, but not every
project is a prettier project. A project that declares prettier keeps its own
configuration; one that declares none is formatted with the defaults dev-bot
ships in `prettier.default.json`, so formatting works the same everywhere instead
of a `--check` run exiting with "no prettier config".
"""

from __future__ import annotations

import json
import os
import shutil

# dev-bot's own defaults, used when the target project declares no config.
DEFAULT_CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "prettier.default.json"
)

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
    ".prettierrc.mts",
    ".prettierrc.cts",
    "prettier.config.js",
    "prettier.config.cjs",
    "prettier.config.mjs",
    "prettier.config.ts",
    "prettier.config.mts",
    "prettier.config.cts",
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
    configuration.
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


def prettier_config_args(target: str) -> list[str]:
    """The `--config` arguments that pin the configuration for `target`.

    Empty when the project declares prettier — prettier then resolves the
    project's own config — and dev-bot's default config otherwise.
    """
    if has_prettier_config(target):
        return []
    return ["--config", DEFAULT_CONFIG_PATH]


def prettier_batch_config_args(targets: list[str]) -> list[tuple[list[str], list[str]]]:
    """Split a multi-file run into `(targets, config_args)` invocations.

    One `--config` applies to every file in an invocation, so the targets are
    partitioned: files whose project declares prettier are handed to prettier
    without the flag (their own config resolves), and the rest get dev-bot's
    default. One pass for the whole batch would either override a nested
    project's settings or drop the default for the unconfigured files.
    """
    configured: list[str] = []
    unconfigured: list[str] = []
    for target in targets:
        (configured if has_prettier_config(target) else unconfigured).append(target)

    runs: list[tuple[list[str], list[str]]] = []
    if configured:
        runs.append((configured, []))
    if unconfigured:
        runs.append((unconfigured, ["--config", DEFAULT_CONFIG_PATH]))
    return runs
