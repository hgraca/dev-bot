#!/usr/bin/env python3
"""Translate the canonical per-module MCP manifest to a harness-shaped config.

Single source of truth for the canonical -> harness mapping that the opencode
registration path (bin/init.sh), the claudecode .mcp.json regeneration
(src/harnesses/claudecode/init.sh) and the stale-detection helper
(mcp_key_is_current.py) all consume. Keeping the mapping here, rather than
duplicated per consumer, is what prevents the drift the two-file per-harness
scheme (mcp.opencode.json / mcp.claudecode.json) suffered.

Canonical module manifest (src/agentic/<module>/mcp.json):

    { "mcp": { "<server>": { "type": "stdio"|"http",
                             "command": [argv...],   // stdio — uniform argv
                             "url": "...",           // http
                             "oauth": bool,          // http passthrough
                             "env": { "K": "V" } } } }

No `enabled` field: module enablement (disabled_modules) is the only gate, so
an enabled module's servers are always wired into every harness.

Tokens resolved at translation time:
  {harness-dir}  -> .opencode | .claude   (wrapper/serve-script paths)
  {host}         -> opencode | claudecode (server --host args)
Placeholders __GPU_ENABLED__ and __DEV_BOT_ROOT__ are resolved only when
--gpu/--root are supplied: init passes both; mcp_key_is_current.py omits them
and applies its own placeholder-insensitive comparison afterwards.

Output shapes:
  opencode   stdio -> {type: local, command, environment}   (env renamed)
             http  -> {type: remote, url, oauth?}
  claudecode stdio -> {type: stdio, command: argv[0], args: argv[1:], env}
             http  -> {type: http, url, env?}               (oauth dropped)

Usage:
  mcp_translate.py <manifest> <harness> [--gpu VAL] [--root PATH]

Exit codes: 0 ok (prints {"<server>": {...}, ...}); 1 invalid manifest/harness.
"""

import argparse
import json
import sys
from typing import Any, Optional

HARNESSES = ("opencode", "claudecode")
TRANSPORTS = ("stdio", "http")
# Canonical entry keys the translator understands. Underscore-prefixed keys are
# annotations at any level and are ignored (hooks.json convention). Anything
# else is a migration mistake — a leftover harness-specific field such as
# "enabled" or "environment" — and fails loudly rather than being silently
# dropped.
ENTRY_KEYS = ("type", "command", "url", "oauth", "env")

HARNESS_DIRS = {"opencode": ".opencode", "claudecode": ".claude"}
# {host} resolves to the PRODUCT name each harness is known by — opencode, and
# Claude Code = "claude" (module dir is .claude, module name claudecode).
# Needed by servers whose --host arg selects their config location (e.g.
# codebase-index reads .opencode/codebase-index.json vs .claude/codebase-index.json).
HOST_NAMES = {"opencode": "opencode", "claudecode": "claude"}


def _substitute(
    value: Any, harness: str, gpu: Optional[str], root: Optional[str]
) -> Any:
    """Deep-replace tokens/placeholders in strings within the entry."""
    if isinstance(value, str):
        value = value.replace("{harness-dir}", HARNESS_DIRS[harness])
        value = value.replace("{host}", HOST_NAMES[harness])
        if gpu is not None:
            value = value.replace("__GPU_ENABLED__", gpu)
        if root is not None:
            value = value.replace("__DEV_BOT_ROOT__", root)
        return value
    if isinstance(value, list):
        return [_substitute(v, harness, gpu, root) for v in value]
    if isinstance(value, dict):
        return {
            k: _substitute(v, harness, gpu, root)
            for k, v in value.items()
            if not k.startswith("_")
        }
    return value


def _validate_entry(server: str, entry: Any) -> None:
    """Raise ValueError with a server-scoped message on an invalid entry."""
    if not isinstance(entry, dict):
        raise ValueError(f"server '{server}': entry must be an object")
    unknown = [k for k in entry if not k.startswith("_") and k not in ENTRY_KEYS]
    if unknown:
        raise ValueError(
            f"server '{server}': unknown key(s) {', '.join(sorted(unknown))} — "
            f"canonical keys: {', '.join(ENTRY_KEYS)}"
        )
    transport = entry.get("type")
    if transport not in TRANSPORTS:
        raise ValueError(
            f"server '{server}': unsupported transport type '{transport}' — "
            f"valid: {', '.join(TRANSPORTS)}"
        )
    if transport == "stdio":
        command = entry.get("command")
        if not isinstance(command, list) or not command or not all(
            isinstance(arg, str) for arg in command
        ):
            raise ValueError(
                f"server '{server}': stdio requires a non-empty command array"
            )
        if entry.get("url"):
            raise ValueError(f"server '{server}': stdio must not carry a url")
    else:  # http
        if not isinstance(entry.get("url"), str) or not entry["url"]:
            raise ValueError(f"server '{server}': http requires a url")
    env = entry.get("env")
    if env is not None and (
        not isinstance(env, dict)
        or not all(isinstance(k, str) and isinstance(v, str) for k, v in env.items())
    ):
        raise ValueError(f"server '{server}': env must map string keys to string values")


def load_canonical(path: str) -> Any:
    """Return the parsed canonical manifest (raises on parse error)."""
    with open(path) as f:
        return json.load(f)


def server_map(data: Any) -> dict[str, Any]:
    """Return {server: entry} for the manifest, dropping underscore keys."""
    mcp = data.get("mcp")
    if not isinstance(mcp, dict):
        raise ValueError("manifest must carry an 'mcp' object")
    return {k: v for k, v in mcp.items() if not k.startswith("_")}


def translate(
    entry: Any,
    harness: str,
    gpu: Optional[str] = None,
    root: Optional[str] = None,
) -> dict[str, Any]:
    """Return the harness-shaped deep copy of one canonical entry."""
    if harness not in HARNESSES:
        raise ValueError(
            f"unsupported harness '{harness}' — valid: {', '.join(HARNESSES)}"
        )
    _validate_entry("<server>", entry)

    transport = entry["type"]

    if harness == "opencode":
        if transport == "stdio":
            out: dict[str, Any] = {
                "type": "local",
                "command": _substitute(entry["command"], harness, gpu, root),
            }
        else:
            out = {
                "type": "remote",
                "url": _substitute(entry["url"], harness, gpu, root),
            }
            if "oauth" in entry:
                out["oauth"] = entry["oauth"]
        env = entry.get("env")
        if isinstance(env, dict) and env:
            out["environment"] = _substitute(env, harness, gpu, root)
        return out

    # claudecode
    if transport == "stdio":
        argv = _substitute(entry["command"], harness, gpu, root)
        out = {"type": "stdio", "command": argv[0]}
        if len(argv) > 1:
            out["args"] = argv[1:]
    else:
        out = {"type": "http", "url": _substitute(entry["url"], harness, gpu, root)}
    env = entry.get("env")
    if isinstance(env, dict) and env:
        out["env"] = _substitute(env, harness, gpu, root)
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Translate a canonical mcp.json manifest to a harness shape."
    )
    parser.add_argument("manifest", help="canonical src/agentic/<module>/mcp.json")
    parser.add_argument("harness", choices=HARNESSES, help="target harness")
    parser.add_argument("--gpu", help="resolve __GPU_ENABLED__ to this value")
    parser.add_argument("--root", help="resolve __DEV_BOT_ROOT__ to this path")
    args = parser.parse_args(argv)

    try:
        servers = server_map(load_canonical(args.manifest))
        translated = {}
        for name, entry in servers.items():
            _validate_entry(name, entry)
            translated[name] = translate(entry, args.harness, args.gpu, args.root)
    except (OSError, ValueError, json.JSONDecodeError) as e:
        print(f"FATAL: mcp_translate: {e}", file=sys.stderr)
        return 1

    print(json.dumps(translated, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
