#!/usr/bin/env python3
"""forensics — language-agnostic core for the forensics dev-bot module.

Commands:
  langs   discover language plugins and print their capability metadata
  doctor  report each plugin's resolved engine

The core knows no language-specifics: every language lives in
``langs/<lang>/plugin.sh`` and answers the plugin contract
(``meta | doctor | provision | units``).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

TOOL_VERSION = "0.1.0"

_META_REQUIRED = ("lang", "extensions")


def _module_dir() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _langs_dir() -> str:
    return os.environ.get("FORENSICS_LANGS_DIR") or os.path.join(_module_dir(), "langs")


def _plugin_scripts(langs_dir: str) -> list:
    if not os.path.isdir(langs_dir):
        return []
    scripts = []
    for name in sorted(os.listdir(langs_dir)):
        script = os.path.join(langs_dir, name, "plugin.sh")
        if os.path.isfile(script):
            scripts.append((name, script))
    return scripts


def _run_plugin(script: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", script, *args], capture_output=True, text=True)


def _load_meta(script: str) -> dict:
    proc = _run_plugin(script, "meta")
    if proc.returncode != 0:
        raise ValueError("`meta` exited %d: %s" % (proc.returncode, (proc.stderr or "").strip()))
    raw = (proc.stdout or "").strip()
    try:
        meta = json.loads(raw)
    except ValueError as exc:
        raise ValueError("`meta` did not return JSON: %s" % exc)
    if not isinstance(meta, dict):
        raise ValueError("`meta` must return a JSON object")
    missing = [key for key in _META_REQUIRED if not meta.get(key)]
    if missing:
        raise ValueError("`meta` is missing required key(s): %s" % ", ".join(missing))
    if not isinstance(meta.get("extensions"), list):
        raise ValueError("`meta.extensions` must be a list")
    return meta


def _discover(langs_dir: str) -> tuple:
    plugins = []
    errors = []
    for name, script in _plugin_scripts(langs_dir):
        try:
            meta = _load_meta(script)
        except ValueError as exc:
            errors.append({"plugin": name, "error": str(exc)})
            continue
        meta.setdefault("capabilities", [])
        meta.setdefault("unit_kinds", [])
        meta.setdefault("metrics", [])
        meta["path"] = script
        plugins.append(meta)
    return plugins, errors


def _parse_format(args: list) -> str:
    fmt = "markdown"
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--json":
            fmt = "json"
        elif arg == "--markdown":
            fmt = "markdown"
        elif arg == "--format" and index + 1 < len(args):
            fmt = args[index + 1]
            index += 1
        index += 1
    return "json" if fmt == "json" else "markdown"


def _parse_opt(args: list, name: str):
    if name in args:
        index = args.index(name)
        if index + 1 < len(args):
            return args[index + 1]
    return None


def cmd_langs(args: list) -> int:
    fmt = _parse_format(args)
    plugins, errors = _discover(_langs_dir())

    if fmt == "json":
        print(json.dumps({"ok": not errors, "plugins": plugins, "errors": errors}, indent=2))
    else:
        print("| lang | extensions | capabilities | unit kinds |")
        print("| --- | --- | --- | --- |")
        for plugin in plugins:
            print(
                "| %s | %s | %s | %s |"
                % (
                    plugin.get("lang", ""),
                    ", ".join(plugin.get("extensions", [])),
                    ", ".join(plugin.get("capabilities", [])),
                    ", ".join(plugin.get("unit_kinds", [])),
                )
            )
        if not plugins:
            print("(no language plugins found in %s)" % _langs_dir())

    for error in errors:
        print("ERROR: plugin '%s': %s" % (error["plugin"], error["error"]), file=sys.stderr)
    return 1 if errors else 0


def cmd_doctor(args: list) -> int:
    fmt = _parse_format(args)
    project = _parse_opt(args, "--project") or os.getcwd()
    plugins, errors = _discover(_langs_dir())

    results = []
    for plugin in plugins:
        proc = _run_plugin(plugin["path"], "doctor", "--project", project)
        raw = (proc.stdout or "").strip()
        try:
            doc = json.loads(raw) if raw else {"ok": False, "error": "no output"}
        except ValueError:
            doc = {"ok": False, "error": "`doctor` did not return JSON"}
        doc.setdefault("lang", plugin.get("lang"))
        results.append(doc)
        if not doc.get("ok"):
            errors.append({"plugin": plugin.get("lang", "?"), "error": doc.get("error", "doctor failed")})

    if fmt == "json":
        print(json.dumps({"ok": not errors, "doctor": results, "errors": errors}, indent=2))
    else:
        for doc in results:
            engine = doc.get("engine") or {}
            status = "ok" if doc.get("ok") else "MISSING"
            detail = " (%s)" % engine.get("version") if engine.get("version") else ""
            print("- %s: %s%s" % (doc.get("lang"), status, detail))

    for error in errors:
        print("ERROR: %s: %s" % (error["plugin"], error["error"]), file=sys.stderr)
    return 1 if errors else 0


_HANDLERS = {"langs": cmd_langs, "doctor": cmd_doctor}


def main(argv: list) -> int:
    if not argv:
        print("ERROR: no command", file=sys.stderr)
        return 2

    command, rest = argv[0], argv[1:]

    if command == "--version":
        print("forensics %s" % TOOL_VERSION)
        return 0
    if command in ("--help", "-h"):
        print("Usage: forensics-lib.py <langs|doctor> [options]")
        return 0

    handler = _HANDLERS.get(command)
    if handler is None:
        print("ERROR: unknown core command '%s'" % command, file=sys.stderr)
        return 2

    return handler(rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
