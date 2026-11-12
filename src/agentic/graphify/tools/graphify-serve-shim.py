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
import time
from pathlib import Path
from typing import Any

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


def _resolve_project_graph(target: str) -> Path | None:
    """Resolve a path to its owning registered project's graph file.

    A polyrepo session is rooted at the container, where `graphify-out/` holds
    no code and therefore no nodes; the graph that answers a question about
    `core/app/...` lives in `core/`. Resolution goes through the same registry
    `devbot tool project-for-path` uses, so the two cannot disagree.
    """
    try:
        # The registry helper ships beside this file, so import it from the
        # install tree; only the project list comes from the configured root.
        sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "_shared"))
        import resolve_project  # noqa: PLC0415

        config = _devbot_root() / ".devbot.global.jsonc"
        projects = resolve_project.load_projects(str(config))
        owner = resolve_project.resolve_project(target, projects)
    except Exception:
        return None
    if not owner:
        return None
    return Path(owner) / "graphify-out" / "graph.json"


def _graph_for(project_arg, default_graph: Path) -> Path:
    """The requested project's graph, else the session project's own graph."""
    if isinstance(project_arg, str) and project_arg.strip():
        resolved = _resolve_project_graph(project_arg.strip())
        if resolved is not None:
            return resolved
    return default_graph


def _head(project_root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(project_root), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


# `_stale` runs on every tool call, and its HEAD probe forks git. A short TTL
# keeps a tool-heavy session from paying that per request while still noticing a
# commit within half a minute.
_STALE_TTL_SECONDS = 30
_stale_cache: dict[str, tuple[float, bool]] = {}


def _stale(project_root: Path) -> bool:
    """True when the graph was built for a different commit than HEAD.

    `graphify-update-bg.sh` records the SHA it built from; a mismatch means
    commits landed since. Nothing else refires the build — the commit trigger
    is not wired into any harness — so the query path is where freshness has to
    be enforced.
    """
    key = str(project_root)
    now = time.monotonic()
    cached = _stale_cache.get(key)
    if cached is not None and now - cached[0] < _STALE_TTL_SECONDS:
        return cached[1]
    record = project_root / "graphify-out" / ".graphify-head"
    try:
        recorded = record.read_text(encoding="utf-8").strip()
    except OSError:
        recorded = ""
    if not recorded:
        # A graph that predates the marker cannot claim to be current. The
        # session graph gets an unconditional launch-time update, but a routed
        # child only reaches the per-call path — without this it would stay
        # stale forever. One bootstrap build writes the marker.
        value = _nodes(project_root / "graphify-out" / "graph.json") > 0
        if not value:
            _stale_cache[key] = (now, False)
        else:
            _stale_cache.pop(key, None)
        return value
    head = _head(project_root)
    value = bool(head and head != recorded)
    if value:
        # Never cache a stale verdict: the build it triggers writes a new
        # record within seconds, and a cached True would keep reporting stale
        # (and keep a rebuild checked for) until the TTL expired.
        _stale_cache.pop(key, None)
    else:
        _stale_cache[key] = (now, False)
    return value


def _prepare(graph_file: Path) -> None:
    """Make an empty graph build, and start a build when none is running."""
    project_root = _project_root(graph_file)
    _ensure_placeholder(graph_file)
    if _nodes(graph_file) == 0:
        _seed_from_main(project_root, graph_file)
    if _build_in_progress(project_root):
        return
    if _nodes(graph_file) == 0 or _stale(project_root):
        _start_update(project_root)


def _not_ready(types, state: str, graph_file: Path, reason: str):
    """An honest error naming the graph that is not ready."""
    return types.ServerResult(
        types.CallToolResult(
            content=[
                types.TextContent(
                    type="text",
                    text=(
                        f"graphify: not_ready ({state}) for {_project_root(graph_file)} — {reason}"
                    ),
                )
            ],
            isError=True,
        )
    )


async def _run(graph_file: Path, project_root: Path) -> None:
    import graphify.serve as graphify_serve

    server = graphify_serve._build_server(str(graph_file))
    from mcp import types
    from mcp.server.stdio import stdio_server

    # graphify.serve binds ONE graph at build time, so a second project needs a
    # second instance. Kept per resolved graph file, built lazily on first use.
    instances: dict[Path, Any] = {}

    def instance_for(target: Path):
        if target not in instances:
            _prepare(target)
            other = graphify_serve._build_server(str(target))
            instances[target] = other.request_handlers[types.CallToolRequest]
        return instances[target]

    original = server.request_handlers[types.CallToolRequest]

    async def guarded(request):
        args = getattr(request.params, "arguments", None) or {}
        explicit = args.get("project") if isinstance(args, dict) else None
        target = _graph_for(explicit, graph_file)
        # Prepare BEFORE the status check: a child whose graph is missing or
        # empty would otherwise report not_ready forever, because _prepare (the
        # only thing that starts a build) sits behind the early return.
        _prepare(target)
        state, reason = _status(_project_root(target), target)
        # A rebuild being under way is not a reason to refuse a graph that
        # already has nodes: the commit that triggered it left the previous
        # graph perfectly usable, and erroring would take the tool away for
        # the length of every rebuild.
        usable_while_building = state == "building" and _nodes(target) > 0
        if state != "ready" and not usable_while_building:
            return _not_ready(types, state, target, reason)
        # `project` is routing only, never a graphify argument — strip it for
        # the default graph too, or the upstream handler receives an unexpected
        # keyword and fails.
        if isinstance(args, dict) and "project" in args:
            remaining = dict(args)
            remaining.pop("project", None)
            request.params.arguments = remaining
        if target == graph_file:
            return await original(request)
        return await instance_for(target)(request)

    server.request_handlers[types.CallToolRequest] = guarded

    # Advertise `project` on every tool so the caller knows the graph can be
    # selected; the schemas come from graphify and are extended, not replaced.
    upstream_list = server.request_handlers[types.ListToolsRequest]

    async def list_with_project(request):
        result = await upstream_list(request)
        tools = getattr(getattr(result, "root", None), "tools", None) or []
        for tool in tools:
            schema = getattr(tool, "inputSchema", None)
            if isinstance(schema, dict):
                properties = schema.setdefault("properties", {})
                if isinstance(properties, dict):
                    properties["project"] = {
                        "type": "string",
                        "description": (
                            "Path of a registered project whose graph to query "
                            "(file or directory). Defaults to this session's project."
                        ),
                    }
        return result

    server.request_handlers[types.ListToolsRequest] = list_with_project

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
