#!/usr/bin/env python3
"""Migrate an OpenCode 1.x opencode.jsonc to the 2.x shapes, in place.

Both harnesses read the same `opencode.jsonc`, so a project that ran the v1
adapter already has a v1 document. V2 accepts the deprecated aliases, but only
for reading — dev-bot writes `plugins`, `permissions`, `agents`, `providers` and
`mcp.servers`, and half a document in each shape is worse than either.

Mapping (per the V1→V2 guide and the v2 config schema):

  plugin               -> plugins          tuple -> {package, options}
  permission object    -> permissions      ordered rules, last match wins
  agent                -> agents           prompt->system, disable->disabled,
                                           variant appended as model#variant
  provider             -> providers        npm->package, options->settings
  mcp.<name>           -> mcp.servers      enabled inverted to disabled
  lsp                  -> dropped          v2 accepts it but runs no servers

Dev-bot-owned v1 plugin entries and opencode-pty are dropped: they are
re-registered by init.sh, and opencode-pty has no v2 build at all.

Usage:
  migrate_v1.py <config> [--backup <path>]
Prints one line per change; exit 0 when the file was migrated.
"""

import json
import os
import shutil
import sys

sys.path.insert(0, os.environ.get("V2_SHARED_DIR", ""))

# v1 permission keys with no v2 action. Dropping them is deliberate: a
# mistranslated rule would silently allow or deny the wrong thing.
_DROPPED_PERMISSIONS = {"list", "todowrite", "todoread", "codesearch", "lsp", "doom_loop"}
_RENAMED_PERMISSIONS = {"bash": "shell", "task": "subagent"}
# Plugin entries init.sh owns: re-created from the v2 dist and required list.
_DEV_BOT_PLUGIN_PREFIXES = (".opencode/plugins/", ".opencode/tui-plugins/")
# Packages with no v2 build (V1 plugin implementations do not run on V2).
_NO_V2_BUILD = ("opencode-pty",)

# Order matters: the external_directory catch-all deny must precede its allows,
# and everything else follows.
_EFFECT_FIRST_ACTIONS = ("external_directory",)


def _rule(action, resource, effect):
    return {"action": action, "resource": resource, "effect": effect}


def _normalise_effect(value):
    if isinstance(value, bool):
        return "allow" if value else "deny"
    if value in ("allow", "deny", "ask"):
        return value
    return None


def migrate_permissions(permission, report):
    rules = []
    deferred = []
    for key, value in permission.items():
        if key in _DROPPED_PERMISSIONS:
            report.append(f"permissions: dropped '{key}' (no v2 action)")
            continue
        action = _RENAMED_PERMISSIONS.get(key, key)
        if isinstance(value, dict):
            for resource, effect in value.items():
                effect = _normalise_effect(effect)
                if effect is None:
                    report.append(f"permissions: skipped {action}/{resource} (unknown effect)")
                    continue
                (rules if action in _EFFECT_FIRST_ACTIONS else deferred).append(
                    _rule(action, resource, effect)
                )
        else:
            effect = _normalise_effect(value)
            if effect is None:
                report.append(f"permissions: skipped '{key}' (unknown effect)")
                continue
            (rules if action in _EFFECT_FIRST_ACTIONS else deferred).append(
                _rule(action, "*", effect)
            )
    return rules + deferred


def migrate_agent(entry):
    out = {}
    variant = None
    for key, value in entry.items():
        if key == "prompt":
            out["system"] = value
        elif key == "disable":
            out["disabled"] = bool(value)
        elif key == "variant":
            variant = value
        else:
            out[key] = value
    if variant and isinstance(out.get("model"), str) and "#" not in out["model"]:
        out["model"] = f"{out['model']}#{variant}"
    return out


def migrate_provider(entry):
    out = {}
    for key, value in entry.items():
        if key == "npm":
            out["package"] = value
        elif key == "options":
            out["settings"] = value
        else:
            out[key] = value
    return out


def migrate_plugins(entries, report):
    out = []
    for entry in entries:
        if isinstance(entry, list):
            if len(entry) != 2:
                report.append("plugins: dropped a malformed tuple entry")
                continue
            entry = {"package": entry[0], "options": entry[1]}
        if isinstance(entry, str):
            name = entry
        elif isinstance(entry, dict):
            name = str(entry.get("package", ""))
        else:
            continue

        if any(name.startswith(p) for p in _DEV_BOT_PLUGIN_PREFIXES):
            report.append(f"plugins: dropped '{name}' (dev-bot re-registers it)")
            continue
        if any(name.startswith(p) for p in _NO_V2_BUILD):
            report.append(f"plugins: dropped '{name}' (no v2 build)")
            continue
        if name.startswith(("./", "../", "/")) or name.endswith((".ts", ".js")):
            report.append(
                f"plugins: '{name}' points at a local file — move it under "
                f".opencode/plugins/ and register the package for v2"
            )
            out.append(entry)
            continue
        out.append(entry)
    return out


def migrate_mcp(mcp, report):
    servers = {}
    for name, entry in mcp.items():
        if not isinstance(entry, dict):
            continue
        entry = dict(entry)
        if "enabled" in entry:
            entry["disabled"] = not bool(entry.pop("enabled"))
            report.append(f"mcp.servers.{name}: enabled -> disabled (inverted)")
        servers[name] = entry
    return {"servers": servers}


def _plugin_name(entry):
    if isinstance(entry, str):
        return entry
    if isinstance(entry, dict):
        return str(entry.get("package", ""))
    return ""


def migrate(cfg):
    report = []
    out = {}
    # A config can carry both shapes after a v1/v2 handover. The v2 sections
    # already present are newer than the legacy shape, so the migration merges
    # into them instead of replacing them.
    for key in ("plugins", "permissions", "agents", "providers"):
        if key in cfg:
            out[key] = cfg[key]
    merged_plugins = list(out.get("plugins") or [])
    known_plugins = {_plugin_name(entry) for entry in merged_plugins}

    for key, value in cfg.items():
        if key == "plugin":
            for entry in migrate_plugins(value or [], report):
                name = _plugin_name(entry)
                if name and name in known_plugins:
                    report.append(f"plugins: kept the v2 registration for '{name}'")
                    continue
                merged_plugins.append(entry)
                known_plugins.add(name)
            out["plugins"] = merged_plugins
            report.append("plugin -> plugins")
        elif key in ("plugins", "permissions", "agents", "providers"):
            # Seeded above; the legacy branches merge into them.
            continue
        elif key == "permission":
            converted = migrate_permissions(value or {}, report)
            existing = out.get("permissions")
            out["permissions"] = (list(existing) + converted) if isinstance(existing, list) else converted
            report.append("permission -> permissions")
        elif key == "agent":
            converted = {name: migrate_agent(entry or {}) for name, entry in (value or {}).items()}
            existing = out.get("agents")
            out["agents"] = {**converted, **(existing if isinstance(existing, dict) else {})}
            report.append("agent -> agents")
        elif key == "provider":
            converted = {name: migrate_provider(entry or {}) for name, entry in (value or {}).items()}
            existing = out.get("providers")
            out["providers"] = {**converted, **(existing if isinstance(existing, dict) else {})}
            report.append("provider -> providers")
        elif key == "mcp":
            mcp = value or {}
            # A v2-shaped block already carries `servers`; migrating it would
            # nest them again as mcp.servers.servers.
            if isinstance(mcp, dict) and "servers" in mcp:
                out["mcp"] = mcp
            else:
                out["mcp"] = migrate_mcp(mcp, report)
        elif key == "lsp":
            report.append("lsp: dropped (inert in v2 — no language servers)")
        else:
            out[key] = value

    out.setdefault("plugins", merged_plugins)
    if "mcp" not in out:
        out["mcp"] = {"servers": {}}
    return out, report


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    path = argv[1]
    backup = None
    if "--backup" in argv:
        backup = argv[argv.index("--backup") + 1]

    from read_jsonc import load_jsonc  # type: ignore

    cfg = load_jsonc(path)
    migrated, report = migrate(cfg)

    if backup:
        shutil.copy2(path, backup)
        report.append(f"backup written to {backup}")

    with open(path, "w") as handle:
        json.dump(migrated, handle, indent=2)
        handle.write("\n")

    load_jsonc(path)  # refuse to leave an unparseable config behind
    for line in report:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
