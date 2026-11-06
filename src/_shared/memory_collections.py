#!/usr/bin/env python3
"""Resolve the memory collections searched by `search-memories`.

Reads `memory_collections` from the project config
(`<project>/.devbot.project.jsonc`) and the global config
(`<DEV_BOT_ROOT>/.devbot.global.jsonc`), validates it, merges the two maps
(global first, project last — a shared key is replaced wholesale), expands
placeholders, and prints the resolved set as JSON.

Shape:

  "memory_collections": {
    "<key>": { "path": "<path>", "semantic": false }
  }

Reserved keys: `project` only in the project config, `global` only in the
global config. Custom keys may appear in either file.

Placeholders: `{project}`, `{devbot_dir}`, `${DEV_BOT_ROOT}`, `~`.

Usage:
  memory_collections.py [--project-root DIR]

Output (stdout, JSON):

  {"collections": [
    {"key": "project", "path": "/abs/memory", "semantic": false,
     "physical": "my-project", "kind": "project", "source": "default",
     "exists": true, "index": "/abs/.mdctx/context-index.json"},
    ...
  ]}

A project-scoped custom key is namespaced by the project name in its physical
qmd collection name and mdctx index file, so the same key in two projects does
not collide. A global custom key is shared as-is.

Errors are written to stderr as `ERROR: ...` with exit code 2.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from read_jsonc import load_jsonc  # noqa: E402

PROJECT_KEY = "project"
GLOBAL_KEY = "global"
GLOBAL_COLLECTION = "dev-bot-global"
CUSTOM_PREFIX = "dev-bot-custom-"


class CollectionConfigError(Exception):
    """A collection config is malformed or a reserved key is misplaced."""


def devbot_root() -> Path:
    """The dev-bot install root (DEV_BOT_ROOT override wins)."""
    override = os.environ.get("DEV_BOT_ROOT")
    if override:
        return Path(override).resolve()
    return Path(__file__).resolve().parents[2]


def _load_config(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        data = load_jsonc(str(path))
    except Exception as exc:  # noqa: BLE001 — surface the parser message
        raise CollectionConfigError(f"cannot parse {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise CollectionConfigError(f"{path}: top-level config must be an object")
    return data


def _section(path: Path) -> dict:
    section = _load_config(path).get("memory_collections", {})
    if section is None:
        return {}
    if not isinstance(section, dict):
        raise CollectionConfigError(f"{path}: memory_collections must be an object")
    return section


def _global_config(root: Path) -> Path:
    """The effective global config: DEV_BOT_GLOBAL_CONFIG wins over the root."""
    override = os.environ.get("DEV_BOT_GLOBAL_CONFIG")
    if override:
        return Path(override).expanduser().resolve()
    return root / ".devbot.global.jsonc"


def _resolve_devbot_dir(project_root: Path, root: Path) -> str:
    for cfg in (project_root / ".devbot.project.jsonc", _global_config(root)):
        value = _load_config(cfg).get("devbot_dir")
        if isinstance(value, str) and value:
            return value
    return ".agents"


def _project_name(project_root: Path) -> str:
    value = _load_config(project_root / ".devbot.project.jsonc").get("project_name")
    if isinstance(value, str) and value:
        return value
    return project_root.name


def _validate_entry(key: str, value: object, path: Path) -> tuple[str, bool]:
    if not re.fullmatch(r"[A-Za-z0-9._-]+", key) or ".." in key:
        raise CollectionConfigError(
            f"{path}: collection name '{key}' may only contain letters, digits, "
            "'.', '_' and '-'"
        )
    if not isinstance(value, dict):
        raise CollectionConfigError(f"{path}: collection '{key}' must be an object")
    unknown = set(value) - {"path", "semantic"}
    if unknown:
        raise CollectionConfigError(
            f"{path}: collection '{key}' has unknown key(s): {', '.join(sorted(unknown))}"
        )
    location = value.get("path")
    if not isinstance(location, str) or not location.strip():
        raise CollectionConfigError(f"{path}: collection '{key}' needs a non-empty path")
    if key == GLOBAL_KEY and (
        "{project}" in location
        or not (
            os.path.isabs(location)
            or location.startswith("${DEV_BOT_ROOT}")
            or location.startswith("~")
        )
    ):
        raise CollectionConfigError(
            f"{path}: collection '{key}' must be machine-wide "
            "(absolute, ${DEV_BOT_ROOT}/…, or ~/…), not project-dependent"
        )
    semantic = value.get("semantic", False)
    if not isinstance(semantic, bool):
        raise CollectionConfigError(
            f"{path}: collection '{key}' semantic must be true or false"
        )
    return location, semantic


def _project_collection_path(project_root: Path, root: Path) -> str:
    """A project's configured collection root, honoring a `project` override."""
    devbot_dir = _resolve_devbot_dir(project_root, root)
    section = _section(project_root / ".devbot.project.jsonc")
    location = "{project}/{devbot_dir}/memory/latent"
    entry = section.get(PROJECT_KEY)
    if isinstance(entry, dict):
        candidate = entry.get("path")
        if isinstance(candidate, str) and candidate.strip():
            location = candidate
    return _expand(location, project_root, devbot_dir, root)


def _expand(location: str, project_root: Path, devbot_dir: str, root: Path) -> str:
    if os.path.isabs(devbot_dir):
        expanded = location.replace("{project}/{devbot_dir}", devbot_dir)
    else:
        expanded = location
    expanded = expanded.replace("{project}", str(project_root))
    expanded = expanded.replace("{devbot_dir}", devbot_dir)
    expanded = expanded.replace("${DEV_BOT_ROOT}", str(root))
    expanded = os.path.expanduser(expanded)
    if not os.path.isabs(expanded):
        expanded = str(project_root / expanded)
    # Resolve symlinks so an alias and its target share one identity and the
    # foreign-vault check cannot be bypassed by a symlinked path.
    return os.path.realpath(expanded)


def _corpus_digest(resolved: str) -> str:
    """One identity per canonical corpus path.

    The digest covers only the resolved root: two keys (or two projects) that
    name the same directory share one qmd registration and one mdctx index
    (qmd rejects duplicate registrations for a path), while different roots
    never collide.
    """
    return hashlib.sha256(resolved.encode()).hexdigest()[:12]


def _physical(
    key: str, project_root: Path, source: str, resolved: str
) -> str:
    if key == GLOBAL_KEY:
        return GLOBAL_COLLECTION
    if key == PROJECT_KEY:
        return _project_name(project_root)
    return f"{CUSTOM_PREFIX}{_corpus_digest(resolved)}"


def _index_for(
    key: str, kind: str, project_root: Path, root: Path, source: str, resolved: str
) -> str:
    if kind == "project":
        return str(project_root / ".mdctx" / "context-index.json")
    if kind == "global":
        # The mdctx gateway serves the shipped store and its index. An
        # overridden global root gets its own index so the gateway can never
        # refresh or overwrite it.
        conventional = root / "storage" / "global-memories"
        if Path(resolved).resolve() == conventional.resolve():
            return str(root / "storage" / ".mdctx" / "context-index.json")
        return str(
            root
            / "storage"
            / ".mdctx"
            / "collections"
            / f"{_corpus_digest(resolved)}.json"
        )
    return str(
        root
        / "storage"
        / ".mdctx"
        / "collections"
        / f"{_corpus_digest(resolved)}.json"
    )


def _kind(key: str) -> str:
    if key in (PROJECT_KEY, GLOBAL_KEY):
        return key
    return "custom"


def load_collections(
    project_root: Path, root: Path | None = None
) -> list[dict]:
    """Resolve the merged collection set for `project_root`.

    Raises CollectionConfigError on a malformed config or a misplaced
    reserved key.
    """
    project_root = Path(project_root).resolve()
    root = Path(root).resolve() if root is not None else devbot_root()
    project_cfg = project_root / ".devbot.project.jsonc"
    global_cfg = _global_config(root)

    global_section = _section(global_cfg)
    project_section = _section(project_cfg)
    if PROJECT_KEY in global_section:
        raise CollectionConfigError(
            f"{global_cfg}: reserved collection '{PROJECT_KEY}' may only be set in the project config"
        )
    if GLOBAL_KEY in project_section:
        raise CollectionConfigError(
            f"{project_cfg}: reserved collection '{GLOBAL_KEY}' may only be set in the global config"
        )

    devbot_dir = _resolve_devbot_dir(project_root, root)

    merged: dict[str, dict] = {
        PROJECT_KEY: {
            "path": "{project}/{devbot_dir}/memory/latent",
            "semantic": False,
            "source": "default",
        },
        GLOBAL_KEY: {
            "path": "${DEV_BOT_ROOT}/storage/global-memories",
            "semantic": False,
            "source": "default",
        },
    }
    for source, section, cfg in (
        ("global", global_section, global_cfg),
        ("project", project_section, project_cfg),
    ):
        for key, value in section.items():
            location, semantic = _validate_entry(key, value, cfg)
            merged[key] = {
                "path": location,
                "semantic": semantic,
                "source": source,
            }

    ordered = [PROJECT_KEY, GLOBAL_KEY]
    ordered += sorted(key for key in merged if key not in ordered)
    resolved_by_key = {
        key: _expand(merged[key]["path"], project_root, devbot_dir, root)
        for key in ordered
    }

    # A custom key that aliases a built-in root reuses the built-in identity:
    # qmd rejects a second registration for the same path, and mdctx must not
    # build a second index for it.
    builtin_identity: dict[str, tuple[str, str]] = {}
    for key in (PROJECT_KEY, GLOBAL_KEY):
        entry = merged[key]
        kind = _kind(key)
        builtin_identity[resolved_by_key[key]] = (
            _physical(key, project_root, entry["source"], resolved_by_key[key]),
            _index_for(
                key, kind, project_root, root, entry["source"], resolved_by_key[key]
            ),
        )

    # A custom alias into another checkout's vault would let this project's
    # reindex repoint that project's collection. Reject it; the owning project's
    # own sessions own its vault.
    current_project = project_root.resolve()
    foreign_project_memories: dict[str, str] = {}
    for project_path in _load_config(global_cfg).get("projects", []) or []:
        try:
            project = Path(project_path).resolve()
            if project == current_project or not project.is_dir():
                continue
            project_memory = _project_collection_path(project, root)
        except Exception:  # noqa: BLE001 — a sibling's config is not ours
            continue
        foreign_project_memories[project_memory] = _project_name(project)

    collections = []
    for key in ordered:
        entry = merged[key]
        resolved = resolved_by_key[key]
        kind = _kind(key)
        if kind == "custom" and resolved in foreign_project_memories:
            raise CollectionConfigError(
                f"collection '{key}' points at project "
                f"'{foreign_project_memories[resolved]}'s vault; a custom "
                "collection cannot alias another checkout's project collection"
            )
        if kind == "custom" and resolved in builtin_identity:
            physical, index = builtin_identity[resolved]
        else:
            physical = _physical(key, project_root, entry["source"], resolved)
            index = _index_for(
                key, kind, project_root, root, entry["source"], resolved
            )
        collections.append(
            {
                "key": key,
                "path": resolved,
                "semantic": entry["semantic"],
                "physical": physical,
                "kind": kind,
                "source": entry["source"],
                "exists": os.path.isdir(resolved),
                "index": index,
            }
        )

    return collections


def main() -> None:
    parser = argparse.ArgumentParser(
        description="resolve the memory_collections config to absolute paths"
    )
    parser.add_argument(
        "--project-root",
        default=os.getcwd(),
        help="project root holding .devbot.project.jsonc (default: cwd)",
    )
    args = parser.parse_args()

    try:
        collections = load_collections(Path(args.project_root))
    except CollectionConfigError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)

    print(json.dumps({"collections": collections}, indent=2))


if __name__ == "__main__":
    main()
