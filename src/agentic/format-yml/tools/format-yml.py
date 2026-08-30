#!/usr/bin/env python3
# Formats YAML files with consistent formatting via prettier.
# Supports both .yml and .yaml extensions. Preserves comments, key ordering,
# and block scalars (|, >). Quotes ambiguous unquoted strings (true/false/yes/no/null/numbers).
#
# Indentation and formatting follow project .editorconfig when present.
# File mode: prettier reads .editorconfig natively (since v2).
# Pipe mode: settings are parsed explicitly and passed as prettier CLI flags.
#
# Usage:
#   format-yml.py path/to/directory     # format all .yml/.yaml files recursively
#   format-yml.py file1.yml file2.yaml  # format specific files in-place
#   cat data.yml | format-yml.py         # pipe mode: stdin -> stdout
#   format-yml.py --help                 # show this help
#
# Dependencies: node, prettier (installed via npm -g)

import sys
import os
import shutil
import subprocess

# Allow importing from src/_shared/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../_shared"))
from editorconfig import get_prettier_args  # noqa: E402  # type: ignore[import-not-found]


USAGE = """\
Usage:
  format-yml.py <directory>               Format all .yml/.yaml files in directory (recursive)
  format-yml.py <file> [<file>...]         Format specific files in-place
  cat file.yml | format-yml.py            Pipe mode: stdin -> stdout
  format-yml.py --help                    Show this help
"""

# File mode: prettier natively reads .editorconfig for indent settings.
# Pipe mode: extra args from .editorconfig are appended at runtime.
# --ignore-path /dev/null: prettier otherwise follows the project .gitignore
# from its CWD and silently skips every gitignored path — including .agents/**
# (the agent's own workspace). Our tools decide what to format (explicit file
# args, EXCLUDED_DIRS for directory mode); prettier must not re-apply ignore.
PRETTIER_CMD = ["prettier", "--parser", "yaml", "--print-width", "999", "--ignore-path", "/dev/null"]


def check_prettier() -> None:
    """Verify prettier is available. Raises RuntimeError if not found."""
    if shutil.which("node") is None:
        raise RuntimeError(
            "node is required but not found. Install via your system package manager:\n"
            "  Ubuntu/Debian: apt install nodejs npm\n"
            "  Fedora:        dnf install nodejs npm\n"
            "  macOS:         brew install node"
        )
    if shutil.which("prettier") is None:
        raise RuntimeError(
            "prettier is required but not found. Install via:\n"
            "  npm install -g prettier"
        )


# ── Core formatting logic via prettier ──────────────────────────────────────


def format_yaml_text(text: str, file_path: str | None = None, extra_args: list[str] | None = None) -> str:
    """Format YAML text using prettier.

    Pipes text through prettier --parser yaml with no line wrapping.
    Preserves comments, key ordering, and block scalars (|, >).
    Indentation follows project .editorconfig when present.

    Args:
        text: Raw YAML text.
        file_path: Optional file path (reserved for future extension).
        extra_args: Extra prettier CLI args (e.g. from .editorconfig for pipe mode).

    Returns:
        Formatted YAML text.
    """
    cmd = PRETTIER_CMD + (extra_args or [])
    proc = subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=30)
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise ValueError(f"prettier formatting failed: {stderr or '(no error output)'}")

    return proc.stdout


# ── File-level operations ──────────────────────────────────────────────────


YAML_EXTENSIONS = ('.yml', '.yaml')
EXCLUDED_DIRS = frozenset({'.git', 'no-vcs', 'node_modules', 'storage', 'tests', 'vendor', '__pycache__', '.opencode', '.ai', 'graphify-out'})


def is_yaml_file(path: str) -> bool:
    """Check if a file path has a YAML extension (.yml or .yaml)."""
    return path.lower().endswith(YAML_EXTENSIONS)


def format_file(path: str) -> None:
    """Format a single YAML file in-place via prettier pipe.

    Passes --stdin-filepath so prettier can locate .editorconfig
    from the file's directory tree.
    """
    with open(path, 'r', encoding='utf-8') as f:
        original = f.read()

    formatted = format_yaml_text(original, file_path=path, extra_args=["--stdin-filepath", path])

    if formatted == original:
        return

    with open(path, 'w', encoding='utf-8') as f:
        f.write(formatted)


def format_files_batch(file_paths: list[str]) -> None:
    """Format multiple YAML files in a single prettier --write invocation."""
    if not file_paths:
        return

    cmd = PRETTIER_CMD + ["--write"] + file_paths
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            stderr = proc.stderr.strip()
            print(f"Error: prettier batch formatting failed: {stderr or '(no error output)'}", file=sys.stderr)
    except subprocess.TimeoutExpired:
        print(f"Error: prettier timed out formatting {len(file_paths)} files", file=sys.stderr)


def find_yaml_files(directory: str) -> list[str]:
    """Recursively find all .yml and .yaml files in a directory."""
    result = []
    for root, dirs, files in os.walk(directory):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for fname in files:
            if is_yaml_file(fname):
                result.append(os.path.join(root, fname))
    return sorted(result)


# ── Main ────────────────────────────────────────────────────────────────────


def main() -> int:
    # Verify prettier is available at startup
    try:
        check_prettier()
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    args = sys.argv[1:]

    if "--help" in args or "-h" in args:
        print(USAGE, end='')
        return 0

    if not args:
        # Pipe mode
        if sys.stdin.isatty():
            print("Error: no arguments given and stdin is a terminal.", file=sys.stderr)
            print(USAGE, end='', file=sys.stderr)
            return 1
        text = sys.stdin.read()
        try:
            extra = get_prettier_args(".yml")
            sys.stdout.write(format_yaml_text(text, file_path=None, extra_args=extra))
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0

    paths = args
    errors = 0

    for path in paths:
        if os.path.isdir(path):
            yaml_files = find_yaml_files(path)
            if yaml_files:
                print(f"Formatting {len(yaml_files)} YAML files in {path}...")
                try:
                    format_files_batch(yaml_files)
                except Exception as e:
                    print(f"Error formatting {path}: {e}", file=sys.stderr)
                    errors += 1
        elif os.path.isfile(path):
            try:
                format_file(path)
            except Exception as e:
                print(f"Error formatting {path}: {e}", file=sys.stderr)
                errors += 1
        else:
            print(f"Error: {path!r} is not a file or directory.", file=sys.stderr)
            errors += 1

    return 0 if errors == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
