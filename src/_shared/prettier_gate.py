#!/usr/bin/env python3
"""Picks the prettier configuration and ignore file a format-* run should use.

The format-* tools install into every project dev-bot scaffolds, but not every
project is a prettier project. A project that declares prettier keeps its own
configuration; one that declares none is formatted with the defaults dev-bot
ships in `prettier.default.json`, so formatting works the same everywhere instead
of a `--check` run exiting with "no prettier config".

Ignore rules follow the project too: a `.prettierignore` governs the files under
it, so a project that scopes prettier narrowly is not reformatted behind its
back. The agent workspace (`.agents/` by default) is exempt — it is dev-bot's own
artifact and the project's rules were never written about it.
"""

from __future__ import annotations

import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read_jsonc import load_jsonc  # noqa: E402  # type: ignore[import-not-found]

# dev-bot's own defaults, used when the target project declares no config.
DEFAULT_CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "prettier.default.json"
)

IGNORE_FILENAME = ".prettierignore"
PROJECT_CONFIG_FILENAME = ".devbot.project.jsonc"
DEFAULT_DEVBOT_DIR = ".agents"

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


def _walk_up(target: str):
    """Yield every ancestor directory of `target`, nearest first."""
    directory = os.path.abspath(target)
    if not os.path.isdir(directory):
        directory = os.path.dirname(directory)
    while True:
        yield directory
        parent = os.path.dirname(directory)
        if parent == directory:
            return
        directory = parent


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


def find_prettier_ignore(target: str) -> str | None:
    """The `.prettierignore` governing `target`, or None when there is none.

    Walks up from `target` the way prettier resolves its own ignore files, so a
    repository-level ignore governs a file in a nested package.
    """
    for directory in _walk_up(target):
        candidate = os.path.join(directory, IGNORE_FILENAME)
        if os.path.isfile(candidate):
            return candidate
    return None


def _global_config_path() -> str:
    """The effective global config path.

    Mirrors `_devbot_global_config` in functions.sh: DEV_BOT_GLOBAL_CONFIG
    redirects the path, so tests and callers can point at an isolated config.
    Ignoring it would read the developer's real one.
    """
    override = os.environ.get("DEV_BOT_GLOBAL_CONFIG")
    if override:
        return override
    root = os.environ.get("DEV_BOT_ROOT") or os.path.abspath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    )
    return os.path.join(root, ".devbot.global.jsonc")


def _configured_devbot_dir(config_path: str) -> str | None:
    """The `devbot_dir` a config file declares, or None."""
    try:
        data = load_jsonc(config_path)
    except (OSError, ValueError):
        return None
    value = data.get("devbot_dir") if isinstance(data, dict) else None
    return value if isinstance(value, str) and value else None


def _devbot_dir(project_root: str | None) -> str:
    """`devbot_dir` with project-first, global-fallback precedence.

    Mirrors `_devbot_get_project_dir`: the project's own value wins, then the
    install-wide one, then `.agents`. Without the global step a project that sets
    `devbot_dir` only globally would not be recognised as its own workspace, and
    its `.prettierignore` would suppress formatting of dev-bot's files.
    """
    if project_root:
        value = _configured_devbot_dir(os.path.join(project_root, PROJECT_CONFIG_FILENAME))
        if value:
            return value
    return _configured_devbot_dir(_global_config_path()) or DEFAULT_DEVBOT_DIR


def in_agent_workspace(target: str) -> bool:
    """Whether `target` lives inside its project's agent workspace.

    The vault is dev-bot's own artifact: a project's `.prettierignore` was
    written about the project's files, not about it, so the ignore file is not
    applied there.
    """
    target = os.path.abspath(target)
    for directory in _walk_up(target):
        if os.path.isfile(os.path.join(directory, PROJECT_CONFIG_FILENAME)):
            devbot_dir = _devbot_dir(directory)
            relative = os.path.relpath(target, directory)
            return relative == devbot_dir or relative.startswith(devbot_dir + os.sep)
    # No project config anywhere: the effective devbot_dir still decides. It is
    # a relative path, not a single segment (".config/devbot" is legal), so
    # compare against each ancestor rather than one path component.
    devbot_dir = _devbot_dir(None)
    for directory in _walk_up(target):
        relative = os.path.relpath(target, directory)
        if relative == devbot_dir or relative.startswith(devbot_dir + os.sep):
            return True
    return False


def prettier_ignore_args(target: str) -> list[str]:
    """The `--ignore-path` arguments that apply `target`'s project rules.

    Passing any `--ignore-path` replaces prettier 3's default list
    (`[.gitignore, .prettierignore]`), which keeps the deliberate behaviour that
    a gitignored path — the `.agents/` vault — is still formatted. The project's
    `.prettierignore` is honoured where it exists, `/dev/null` otherwise, and the
    agent workspace always formats.

    Prettier applies these rules to `--stdin-filepath` input too (verified on
    3.x: an ignored path comes back unchanged), so stdin mode needs no separate
    ignore check of its own.
    """
    if in_agent_workspace(target):
        return ["--ignore-path", os.devnull]
    ignore = find_prettier_ignore(target)
    return ["--ignore-path", ignore or os.devnull]


def prettier_batch_config_args(targets: list[str]) -> list[tuple[list[str], list[str]]]:
    """Split a multi-file run into `(targets, args)` invocations.

    One `--config` and one `--ignore-path` apply to everything in an invocation,
    so the targets are partitioned by both: files whose project declares
    prettier are handed to prettier without a `--config` (their own resolves) and
    the rest get dev-bot's default, while each project's `.prettierignore` only
    ever applies to its own files. One pass for the whole batch would either
    override a nested project's settings or drop the default for the others.
    """
    groups: dict[tuple[str, ...], list[str]] = {}
    order: list[tuple[str, ...]] = []
    for target in targets:
        args = tuple(prettier_config_args(target) + prettier_ignore_args(target))
        if args not in groups:
            groups[args] = []
            order.append(args)
        groups[args].append(target)
    return [(groups[args], list(args)) for args in order]
