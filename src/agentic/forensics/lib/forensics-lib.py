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

import datetime
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import analyse  # noqa: E402
import commitparse  # noqa: E402
import gitmine  # noqa: E402  (local module, resolved via the sys.path entry above)
import report  # noqa: E402
import store  # noqa: E402
import szz  # noqa: E402

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


def _run_plugin_stdin(script: str, payload: dict, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", script, *args], input=json.dumps(payload), capture_output=True, text=True)


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


def _parse_args(args: list) -> tuple:
    opts = {}
    positionals = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg.startswith("--"):
            if index + 1 < len(args) and not args[index + 1].startswith("--"):
                opts[arg[2:]] = args[index + 1]
                index += 2
            else:
                opts[arg[2:]] = True
                index += 1
        else:
            positionals.append(arg)
            index += 1
    return opts, positionals


def _default_db_path(repo: str) -> str:
    out_dir = os.path.join(os.path.abspath(repo), ".forensics")
    os.makedirs(out_dir, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    return os.path.join(out_dir, "%s.sqlite" % stamp)


def _ensure_self_ignored(db_path: str) -> None:
    """Write a `.gitignore` of `*` — but only inside the tool-owned `.forensics` dir.

    Never outside it: a blanket `*` written into an arbitrary `--db` directory
    would hide the whole repository from git.
    """
    directory = os.path.dirname(os.path.abspath(db_path))
    if os.path.basename(directory) != ".forensics":
        return
    os.makedirs(directory, exist_ok=True)
    ignore = os.path.join(directory, ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8") as handle:
            handle.write("*\n")


def _extract_units(repo: str, file_types: dict, langs=None) -> tuple:
    """Run each units-capable plugin over the files whose extension it owns.

    Returns (units, errors). One plugin's failure is collected and the others
    still run — a single unavailable engine must not discard the rest.
    """
    plugins, _ = _discover(_langs_dir())
    units = []
    errors = []
    for plugin in plugins:
        if "units" not in plugin.get("capabilities", []):
            continue
        if langs and plugin.get("lang") not in langs:
            continue
        paths = []
        for extension in plugin.get("extensions", []):
            paths += file_types.get(extension.lstrip(".").lower(), [])
        if not paths:
            continue
        proc = _run_plugin_stdin(plugin["path"], {"project": repo, "files": paths}, "units")
        if proc.returncode != 0:
            errors.append("%s: %s" % (plugin.get("lang"), (proc.stderr or "").strip() or "plugin failed"))
            continue
        try:
            doc = json.loads(proc.stdout)
        except ValueError:
            errors.append("%s: plugin returned non-JSON" % plugin.get("lang"))
            continue
        units += doc.get("units", [])
    return units, errors


def cmd_mine(args: list) -> int:
    fmt = _parse_format(args)
    opts, positionals = _parse_args(args)

    repo = positionals[0] if positionals else os.getcwd()
    if not os.path.isdir(repo):
        print("ERROR: not a directory: %s" % repo, file=sys.stderr)
        return 1
    if not gitmine._is_repo(repo):
        print("ERROR: not a git repository: %s" % repo, file=sys.stderr)
        return 1

    # Git emits repo-root-relative paths; canonicalise to the toplevel so a
    # subdirectory argument yields the same evidence and the DB lands at the root.
    repo = gitmine.toplevel(repo) or os.path.abspath(repo)

    plugins, _ = _discover(_langs_dir())
    available_langs = [plugin.get("lang") for plugin in plugins if plugin.get("lang")]
    requested_lang = opts.get("lang") if isinstance(opts.get("lang"), str) else None
    langs = None
    if requested_lang and requested_lang != "auto":
        if requested_lang not in available_langs:
            print(
                "ERROR: unknown language '%s' (available: %s)" % (requested_lang, ", ".join(available_langs) or "none"),
                file=sys.stderr,
            )
            return 2
        langs = {requested_lang}

    since = opts.get("since") if isinstance(opts.get("since"), str) else None
    until = opts.get("until") if isinstance(opts.get("until"), str) else None
    db_path = opts.get("db") if isinstance(opts.get("db"), str) else _default_db_path(repo)

    try:
        data = gitmine.mine_log(repo, since, until)
    except RuntimeError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1

    _ensure_self_ignored(db_path)

    conn = store.connect(db_path)
    try:
        store.reset(conn)
        store.write_meta(
            conn,
            {
                "tool": "forensics",
                "version": TOOL_VERSION,
                "repo": data["repo"],
                "head": data["head"],
                "since": since or "",
                "until": until or "",
            },
        )
        enriched = commitparse.enrich(data["commits"])
        store.write_commits(conn, enriched)
        store.write_changes(conn, data["changes"])
        store.derive_files(conn)
        conn.commit()
        warnings = []
        granularity = opts.get("granularity") if isinstance(opts.get("granularity"), str) else "unit"
        if granularity != "file":
            file_types = {}
            for row in conn.execute("SELECT path, type FROM files").fetchall():
                file_types.setdefault((row["type"] or "").lower(), []).append(row["path"])
            units, errors = _extract_units(data["repo"], file_types, langs)
            warnings += ["unit extraction skipped (%s)" % error for error in errors]
            if units:
                store.write_units(conn, units)
                conn.commit()

        if not opts.get("no-defects"):
            links = szz.link_defects(data["repo"], enriched)
            if links:
                store.write_defect_links(conn, links)
                conn.commit()

        result_counts = store.counts(conn)
    finally:
        conn.close()

    doc = {
        "ok": True,
        "db": os.path.abspath(db_path),
        "repo": data["repo"],
        "counts": result_counts,
        "warnings": warnings,
    }
    if fmt == "json":
        print(json.dumps(doc, indent=2))
    else:
        print("Mined %s" % data["repo"])
        print("- db: %s" % doc["db"])
        for name in ("commits", "changes", "files", "units"):
            print("- %s: %d" % (name, result_counts[name]))
        for warning in warnings:
            print("WARN: %s" % warning)
    return 0


def cmd_provision(args: list) -> int:
    opts, _ = _parse_args(args)
    lang = opts.get("lang")
    plugins, _ = _discover(_langs_dir())
    available = [plugin.get("lang") for plugin in plugins]

    if not isinstance(lang, str) or not lang:
        print("ERROR: --lang is required (available: %s)" % (", ".join(available) or "none"), file=sys.stderr)
        return 2

    for plugin in plugins:
        if plugin.get("lang") == lang:
            proc = _run_plugin(plugin["path"], "provision")
            if proc.stdout:
                sys.stdout.write(proc.stdout)
            if proc.stderr:
                sys.stderr.write(proc.stderr)
            return proc.returncode

    print("ERROR: no plugin for language '%s' (available: %s)" % (lang, ", ".join(available) or "none"), file=sys.stderr)
    return 2


def cmd_analyse(args: list) -> int:
    fmt = _parse_format(args)
    opts, positionals = _parse_args(args)

    if not positionals:
        print("ERROR: a database path is required", file=sys.stderr)
        return 2
    db_path = positionals[0]
    if not os.path.isfile(db_path):
        print("ERROR: database not found: %s" % db_path, file=sys.stderr)
        return 1

    view = opts.get("view") if isinstance(opts.get("view"), str) else "hotspots"
    if view not in analyse._VIEWS:
        print("ERROR: view '%s' is not implemented yet (Phase 1)" % view, file=sys.stderr)
        return 3

    top = None
    if isinstance(opts.get("top"), str) and opts["top"].isdigit():
        top = int(opts["top"])

    conn = store.connect(db_path)
    try:
        rows = analyse._VIEWS[view](conn, top)
    finally:
        conn.close()

    doc = {"ok": True, "view": view, "count": len(rows), view: rows}
    if fmt == "json":
        print(json.dumps(doc, indent=2))
    else:
        print("| hotspot | complexity | commits | path |")
        print("| --- | --- | --- | --- |")
        for row in rows:
            print("| %.3f | %d | %d | %s |" % (row["hotspot"], row["complexity"], row["commits"], row["path"]))
    return 0


def cmd_report(args: list) -> int:
    fmt = _parse_format(args)
    opts, positionals = _parse_args(args)

    if not positionals:
        print("ERROR: a database path is required", file=sys.stderr)
        return 2
    db_path = positionals[0]
    if not os.path.isfile(db_path):
        print("ERROR: database not found: %s" % db_path, file=sys.stderr)
        return 1

    conn = store.connect(db_path)
    try:
        doc = report.build(conn)
    finally:
        conn.close()

    if fmt == "json":
        rendered = json.dumps(doc, indent=2) + "\n"
    else:
        rendered = report.to_markdown(doc)

    out_dir = opts.get("out") if isinstance(opts.get("out"), str) else None
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, "report.json" if fmt == "json" else "report.md")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(rendered)
        print("Wrote %s" % path)
    else:
        sys.stdout.write(rendered)
    return 0


_HANDLERS = {
    "langs": cmd_langs,
    "doctor": cmd_doctor,
    "mine": cmd_mine,
    "analyse": cmd_analyse,
    "report": cmd_report,
    "provision": cmd_provision,
}


def main(argv: list) -> int:
    if not argv:
        print("ERROR: no command", file=sys.stderr)
        return 2

    command, rest = argv[0], argv[1:]

    if command == "--version":
        print("forensics %s" % TOOL_VERSION)
        return 0
    if command in ("--help", "-h"):
        print("Usage: forensics-lib.py <langs|doctor|mine|provision> [options]")
        return 0

    handler = _HANDLERS.get(command)
    if handler is None:
        print("ERROR: unknown core command '%s'" % command, file=sys.stderr)
        return 2

    return handler(rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
