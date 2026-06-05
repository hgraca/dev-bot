#!/usr/bin/env python3
"""Idempotently add a project path to .devbot.global.jsonc::projects array.

Usage:
  add_project.py <config_file> <project_path>

Exit codes:
  0 — project was already registered (no-op)
  0 — project was added successfully
  1 — error (file missing, parse error, etc.)

The script reads via read_jsonc.py (strips // and /* */ comments),
adds the path if missing, and writes back as JSON.
"""

import json
import sys
import os


def load_jsonc(path):
    """Read a JSONC file, strip comments (reuse read_jsonc logic)."""
    with open(path) as f:
        raw = f.read()

    out = []
    i = 0
    while i < len(raw):
        if raw[i] == '"':
            j = i + 1
            while j < len(raw):
                if raw[j] == "\\":
                    j += 2
                elif raw[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            out.append(raw[i:j])
            i = j
            continue

        if raw[i : i + 2] == "//":
            j = raw.find("\n", i)
            if j == -1:
                break
            i = j
            continue

        if raw[i : i + 2] == "/*":
            j = raw.find("*/", i + 2)
            if j == -1:
                break
            i = j + 2
            continue

        out.append(raw[i])
        i += 1

    return json.loads("".join(out))


def main():
    if len(sys.argv) != 3:
        print("Usage: add_project.py <config_file> <project_path>", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]
    project_path = os.path.abspath(sys.argv[2])

    if not os.path.isfile(config_file):
        print(f"Config file not found: {config_file}", file=sys.stderr)
        sys.exit(1)

    try:
        data = load_jsonc(config_file)
    except Exception as e:
        print(f"Failed to parse {config_file}: {e}", file=sys.stderr)
        sys.exit(1)

    projects = data.setdefault("projects", [])

    # Normalise paths for comparison
    norm = os.path.normpath(project_path)

    for existing in projects:
        if os.path.normpath(existing) == norm:
            # Already registered — no-op
            sys.exit(0)

    projects.append(norm)
    data["projects"] = sorted(set(projects), key=lambda p: p.lower())

    with open(config_file, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    print(f"Registered project: {norm}", file=sys.stderr)


if __name__ == "__main__":
    main()
