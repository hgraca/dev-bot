#!/usr/bin/env python3
"""Report whether a registered MCP key still matches its module template.

reset.sh runs before init on every reinit. Its job is to drop STALE module-
managed MCP entries (old env, outdated command) so init re-registers them
fresh — but removing an entry that already matches its template is pure churn:
init re-appends it at the end of the mcp map, reordering keys and breaking
reinit byte-idempotency (audit-32 NOTE). This helper lets reset remove a key
only when it is actually stale.

Config files and module templates use different shapes, and both are handled:

  config (opencode.jsonc):  {"mcp":         {"<key>": {...}}}
  config (.mcp.json):       {"mcpServers":  {"<key>": {...}}}
  module (mcp.opencode.json):   {"<key>": {...}}            (key at top level)
  module (mcp.claudecode.json): {"mcpServers": {"<key>": {...}}}

The __GPU_ENABLED__ placeholder is treated as current-any-value: the resolved
GPU value (cuda/metal/vulkan/false) is machine-dependent and legitimately
differs between configs, so it must not trigger a re-registration. Anything
else that differs (command, env shape, type) is stale.

Usage:
  mcp_key_is_current.py <config_file> <module_template_file> <key>

Exit codes:
  0 — key absent from config, or registered def matches the template (no
      removal needed; "absent" is trivially current — nothing to churn)
  1 — key present but STALE (differs from template) — reset should remove it
"""

import json
import sys
import os


def _load_jsonc(path):
    """Read a JSONC file (comments stripped) and return parsed data."""
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


def _find_entry(data, key):
    """Locate the entry dict for `key` in any supported map shape."""
    if not isinstance(data, dict):
        return None
    # Key at top level (mcp.opencode.json module template shape).
    if isinstance(data.get(key), dict):
        return data[key]
    # Key under a servers map (config files + mcp.claudecode.json templates).
    for map_key in ("mcp", "mcpServers"):
        m = data.get(map_key)
        if isinstance(m, dict) and isinstance(m.get(key), dict):
            return m[key]
    return None


def _normalize(entry, config_entry):
    """Return a comparable copy of a template entry.

    __GPU_ENABLED__ is rewritten to whatever GPU value the config resolved —
    the only runtime-dependent field. Other differences stay visible.
    """
    entry = json.loads(json.dumps(entry))  # deep copy
    env = entry.get("environment")
    if isinstance(env, dict) and "__GPU_ENABLED__" in env.values():
        config_env = config_entry.get("environment") or {}
        resolved = next(
            (v for v in config_env.values() if v != "__GPU_ENABLED__"),
            "__GPU_ENABLED__",
        )
        for k, v in env.items():
            if v == "__GPU_ENABLED__":
                env[k] = resolved
    return entry


def main():
    if len(sys.argv) != 4:
        print("Usage: mcp_key_is_current.py <config_file> <module_template_file> <key>", file=sys.stderr)
        sys.exit(1)

    config_file, template_file, key = sys.argv[1], sys.argv[2], sys.argv[3]

    if not os.path.isfile(config_file) or not os.path.isfile(template_file):
        # Nothing to compare — trivially current (nothing to remove).
        sys.exit(0)

    try:
        config_entry = _find_entry(_load_jsonc(config_file), key)
        template_entry = _find_entry(_load_jsonc(template_file), key)
    except Exception as e:
        print(f"Failed to parse config/template: {e}", file=sys.stderr)
        sys.exit(0)  # fail safe: don't churn on a parse anomaly

    if config_entry is None or template_entry is None:
        # Absent from config, or no longer declared by the module — nothing to
        # refresh (and nothing for init to re-register either).
        sys.exit(0)

    if json.dumps(_normalize(template_entry, config_entry), sort_keys=True) == \
            json.dumps(config_entry, sort_keys=True):
        sys.exit(0)  # current — skip removal
    sys.exit(1)  # stale — reset should remove so init re-registers


if __name__ == "__main__":
    main()
