#!/usr/bin/env python3
"""Seed ~/.claude.json so Claude Code skips its trust + onboarding dialogs in
the test container.

The container runs the project at /app (an isolated per-run copy), while Claude
Code keys trust and onboarding by absolute project path in ~/.claude.json — a
sibling of the host-mounted ~/.claude/ directory, and therefore NOT shared. So
every fresh container re-asks "Do you trust the files in this folder?".

Start from the host's file when available (mounted read-only at <host-config>,
inheriting account preferences) and mark <project-path> trusted. User-scope MCP
servers are NOT inherited — they are dropped from the seeded copy, so the
container sees only dev-bot's project-wired servers (/app/.mcp.json); a host
entry such as a phpstorm registration is unreachable in-container. The host file
is only ever read; the seeded copy is container-local.

Usage:
  seed-claude-config.py <project-path> [<host-config>]
"""

import json
import os
import sys


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1
    project = argv[1]
    host_config = argv[2] if len(argv) > 2 else ""

    dst = os.path.join(os.path.expanduser("~"), ".claude.json")

    data = {}
    for src in (dst, host_config):
        if not src or not os.path.exists(src):
            continue
        try:
            with open(src, encoding="utf-8") as fh:
                loaded = json.load(fh)
        except (OSError, ValueError):
            continue
        if isinstance(loaded, dict):
            data = loaded
            break

    # Drop user-scope MCP servers from the SEEDED copy: the container must see
    # only dev-bot's project-wired servers (from /app/.mcp.json). A host entry
    # such as a `phpstorm` registration points at a host-only IDE port that is
    # unreachable in-container and surfaces in the audit as a stray connection
    # failure. The host file is only read — this writes the container-local copy.
    data.pop("mcpServers", None)
    for project_entry in data.get("projects", {}).values():
        if isinstance(project_entry, dict):
            project_entry.pop("mcpServers", None)

    data["hasCompletedOnboarding"] = True
    projects = data.setdefault("projects", {})
    entry = projects.setdefault(project, {})
    entry["hasTrustDialogAccepted"] = True
    entry["hasCompletedProjectOnboarding"] = True
    entry["projectOnboardingSeenCount"] = 1

    try:
        with open(dst, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
    except OSError as exc:
        print(f"WARN: could not write {dst}: {exc}", file=sys.stderr)
        return 0  # best-effort: the harness still launches, only the dialogs return
    print(f"seeded {dst}: {project} trusted, onboarding complete")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
