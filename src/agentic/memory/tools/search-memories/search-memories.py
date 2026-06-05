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
DEVBOT_ROOT = find_devbot_root(SCRIPT_DIR)


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
        # projects share the same global-memories store.
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


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------


def format_markdown(results: list[dict]) -> str:
    if not results:
        return "# Memories\n\n_No memory vault matches found._\n"
    parts = ["# Memories", ""]
    for r in results:
        file_uri = r.get("file", "")
        if "_body" in r:
            body, err = r["_body"], None
        else:
            body, err = fetch_file_body(file_uri)
        if err:
            parts.append(f"_Error reading file `{file_uri}`: {err}_")
        elif body:
            parts.append(body)
        else:
            parts.append("_(empty file)_")
        parts.append("")
        parts.append("---")
        parts.append("")

    return "\n".join(parts)


def format_json(results: list[dict]) -> dict:
    memories = []
    for r in results:
        file_uri = r.get("file", "")
        body = r["_body"] if "_body" in r else fetch_file_body(file_uri)[0]
        memories.append(body or "")
    return {"memories": memories}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def resolve_collection(project_root: Path) -> str:
    """Resolve QMD collection name from .devbot.project.jsonc."""
    cfg_path = project_root / ".devbot.project.jsonc"
    try:
        raw = cfg_path.read_text()
        stripped = "\n".join(
            line for line in raw.split("\n")
            if not line.strip().startswith("//")
        )
        data = json.loads(stripped)
        return data.get("project_name", "devbot")
    except Exception:
        return "devbot"


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
        help="QMD collection name (default: auto-detected from devbot.jsonc)",
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
    collection = args.collection or resolve_collection(project_root)
    queries: list[str] = args.query

    results, err = search_qmd(queries, collection, args.max_results)
    if err:
        if args.format == "json":
            print(
                json.dumps(
                    {"status": "error", "code": "QMD_SEARCH_FAILED", "message": err}
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
        body, _ = fetch_file_body(file_uri)
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
