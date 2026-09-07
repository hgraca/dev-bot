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
import shutil
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


def _read_jsonc_scalar(cfg_path: Path, key: str) -> str:
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
        result = subprocess.run(
            ["python3", str(reader), str(cfg_path), key],
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
    queries: list[str], collection: str, max_results: int
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
        cmd += ["-c", "dev-bot-global"]

        stdout, err = run_qmd_cli(cmd)
        if err:
            return None, err

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
    contract (project collection + dev-bot-global): the project latent vault
    and the shared global-memories store are each indexed and searched.

    Returns [(root_dir, index_file)]:
      - project: <project>/.agents/memory/latent  + <project>/.mdctx/context-index.json
      - global:  <DEV_BOT_ROOT>/storage/global-memories + <DEV_BOT_ROOT>/storage/.mdctx/context-index.json
    """
    devbot_dir = resolve_devbot_dir(project_root)
    latent = project_root / devbot_dir / "memory" / "latent"
    project_pair = (latent, project_root / ".mdctx" / "context-index.json")
    global_pair = (
        DEVBOT_ROOT / "storage" / "global-memories",
        DEVBOT_ROOT / "storage" / ".mdctx" / "context-index.json",
    )
    return [project_pair, global_pair]


def search_mdctx(
    queries: list[str], project_root: Path, max_results: int
) -> tuple[list[dict] | None, str | None]:
    """Search the mdctx project + global indexes for each query.

    mdctx search yields root-relative paths; each result is mapped to an
    absolute path under its docs root so body fetching is a plain disk read
    (no `mdctx get`). Results from both stores are merged and deduplicated by
    absolute path, mirroring search_qmd's dual-collection contract.
    """
    pairs = [(root, idx) for root, idx in resolve_mdctx_indexes(project_root) if idx.is_file()]
    if not pairs:
        return None, (
            "mdctx index not found — run `devbot reinit` (or mdctx init.sh) so the "
            ".mdctx/context-index.json files are built first"
        )

    all_results: list[dict] = []
    seen_files: set[str] = set()

    for query in queries:
        for root, index_file in pairs:
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

            for r in data:
                rel = r.get("path", "")
                if not rel:
                    continue
                abs_path = str((root / rel).resolve()) if not Path(rel).is_absolute() else rel
                if abs_path in seen_files:
                    continue
                seen_files.add(abs_path)
                all_results.append(
                    {
                        "docid": "",
                        "score": r.get("score", 0),
                        "file": abs_path,
                        "title": r.get("title", ""),
                        "snippet": "",
                    }
                )

    # Sort by score descending, limit
    all_results.sort(key=lambda r: r.get("score", 0), reverse=True)
    return all_results[:max_results], None


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
    return strip_yaml_frontmatter(stdout or "").strip(), None


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
    return strip_yaml_frontmatter(content).strip(), None


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------


def format_markdown(results: list[dict]) -> str:
    if not results:
        return "# Memories\n\n_No memory vault matches found._\n"
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


def format_json(results: list[dict]) -> dict:
    # Each memory carries its source file (qmd uri or absolute path) so
    # callers can tell project-vs-global provenance (audit-51/52 NOTE).
    memories = []
    for r in results:
        memories.append({"file": r.get("file", ""), "body": r.get("_body") or ""})
    return {"memories": memories}


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
        help="qmd collection name (qmd engine only; mdctx resolves roots on disk)",
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

    # Engine dispatch: qmd and mdctx are interchangeable behind this CLI,
    # selected by memory_search_provider. Each engine's search covers the
    # project vault AND the shared global store ("as it currently works" for
    # qmd's project collection + dev-bot-global).
    if provider == "mdctx":
        results, err = search_mdctx(args.query, project_root, args.max_results)
        body_fetch = fetch_mdctx_body
    else:
        collection = args.collection or resolve_collection(project_root)
        results, err = search_qmd(args.query, collection, args.max_results)
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

    if args.format == "json":
        print(json.dumps(format_json(results), indent=2))
    else:
        print(format_markdown(results))


if __name__ == "__main__":
    main()
