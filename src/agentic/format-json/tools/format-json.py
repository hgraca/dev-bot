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

import sys
import os
import subprocess

# Allow importing from src/_shared/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../_shared"))
from editorconfig import get_prettier_args  # noqa: E402


USAGE = """\
Usage:
  format-json.py <directory>               Format all .json/.jsonc files in directory (recursive)
  format-json.py <file> [<file>...]         Format specific files in-place
  cat file.json | format-json.py           Pipe mode: stdin -> stdout
  format-json.py --help                    Show this help
"""

# File mode: prettier natively reads .editorconfig for indent settings.
# Pipe mode: extra args from .editorconfig are appended at runtime.
PRETTIER_CMD = ["prettier", "--parser", "json", "--print-width", "80"]


def check_prettier() -> None:
    """Verify prettier is available. Raises RuntimeError if not found."""
    try:
        subprocess.run(["node", "--version"], capture_output=True, text=True, check=True, timeout=5)
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        raise RuntimeError(
            "node is required but not found. Install via your system package manager:\n"
            "  Ubuntu/Debian: apt install nodejs npm\n"
            "  Fedora:        dnf install nodejs npm\n"
            "  macOS:         brew install node"
        )
    try:
        subprocess.run(["prettier", "--version"], capture_output=True, text=True, check=True, timeout=10)
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        raise RuntimeError(
            "prettier is required but not found. Install via:\n"
            "  npm install -g prettier"
        )


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
    proc = subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=30)
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise ValueError(f"prettier formatting failed: {stderr or '(no error output)'}")

    return proc.stdout


# ── File-level operations ──────────────────────────────────────────────────


JSON_EXTENSIONS = ('.json', '.jsonc')
EXCLUDED_DIRS = frozenset({'.git', 'no-vcs', 'node_modules', 'storage', 'tests', 'vendor', '__pycache__', '.opencode', '.ai', 'graphify-out'})


def is_json_file(path: str) -> bool:
    """Check if a file path has a JSON or JSONC extension."""
    return path.lower().endswith(JSON_EXTENSIONS)


def format_file(path: str) -> None:
    """Format a single JSON or JSONC file in-place via prettier pipe.

    Passes --stdin-filepath so prettier can locate .editorconfig
    from the file's directory tree.
    """
    with open(path, 'r', encoding='utf-8') as f:
        original = f.read()

    formatted = format_json_text(original, file_path=path, extra_args=["--stdin-filepath", path])

    if formatted != original:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(formatted)


def format_files_batch(file_paths: list[str]) -> None:
    """Format multiple JSON/JSONC files in a single prettier --write invocation."""
    if not file_paths:
        return

    cmd = PRETTIER_CMD + ["--write"] + file_paths
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if proc.returncode != 0:
            stderr = proc.stderr.strip()
            print(f"Error: prettier batch formatting failed: {stderr or '(no error output)'}", file=sys.stderr)
    except subprocess.TimeoutExpired:
        print(f"Error: prettier timed out formatting {len(file_paths)} files", file=sys.stderr)


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
            extra = get_prettier_args(".jsonc")
            sys.stdout.write(format_json_text(text, file_path=None, extra_args=extra))
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0

    paths = args
    errors = 0

    for path in paths:
        if os.path.isdir(path):
            json_files = find_json_files(path)
            if json_files:
                print(f"Formatting {len(json_files)} JSON files in {path}...")
                try:
                    format_files_batch(json_files)
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
