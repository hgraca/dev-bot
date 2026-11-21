#!/usr/bin/env python3
"""search — one ripgrep call that answers the question instead of reframing it.

The corpus showed `rg` run again and again on the same pattern: the first result
was unreadable (thousands of lines, vendored trees, generated files), so the
agent re-ran with different flags. This applies repo-safe exclusions and prints a
digest — file, match count, and the first few matches per file — so one call
usually settles it.

Exit codes: 0 matches found, 1 none found, 2 usage, 3 ripgrep missing.

Usage:
    search.py "def main"
    search.py "TODO" --path src --max-per-file 3
    search.py "class Foo" --glob '*.php' --ignore-case
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

EXIT_MATCH = 0
EXIT_NO_MATCH = 1
EXIT_USAGE = 2
EXIT_NO_RG = 3

# Directories whose contents are not the answer: dependencies, build output,
# generated artefacts and other agents' worktrees.
DEFAULT_EXCLUDES = (
    ".git",
    "node_modules",
    "vendor",
    "storage",
    "graphify-out",
    "no-vcs",
    ".agents/worktrees",
    "__pycache__",
    ".venv",
    "dist",
    "build",
)


def run_rg(args: list[str], cwd: str | None, timeout: int = 120) -> tuple[str, int, str]:
    try:
        result = subprocess.run(
            ["rg", *args], capture_output=True, text=True, timeout=timeout, cwd=cwd
        )
        return result.stdout, result.returncode, result.stderr.strip()
    except FileNotFoundError:
        raise SystemExit(EXIT_NO_RG)
    except subprocess.TimeoutExpired:
        return "", 1, f"rg timed out after {timeout}s"


def collect(
    pattern: str,
    path: str,
    globs: list[str],
    excludes: list[str],
    fixed: bool,
    ignore_case: bool,
    cwd: str | None,
    keep_per_file: int = 200,
) -> tuple[dict, str]:
    """Return (per-file matches, warning). Uses rg --json so no output is parsed."""
    args = ["--json", "--line-number", "--no-heading", "--color", "never"]
    if fixed:
        args.append("--fixed-strings")
    if ignore_case:
        args.append("--ignore-case")
    for glob in globs:
        args += ["--glob", glob]
    for exclude in excludes:
        args += ["--glob", f"!{exclude}/**"]
        args += ["--glob", f"!**/{exclude}/**"]
    args += ["--", pattern]
    if path:
        args.append(path)

    out, rc, err = run_rg(args, cwd=cwd)
    if rc not in (0, 1):
        return {}, err or f"rg exited {rc}"

    files: dict[str, dict] = {}
    for line in out.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("type") != "match":
            continue
        data = event.get("data") or {}
        filename = (data.get("path") or {}).get("text") or "?"
        line_no = data.get("line_number") or 0
        text = ((data.get("lines") or {}).get("text") or "").rstrip("\n")
        entry = files.setdefault(filename, {"count": 0, "lines": []})
        entry["count"] += 1
        if len(entry["lines"]) < keep_per_file:
            entry["lines"].append((line_no, text.strip()))
    return files, ""


def render(files: dict, pattern: str, max_per_file: int, max_files: int) -> str:
    ordered = sorted(files.items(), key=lambda item: (-item[1]["count"], item[0]))
    total_files = len(ordered)
    total_matches = sum(entry["count"] for entry in files.values())
    lines = [
        f"## `{pattern}` — {total_matches} match(es) in {total_files} file(s)",
        "",
    ]
    for filename, entry in ordered[:max_files]:
        lines.append(f"**{filename}** ({entry['count']})")
        for line_no, text in entry["lines"][:max_per_file]:
            lines.append(f"  {line_no}: {text[:200]}")
        if entry["count"] > max_per_file:
            lines.append(f"  … {entry['count'] - max_per_file} more")
        lines.append("")
    if total_files > max_files:
        lines.append(f"… {total_files - max_files} more file(s) not shown")
        lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Search with a digest instead of raw output")
    parser.add_argument("pattern", help="pattern to search for")
    parser.add_argument("--path", default=".", help="path to search (default: .)")
    parser.add_argument("--glob", action="append", default=[], help="include glob (repeatable)")
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help=f"extra directory to exclude (defaults: {', '.join(DEFAULT_EXCLUDES)})",
    )
    parser.add_argument("--no-default-excludes", action="store_true")
    parser.add_argument("--max-per-file", type=int, default=5)
    parser.add_argument("--max-files", type=int, default=30)
    parser.add_argument("--fixed-strings", action="store_true")
    parser.add_argument("--ignore-case", "-i", action="store_true")
    parser.add_argument("--cwd", default=None)
    args = parser.parse_args(argv)

    if args.max_per_file < 1 or args.max_files < 1:
        print("ERROR: --max-per-file and --max-files must be positive", file=sys.stderr)
        return EXIT_USAGE

    excludes = list(args.exclude)
    if not args.no_default_excludes:
        excludes += list(DEFAULT_EXCLUDES)

    files, warning = collect(
        args.pattern,
        args.path,
        args.glob,
        excludes,
        args.fixed_strings,
        args.ignore_case,
        args.cwd,
        keep_per_file=max(200, args.max_per_file),
    )
    if warning:
        print(f"ERROR: {warning}", file=sys.stderr)
        return EXIT_USAGE
    if not files:
        print(f"## `{args.pattern}` — no matches", file=sys.stderr)
        return EXIT_NO_MATCH
    print(render(files, args.pattern, args.max_per_file, args.max_files))
    return EXIT_MATCH


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
