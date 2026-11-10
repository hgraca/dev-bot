#!/usr/bin/env python3
"""search-memories — search the memory vault and return full file bodies.

Searches the QMD memory vault for files matching the given queries, then fetches
each matched file's full content (frontmatter stripped) and assembles all bodies
into a single output.

Usage:
  python3 search-memories.py --query "planning workflow"
  python3 search-memories.py --query "planning" --query "workflow"
  python3 search-memories.py --query "billing" --collection core --max-results 10
  python3 search-memories.py --query "billing" --format json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def find_devbot_root(start: Path) -> Path:
    """Walk up from start until we find src/agentic/."""
    p = start.resolve()
    for _ in range(10):
        if (p / "src" / "agentic" / "memory").is_dir():
            return p
        p = p.parent
    return start.resolve()


SCRIPT_DIR = Path(__file__).resolve().parent
# SEARCH_MEMORIES_DEV_BOT_ROOT overrides the devbot install root (hermetic
# tests: redirects the global-store index pair + provider config into a
# scratch sandbox), mirroring the SEARCH_MEMORIES_XDG_CACHE_HOME override.
DEVBOT_ROOT = Path(
    os.environ.get("SEARCH_MEMORIES_DEV_BOT_ROOT") or find_devbot_root(SCRIPT_DIR)
).resolve()


def _qmd_env() -> dict:
    """Build env for qmd subprocesses.

    XDG_CACHE_HOME is stripped so production searches always hit the user's
    default qmd index (where the reindex hook writes). Tests can opt into an
    isolated index by setting SEARCH_MEMORIES_XDG_CACHE_HOME, which is
    forwarded as XDG_CACHE_HOME (used by the e2e BATS suite).
    """
    env = os.environ.copy()
    env.pop("XDG_CACHE_HOME", None)
    override = os.environ.get("SEARCH_MEMORIES_XDG_CACHE_HOME")
    if override:
        env["XDG_CACHE_HOME"] = override
    return env


def run_qmd_cli(args: list[str]) -> tuple[str | None, str | None]:
    """Run qmd CLI with given args. Returns (stdout, error_message)."""
    qmd_path = shutil.which("qmd")
    if not qmd_path:
        return None, "qmd CLI not found. Install with: npm install -g @tobilu/qmd"
    try:
        result = subprocess.run(
            [qmd_path] + args,
            capture_output=True,
            text=True,
            timeout=30,
            env=_qmd_env(),
        )
        if result.returncode != 0:
            return None, result.stderr.strip() or result.stdout.strip()
        return result.stdout.strip(), None
    except FileNotFoundError:
        return None, "qmd CLI not found. Install with: npm install -g @tobilu/qmd"
    except subprocess.TimeoutExpired:
        return None, "qmd search timed out after 30s"


def _read_jsonc_scalar(cfg_path: Path, key: str, section: str = "") -> str:
    """Read a scalar key from a JSONC config via read_jsonc.py.

    read_jsonc.py is the canonical JSONC parser (handles full-line, inline
    and block comments) — ad-hoc comment stripping silently breaks on inline
    or /* */ comments. Returns "" when the file or reader is missing, the key
    is absent, or parsing fails.
    """
    reader = DEVBOT_ROOT / "src" / "_shared" / "read_jsonc.py"
    if not cfg_path.is_file() or not reader.is_file():
        return ""
    try:
        args = ["python3", str(reader), str(cfg_path)]
        if section:
            args.append(section)
        args.append(key)
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return ""


def resolve_provider() -> str:
    """Resolve the active memory-search engine module: "qmd" or "mdctx".

    SEARCH_MEMORIES_PROVIDER env override wins (hermetic tests, mirrors
    SEARCH_MEMORIES_XDG_CACHE_HOME). Otherwise the global-only key
    memory_search_provider is read from <DEVBOT_ROOT>/.devbot.global.jsonc via
    read_jsonc.py (JSONC-aware). Absent or invalid => "mdctx" — must agree with
    _devbot_get_memory_search_provider in src/_shared/functions.sh.
    """
    override = os.environ.get("SEARCH_MEMORIES_PROVIDER")
    if override in ("qmd", "mdctx"):
        return override

    provider = _read_jsonc_scalar(DEVBOT_ROOT / ".devbot.global.jsonc", "memory_search_provider")
    return provider if provider in ("qmd", "mdctx") else "mdctx"


# Outer cap (seconds) for the query-time freshness check. It must exceed the
# engine script's own bounds — its build-lock wait (REINDEX_ENSURE_WAIT,
# default 300s) plus a build budget; a real reindex has been observed taking
# ~10 minutes. The previous 300s default sat *below* the script's own wait, so
# python killed a legitimate refresh mid-build and the stale index stayed in
# place — the exact case the check exists to catch.
INDEX_ENSURE_TIMEOUT = int(os.environ.get("SEARCH_MEMORIES_ENSURE_TIMEOUT", "1800"))


def _kill_process_group(proc: subprocess.Popen) -> None:
    """SIGKILL the refresh's whole process group and reap it.

    The script runs in its own session (start_new_session), so its pgid is its
    pid. Killing only the direct child would orphan the engine grandchild
    (mdctx/qmd), leaving it running and holding the build lock.
    """
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        proc.kill()
    try:
        proc.communicate(timeout=10)
    except Exception:  # noqa: BLE001 — best-effort reap, never propagate
        pass


def index_engine_script() -> Path:
    """Path to the canonical memory-index engine (single source of truth)."""
    return DEVBOT_ROOT / "src" / "agentic" / "memory" / "tools" / "reindex-passive-memories.sh"


def ensure_index_current(project_root: Path, provider: str) -> tuple[bool, str]:
    """Make sure the memory index was built for the current checkout.

    Delegates the branch/provider/tree-sha comparison to the canonical engine
    script (`--ensure`), which no-ops when the index is already current and
    rebuilds synchronously when it is not — so a search after a branch switch
    (or a vault-changing pull) never reads a stale index.

    Fail-open: a missing script, a timeout, or a non-zero exit leaves the
    existing index in place, warns on stderr, and never blocks the search.
    SEARCH_MEMORIES_SKIP_INDEX_CHECK=1 disables the check (hermetic tests).
    Returns (ok, detail) where ok is True only when the index is confirmed
    current (status current/rebuilt/no-vault) — it means "the index is
    current", not merely "the process exited 0".
    """
    if os.environ.get("SEARCH_MEMORIES_SKIP_INDEX_CHECK"):
        return True, "skipped"

    script = index_engine_script()
    if not script.is_file():
        return True, "no-engine-script"

    env = os.environ.copy()
    env["DEVBOT_MEMORY_SEARCH_PROVIDER"] = provider
    try:
        proc = subprocess.Popen(
            ["bash", str(script), "--ensure"],
            cwd=str(project_root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            # Own session: a timeout must be able to reap the engine grandchild
            # (mdctx/qmd), not just the bash script.
            start_new_session=True,
        )
    except OSError as e:  # noqa: BLE001 — any spawn failure is fail-open
        detail = f"memory index refresh could not run: {e}"
        print(f"WARN: {detail}", file=sys.stderr)
        return False, detail

    try:
        stdout, stderr = proc.communicate(timeout=INDEX_ENSURE_TIMEOUT)
    except subprocess.TimeoutExpired:
        _kill_process_group(proc)
        detail = f"memory index refresh timed out after {INDEX_ENSURE_TIMEOUT}s"
        print(f"WARN: {detail}", file=sys.stderr)
        return False, detail

    if proc.returncode != 0:
        detail = (stderr or "").strip() or f"exit {proc.returncode}"
        print(f"WARN: memory index refresh failed: {detail}", file=sys.stderr)
        return False, detail

    out = (stdout or "").strip()
    try:
        payload = json.loads(out)
    except ValueError:
        payload = {}
    status = payload.get("status", "") if isinstance(payload, dict) else ""

    # Fail-open, but honest: the script exits 0 with {"status":"stale"} when it
    # could not refresh, so `ok` means "the index is current" — not merely "the
    # process exited 0". Surface the failure instead of silently serving a
    # possibly-stale index.
    if status == "stale":
        reason = payload.get("reason", "stale")
        print(f"WARN: memory index may be stale: {reason}", file=sys.stderr)
        return False, reason
    return status in ("current", "rebuilt", "no-vault"), (status or out)


def current_head(project_root: Path) -> str | None:
    """The checked-out commit, or the branch name on an unborn branch.

    A full SHA catches a same-branch commit landing during the search, which a
    branch name cannot. The symbolic-ref fallback covers a freshly initialised
    repository with no commit yet.
    """
    def _git(*args: str) -> str | None:
        try:
            result = subprocess.run(
                ["git", "-C", str(project_root), *args],
                capture_output=True,
                text=True,
                timeout=10,
            )
        except (OSError, subprocess.TimeoutExpired):
            return None
        if result.returncode != 0:
            return None
        return result.stdout.strip() or None

    sha = _git("rev-parse", "HEAD")
    branch = _git("symbolic-ref", "--short", "HEAD")
    if sha:
        # Same-SHA branch switches and detached HEAD moves are invisible to a
        # bare SHA; pair it with the symbolic ref (or "detached").
        return f"{sha} {branch or 'detached'}"
    return branch


def run_mdctx_cli(args: list[str]) -> tuple[str | None, str | None]:
    """Run mdctx CLI with given args. Returns (stdout, error_message)."""
    mdctx_path = shutil.which("mdctx")
    if not mdctx_path:
        return None, "mdctx CLI not found. Install with: npm install -g mdctx"
    try:
        result = subprocess.run(
            [mdctx_path] + args,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return None, result.stderr.strip() or result.stdout.strip()
        return result.stdout.strip(), None
    except FileNotFoundError:
        return None, "mdctx CLI not found. Install with: npm install -g mdctx"
    except subprocess.TimeoutExpired:
        return None, "mdctx search timed out after 30s"


def search_qmd(
    queries: list[str],
    collection: str,
    max_results: int,
    include_global: bool = True,
) -> tuple[list[dict] | None, str | None]:
    """Search QMD for each query and return merged, deduplicated results."""
    all_results: list[dict] = []
    seen_files: set[str] = set()

    for query in queries:
        cmd = ["search", query, "--json", "-n", str(max_results)]
        if collection:
            cmd += ["-c", collection]
        # Also search the shared global memory collection (covers latent/global symlink).
        # Single fixed name — QMD won't allow duplicate collections per path, and all
        # projects share the same global-memories store (storage/global-memories).
        global_cmd = (cmd + ["-c", "dev-bot-global"]) if include_global else cmd

        stdout, err = run_qmd_cli(global_cmd)
        # audit-01 (macOS host) FAIL: on a project whose dev-bot-global
        # collection was never registered (fresh install / partial reinit) qmd
        # errors "Collection not found: dev-bot-global" and the combined call
        # fails EVERY query. Degrade gracefully: retry without the global flag
        # so project-vault search still works.
        if (
            include_global
            and err
            and "Collection not found" in err
            and "dev-bot-global" in err
        ):
            stdout, err = run_qmd_cli(cmd)
        if err:
            return None, err
        if stdout is None:
            continue

        try:
            data = json.loads(stdout)
        except json.JSONDecodeError:
            return None, f"Failed to parse qmd output: {stdout[:500]}"

        if isinstance(data, dict) and data.get("results"):
            results = data["results"]
        elif isinstance(data, list):
            results = data
        else:
            continue

        for r in results:
            file_uri = r.get("file", "")
            if file_uri and file_uri not in seen_files:
                seen_files.add(file_uri)
                all_results.append(
                    {
                        "docid": r.get("docid", ""),
                        "score": r.get("score", 0),
                        "file": file_uri,
                        "title": r.get("title", ""),
                        "snippet": r.get("snippet", ""),
                    }
                )

    # Sort by score descending, limit
    all_results.sort(key=lambda r: r.get("score", 0), reverse=True)
    return all_results[:max_results], None


def search_qmd_scoped(
    queries: list[str],
    collections: list[str],
    max_results: int,
    include_global: bool = True,
) -> tuple[list[dict] | None, str | None]:
    """Search several qmd collections (the polyrepo read set) plus global.

    One `search_qmd` pass per collection — each also covers `dev-bot-global` —
    merged and deduplicated by file. A collection that was never registered
    ("Collection not found") is skipped rather than failing every query, so one
    un-indexed child project cannot break a polyrepo search.
    """
    merged: list[dict] = []
    seen: set[str] = set()
    any_success = False

    def _extend(results: list[dict] | None) -> None:
        for r in results or []:
            file_uri = r.get("file", "")
            if file_uri and file_uri not in seen:
                seen.add(file_uri)
                merged.append(r)

    for collection in collections:
        results, err = search_qmd(
            queries, collection, max_results, include_global=include_global
        )
        if err:
            if "Collection not found" in err:
                print(f"NOTICE: {err} — skipping collection {collection!r}", file=sys.stderr)
                continue
            return None, err
        any_success = True
        _extend(results)

    # Each per-collection call bundles `-c dev-bot-global`, but a missing
    # project collection fails that combined call — so when no collection
    # succeeded, search the shared global store on its own.
    if not any_success and include_global:
        results, err = search_qmd(
            queries, "dev-bot-global", max_results, include_global=False
        )
        if err and "Collection not found" not in err:
            return None, err
        _extend(results)

    merged.sort(key=lambda r: r.get("score", 0), reverse=True)
    return merged[:max_results], None


def resolve_devbot_dir(project_root: Path) -> str:
    """Resolve the devbot state dir for a project (bash: _devbot_get_project_dir).

    Project .devbot.project.jsonc wins, then global .devbot.global.jsonc,
    then ".agents" (the bash default). Used to locate the project latent vault
    for the mdctx engine (which resolves roots on disk, not qmd collections).
    """
    for cfg_path in (
        project_root / ".devbot.project.jsonc",
        DEVBOT_ROOT / ".devbot.global.jsonc",
    ):
        devbot_dir = _read_jsonc_scalar(cfg_path, "devbot_dir")
        if devbot_dir:
            return devbot_dir
    return ".agents"


def resolve_mdctx_indexes(
    project_root: Path,
) -> list[tuple[Path, Path]]:
    """Locate the (docs root, index file) pairs searchable under mdctx.

    mdctx builds one flat JSON index per real root (it does not follow
    symlinks — the project vault's latent/global symlink is therefore NOT
    covered by the project index). This mirrors search_qmd's dual-store
    contract (project collection + dev-bot-global): the project latent corpus
    and the shared global-memories store are each indexed and searched.

    Returns [(root_dir, index_file)]:
      - project: <project>/.agents/memory/latent + <project>/.mdctx/context-index.json
      - global:  <DEV_BOT_ROOT>/storage/global-memories + <DEV_BOT_ROOT>/storage/.mdctx/context-index.json
    """
    devbot_dir = resolve_devbot_dir(project_root)
    memory_root = project_root / devbot_dir / "memory" / "latent"
    project_pair = (memory_root, project_root / ".mdctx" / "context-index.json")
    global_pair = (
        DEVBOT_ROOT / "storage" / "global-memories",
        DEVBOT_ROOT / "storage" / ".mdctx" / "context-index.json",
    )
    return [project_pair, global_pair]


def _index_corpus_root(project_root: Path, index_file: Path) -> Path:
    """The root an mdctx index was built from: memory/latent/ or memory/.

    The branch record is authoritative when it carries a corpus marker:
    "latent" is the current corpus, while "memory" describes the older
    whole-memory index, read as-is until the rebuild replaces it. A legacy
    index has no such record, so its recorded root decides.
    """
    devbot_dir = resolve_devbot_dir(project_root)
    memory = project_root / devbot_dir / "memory"
    record = project_root / devbot_dir / "logs" / "memory-index-branch.json"
    try:
        data = json.loads(record.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    if data.get("corpus") == "latent":
        return memory / "latent"
    if data.get("corpus") == "memory":
        return memory
    try:
        index = json.loads(index_file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return memory / "latent"
    # mdctx records the directory it built from; trust it over any filename
    # heuristic (a legacy latent index can contain a work/note.md entry).
    root = index.get("root")
    if root:
        root_path = Path(root)
        if not root_path.is_absolute():
            # mdctx records the root relative to the index file.
            root_path = index_file.parent / root_path
        root_path = root_path.resolve()
        if root_path == memory.resolve():
            return memory
        if root_path == (memory / "latent").resolve():
            return memory / "latent"
    entries = index.get("entries", {})
    paths = entries.keys() if isinstance(entries, dict) else []
    if any(str(path).startswith(("latent/", "work/", "thinking/", "active/")) for path in paths):
        return memory
    return memory / "latent"


def _scoped_mdctx_pairs(
    project_roots: list[Path],
    collections: list[dict] | None = None,
) -> list[tuple[Path, Path, str, int, str]]:
    """(docs_root, index_file, kind, group, key) pairs for a read set.

    `group` is the project's position in the read set (focus projects first,
    then the polyrepo), so callers rank hits project-by-project instead of
    comparing corpus-relative BM25 scores across vaults. Projects whose mdctx
    index has not been built yet are skipped.

    When `collections` is None the legacy pair is returned (read-set project
    indexes + the global store). Otherwise global and custom collections come
    from the resolved config: the global index lives under `storage/.mdctx/`,
    and each custom collection gets its own shared index under
    `storage/.mdctx/collections/<key>.json`.
    """
    pairs: list[tuple[Path, Path, str, int, str]] = []
    selected_indexes = (
        None
        if collections is None
        else {
            str(Path(entry["index"]).resolve())
            for entry in collections
            if entry["kind"] == "project"
        }
    )
    if selected_indexes is None or selected_indexes:
        seen: set[str] = set()
        for group, root in enumerate(project_roots):
            root = Path(root)
            key = str(root)
            if key in seen:
                continue
            seen.add(key)
            index = root / ".mdctx" / "context-index.json"
            index_key = str(index.resolve())
            if selected_indexes is not None and index_key not in selected_indexes:
                continue
            if not index.is_file():
                continue
            configured = next(
                (
                    entry
                    for entry in (collections or [])
                    if entry["kind"] == "project"
                    and str(Path(entry["index"]).resolve()) == index_key
                ),
                None,
            )
            # The default collection is the latent corpus; only a genuinely
            # different configured path is an override. Comparing against the
            # latent root keeps a legacy whole-memory index readable through
            # _index_corpus_root until the rebuild replaces it.
            conventional = root / resolve_devbot_dir(root) / "memory" / "latent"
            if (
                configured is not None
                and Path(configured["path"]).resolve() != conventional.resolve()
            ):
                corpus_root = Path(configured["path"])
            else:
                corpus_root = _index_corpus_root(root, index)
            pairs.append((corpus_root, index, "project", group, "project"))

    if collections is None:
        global_index = DEVBOT_ROOT / "storage" / ".mdctx" / "context-index.json"
        if global_index.is_file():
            pairs.append(
                (
                    DEVBOT_ROOT / "storage" / "global-memories",
                    global_index,
                    "global",
                    -1,
                    "global",
                )
            )
        return pairs

    for entry in collections:
        kind = entry["kind"]
        if kind not in ("global", "custom"):
            continue
        index = Path(entry["index"])
        if not index.is_file():
            if kind == "custom":
                print(
                    f"NOTICE: collection '{entry['key']}' has no mdctx index at "
                    f"{index} — run reindex-memories",
                    file=sys.stderr,
                )
            continue
        group = -1 if kind == "global" else -2
        pairs.append((Path(entry["path"]), index, kind, group, entry["key"]))

    # Two logical keys naming the same corpus share one index; query it once.
    unique: list[tuple[Path, Path, str, int, str]] = []
    seen_indexes: set[str] = set()
    for pair in pairs:
        key = str(pair[1].resolve())
        if key in seen_indexes:
            continue
        seen_indexes.add(key)
        unique.append(pair)
    return unique


def search_mdctx(
    queries: list[str],
    project_root: Path,
    max_results: int,
    projects: list[Path] | None = None,
    collections: list[dict] | None = None,
) -> tuple[list[dict] | None, str | None]:
    """Search the mdctx project + global indexes for each query.

    mdctx search yields root-relative paths; each result is mapped to an
    absolute path under its docs root so body fetching is a plain disk read
    (no `mdctx get`). Results from both stores are merged and deduplicated by
    absolute path, mirroring search_qmd's dual-collection contract.

    Merging is **project-first** (audit-53 FAIL-1): mdctx BM25 scores are
    corpus-relative (IDF over each index's own document set), so a small
    project vault and the 613-file global store are not on a comparable scale
    — a raw-score merge (or a flat multiplier on it) lets global partial
    matches bury the project's full matches below the result window. The
    project vault's hits therefore rank first (sorted by their own score), and
    the global store fills the remaining slots — the project vault is never
    silent behind global noise.
    """
    read_projects = list(projects) if projects else [project_root]
    pairs = _scoped_mdctx_pairs(read_projects, collections)
    if not pairs:
        return None, (
            "mdctx index not found — run `devbot reinit` (or mdctx init.sh) so the "
            ".mdctx/context-index.json files are built first"
        )

    project_buckets: dict[int, list[dict]] = {}
    global_results: list[dict] = []
    custom_buckets: dict[str, list[dict]] = {}
    seen_files: set[str] = set()

    def _append(store_results: list[dict], root: Path, rel: str, score: float, title: str) -> None:
        abs_path = str((root / rel).resolve()) if not Path(rel).is_absolute() else rel
        if abs_path in seen_files:
            return
        # A stale index entry (note deleted from disk) must not surface as a
        # dangling "body not fetched" hit (audit-80 N3); the index catches up at
        # the next prune.
        if not Path(abs_path).is_file():
            return
        seen_files.add(abs_path)
        store_results.append(
            {
                "docid": "",
                "score": score,
                "file": abs_path,
                "title": title,
                "snippet": "",
            }
        )

    for query in queries:
        for root, index_file, kind, group, key in pairs:
            cmd = ["search", query, "--json", "-n", str(max_results), "-i", str(index_file)]
            stdout, err = run_mdctx_cli(cmd)
            if err:
                return None, err
            if stdout is None:
                continue
            try:
                data = json.loads(stdout)
            except json.JSONDecodeError:
                return None, f"Failed to parse mdctx output: {stdout[:500]}"

            if not isinstance(data, list):
                continue

            if kind == "global":
                store_results = global_results
            elif kind == "custom":
                store_results = custom_buckets.setdefault(key, [])
            else:
                store_results = project_buckets.setdefault(group, [])
            for r in data:
                rel = r.get("path", "")
                if not rel:
                    continue
                _append(store_results, root, rel, r.get("score", 0), r.get("title", ""))

    # Rank project-by-project in read-set order (focus projects, then the
    # polyrepo), each internally by score, then the global store — never
    # compare corpus-relative BM25 scores across vaults (audit-53).
    ordered: list[dict] = []
    for group in range(len(read_projects)):
        bucket = project_buckets.get(group, [])
        bucket.sort(key=lambda r: r.get("score", 0), reverse=True)
        ordered.extend(bucket)
    global_results.sort(key=lambda r: r.get("score", 0), reverse=True)

    # Custom collections are their own corpora too: never compare their
    # corpus-relative scores against the vaults or the global store. They rank
    # last, in key order.
    custom_results: list[dict] = []
    for key in sorted(custom_buckets):
        bucket = custom_buckets[key]
        bucket.sort(key=lambda r: r.get("score", 0), reverse=True)
        custom_results.extend(bucket)

    # audit-52/55/56 NOTE: mdctx indexes a capped set of extracted keywords per
    # file — an exact literal (error code, slug, numeric/dashed marker, filename
    # stem) is usually NOT among them, so a keyword search silently misses files
    # that plainly contain the term. When the keyword index yields nothing, fall
    # back to a bounded full-text substring scan of the vault roots.
    if not ordered and not global_results and not custom_results:
        return _literal_fallback(queries, [(r, i) for r, i, *_ in pairs], max_results), None

    merged = (ordered + global_results + custom_results)[:max_results]
    return merged, None


def _literal_fallback(
    queries: list[str], pairs: list[tuple[Path, Path]], max_results: int
) -> list[dict]:
    """Direct substring scan of the vault roots (audit-52/55/56 exact-literal gap).

    Runs only when the mdctx keyword search returned nothing. Scans each
    indexed root's `.md`/`.mdx` files (devbot vaults are small — well under a
    second for ~1000 files) for a case-insensitive substring of the query.
    Results carry score 0.0 — below any keyword hit, but the fallback only runs
    when there were none. Symlinked files are skipped (mdctx does not follow
    symlinks; the global store is scanned through its real root).
    """
    seen: set[str] = set()
    hits: list[dict] = []
    for query in queries:
        q = (query or "").lower().strip()
        if not q:
            continue
        for root, _index_file in pairs:
            if not root.is_dir():
                continue
            for p in root.rglob("*"):
                if not (p.is_file() and p.suffix.lower() in (".md", ".mdx")):
                    continue
                if p.is_symlink():
                    continue
                try:
                    text = p.read_text(encoding="utf-8", errors="replace")
                except Exception:
                    continue
                if q in text.lower():
                    key = str(p.resolve())
                    if key in seen:
                        continue
                    seen.add(key)
                    hits.append(
                        {
                            "docid": "",
                            "score": 0.0,
                            "file": key,
                            "title": p.stem,
                            "snippet": "",
                        }
                    )
                    if len(hits) >= max_results:
                        return hits
    return hits


def _frontmatter_block(content: str) -> str:
    """Return the YAML frontmatter body (between the --- delimiters), or ''."""
    if not content.startswith("---"):
        return ""
    end = content.find("\n---", 3)
    if end == -1:
        return ""
    return content[3:end]


def _strip_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] in "\"'" and value[-1] == value[0]:
        return value[1:-1]
    return value


def extract_superseded_by(content: str) -> list[str]:
    """Read `superseded_by:` paths from a file's YAML frontmatter.

    Handles the inline-list, single-value, and block-list forms; returns [] when
    the key is absent or the file has no frontmatter.
    """
    lines = _frontmatter_block(content).splitlines()
    for i, line in enumerate(lines):
        match = re.match(r"\s*superseded_by:\s*(.*)$", line)
        if not match:
            continue
        value = match.group(1).strip()
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            if not inner:
                return []
            return [p for p in (_strip_quotes(x.strip()) for x in inner.split(",")) if p]
        if value:
            return [_strip_quotes(value)]
        collected = []
        for follow in lines[i + 1 :]:
            item = follow.strip()
            if not item.startswith("- "):
                break
            collected.append(_strip_quotes(item[2:].strip()))
        return [p for p in collected if p]
    return []


def supersession_notice(content: str) -> str | None:
    """Body-visible warning naming the note(s) that supersede this one.

    Frontmatter is stripped from what search-memories returns, so a
    `superseded_by:` key would otherwise be invisible to the reader.
    """
    paths = extract_superseded_by(content)
    if not paths:
        return None
    refs = ", ".join(f"`{p}`" for p in paths)
    return f"> **SUPERSEDED by** {refs} — read the replacement before relying on this."


def _with_supersession_notice(content: str) -> str:
    """Strip frontmatter, then prepend a supersession warning when present."""
    body = strip_yaml_frontmatter(content).strip()
    notice = supersession_notice(content)
    if notice:
        return f"{notice}\n\n{body}"
    return body


def strip_yaml_frontmatter(content: str) -> str:
    """Strip YAML frontmatter (--- ... ---) from file content."""
    if not content.startswith("---"):
        return content
    end = content.find("\n---", 3)
    if end == -1:
        return content
    return content[end + 4 :].lstrip("\n")


def fetch_file_body(file_uri: str) -> tuple[str | None, str | None]:
    """Fetch full file content via `qmd get` and strip frontmatter."""
    stdout, err = run_qmd_cli(["get", file_uri])
    if err:
        return None, err
    return _with_supersession_notice(stdout or ""), None


def fetch_mdctx_body(file_path: str) -> tuple[str | None, str | None]:
    """Read a markdown file directly from disk (mdctx results are fs paths).

    mdctx ships no `get` subcommand — its search returns root-relative paths,
    so the full body is a plain file read plus the same frontmatter strip the
    qmd path applies to `qmd get` output.
    """
    try:
        content = Path(file_path).read_text(encoding="utf-8", errors="replace")
    except Exception as e:  # noqa: BLE001 — any read failure becomes a message
        return None, f"Error reading file {file_path}: {e}"
    return _with_supersession_notice(content), None


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------


def format_markdown(results: list[dict], note: str | None = None) -> str:
    if not results:
        cleaned = re.sub(r"\s+", " ", note).strip() if note else ""
        suffix = f" — {cleaned}" if cleaned else ""
        return f"# Memories\n\n_No memory vault matches found{suffix}._\n"
    parts = ["# Memories", ""]
    for r in results:
        file_uri = r.get("file", "")
        body = r.get("_body")
        if body is None:
            parts.append(f"_Error reading file `{file_uri}`: body not fetched_")
        elif body:
            parts.append(body)
        else:
            parts.append("_(empty file)_")
        if file_uri:
            parts.append("")
            parts.append(f"_File: `{file_uri}`_")
        parts.append("")
        parts.append("---")
        parts.append("")

    return "\n".join(parts)


def format_json(results: list[dict], note: str | None = None) -> dict:
    # Each memory carries its source file (qmd uri or absolute path) so
    # callers can tell project-vs-global provenance (audit-51/52 NOTE).
    memories = []
    for r in results:
        memories.append({"file": r.get("file", ""), "body": r.get("_body") or ""})
    payload: dict[str, object] = {"memories": memories}
    if note and not memories:
        payload["note"] = note
    return payload


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def resolve_collection(project_root: Path) -> str:
    """Resolve QMD collection name from .devbot.project.jsonc.

    Fallback mirrors qmd/init.sh exactly: when project_name is missing or
    empty, the collection is the project directory basename. The two files
    must agree — search-memories queries the collection qmd/init.sh
    registered, so a hardcoded fallback ("devbot") broke every default
    invocation ("Collection not found: devbot", audit-32/33).
    """
    project_name = _read_jsonc_scalar(project_root / ".devbot.project.jsonc", "project_name")
    return project_name or project_root.name


def _import_memory_collections():
    """Import the shared collection resolver from this checkout (fail-open None)."""
    shared = Path(__file__).resolve().parents[4] / "_shared"
    if shared.is_dir() and str(shared) not in sys.path:
        sys.path.insert(0, str(shared))
    try:
        import importlib

        return importlib.import_module("memory_collections")
    except Exception:  # noqa: BLE001 — an old install lacks the module
        return None


def _builtin_collections(project_root: Path) -> list[dict]:
    """The pre-config default: the project latent corpus + the shared global store."""
    devbot_dir = resolve_devbot_dir(project_root)
    memory = project_root / devbot_dir / "memory" / "latent"
    global_dir = DEVBOT_ROOT / "storage" / "global-memories"
    return [
        {
            "key": "project",
            "path": str(memory),
            "semantic": False,
            "physical": resolve_collection(project_root),
            "kind": "project",
            "source": "default",
            "exists": memory.is_dir(),
            "index": str(project_root / ".mdctx" / "context-index.json"),
        },
        {
            "key": "global",
            "path": str(global_dir),
            "semantic": False,
            "physical": "dev-bot-global",
            "kind": "global",
            "source": "default",
            "exists": global_dir.is_dir(),
            "index": str(DEVBOT_ROOT / "storage" / ".mdctx" / "context-index.json"),
        },
    ]


def load_collections_for(project_root: Path) -> list[dict]:
    """Resolve memory_collections for one project, falling back to the built-ins."""
    resolver = _import_memory_collections()
    if resolver is None:
        return _builtin_collections(project_root)
    try:
        return resolver.load_collections(project_root, DEVBOT_ROOT)
    except Exception as exc:  # noqa: BLE001 — a bad config degrades, never breaks search
        print(f"ERROR: {exc} — using the built-in collections", file=sys.stderr)
        return _builtin_collections(project_root)


def session_collections(project_root: Path, read_projects: list[Path]) -> list[dict]:
    """Collections for a search: per-read-project `project` slots + global/custom.

    A polyrepo session takes the `project` slot from each project it reads
    (the focus scope), while global and custom collections come from the
    session project's config (plus the global config). A normal session's read
    set is just itself, so this is the full merged set.
    """
    session = load_collections_for(project_root)
    entries = [entry for entry in session if entry["kind"] in ("global", "custom")]
    projects = []
    for read_project in read_projects:
        source = session if str(read_project) == str(project_root) else load_collections_for(read_project)
        entry = next((c for c in source if c["kind"] == "project"), None)
        if entry is not None:
            projects.append(entry)
    return projects + entries


def _import_shared(name: str):
    """Import a module from <DEVBOT_ROOT>/src/_shared (fail-open None).

    The path-to-project resolver lives there so bash and Python share one
    implementation (see src/_shared/resolve_project.py).
    """
    shared = DEVBOT_ROOT / "src" / "_shared"
    if shared.is_dir() and str(shared) not in sys.path:
        sys.path.insert(0, str(shared))
    try:
        import importlib

        return importlib.import_module(name)
    except Exception:  # noqa: BLE001 — an old/sandboxed install lacks it
        return None


def resolve_polyrepo(project_root: Path) -> bool:
    """Whether the project is a polyrepo (project-first, global-fallback)."""
    value = _read_jsonc_scalar(project_root / ".devbot.project.jsonc", "type", "workspace")
    if not value:
        value = _read_jsonc_scalar(DEVBOT_ROOT / ".devbot.global.jsonc", "type", "workspace")
    return value == "polyrepo"


def resolve_registered_project(path: Path) -> Path | None:
    """The registered project (global `projects`) containing `path`, or None."""
    resolver = _import_shared("resolve_project")
    if resolver is None:
        return None
    projects = resolver.load_projects(str(DEVBOT_ROOT / ".devbot.global.jsonc"))
    match = resolver.resolve_project(str(path), projects)
    return Path(match) if match else None


def polyrepo_read_projects(project_root: Path, focus_paths: list[str]) -> list[Path]:
    """Project read set for a polyrepo session.

    Focus projects (resolved from the touched paths) first, then the polyrepo
    itself. Untouched siblings are never included. The global store is added by
    the engine, not here.
    """
    roots: list[Path] = []
    seen: set[str] = set()
    for focus in focus_paths or []:
        project = resolve_registered_project(Path(focus))
        if project is None:
            continue
        key = str(project)
        if key in seen:
            continue
        seen.add(key)
        roots.append(project)
    if str(project_root) not in seen:
        roots.append(project_root)
    return roots


def main() -> None:
    parser = argparse.ArgumentParser(
        description="search-memories: search memory vault and return full file bodies"
    )
    parser.add_argument(
        "--query",
        action="append",
        required=True,
        help="Search query (can be specified multiple times)",
    )
    parser.add_argument(
        "--collection",
        default="",
        help=(
            "configured collection key (or physical name) to search exclusively; "
            "qmd also accepts an ad-hoc registered collection name"
        ),
    )
    parser.add_argument(
        "--focus",
        action="append",
        default=[],
        help=(
            "Path the session is touching (file or dir; repeatable). In a "
            "polyrepo session it selects the project(s) whose vault is searched "
            "alongside the polyrepo and the global store; ignored otherwise."
        ),
    )
    parser.add_argument(
        "--max-results",
        type=int,
        default=5,
        help="Maximum number of matched files to return (default: 5)",
    )
    parser.add_argument(
        "--format",
        choices=["markdown", "json"],
        default="markdown",
        help="Output format (default: markdown)",
    )
    args = parser.parse_args()

    project_root = Path(os.getcwd())
    provider = resolve_provider()

    # A polyrepo session scopes memory to the projects the session touches
    # (from --focus) plus itself; a normal project keeps its single vault.
    polyrepo = resolve_polyrepo(project_root)
    if polyrepo:
        read_projects = polyrepo_read_projects(project_root, args.focus)
    else:
        read_projects = [project_root]

    # Branch awareness: never query an index built for a different checkout.
    # The canonical engine script no-ops when the recorded {branch, provider,
    # tree_sha} matches and rebuilds synchronously when it does not. Fail-open
    # (a failed refresh only warns — the search proceeds). Run per project in
    # the read set so a sibling's index is current before it is queried.
    index_ok = True
    index_detail = ""
    heads_before = {str(project): current_head(project) for project in read_projects}
    for read_project in read_projects:
        ok, detail = ensure_index_current(read_project, provider)
        if not ok:
            index_ok = False
            index_detail = detail

    # Resolve the configured collections for this session. A normal project
    # searches its own vault + the global store + configured customs; a
    # polyrepo scopes `project` slots to the read set but always searches
    # global and custom collections.
    collections = session_collections(project_root, read_projects)
    if args.collection:
        # A logical key wins over a physical name: `project_name` can equal a
        # custom key, and selecting the key must not also select the vault.
        selected = [
            entry for entry in collections if entry["key"] == args.collection
        ]
        if not selected:
            selected = [
                entry
                for entry in collections
                if entry["physical"] == args.collection
            ]
        if selected:
            collections = selected
        elif provider == "qmd":
            # Legacy: --collection may name an ad-hoc qmd collection registered
            # outside memory_collections (the qmd skill documents this).
            collections = [
                {
                    "key": args.collection,
                    "path": "",
                    "semantic": False,
                    "physical": args.collection,
                    "kind": "custom",
                    "source": "explicit",
                    "exists": True,
                }
            ]
        else:
            print(
                f"ERROR: collection '{args.collection}' is not configured",
                file=sys.stderr,
            )
            sys.exit(1)
    include_global = not bool(args.collection)
    global_exists = any(
        entry["kind"] == "global" and entry["exists"] for entry in collections
    )
    include_global = include_global and global_exists
    for entry in collections:
        if not entry["exists"]:
            print(
                f"NOTICE: collection '{entry['key']}' path does not exist: "
                f"{entry['path']}",
                file=sys.stderr,
            )

    # Engine dispatch: qmd and mdctx are interchangeable behind this CLI,
    # selected by memory_search_provider. Both consume the resolved collections.
    if provider == "mdctx":
        results, err = search_mdctx(
            args.query,
            project_root,
            args.max_results,
            projects=read_projects,
            collections=collections,
        )
        body_fetch = fetch_mdctx_body
    else:
        semantic_keys = [entry["key"] for entry in collections if entry["semantic"]]
        if semantic_keys:
            print(
                "NOTICE: semantic is reserved (qmd runs BM25-only); ignoring for: "
                + ", ".join(semantic_keys),
                file=sys.stderr,
            )
        # `global` is bundled into every search_qmd call; search it once by
        # leaving it out of the per-collection list.
        by_name: dict[str, str] = {}
        for entry in collections:
            # A configured root that no longer exists must not fall back to a
            # stale qmd registration pointing at the old corpus.
            if not entry["exists"]:
                continue
            if entry["kind"] == "global":
                if not include_global:
                    by_name[entry["physical"]] = entry["path"]
                continue
            name = entry["physical"]
            if name in by_name and by_name[name] != entry["path"]:
                print(
                    f"WARN: qmd collection {name!r} maps to both "
                    f"{by_name[name]} and {entry['path']}; searching it once",
                    file=sys.stderr,
                )
                continue
            by_name[name] = entry["path"]
        results, err = search_qmd_scoped(
            args.query,
            list(by_name),
            args.max_results,
            include_global=include_global,
        )
        body_fetch = fetch_file_body

    if err:
        if args.format == "json":
            engine_code = "MDCTX" if provider == "mdctx" else "QMD"
            print(
                json.dumps(
                    {"status": "error", "code": f"{engine_code}_SEARCH_FAILED", "message": err}
                )
            )
        else:
            print(f"Error: {err}", file=sys.stderr)
        sys.exit(1)

    results = results or []

    # Deduplicate by body content after fetching
    seen_bodies: set[str] = set()
    unique_results: list[dict] = []
    for r in results:
        file_uri = r.get("file", "")
        body, _ = body_fetch(file_uri)
        body_key = (body or "").strip()
        if body_key and body_key in seen_bodies:
            continue
        if body_key:
            seen_bodies.add(body_key)
        r = dict(r)
        r["_body"] = body
        unique_results.append(r)
    results = unique_results

    # Final HEAD snapshot after search and body retrieval: a checkout change
    # during those operations can mix indexed paths with another tree's files.
    for read_project in read_projects:
        key = str(read_project)
        head_before = heads_before.get(key)
        head_after = current_head(read_project)
        if head_before and head_after and head_before != head_after:
            drift = (
                f"HEAD moved from {head_before} to {head_after} during the search; "
                "re-check the branch before committing"
            )
            print(f"WARN: {drift}", file=sys.stderr)
            index_ok = False
            index_detail = f"{index_detail}; {drift}" if index_detail else drift

    note = None if index_ok else f"index may be stale ({index_detail})"
    if args.format == "json":
        print(json.dumps(format_json(results, note), indent=2))
    else:
        print(format_markdown(results, note))


if __name__ == "__main__":
    main()
