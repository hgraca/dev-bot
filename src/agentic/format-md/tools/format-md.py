#!/usr/bin/env python3
# Formats markdown files with consistent formatting via prettier.
# Handles tables, headings, lists, code fences, and all markdown features.
#
# Indentation and formatting follow project .editorconfig when present.
# File mode: prettier reads .editorconfig natively (since v2).
# Pipe mode: settings are parsed explicitly and passed as prettier CLI flags.
#
# Usage:
#   format-md.py path/to/directory    # format all .md files recursively
#   format-md.py file1.md file2.md    # format specific files in-place
#   cat file.md | format-md.py        # pipe mode: stdin -> stdout
#   format-md.py --help               # show this help
#
# Dependencies: node, prettier (installed via npm -g)

from __future__ import annotations

import sys
import os
import subprocess

# Allow importing from src/_shared/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../_shared"))
from editorconfig import get_prettier_args  # noqa: E402  # type: ignore[import-not-found]
from prettier_gate import has_prettier_config, prettier_available  # noqa: E402


USAGE = """\
Usage:
  format-md.py <directory>         Format all .md files in directory (recursive)
  format-md.py <file> [<file>...]  Format specific files in-place
  cat file.md | format-md.py       Pipe mode: stdin -> stdout
  format-md.py --help              Show this help
"""

# File mode: prettier natively reads .editorconfig for indent settings.
# Pipe mode: extra args from .editorconfig are appended at runtime.
# --ignore-path /dev/null: prettier otherwise follows the project .gitignore
# from its CWD and silently skips every gitignored path — including .agents/**
# (the agent's own workspace). Our tools decide what to format (explicit file
# args, EXCLUDED_DIRS for directory mode); prettier must not re-apply ignore.
PRETTIER_CMD = ["prettier", "--parser", "markdown", "--print-width", "999", "--ignore-path", "/dev/null"]


# ── Core formatting logic via prettier ──────────────────────────────────────


def format_md_text(text: str, extra_args: list[str] | None = None) -> str:
    """Format markdown text using prettier.

    Pipes text through prettier --parser markdown with no line wrapping.
    Handles tables, headings, lists, code fences, and all markdown features.
    Indentation follows project .editorconfig when present.

    Args:
        text: Raw markdown text.
        extra_args: Extra prettier CLI args (e.g. from .editorconfig for pipe mode).

    Returns:
        Formatted markdown text.
    """
    cmd = PRETTIER_CMD + (extra_args or [])
    try:
        proc = subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=30)
    except FileNotFoundError as e:
        # The binary vanished between the availability check and the exec.
        # Reported as a formatting failure — never as a vanished file, whose
        # warning exits 0 and would hide a broken installation.
        raise ValueError(f"prettier could not be executed: {e}") from e
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise ValueError(f"prettier formatting failed: {stderr or '(no error output)'}")

    return proc.stdout


# ── File-level operations ──────────────────────────────────────────────────


EXCLUDED_DIRS = frozenset({'.git', 'no-vcs', 'node_modules', 'storage', 'tests', 'vendor', '__pycache__', '.opencode', '.ai', 'graphify-out'})


def _warn_missing(path: str) -> None:
    """Report a path that has nothing to format.

    The file.edited hook can fire for a path that is renamed or deleted before
    — or while — the formatter runs, so this is a warning, never a failure.
    """
    print(f"WARN: {path!r} is not a file or directory — nothing to format", file=sys.stderr)


def format_file(path: str) -> None:
    """Format a single markdown file in-place via prettier pipe.

    Passes --stdin-filepath so prettier can locate .editorconfig
    from the file's directory tree.
    """
    with open(path, "r", encoding="utf-8") as f:
        original = f.read()
    formatted = format_md_text(original, extra_args=["--stdin-filepath", path])
    if formatted == original:
        return
    # Formatting spans a prettier subprocess, so the file can change while it
    # runs — the agent's next edit landing in that window. Writing the result
    # computed from the stale read would silently discard that edit, so re-read
    # and back off; the next edit event formats the newer content.
    with open(path, "r", encoding="utf-8") as f:
        current = f.read()
    if current != original:
        print(
            f"WARN: {path} changed while it was being formatted — not overwriting",
            file=sys.stderr,
        )
        return
    with open(path, "w", encoding="utf-8") as f:
        f.write(formatted)


def format_files_batch(file_paths: list[str]) -> None:
    """Format multiple markdown files in a single prettier --write invocation."""
    if not file_paths:
        return

    cmd = PRETTIER_CMD + ["--embedded-language-formatting", "off", "--write"] + file_paths
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            stderr = proc.stderr.strip()
            print(f"Error: prettier batch formatting failed: {stderr or '(no error output)'}", file=sys.stderr)
    except subprocess.TimeoutExpired:
        print(f"Error: prettier timed out formatting {len(file_paths)} files", file=sys.stderr)


def find_md_files(directory: str) -> list[str]:
    """Recursively find all .md files in a directory."""
    result = []
    for root, dirs, files in os.walk(directory):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for fname in files:
            if fname.endswith(".md"):
                result.append(os.path.join(root, fname))
    return sorted(result)


# ── Main ────────────────────────────────────────────────────────────────────


def main() -> int:
    args = sys.argv[1:]

    if "--help" in args or "-h" in args:
        print(USAGE, end="")
        return 0

    available = prettier_available()

    if not args:
        # Pipe mode
        if sys.stdin.isatty():
            print("Error: no arguments given and stdin is a terminal.", file=sys.stderr)
            print(USAGE, end="", file=sys.stderr)
            return 1
        text = sys.stdin.read()
        if not available:
            # Pass the input through rather than lose it: a formatter that cannot
            # run must not swallow a pipe.
            print(
                "WARN: prettier (or node) not found — passing markdown through unformatted",
                file=sys.stderr,
            )
            sys.stdout.write(text)
            return 0
        try:
            extra = get_prettier_args(".md")
            sys.stdout.write(format_md_text(text, extra_args=extra))
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0

    # File and directory runs: a missing prettier is a no-op, never a failure —
    # the file.edited hook must not fail an edit.
    if not available:
        print("WARN: prettier (or node) not found — skipping markdown formatting", file=sys.stderr)
        return 0

    # ...and only where the project actually declares prettier. Running it anyway
    # imposes a standard the project never adopted, and fights one it did (a Biome
    # project's multi-line "files" array was collapsed by exactly that). A
    # multi-path call is judged by its first path — the hook always passes one.
    if not has_prettier_config(args[0]):
        return 0

    paths = args
    errors = 0

    for path in paths:
        if os.path.isdir(path):
            md_files = find_md_files(path)
            if md_files:
                print(f"Formatting {len(md_files)} markdown files in {path}...")
                try:
                    format_files_batch(md_files)
                except Exception as e:
                    print(f"Error formatting {path}: {e}", file=sys.stderr)
                    errors += 1
        elif os.path.isfile(path):
            try:
                format_file(path)
            except FileNotFoundError:
                # Renamed or deleted while prettier was running — the same
                # "nothing to format" case as below, one window later.
                _warn_missing(path)
            except Exception as e:
                print(f"Error formatting {path}: {e}", file=sys.stderr)
                errors += 1
        else:
            # Nothing to format: the hook can fire for a path that is renamed
            # or deleted before it runs. Warn, but exit 0 — a vanished file
            # must not fail the hook.
            _warn_missing(path)

    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
