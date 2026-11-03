#!/usr/bin/env python3
# Formats JSON and JSONC files with consistent formatting via prettier.
# Handles JSONC (comments, trailing commas) natively — no comment stripping needed.
#
# Indentation and formatting follow project .editorconfig when present.
# File mode: prettier reads .editorconfig natively (since v2).
# Pipe mode: settings are parsed explicitly and passed as prettier CLI flags.
#
# Usage:
#   format-json.py path/to/directory     # format all .json/.jsonc files recursively
#   format-json.py file1.json file2.jsonc # format specific files in-place
#   cat data.json | format-json.py        # pipe mode: stdin -> stdout
#   format-json.py --help                 # show this help
#
# Dependencies: node, prettier (installed via npm -g)

from __future__ import annotations

import sys
import os
import subprocess

# Allow importing from src/_shared/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../_shared"))
from editorconfig import get_prettier_args  # noqa: E402  # type: ignore[import-not-found]
from prettier_gate import (  # noqa: E402
    prettier_available,
    prettier_batch_config_args,
    prettier_config_args,
    prettier_ignore_args,
)


USAGE = """\
Usage:
  format-json.py <directory>               Format all .json/.jsonc files in directory (recursive)
  format-json.py <file> [<file>...]         Format specific files in-place
  format-json.py --check <path>...          Report files that need formatting (exit 1 if any)
  format-json.py --force <file> [<file>...] Accepted for compatibility (no effect)
  cat file.json | format-json.py           Pipe mode: stdin -> stdout
  format-json.py --help                    Show this help
"""

# File mode: prettier natively reads .editorconfig for indent settings.
# Pipe mode: extra args from .editorconfig are appended at runtime.
# --ignore-path: pinned per target by prettier_gate.prettier_ignore_args — the
# project's .prettierignore, or /dev/null where it declares none. Passing it at
# all replaces prettier's default [.gitignore, .prettierignore], which keeps the
# deliberate behaviour that a gitignored .agents/** workspace is still formatted.
PRETTIER_CMD = ["prettier", "--parser", "json", "--print-width", "80"]


# ── Core formatting logic via prettier ──────────────────────────────────────


def format_json_text(text: str, file_path: str | None = None, extra_args: list[str] | None = None) -> str:
    """Format JSON/JSONC text using prettier.

    Pipes text through prettier --parser json.
    Handles JSONC (comments, trailing commas) natively.
    Indentation follows project .editorconfig when present.

    Args:
        text: Raw JSON or JSONC text.
        file_path: Optional file path (reserved for future extension).
        extra_args: Extra prettier CLI args (e.g. from .editorconfig for pipe mode).

    Returns:
        Formatted JSON text.
    """
    cmd = PRETTIER_CMD + (extra_args or [])
    try:
        proc = subprocess.run(
            cmd, input=text.encode("utf-8"), capture_output=True, timeout=30
        )
    except FileNotFoundError as e:
        # The binary vanished between the availability check and the exec.
        # Reported as a formatting failure — never as a vanished file, whose
        # warning exits 0 and would hide a broken installation.
        raise ValueError(f"prettier could not be executed: {e}") from e
    if proc.returncode != 0:
        stderr = proc.stderr.decode("utf-8", "replace").strip()
        raise ValueError(f"prettier formatting failed: {stderr or '(no error output)'}")

    return proc.stdout.decode("utf-8")


# ── File-level operations ──────────────────────────────────────────────────


JSON_EXTENSIONS = ('.json', '.jsonc')
EXCLUDED_DIRS = frozenset({'.git', 'no-vcs', 'node_modules', 'storage', 'tests', 'vendor', '__pycache__', '.opencode', '.ai', 'graphify-out'})


def is_json_file(path: str) -> bool:
    """Check if a file path has a JSON or JSONC extension."""
    return path.lower().endswith(JSON_EXTENSIONS)


def _warn_missing(path: str) -> None:
    """Report a path that has nothing to format.

    The file.edited hook can fire for a path that is renamed or deleted before
    — or while — the formatter runs, so this is a warning, never a failure.
    """
    print(f"WARN: {path!r} is not a file or directory — nothing to format", file=sys.stderr)


def format_file(path: str, check: bool = False) -> bool:
    """Format one JSON/JSONC file, or report it in check mode.

    Returns True when the file needs changing (check) or was changed (write).
    """
    with open(path, 'r', encoding='utf-8', newline='') as f:
        original = f.read()

    formatted = format_json_text(
        original,
        file_path=path,
        extra_args=prettier_config_args(path) + prettier_ignore_args(path) + ["--stdin-filepath", path],
    )

    if formatted == original:
        return False
    if check:
        return True

    # Formatting spans a prettier subprocess, so the file can change while it
    # runs — the agent's next edit landing in that window. Writing the result
    # computed from the stale read would silently discard that edit, so re-read
    # and back off; the next edit event formats the newer content.
    with open(path, 'r', encoding='utf-8', newline='') as f:
        current = f.read()

    if current != original:
        print(
            f"WARN: {path} changed while it was being formatted — not overwriting",
            file=sys.stderr,
        )
        return False

    with open(path, 'w', encoding='utf-8') as f:
        f.write(formatted)
    return True


def format_files_batch(file_paths: list[str]) -> bool:
    """Format multiple JSON/JSONC files, one prettier --write per config group."""
    if not file_paths:
        return True

    for batch, batch_args in prettier_batch_config_args(file_paths):
        cmd = PRETTIER_CMD + batch_args + ["--write"] + batch
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            if proc.returncode != 0:
                stderr = proc.stderr.strip()
                print(f"Error: prettier batch formatting failed: {stderr or '(no error output)'}", file=sys.stderr)
                return False
        except subprocess.TimeoutExpired:
            print(f"Error: prettier timed out formatting {len(batch)} files", file=sys.stderr)
            return False
    return True


def find_json_files(directory: str) -> list[str]:
    """Recursively find all .json and .jsonc files in a directory."""
    result = []
    for root, dirs, files in os.walk(directory):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for fname in files:
            if is_json_file(fname):
                result.append(os.path.join(root, fname))
    return sorted(result)


# ── Main ────────────────────────────────────────────────────────────────────


def main() -> int:
    args = sys.argv[1:]

    if "--help" in args or "-h" in args:
        print(USAGE, end='')
        return 0

    # --force is accepted for compatibility with callers written against the old
    # prettier gate (`devbot reinit` passes it); a project without a config is now
    # formatted with dev-bot's defaults anyway, so it has no further effect.
    args = [a for a in args if a != "--force"]
    check = "--check" in args
    if check:
        args = [a for a in args if a != "--check"]
        if not args:
            print("Error: --check requires at least one path.", file=sys.stderr)
            print(USAGE, end="", file=sys.stderr)
            return 1

    available = prettier_available()

    if not args:
        # Pipe mode
        if sys.stdin.isatty():
            print("Error: no arguments given and stdin is a terminal.", file=sys.stderr)
            print(USAGE, end='', file=sys.stderr)
            return 1
        text = sys.stdin.read()
        if not available:
            # Pass the input through rather than lose it: a formatter that cannot
            # run must not swallow a pipe.
            print(
                "WARN: prettier (or node) not found — passing JSON through unformatted",
                file=sys.stderr,
            )
            sys.stdout.write(text)
            return 0
        try:
            extra = get_prettier_args(".jsonc") + ["--ignore-path", os.devnull]
            sys.stdout.write(format_json_text(text, file_path=None, extra_args=extra))
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0

    # File and directory runs: a missing prettier is a no-op, never a failure —
    # the file.edited hook must not fail an edit.
    if not available:
        if check:
            print("ERROR: prettier (or node) not found — cannot verify formatting", file=sys.stderr)
            return 2
        print("WARN: prettier (or node) not found — skipping JSON formatting", file=sys.stderr)
        return 0

    paths = args
    errors = 0
    checked = 0
    changed = 0

    for path in paths:
        if os.path.isdir(path):
            json_files = find_json_files(path)
            if check:
                for json_file in json_files:
                    checked += 1
                    try:
                        if format_file(json_file, check=True):
                            changed += 1
                            print(json_file)
                    except Exception as e:
                        print(f"Error formatting {path}: {e}", file=sys.stderr)
                        errors += 1
                continue
            if json_files:
                print(f"Formatting {len(json_files)} JSON files in {path}...")
                before = {}
                for json_file in json_files:
                    try:
                        with open(json_file, "r", encoding="utf-8", newline="") as f:
                            before[json_file] = f.read()
                    except OSError:
                        pass
                try:
                    if not format_files_batch(json_files):
                        errors += 1
                except Exception as e:
                    print(f"Error formatting {path}: {e}", file=sys.stderr)
                    errors += 1
                for json_file, old in before.items():
                    try:
                        with open(json_file, "r", encoding="utf-8", newline="") as f:
                            if f.read() != old:
                                changed += 1
                    except OSError:
                        pass
                checked += len(json_files)
        elif os.path.isfile(path):
            checked += 1
            try:
                if format_file(path, check=check):
                    changed += 1
                    if check:
                        print(path)
            except FileNotFoundError:
                # Renamed or deleted while prettier was running — the same
                # "nothing to format" case as below, one window later.
                _warn_missing(path)
                if check:
                    errors += 1
            except Exception as e:
                print(f"Error formatting {path}: {e}", file=sys.stderr)
                errors += 1
        else:
            # Nothing to format: the hook can fire for a path that is renamed
            # or deleted before it runs. Warn, but exit 0 — a vanished file
            # must not fail the hook. A --check gate is different: a missing
            # target is a failed verification, not a no-op.
            _warn_missing(path)
            if check:
                errors += 1

    if check:
        print(f"format-json: {checked} file(s) checked, {changed} need formatting")
        return 1 if changed or errors else 0
    print(f"format-json: {checked} file(s) checked, {changed} changed")
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
