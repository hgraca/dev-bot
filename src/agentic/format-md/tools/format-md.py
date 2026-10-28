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
from prettier_gate import (  # noqa: E402
    prettier_available,
    prettier_batch_config_args,
    prettier_config_args,
)


USAGE = """\
Usage:
  format-md.py <directory>         Format all .md files in directory (recursive)
  format-md.py <file> [<file>...]  Format specific files in-place
  format-md.py --check <path>...   Report files that need formatting (exit 1 if any)
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


EXCLUDED_DIRS = frozenset({'.git', 'no-vcs', 'node_modules', 'storage', 'tests', 'vendor', '__pycache__', '.opencode', '.ai', 'graphify-out'})


def _warn_missing(path: str) -> None:
    """Report a path that has nothing to format.

    The file.edited hook can fire for a path that is renamed or deleted before
    — or while — the formatter runs, so this is a warning, never a failure.
    """
    print(f"WARN: {path!r} is not a file or directory — nothing to format", file=sys.stderr)


def format_file(path: str, check: bool = False, embedded: bool = True) -> bool:
    """Format one file in place, or report it in check mode.

    Returns True when the file needs changing (check) or was changed (write).
    """
    with open(path, "r", encoding="utf-8", newline="") as f:
        original = f.read()
    extra = prettier_config_args(path) + ["--stdin-filepath", path]
    if not embedded:
        extra += ["--embedded-language-formatting", "off"]
    formatted = format_md_text(original, extra_args=extra)
    if formatted == original:
        return False
    if check:
        return True
    # Formatting spans a prettier subprocess, so the file can change while it
    # runs — the agent's next edit landing in that window. Writing the result
    # computed from the stale read would silently discard that edit, so re-read
    # and back off; the next edit event formats the newer content.
    with open(path, "r", encoding="utf-8", newline="") as f:
        current = f.read()
    if current != original:
        print(
            f"WARN: {path} changed while it was being formatted — not overwriting",
            file=sys.stderr,
        )
        return False
    with open(path, "w", encoding="utf-8") as f:
        f.write(formatted)
    return True


def format_files_batch(file_paths: list[str]) -> bool:
    """Format multiple markdown files, one prettier --write per config group."""
    if not file_paths:
        return True

    for batch, config_args in prettier_batch_config_args(file_paths):
        cmd = PRETTIER_CMD + config_args + ["--embedded-language-formatting", "off", "--write"] + batch
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if proc.returncode != 0:
                stderr = proc.stderr.strip()
                print(f"Error: prettier batch formatting failed: {stderr or '(no error output)'}", file=sys.stderr)
                return False
        except subprocess.TimeoutExpired:
            print(f"Error: prettier timed out formatting {len(batch)} files", file=sys.stderr)
            return False
    return True


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

    check = "--check" in args
    if check:
        args = [a for a in args if a != "--check"]
        if not args:
            print("Error: --check requires at least one path.", file=sys.stderr)
            print(USAGE, end="", file=sys.stderr)
            return 1

    # A missing prettier is a no-op for the edit hook, but a --check gate that
    # cannot run must not report a false green.
    if not available:
        if check:
            print("ERROR: prettier (or node) not found — cannot verify formatting", file=sys.stderr)
            return 2
        print("WARN: prettier (or node) not found — skipping markdown formatting", file=sys.stderr)
        return 0

    paths = args
    errors = 0
    checked = 0
    changed = 0

    for path in paths:
        if os.path.isdir(path):
            md_files = find_md_files(path)
            if check:
                for md_file in md_files:
                    checked += 1
                    try:
                        if format_file(md_file, check=True, embedded=False):
                            changed += 1
                            print(md_file)
                    except Exception as e:
                        print(f"Error formatting {path}: {e}", file=sys.stderr)
                        errors += 1
                continue
            if md_files:
                print(f"Formatting {len(md_files)} markdown files in {path}...")
                before = {}
                for md_file in md_files:
                    try:
                        with open(md_file, "r", encoding="utf-8", newline="") as f:
                            before[md_file] = f.read()
                    except OSError:
                        pass
                try:
                    if not format_files_batch(md_files):
                        errors += 1
                except Exception as e:
                    print(f"Error formatting {path}: {e}", file=sys.stderr)
                    errors += 1
                for md_file, old in before.items():
                    try:
                        with open(md_file, "r", encoding="utf-8", newline="") as f:
                            if f.read() != old:
                                changed += 1
                    except OSError:
                        pass
                checked += len(md_files)
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
        print(f"format-md: {checked} file(s) checked, {changed} need formatting")
        return 1 if changed or errors else 0
    print(f"format-md: {checked} file(s) checked, {changed} changed")
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
