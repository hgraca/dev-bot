#!/usr/bin/env python3
"""Report whether a registered MCP key still matches its module template.

reset.sh runs before init on every reinit. Its job is to drop STALE module-
managed MCP entries (old env, outdated command) so init re-registers them
fresh — but removing an entry that already matches its template is pure churn:
init re-appends it at the end of the mcp map, reordering keys and breaking
reinit byte-idempotency (audit-32 NOTE). This helper lets reset remove a key
only when it is actually stale.

The module template is the single canonical manifest (mcp.json, {"mcp": {...}})
and is translated to the target harness shape before comparison, so config and
template always speak the same vocabulary:

  config (opencode.jsonc):  {"mcp":         {"<key>": {type: local, ... environment: {...}}}}
  config (.mcp.json):       {"mcpServers":  {"<key>": {type: stdio, ... env: {...}}}}
  module (mcp.json):        {"mcp":         {"<key>": {type: stdio|http, command, env: {...}}}}

Translation runs with placeholders UNRESOLVED (mcp_translate.py --gpu/--root
omitted): the resolved values are machine-dependent (GPU string, install root,
SIGNOZ token) and legitimately differ between configs, so a differing resolved
value must not trigger a re-registration. Comparison then normalizes:

  - __GPU_ENABLED__     whole-value placeholder: any config value is current
  - __DEV_BOT_ROOT__    path-prefix placeholder: the suffix after the
                        placeholder must still match (root layout drift is stale)
  - {env:VAR}           env indirection: current whether the config holds the
                        literal, a registration-time-resolved value, or omits
                        the key (unset at registration — claudecode drops it)

Usage:
  mcp_key_is_current.py <config_file> <module_mcp.json> <key> <harness>

Exit codes:
  0 — key absent from config, or registered def matches the template (no
      removal needed; "absent" is trivially current — nothing to churn)
  1 — key present but STALE (differs from template) — reset should remove it
"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
from mcp_translate import load_canonical, server_map, translate  # noqa: E402


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
    # Key at top level.
    if isinstance(data.get(key), dict):
        return data[key]
    # Key under a servers map (config files + canonical mcp.json).
    for map_key in ("mcp", "mcpServers"):
        m = data.get(map_key)
        if isinstance(m, dict) and isinstance(m.get(key), dict):
            return m[key]
    return None


def _normalize(entry, config_entry):
    """Return a comparable copy of the translated template entry.

    Placeholders are rewritten to whatever the config resolved — the only
    runtime-dependent fields:
      - __GPU_ENABLED__    whole-value placeholder (cuda/metal/vulkan/false)
      - __DEV_BOT_ROOT__   path-prefix placeholder (absolute install root);
                           the suffix after the placeholder must match the
                           config's value for the entry to stay current
      - {env:VAR}          env indirection: dropped from the comparison, since
                           the config may hold the literal (opencode native),
                           a registration-resolved value (claudecode), or no
                           key at all (var unset at registration)
    Other differences stay visible.
    """
    entry = json.loads(json.dumps(entry))  # deep copy

    # The env block is named `environment` (opencode) or `env` (claudecode)
    # depending on the harness the template was translated for.
    env = None
    config_env = None
    for key in ("environment", "env"):
        if isinstance(entry.get(key), dict):
            env = entry[key]
            config_env = config_entry.get(key)
        elif isinstance(config_entry.get(key), dict):
            config_env = config_entry[key]
    if not isinstance(env, dict):
        return entry

    config_env = config_env if isinstance(config_env, dict) else {}
    for k, v in list(env.items()):
        if v == "__GPU_ENABLED__":
            resolved = config_env.get(k)
            # Any resolved string is current (GPU value is machine-dependent);
            # a non-string (legacy boolean true — audit-28) is not.
            if isinstance(resolved, str) and resolved != "__GPU_ENABLED__":
                env[k] = resolved
        elif "__DEV_BOT_ROOT__" in v:
            prefix, _, suffix = v.partition("__DEV_BOT_ROOT__")
            cv = config_env.get(k)
            if (
                isinstance(cv, str)
                and cv
                and cv.startswith(prefix)
                and cv.endswith(suffix)
                and len(cv) >= len(prefix) + len(suffix)
            ):
                env[k] = cv
        elif v.startswith("{env:") and v.endswith("}"):
            # Env indirection: current whether the config resolved it, kept the
            # literal, or omitted the key. Drop from both sides.
            env.pop(k)
            config_env.pop(k, None)
    return entry


def main():
    if len(sys.argv) != 5:
        print(
            "Usage: mcp_key_is_current.py <config_file> <module_mcp.json> <key> <harness>",
            file=sys.stderr,
        )
        sys.exit(1)

    config_file, template_file, key, harness = sys.argv[1:5]

    if not os.path.isfile(config_file) or not os.path.isfile(template_file):
        # Nothing to compare — trivially current (nothing to remove).
        sys.exit(0)

    try:
        config_entry = _find_entry(_load_jsonc(config_file), key)
        template_entry = _find_entry(load_canonical(template_file), key)
    except Exception as e:
        print(f"Failed to parse config/template: {e}", file=sys.stderr)
        sys.exit(0)  # fail safe: don't churn on a parse anomaly

    if config_entry is None or template_entry is None:
        # Absent from config, or no longer declared by the module — nothing to
        # refresh (and nothing for init to re-register either).
        sys.exit(0)

    try:
        translated = translate(template_entry, harness)
    except Exception as e:
        print(f"Failed to translate module template: {e}", file=sys.stderr)
        sys.exit(0)  # fail safe: don't churn on an invalid template

    if json.dumps(_normalize(translated, config_entry), sort_keys=True) == \
            json.dumps(config_entry, sort_keys=True):
        sys.exit(0)  # current — skip removal
    sys.exit(1)  # stale — reset should remove so init re-registers


if __name__ == "__main__":
    main()
