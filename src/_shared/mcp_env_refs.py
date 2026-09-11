#!/usr/bin/env python3
"""List the {env:VAR} references declared by an MCP manifest.

The env-var presence check wired into bin/init.sh, bin/reinit.sh and the
harness start.sh scripts needs the set of environment variables a module's
mcp.json indirection ({env:VAR}, whole-value-only) references — without
resolving them (secrets never land in configs; the client expands the token at
launch from its own process env). This helper is the parser half of that check:
the caller (bash) decides which vars are actually missing.

It reads both the canonical src/agentic/<module>/mcp.json ({'mcp': {...}},
'env' map) and the runtime .opencode/<name>.mcp.json written by module inits
({<server>: {...}}, indirection under env/environment/headers).

The canonical shape and the {env:VAR} contract are owned by mcp_translate.py;
this helper reuses its parser (load_canonical/server_map) and matching rules so
the two can never drift apart on what a valid reference looks like.

Usage:
  mcp_env_refs.py <mcp.json>

Output (stdout): one line per whole-value {env:VAR} env entry —
  <server>\t<env_key>\t<VAR>

Exit codes: 0 ok; 1 unreadable/invalid manifest (FATAL on stderr).
"""

import json
import re
import sys

# Mirrors the whole-value-only contract enforced in mcp_translate._validate_entry.
ENV_REF = re.compile(r"\{env:([A-Za-z_][A-Za-z0-9_]*)\}")


# Runtime manifests (module inits writing .opencode/<name>.mcp.json) carry no
# 'mcp' wrapper and hold indirection under these maps; canonical manifests only
# ever use 'env'.
_RUNTIME_MAPS = ("env", "environment", "headers")


def env_refs(path: str) -> list[tuple[str, str, str]]:
    """Return [(server, key, var), ...] for every whole-value {env:VAR} ref.

    Accepts both manifest shapes:
      - canonical: {"mcp": {<server>: {...}}}  — reads the 'env' map only
      - runtime:   {<server>: {...}}           — reads env/environment/headers
    """
    with open(path) as f:
        data = json.load(f)

    if not isinstance(data, dict):
        raise ValueError("manifest must be a JSON object")

    mcp = data.get("mcp")
    if isinstance(mcp, dict):
        servers = mcp
        maps = ("env",)
    else:
        servers = data
        maps = _RUNTIME_MAPS

    refs: list[tuple[str, str, str]] = []
    for server, entry in servers.items():
        if server.startswith("_") or not isinstance(entry, dict):
            continue
        for map_key in maps:
            env = entry.get(map_key)
            if not isinstance(env, dict):
                continue
            for key, value in env.items():
                if key.startswith("_") or not isinstance(value, str):
                    # Underscore-prefixed keys are annotations (dropped by the
                    # translator at any level) — same parity as mcp_translate.
                    continue
                m = ENV_REF.fullmatch(value)
                if m:
                    refs.append((server, key, m.group(1)))
    return refs


def main(argv=None) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="List {env:VAR} references of an MCP manifest."
    )
    parser.add_argument("manifest", help="canonical mcp.json or runtime .opencode/<name>.mcp.json")
    args = parser.parse_args(argv)

    try:
        for server, key, var in env_refs(args.manifest):
            print(f"{server}\t{key}\t{var}")
    except (OSError, ValueError, json.JSONDecodeError) as e:
        print(f"FATAL: mcp_env_refs: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
