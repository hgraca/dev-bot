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


def _avg(value) -> str:
    return f"{value:.2f}" if isinstance(value, (int, float)) else _MISSING


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


def _cell_lines(cell) -> list[str]:
    """A cell split into the lines it renders as — ``<br>`` stacks a cell."""
    return str(cell).split("<br>")


def render_table(header, aligns, rows) -> list[str]:
    """Render a pipe table, padding every column so the source stays aligned.

    A cell may stack content with ``<br>``. Such a cell keeps one physical line
    — a markdown table row must not wrap — so its column sizes to the longest
    segment while the cell itself is the longer joined string. That cell gets no
    padding, leaving the trailing pipes of a stacked table unaligned in the
    source. Renderers ignore pipe alignment, so the output is unaffected, and
    the well-formed-table invariant the suite asserts on the other tables does
    not apply to stacked ones.
    """
    ncol = len(header)
    # Markdown needs at least 3 dashes in the separator row, so every column is
    # at least that wide — otherwise the separator and the padded rows disagree.
    widths = [max(len(str(h)), 3) for h in header]
    for row in rows:
        for i in range(ncol):
            for segment in _cell_lines(row[i]):
                widths[i] = max(widths[i], len(segment))

    lines = [
        "| " + " | ".join(_pad(header[i], widths[i], aligns[i]) for i in range(ncol)) + " |",
        "| " + " | ".join(_separator(widths[i], aligns[i]) for i in range(ncol)) + " |",
    ]
    for row in rows:
        lines.append(
            "| " + " | ".join(_pad(row[i], widths[i], aligns[i]) for i in range(ncol)) + " |"
        )
    return lines


_BUCKET_VERDICT = {
    "workhorse": "keep",
    "specialist": "keep",
    "improve": "fix the implementation",
    "unproven": "not enough data",
}


def _quadrant_cell(bucket: str, tools: list[dict]) -> str:
    """One quadrant: the bucket's name and verdict, then one line per tool."""
    lines = [f"**{bucket}** · {_BUCKET_VERDICT[bucket]}"]
    lines += [
        f"{t.get('name', '?')} ({_avg(t.get('avg'))}, {_int(t.get('uses', 0))})" for t in tools
    ]
    if len(lines) == 1:
        lines.append(_MISSING)
    return "<br>".join(lines)


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

    grades = data.get("tool_grades") or {}
    grade_tools = grades.get("tools") or []
    if grade_tools:
        scope_word = "all projects" if grades.get("scope") == "all" else "one project"
        grade_days = grades.get("days")
        rows_label = f"{_int(grades.get('rows'))} row(s)"
        total_label = f"{_int(grades.get('total_rows'))} row(s)"
        if isinstance(grade_days, int):
            day_word = "day" if grade_days == 1 else "days"
            window_phrase = f"the last {_int(grade_days)} {day_word}"
        else:
            window_phrase = "the whole CSV"
        out += [
            "",
            "## Tool Grades",
            "",
            f"Averaged over rows where the tool was used (grade ≥ 1); highest first, unused last. "
            f"{rows_label} in {window_phrase} ({scope_word}); "
            f"{total_label} in the CSV.",
            "",
            "`Min` is the worst grade the tool earned, and `σ` how far its grades scatter around "
            "the average — both over the rows counted above. The average alone hides both: a 4.00 "
            "built from four 4s is a different tool from one that scored 5 every time but once "
            "scored 3.",
            "",
            "Read them before leaning on a number. A **low `Min`** means the tool has failed you at "
            "least once — check its reason under Poor ratings before trusting it unsupervised. A "
            "**high `σ`** means the average is not a promise: the outcome varies, so look for a "
            "shared cause in the bad uses. A **high `Min` with a low `σ`** is the strongest signal "
            "in the table — never disappointed, and behaves the same way every time. `σ` is "
            "withheld below three uses, where a spread means nothing.",
            "",
        ]
        rows = [
            [
                t.get("name", "?"),
                t.get("kind", "?"),
                _avg(t.get("avg")),
                _int(t.get("uses", 0)),
                _int(t.get("min")),
                _avg(t.get("stdev")),
            ]
            for t in grade_tools
        ]
        out += render_table(
            ["Tool", "Kind", "Avg", "Uses", "Min", "σ"], ["l", "l", "r", "r", "r", "r"], rows
        )

        # Every tool must be on the grid, or the grid is a lie. A block where
        # only some tools carry a bucket would silently drop the rest, so it
        # renders no grid at all rather than a partial one.
        if all(t.get("bucket") for t in grade_tools):
            bar = grades.get("demand_bar")
            threshold = grades.get("quality_threshold")
            out += ["", "### Tool Quadrants", ""]
            if isinstance(bar, int) and isinstance(threshold, (int, float)):
                out += [
                    f"Quality: `Avg > {threshold:g}` is high. Demand: `uses ≥ {bar}` is often — "
                    f"the median use count of the tools actually used, floored.",
                    "",
                ]
            by_bucket: dict[str, list[dict]] = {}
            for tool in grade_tools:
                by_bucket.setdefault(tool.get("bucket", ""), []).append(tool)
            out += render_table(
                ["Quality", "Many uses", "Few uses"],
                ["l", "l", "l"],
                [
                    [
                        "**High avg**",
                        _quadrant_cell("workhorse", by_bucket.get("workhorse", [])),
                        _quadrant_cell("specialist", by_bucket.get("specialist", [])),
                    ],
                    [
                        "**Low avg**",
                        _quadrant_cell("improve", by_bucket.get("improve", [])),
                        _quadrant_cell("unproven", by_bucket.get("unproven", [])),
                    ],
                ],
            )
            unused = by_bucket.get("unused") or []
            if unused:
                out += [
                    "",
                    "**Never used** — " + ", ".join(t.get("name", "?") for t in unused),
                ]

        poor = [t for t in grade_tools if t.get("reasons")]
        if poor:
            out += ["", "### Poor ratings (1–3)", ""]
            for tool in poor:
                out.append(
                    f"- **{tool.get('name', '?')}** ({tool.get('kind', '?')}, "
                    f"overall avg {_avg(tool.get('avg'))}) — {_int(tool.get('uses', 0))} use(s)"
                )
                for reason in tool["reasons"]:
                    suffix = f" (×{reason['count']})" if reason.get("count", 1) > 1 else ""
                    out.append(f"  - {reason.get('text', '')}{suffix}")

    arguments = data.get("tool_arguments") or {}
    # Render every tool the adapter supplied, known tools first. A hardcoded
    # allow-list here silently hid a newly aggregated tool (pty_spawn) even
    # though the adapter had collected it.
    known = ("bash", "pty_spawn", "skill", "grep", "glob")
    argument_tools = [tool for tool in known if arguments.get(tool)]
    argument_tools += [tool for tool in arguments if tool not in known and arguments.get(tool)]
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
