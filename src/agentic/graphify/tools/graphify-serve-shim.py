#!/usr/bin/env python3
"""Shim around `python -m graphify.serve` for MCP stdio servers.

Two jobs beyond the upstream server:

1. Swallow the BrokenPipeError the mcp SDK raises when the client closes the
   stdio pipe at session teardown (audit-18 NOTE).
2. Make an empty/in-flight graph explicit: start (or seed) a build on MCP
   launch, answer `graphify: not_ready (...)` while the graph has no nodes,
   and let upstream's mtime/size hot-reload serve the graph once it is written.

`graphify.serve` loads graph.json at startup and calls `_maybe_reload()` on
every tool handler, so a background build becomes visible without restarting
the server. While the graph is empty, wrapping the CallToolRequest handler is
what turns the silent "0 nodes" result into an actionable not_ready error.

Usage: python3 graphify-serve-shim.py <graph.json>
"""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
from pathlib import Path

PLACEHOLDER = '{"directed": true, "multigraph": false, "graph": {}, "nodes": [], "links": []}\n'
_note_cache: dict[str, object] = {"key": None, "nodes": 0}


def _devbot_root() -> Path:
    env = os.environ.get("DEVBOT_ROOT")
    if env:
        return Path(env).resolve()
    # <devbot>/src/agentic/graphify/tools/graphify-serve-shim.py
    return Path(__file__).resolve().parents[4]


def _project_root(graph_file: Path) -> Path:
    return graph_file.resolve().parent.parent


def _node_count(graph_file: Path) -> int:
    try:
        data = json.loads(graph_file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return 0
    nodes = data.get("nodes", [])
    return len(nodes) if isinstance(nodes, list) else 0


def _nodes(graph_file: Path) -> int:
    """Node count, cached by mtime+size so tool calls do not reparse 2 MB."""
    try:
        stat = graph_file.stat()
    except OSError:
        return 0
    key = (str(graph_file), stat.st_mtime_ns, stat.st_size)
    if _note_cache.get("key") == key:
        cached = _note_cache.get("nodes")
        return cached if isinstance(cached, int) else 0
    count = _node_count(graph_file)
    _note_cache["key"] = key
    _note_cache["nodes"] = count
    return count


def _build_in_progress(project_root: Path) -> bool:
    pid_file = project_root / "graphify-out" / ".graphify-update.pid"
    try:
        pid = int(pid_file.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _last_build_failed(project_root: Path) -> bool:
    log = project_root / "graphify-out" / ".graphify-update.log"
    try:
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return False
    for line in reversed(lines):
        if "finished (exit " in line:
            return "finished (exit 0)" not in line
    return False


def _indexing_disabled(project_root: Path) -> bool:
    ignore = project_root / ".graphifyignore"
    try:
        lines = [
            line.strip()
            for line in ignore.read_text(encoding="utf-8", errors="replace").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
    except OSError:
        return False
    # `/*` with no negations is a deliberately disabled graph. The managed
    # source scope writes `/*` plus `!src`, which is not disabled.
    return "/*" in lines and not any(line.startswith("!") for line in lines)


def _seed_from_main(project_root: Path, graph_file: Path, main_root: Path | None = None) -> bool:
    """Seed an empty worktree graph from the main checkout.

    graphify stores source_file as a project-relative path, so a copy is safe;
    the background update then refreshes it for the worktree's branch.
    """
    if _nodes(graph_file) > 0:
        return False
    if main_root is None:
        try:
            common = subprocess.check_output(
                ["git", "-C", str(project_root), "rev-parse", "--git-common-dir"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        except (OSError, subprocess.CalledProcessError):
            return False
        if not common:
            return False
        main_root = (project_root / common).resolve().parent if not Path(common).is_absolute() else Path(common).resolve().parent
    if main_root.resolve() == project_root.resolve():
        return False
    source = main_root / "graphify-out" / "graph.json"
    if _node_count(source) <= 0:
        return False
    try:
        graph_file.parent.mkdir(parents=True, exist_ok=True)
        tmp = graph_file.with_suffix(".seed.tmp")
        tmp.write_bytes(source.read_bytes())
        os.replace(tmp, graph_file)
    except OSError:
        return False
    print(f"[graphify] seeded graph from {source}", file=sys.stderr)
    return True


def _start_update(project_root: Path) -> None:
    if _indexing_disabled(project_root):
        return
    runner = _devbot_root() / "src" / "agentic" / "graphify" / "tools" / "graphify-update-bg.sh"
    if not runner.is_file():
        return
    try:
        subprocess.Popen(
            ["bash", str(runner), str(project_root)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            cwd=str(project_root),
        )
    except OSError:
        pass


def _status(project_root: Path, graph_file: Path) -> tuple[str, str]:
    if _nodes(graph_file) > 0:
        return "ready", ""
    if _indexing_disabled(project_root):
        return "disabled", "graph indexing is disabled for this project (.graphifyignore); skip graph queries"
    if _build_in_progress(project_root):
        return "building", "the graph is being built from the current checkout; retry in a few seconds"
    if _last_build_failed(project_root):
        return "failed", "the last graph build failed; see graphify-out/.graphify-update.log, then retry or skip"
    return "empty", "no graph is available yet; run `graphify update .` or retry shortly"


def _ensure_placeholder(graph_file: Path) -> None:
    if graph_file.exists():
        return
    try:
        graph_file.parent.mkdir(parents=True, exist_ok=True)
        graph_file.write_text(PLACEHOLDER, encoding="utf-8")
    except OSError:
        pass


def _is_broken_pipe(exc: BaseException) -> bool:
    if isinstance(exc, BrokenPipeError):
        return True
    return any(_is_broken_pipe(e) for e in getattr(exc, "exceptions", ()) or ())


async def _run(graph_file: Path, project_root: Path) -> None:
    import graphify.serve as graphify_serve

    server = graphify_serve._build_server(str(graph_file))
    from mcp import types
    from mcp.server.stdio import stdio_server
    original = server.request_handlers[types.CallToolRequest]

    async def guarded(request):
        state, reason = _status(project_root, graph_file)
        if state != "ready":
            return types.ServerResult(
                types.CallToolResult(
                    content=[
                        types.TextContent(
                            type="text",
                            text=f"graphify: not_ready ({state}) — {reason}",
                        )
                    ],
                    isError=True,
                )
            )
        return await original(request)

    server.request_handlers[types.CallToolRequest] = guarded

    async with stdio_server() as streams:
        await server.run(streams[0], streams[1], server.create_initialization_options())


def main(argv: list[str]) -> int:
    graph_arg = argv[1] if len(argv) > 1 else "graphify-out/graph.json"
    graph_file = Path(graph_arg).resolve()
    project_root = _project_root(graph_file)

    _ensure_placeholder(graph_file)
    if _nodes(graph_file) == 0:
        _seed_from_main(project_root, graph_file)
    if not _build_in_progress(project_root):
        _start_update(project_root)

    try:
        import graphify.serve as graphify_serve

        if hasattr(graphify_serve, "_filter_blank_stdin"):
            graphify_serve._filter_blank_stdin()
        asyncio.run(_run(graph_file, project_root))
    except BaseException as exc:
        if _is_broken_pipe(exc):
            return 0
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
