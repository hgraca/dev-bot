"""Parse .editorconfig files and derive prettier CLI args for pipe mode.

Prettier natively reads .editorconfig for file-based formatting (since v2).
This module fills the gap for stdin/pipe mode where prettier can't find
.editorconfig because there's no file path to walk up from.
"""

from __future__ import annotations

import os
import fnmatch
import re
from pathlib import Path


def find_editorconfig(start_dir: str | None = None) -> str | None:
    """Walk up from start_dir to find .editorconfig. Returns path or None."""
    if start_dir is None:
        start_dir = os.getcwd()
    current = Path(start_dir).resolve()
    while True:
        candidate = current / ".editorconfig"
        if candidate.is_file():
            return str(candidate)
        parent = current.parent
        if parent == current:
            return None
        current = parent


def _expand_braces(pattern: str) -> list[str]:
    """Expand {a,b,c} brace patterns into multiple patterns."""
    match = re.search(r"\{([^}]+)\}", pattern)
    if not match:
        return [pattern]
    options = [o.strip() for o in match.group(1).split(",")]
    prefix = pattern[: match.start()]
    suffix = pattern[match.end() :]
    results: list[str] = []
    for opt in options:
        results.extend(_expand_braces(prefix + opt + suffix))
    return results


def _glob_match(pattern: str, filename: str) -> bool:
    """Match a filename against an editorconfig glob pattern (e.g. '*.{json,jsonc}')."""
    expanded = _expand_braces(pattern)
    return any(fnmatch.fnmatch(filename, p) for p in expanded)


def get_settings(
    filepath_or_ext: str, start_dir: str | None = None
) -> dict[str, str]:
    """Get editorconfig settings for a given file extension.

    Args:
        filepath_or_ext: An extension like '.md', '.jsonc', '.yml'.
        start_dir: Directory to start searching. Defaults to CWD.

    Returns:
        Dict of settings (indent_size, indent_style, end_of_line, etc.)
    """
    ec_path = find_editorconfig(start_dir)
    if not ec_path:
        return {}

    # Build a fake filename to match against globs
    filename = f"file{filepath_or_ext}" if filepath_or_ext.startswith(".") else os.path.basename(filepath_or_ext)

    settings: dict[str, str] = {}
    current_section: str | None = None

    with open(ec_path, encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith(";") or stripped.startswith("#"):
                continue
            if stripped.startswith("[") and stripped.endswith("]"):
                current_section = stripped.strip("[]").strip()
                continue
            if "=" in stripped:
                key, _, value = stripped.partition("=")
                key = key.strip().lower()
                value = value.strip()
                if key == "root":
                    continue
                if current_section and _glob_match(current_section, filename):
                    settings[key] = value

    return settings


def get_prettier_args(
    filepath_or_ext: str, start_dir: str | None = None
) -> list[str]:
    """Get prettier CLI args derived from .editorconfig settings.

    Only returns args for pipe mode. File mode relies on prettier's
    native .editorconfig support.

    Args:
        filepath_or_ext: Extension like '.md', '.jsonc', '.yml'.
        start_dir: Directory to start .editorconfig search.

    Returns:
        Extra CLI args for prettier (e.g. ['--tab-width', '4']).
    """
    settings = get_settings(filepath_or_ext, start_dir)
    args: list[str] = []

    if "indent_size" in settings:
        try:
            args.extend(["--tab-width", str(int(settings["indent_size"]))])
        except (ValueError, TypeError):
            pass

    if settings.get("indent_style") == "tab":
        args.append("--use-tabs")

    eol = settings.get("end_of_line", "").lower()
    if eol in ("lf", "crlf", "cr"):
        args.extend(["--end-of-line", eol])

    return args
