#!/usr/bin/env python3
"""Render the canonical ``devbot stats`` JSON (schema v1) as Markdown.

Reads the JSON document produced by a harness stats adapter on stdin and writes
a Markdown report to stdout. The canonical contract is documented in
``docs/harnesses.md`` (section "Stats adapters"); a harness adapter only has to
emit that JSON — all presentation lives here, in the parent command.

Columns adapt to the data: ``Tokens`` and ``Cost`` appear only when the adapter
supplies them (``cost_kind`` distinguishes an exact cost from an estimate).
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone

_MISSING = "—"


def _int(value) -> str:
    return f"{value:,}" if isinstance(value, int) else _MISSING


def _cost(value, estimated: bool) -> str:
    if not isinstance(value, (int, float)):
        return _MISSING
    return f"{'~' if estimated else ''}${value:,.2f}"


def _shares(counts) -> list[str]:
    """Percentage labels (1 decimal) that sum to exactly 100.0%.

    Uses the largest-remainder method so per-row rounding never drifts off 100%.
    """
    total = sum(counts)
    if not total:
        return [_MISSING for _ in counts]
    tenths = [c * 1000 / total for c in counts]
    floors = [int(t) for t in tenths]
    remaining = 1000 - sum(floors)
    order = sorted(range(len(counts)), key=lambda i: tenths[i] - floors[i], reverse=True)
    for i in order[: max(0, remaining)]:
        floors[i] += 1
    return [f"{f / 10:.1f}%" for f in floors]


def _generated(raw) -> str:
    try:
        dt = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    except (ValueError, TypeError):
        return str(raw) if raw else _MISSING


def _pad(text, width: int, align: str) -> str:
    text = str(text)
    if align == "r":
        return text.rjust(width)
    if align == "c":
        return text.center(width)
    return text.ljust(width)


def _separator(width: int, align: str) -> str:
    if width < 3:
        width = 3
    if align == "r":
        return "-" * (width - 1) + ":"
    if align == "c":
        return ":" + "-" * (width - 2) + ":"
    return ":" + "-" * (width - 1)


def render_table(header, aligns, rows) -> list[str]:
    """Render a pipe table with per-column padding so every row aligns."""
    ncol = len(header)
    # Markdown needs at least 3 dashes in the separator row, so every column is
    # at least that wide — otherwise the separator and the padded rows disagree.
    widths = [max(len(str(h)), 3) for h in header]
    for row in rows:
        for i in range(ncol):
            widths[i] = max(widths[i], len(str(row[i])))

    lines = [
        "| " + " | ".join(_pad(header[i], widths[i], aligns[i]) for i in range(ncol)) + " |",
        "| " + " | ".join(_separator(widths[i], aligns[i]) for i in range(ncol)) + " |",
    ]
    for row in rows:
        lines.append(
            "| " + " | ".join(_pad(row[i], widths[i], aligns[i]) for i in range(ncol)) + " |"
        )
    return lines


def render(data: dict) -> str:
    harness = data.get("harness") or "unknown"
    days = data.get("days")
    scope_label = data.get("scope_label") or data.get("scope") or _MISSING
    estimated = data.get("cost_kind") == "estimated"
    cost_header = "Cost (est.)" if estimated else "Cost"

    tools = data.get("tools") or []
    servers = data.get("mcp_servers") or []
    total = sum(t.get("count", 0) for t in tools)

    # A column is shown when any tool OR any MCP server supplies it.
    show_tokens = any(x.get("tokens") is not None for x in tools + servers)
    show_cost = any(x.get("cost") is not None for x in tools + servers)
    day_word = "day" if days == 1 else "days"

    out: list[str] = [
        f"# DevBot Tool Usage — {harness}",
        "",
        f"**Window:** last {days} {day_word} · **Scope:** {scope_label} · "
        f"**Generated:** {_generated(data.get('generated_at'))}",
        "",
        "## Tool Usage",
        "",
    ]

    if tools:
        header = ["#", "Tool", "Calls", "Share"]
        aligns = ["r", "l", "r", "r"]
        if show_tokens:
            header.append("Tokens")
            aligns.append("r")
        if show_cost:
            header.append(cost_header)
            aligns.append("r")
        ordered = sorted(tools, key=lambda x: x.get("count", 0), reverse=True)
        shares = _shares([t.get("count", 0) for t in ordered])
        rows = []
        for i, t in enumerate(ordered):
            row = [i + 1, t.get("name", "?"), _int(t.get("count", 0)), shares[i]]
            if show_tokens:
                row.append(_int(t.get("tokens")))
            if show_cost:
                row.append(_cost(t.get("cost"), estimated))
            rows.append(row)
        out += render_table(header, aligns, rows)
    else:
        out.append("_No tool usage in this window._")

    out += ["", "## MCP Server Usage", ""]

    if servers:
        header = ["Server", "Calls", "Share"]
        aligns = ["l", "r", "r"]
        if show_tokens:
            header.append("Tokens")
            aligns.append("r")
        if show_cost:
            header.append(cost_header)
            aligns.append("r")
        header.append("Top tools")
        aligns.append("l")
        ordered = sorted(servers, key=lambda x: x.get("count", 0), reverse=True)
        shares = _shares([s.get("count", 0) for s in ordered])
        rows = []
        for i, s in enumerate(ordered):
            row = [s.get("server", "?"), _int(s.get("count", 0)), shares[i]]
            if show_tokens:
                row.append(_int(s.get("tokens")))
            if show_cost:
                row.append(_cost(s.get("cost"), estimated))
            top = sorted(s.get("tools") or [], key=lambda x: x.get("count", 0), reverse=True)[:5]
            row.append(", ".join(f"{t.get('name', '?')} ({t.get('count', 0):,})" for t in top) or _MISSING)
            rows.append(row)
        out += render_table(header, aligns, rows)
    else:
        out.append("_No MCP server usage in this window._")

    arguments = data.get("tool_arguments") or {}
    argument_tools = [k for k in ("bash", "skill", "grep", "glob") if arguments.get(k)]
    if argument_tools:
        out += ["", "## Tool Arguments", ""]
        for tool in argument_tools:
            out += [f"### {tool}", ""]
            rows = [[e.get("value", _MISSING), _int(e.get("count", 0))] for e in arguments[tool]]
            out += render_table(["Value", "Calls"], ["l", "r"], rows)
            out.append("")

    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid stats JSON: {exc}", file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print("ERROR: stats JSON must be an object", file=sys.stderr)
        return 1
    sys.stdout.write(render(data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
