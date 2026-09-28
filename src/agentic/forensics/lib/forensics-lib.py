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

import csv
import datetime
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import analyse  # noqa: E402
import commitparse  # noqa: E402
import gitmine  # noqa: E402  (local module, resolved via the sys.path entry above)
import metrics  # noqa: E402
import ownership  # noqa: E402
import prstore  # noqa: E402
import report  # noqa: E402
import store  # noqa: E402
import szz  # noqa: E402
import trends  # noqa: E402

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


def _load_json_meta(script: str, required: tuple) -> dict:
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
    missing = [key for key in required if not meta.get(key)]
    if missing:
        raise ValueError("`meta` is missing required key(s): %s" % ", ".join(missing))
    return meta


def _load_meta(script: str) -> dict:
    meta = _load_json_meta(script, _META_REQUIRED)
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


_SOURCE_META_REQUIRED = ("source",)


def _sources_dir() -> str:
    return os.environ.get("FORENSICS_SOURCES_DIR") or os.path.join(_module_dir(), "sources")


def _load_source_meta(script: str) -> dict:
    return _load_json_meta(script, _SOURCE_META_REQUIRED)


def _discover_sources(sources_dir: str) -> tuple:
    """Discover provider adapters, mirroring the language-plugin registry."""
    plugins = []
    errors = []
    for name, script in _plugin_scripts(sources_dir):
        try:
            meta = _load_source_meta(script)
        except ValueError as exc:
            errors.append({"plugin": name, "error": str(exc)})
            continue
        meta.setdefault("capabilities", [])
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
        elif arg == "--csv":
            fmt = "csv"
        elif arg == "--markdown":
            fmt = "markdown"
        elif arg == "--format" and index + 1 < len(args):
            fmt = args[index + 1]
            index += 1
        index += 1
    return fmt if fmt in ("json", "csv", "html") else "markdown"


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


def _source_doctor(opts: dict, fmt: str) -> int:
    project = opts.get("project")
    if not isinstance(project, str) or not project:
        project = os.getcwd()
    wanted = opts.get("source") if isinstance(opts.get("source"), str) else None
    plugins, errors = _discover_sources(_sources_dir())

    results = []
    for plugin in plugins:
        if wanted and plugin.get("source") != wanted:
            continue
        proc = _run_plugin(plugin["path"], "doctor", "--project", project)
        raw = (proc.stdout or "").strip()
        try:
            doc = json.loads(raw) if raw else {"ok": False, "error": "no output"}
        except ValueError:
            doc = {"ok": False, "error": "`doctor` did not return JSON"}
        doc.setdefault("source", plugin.get("source"))
        results.append(doc)
        if not doc.get("ok"):
            errors.append({"plugin": plugin.get("source", "?"), "error": doc.get("error", "doctor failed")})

    if fmt == "json":
        print(json.dumps({"ok": not errors, "doctor": results, "errors": errors}, indent=2))
    else:
        for doc in results:
            engine = doc.get("engine") or {}
            status = "ok" if doc.get("ok") else "MISSING"
            detail = " (%s)" % engine.get("version") if engine.get("version") else ""
            print("- %s: %s%s" % (doc.get("source"), status, detail))

    for error in errors:
        print("ERROR: %s: %s" % (error["plugin"], error["error"]), file=sys.stderr)
    return 1 if errors else 0


def cmd_sources(args: list) -> int:
    fmt = _parse_format(args)
    opts, positionals = _parse_args(args)
    if "doctor" in positionals:
        return _source_doctor(opts, fmt)

    plugins, errors = _discover_sources(_sources_dir())

    if fmt == "json":
        print(json.dumps({"ok": not errors, "sources": plugins, "errors": errors}, indent=2))
    else:
        print("| source | capabilities |")
        print("| --- | --- |")
        for plugin in plugins:
            print("| %s | %s |" % (plugin.get("source", ""), ", ".join(plugin.get("capabilities", []))))
        if not plugins:
            print("(no source plugins found in %s)" % _sources_dir())

    for error in errors:
        print("ERROR: plugin '%s': %s" % (error["plugin"], error["error"]), file=sys.stderr)
    return 1 if errors else 0


_BOOLEAN_FLAGS = {"json", "csv", "markdown", "refresh", "no-defects", "trends"}


def _parse_args(args: list) -> tuple:
    opts = {}
    positionals = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg.startswith("--"):
            name = arg[2:]
            if name in _BOOLEAN_FLAGS:
                opts[name] = True
                index += 1
            elif index + 1 < len(args) and not args[index + 1].startswith("--"):
                opts[name] = args[index + 1]
                index += 2
            else:
                opts[name] = True
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
        if doc.get("ok") is False:
            errors.append("%s: %s" % (plugin.get("lang"), doc.get("error") or "plugin reported failure"))
            continue
        for message in doc.get("errors") or []:
            errors.append("%s: %s" % (plugin.get("lang"), message))
        units += doc.get("units", [])
    return units, errors


def _file_complexity(units: list) -> dict:
    """Per-file complexity from leaf units, falling back to the total."""
    leaf = {}
    total = {}
    for unit in units:
        path = unit["path"]
        complexity = unit.get("complexity") or 0
        total[path] = total.get(path, 0) + complexity
        if unit.get("kind") in ("method", "function"):
            leaf[path] = leaf.get(path, 0) + complexity
        else:
            leaf.setdefault(path, 0)
    return {path: (leaf[path] or total[path]) for path in total}


def _mine_trends(repo: str, langs, interval: str) -> list:
    """Sample the repo over time and measure complexity at each sampled revision."""
    plugins, _ = _discover(_langs_dir())
    extensions = set()
    for plugin in plugins:
        if "units" not in plugin.get("capabilities", []):
            continue
        if langs and plugin.get("lang") not in langs:
            continue
        for extension in plugin.get("extensions", []):
            extensions.add(extension.lstrip(".").lower())
    if not extensions:
        return []

    rows = []
    for entry in trends.sample_revisions(repo, interval):
        worktree = tempfile.mkdtemp(prefix="forensics-trend-")
        try:
            if not trends.add_worktree(repo, entry["revision"], worktree):
                continue
            file_types = {}
            for root, dirs, names in os.walk(worktree):
                dirs[:] = [name for name in dirs if name != ".git"]
                for name in names:
                    extension = os.path.splitext(name)[1].lstrip(".").lower()
                    if extension in extensions:
                        relative = os.path.relpath(os.path.join(root, name), worktree)
                        file_types.setdefault(extension, []).append(relative)
            units, _errors = _extract_units(worktree, file_types, langs)
            for path, complexity in _file_complexity(units).items():
                rows.append(
                    {"revision": entry["revision"], "date": entry["date"], "path": path, "complexity": complexity}
                )
        finally:
            trends.remove_worktree(repo, worktree)
            shutil.rmtree(worktree, ignore_errors=True)
    return rows


def _read_defects(csv_path: str, source: str) -> list:
    """Read a defect CSV: a `path`/`entity` column and a `count`/`defects` column."""
    rows = []
    with open(csv_path, newline="", encoding="utf-8") as handle:
        for record in csv.DictReader(handle):
            lowered = {(key or "").strip().lower(): (value or "").strip() for key, value in record.items()}
            path = lowered.get("path") or lowered.get("entity") or lowered.get("file")
            raw = lowered.get("count") or lowered.get("defects") or lowered.get("bugs") or "0"
            if not path:
                continue
            try:
                count = int(float(raw))
            except ValueError:
                count = 0
            rows.append({"path": path, "count": count, "source": source})
    return rows


def _parse_modules(spec: str) -> list:
    """Parse `name=prefix,name=prefix` into boundary rows (bare name = prefix)."""
    rows = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "=" in part:
            module, prefix = part.split("=", 1)
            rows.append({"module": module.strip(), "prefix": prefix.strip()})
        else:
            rows.append({"module": part, "prefix": part})
    return rows


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
        store.write_releases(conn, gitmine.tags(data["repo"]))
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
                try:
                    ownership_rows, churn_rows = ownership.unit_blame(data["repo"], units)
                except RuntimeError as exc:
                    warnings.append("unit ownership skipped: %s" % exc)
                    ownership_rows, churn_rows = [], []
                if ownership_rows:
                    store.write_unit_ownership(conn, ownership_rows)
                if churn_rows:
                    store.write_unit_churn(conn, churn_rows)
                conn.commit()

        if not opts.get("no-defects"):
            links = szz.link_defects(data["repo"], enriched)
            if links:
                store.write_defect_links(conn, links)
                conn.commit()

        if opts.get("trends"):
            interval = opts.get("trend-interval") if isinstance(opts.get("trend-interval"), str) else "month"
            trend_rows = _mine_trends(data["repo"], langs, interval)
            if trend_rows:
                store.write_complexity_trend(conn, trend_rows)
                conn.commit()

        if isinstance(opts.get("defects"), str):
            csv_path = opts["defects"]
            if os.path.isfile(csv_path):
                defect_rows = _read_defects(csv_path, os.path.basename(csv_path))
                if defect_rows:
                    store.write_defects(conn, defect_rows)
                    conn.commit()
            else:
                warnings.append("defects CSV not found: %s" % csv_path)

        if isinstance(opts.get("modules"), str):
            boundary_rows = _parse_modules(opts["modules"])
            if boundary_rows:
                store.write_boundaries(conn, boundary_rows)
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


_PR_COLUMNS = (
    "author",
    "prs",
    "median_commits_per_pr",
    "median_changes_per_pr",
    "median_time_to_merge_hours",
    "prs_per_day",
)


def _num(value, digits: int = 2):
    return round(value, digits) if value is not None else None


def _parse_iso(value):
    """Parse an ISO-8601 timestamp to UTC, or None — tolerant of a trailing ``Z``."""
    if not value:
        return None
    try:
        moment = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=datetime.timezone.utc)
    return moment.astimezone(datetime.timezone.utc)


def _merge_hours(created_at: str, merged_at: str):
    created, merged = _parse_iso(created_at), _parse_iso(merged_at)
    if created is None or merged is None:
        return None
    return (merged - created).total_seconds() / 3600.0


def _pr_summary(rows: list, since, until) -> dict:
    count = len(rows)
    commits = [row.get("commits") or 0 for row in rows]
    changes = [(row.get("added") or 0) + (row.get("deleted") or 0) for row in rows]
    spans = [_merge_hours(row.get("created_at"), row.get("merged_at")) for row in rows]
    return {
        "prs": count,
        "median_commits_per_pr": _num(metrics.median(commits)),
        "median_changes_per_pr": _num(metrics.median(changes)),
        "median_time_to_merge_hours": _num(metrics.median([span for span in spans if span is not None])),
        "prs_per_day": round(metrics.per_day(count, since, until), 4),
    }


def _pr_report(rows: list, since, until) -> tuple:
    """(project total, per-author rows) for the merged PRs in the window."""
    groups = {}
    for row in rows:
        groups.setdefault(row.get("author") or "(unknown)", []).append(row)
    authors = []
    for author, author_rows in groups.items():
        entry = {"author": author}
        entry.update(_pr_summary(author_rows, since, until))
        authors.append(entry)
    authors.sort(key=lambda item: (-item["prs"], item["author"]))
    return _pr_summary(rows, since, until), authors


def _cell(value):
    return "" if value is None else str(value)


def _print_table(rows: list, columns) -> None:
    print("| " + " | ".join(columns) + " |")
    print("| " + " | ".join("---" for _ in columns) + " |")
    for row in rows:
        print("| " + " | ".join(_cell(row.get(column)) for column in columns) + " |")


def cmd_prs(args: list) -> int:
    """Merged pull-request metrics, served from the PR cache.

    The cache is refreshed only for the spans of the requested window it does not
    already cover, so a repeat run makes no remote call.
    """
    fmt = _parse_format(args)
    opts, positionals = _parse_args(args)

    repo = positionals[0] if positionals else os.getcwd()
    if not os.path.isdir(repo):
        print("ERROR: not a directory: %s" % repo, file=sys.stderr)
        return 1
    if not gitmine._is_repo(repo):
        print("ERROR: not a git repository: %s" % repo, file=sys.stderr)
        return 1
    repo = gitmine.toplevel(repo) or os.path.abspath(repo)

    source = opts.get("source") if isinstance(opts.get("source"), str) else "github"
    try:
        since, until = metrics.resolve_window(
            opts.get("since") if isinstance(opts.get("since"), str) else None,
            opts.get("until") if isinstance(opts.get("until"), str) else None,
        )
    except ValueError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 2

    plugins, _ = _discover_sources(_sources_dir())
    plugin = next((p for p in plugins if p.get("source") == source), None)
    if plugin is None:
        available = ", ".join(p.get("source", "?") for p in plugins) or "none"
        print("ERROR: unknown source '%s' (available: %s)" % (source, available), file=sys.stderr)
        return 2

    db_path = opts.get("db") if isinstance(opts.get("db"), str) else os.path.join(repo, ".forensics", "prs.sqlite")
    _ensure_self_ignored(db_path)

    fresh = not os.path.exists(db_path) or os.path.getsize(db_path) == 0
    conn = prstore.connect(db_path)
    try:
        if fresh:
            prstore.init(conn)
        else:
            problem = prstore.check(conn)
            if problem:
                print("ERROR: %s" % problem, file=sys.stderr)
                return 1

        if opts.get("refresh"):
            gaps = [(since, until)]
        else:
            gaps = metrics.subtract_intervals(since, until, prstore.covered(conn, source, repo))

        fetch_errors = []
        warnings = []
        for gap_since, gap_until in gaps:
            payload = {"project": repo, "since": gap_since.isoformat(), "until": gap_until.isoformat()}
            proc = _run_plugin_stdin(plugin["path"], payload, "fetch")
            doc = {}
            if (proc.stdout or "").strip():
                try:
                    doc = json.loads(proc.stdout)
                except ValueError:
                    doc = {}
            if proc.returncode != 0 or doc.get("ok") is False:
                fetch_errors.append(doc.get("error") or (proc.stderr or "").strip() or "source fetch failed")
                continue
            warnings += ["%s: %s" % (source, message) for message in doc.get("errors") or []]
            prstore.upsert_prs(conn, source, repo, doc.get("pull_requests") or [])
            prstore.record_coverage(conn, source, repo, gap_since, gap_until)

        if fetch_errors:
            for message in fetch_errors:
                print("ERROR: %s" % message, file=sys.stderr)
            return 1

        for message in warnings:
            print("WARN: %s" % message, file=sys.stderr)

        rows = prstore.query_merged(conn, source, repo, since, until)
    finally:
        conn.close()

    total, authors = _pr_report(rows, since, until)
    table = [dict(total, author="TOTAL")] + authors

    if fmt == "json":
        print(
            json.dumps(
                {
                    "ok": True,
                    "source": source,
                    "repo": repo,
                    "since": since.isoformat(),
                    "until": until.isoformat(),
                    "total": total,
                    "authors": authors,
                },
                indent=2,
            )
        )
    elif fmt == "csv":
        writer = csv.writer(sys.stdout)
        writer.writerow(_PR_COLUMNS)
        for row in table:
            writer.writerow([row.get(column, "") for column in _PR_COLUMNS])
    else:
        _print_table(table, _PR_COLUMNS)
    return 0


_COMMIT_COLUMNS = ("author", "author_email", "commits", "median_changes_per_commit", "commits_per_day")


def _filter_by_author_date(commits: list, since, until) -> list:
    """Keep only commits whose author date falls within the window.

    ``git log --since/--until`` filters on committer date, so a rebased or
    cherry-picked commit can come back with an author date outside the window.
    """
    kept = []
    for commit in commits:
        moment = _parse_iso(commit.get("date"))
        if moment is not None and since <= moment <= until:
            kept.append(commit)
    return kept


def _commit_summary(rows: list, since, until) -> dict:
    count = len(rows)
    changes = [(row.get("lines_added") or 0) + (row.get("lines_deleted") or 0) for row in rows]
    return {
        "commits": count,
        "median_changes_per_commit": _num(metrics.median(changes)),
        "commits_per_day": round(metrics.per_day(count, since, until), 4),
    }


def _commit_report(rows: list, since, until) -> tuple:
    """(project total, per-author rows) for commits, folded by email identity."""
    groups = {}
    for row in rows:
        email = row.get("author_email") or ""
        key = email or row.get("author_name") or "(unknown)"
        entry = groups.setdefault(key, {"author": row.get("author_name") or key, "author_email": email, "rows": []})
        entry["rows"].append(row)
    authors = []
    for entry in groups.values():
        item = {"author": entry["author"], "author_email": entry["author_email"]}
        item.update(_commit_summary(entry["rows"], since, until))
        authors.append(item)
    authors.sort(key=lambda item: (-item["commits"], item["author"]))
    return _commit_summary(rows, since, until), authors


def cmd_commits(args: list) -> int:
    """Per-author commit metrics for the window, identities folded via .mailmap."""
    fmt = _parse_format(args)
    opts, positionals = _parse_args(args)

    repo = positionals[0] if positionals else os.getcwd()
    if not os.path.isdir(repo):
        print("ERROR: not a directory: %s" % repo, file=sys.stderr)
        return 1
    if not gitmine._is_repo(repo):
        print("ERROR: not a git repository: %s" % repo, file=sys.stderr)
        return 1
    repo = gitmine.toplevel(repo) or os.path.abspath(repo)

    try:
        since, until = metrics.resolve_window(
            opts.get("since") if isinstance(opts.get("since"), str) else None,
            opts.get("until") if isinstance(opts.get("until"), str) else None,
        )
    except ValueError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 2

    try:
        data = gitmine.mine_log(repo, since.isoformat(), until.isoformat(), mailmap=True)
    except RuntimeError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1

    total, authors = _commit_report(_filter_by_author_date(data["commits"], since, until), since, until)
    table = [dict(total, author="TOTAL", author_email="")] + authors

    if fmt == "json":
        print(
            json.dumps(
                {
                    "ok": True,
                    "repo": repo,
                    "since": since.isoformat(),
                    "until": until.isoformat(),
                    "total": total,
                    "authors": authors,
                },
                indent=2,
            )
        )
    elif fmt == "csv":
        writer = csv.writer(sys.stdout)
        writer.writerow(_COMMIT_COLUMNS)
        for row in table:
            writer.writerow([row.get(column, "") for column in _COMMIT_COLUMNS])
    else:
        _print_table(table, _COMMIT_COLUMNS)
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
        problem = store.check(conn)
        if problem:
            print("ERROR: %s" % problem, file=sys.stderr)
            return 1
        try:
            rows = analyse._VIEWS[view](conn, top)
        except sqlite3.Error as exc:
            print("ERROR: %s" % exc, file=sys.stderr)
            return 1
    finally:
        conn.close()

    doc = {"ok": True, "view": view, "count": len(rows), view: rows}
    if fmt == "json":
        print(json.dumps(doc, indent=2))
    elif fmt == "csv":
        if rows:
            keys = list(rows[0].keys())
            writer = csv.writer(sys.stdout)
            writer.writerow(keys)
            for row in rows:
                writer.writerow([row.get(key, "") for key in keys])
    else:
        if rows:
            keys = list(rows[0].keys())
            print("| " + " | ".join(keys) + " |")
            print("| " + " | ".join("---" for _ in keys) + " |")
            for row in rows:
                print("| " + " | ".join(str(row.get(key, "")) for key in keys) + " |")
        else:
            print("_(none)_")
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
        problem = store.check(conn)
        if problem:
            print("ERROR: %s" % problem, file=sys.stderr)
            return 1
        try:
            doc = report.build(conn)
        except sqlite3.Error as exc:
            print("ERROR: %s" % exc, file=sys.stderr)
            return 1
    finally:
        conn.close()

    if fmt == "json":
        rendered = json.dumps(doc, indent=2) + "\n"
    elif fmt == "html":
        rendered = report.to_html(doc)
    else:
        rendered = report.to_markdown(doc)

    out_dir = opts.get("out") if isinstance(opts.get("out"), str) else None
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        suffix = {"json": "report.json", "html": "report.html"}.get(fmt, "report.md")
        path = os.path.join(out_dir, suffix)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(rendered)
        print("Wrote %s" % path)
    else:
        sys.stdout.write(rendered)
    return 0


_HANDLERS = {
    "langs": cmd_langs,
    "doctor": cmd_doctor,
    "sources": cmd_sources,
    "prs": cmd_prs,
    "commits": cmd_commits,
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
        print("Usage: forensics-lib.py <langs|doctor|sources|prs|commits|mine|analyse|report|provision> [options]")
        return 0

    handler = _HANDLERS.get(command)
    if handler is None:
        print("ERROR: unknown core command '%s'" % command, file=sys.stderr)
        return 2

    return handler(rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
