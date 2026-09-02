#!/usr/bin/env python3
"""Remove an MCP server key from a JSONC config file.

Handles both config shapes:
  - opencode.jsonc:   top-level "mcp" map        { "mcp": { "qmd": {...} } }
  - .mcp.json (Claude Code): top-level "mcpServers" map
Preserves all other keys and structure.

Usage:
  remove_mcp_key.py <config_file> <mcp_key>

Exit codes:
  0 — key was removed or was not present (idempotent)
  1 — error (file missing, parse error, etc.)
"""

import json
import sys
import os


def load_jsonc(path):
    """Read a JSONC file, strip comments."""
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
        print("Usage: remove_mcp_key.py <config_file> <mcp_key>", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]
    mcp_key = sys.argv[2]

    if not os.path.isfile(config_file):
        # File doesn't exist — nothing to do (idempotent)
        sys.exit(0)

    try:
        data = load_jsonc(config_file)
    except Exception as e:
        print(f"Failed to parse {config_file}: {e}", file=sys.stderr)
        sys.exit(1)

    mcp_section = data.get("mcp") or data.get("mcpServers")
    if not mcp_section or mcp_key not in mcp_section:
        # Key not present — idempotent no-op
        sys.exit(0)

    del mcp_section[mcp_key]

    with open(config_file, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    print(f"Removed MCP key '{mcp_key}' from {config_file}", file=sys.stderr)


if __name__ == "__main__":
    main()
