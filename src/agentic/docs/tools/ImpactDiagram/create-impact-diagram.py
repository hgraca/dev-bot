#!/usr/bin/env python3
"""
create-impact-diagram — a use-case map scoped to a git diff.

Reuses the use-case-map scanner (`create-use-case-map.py`) to build the full
architecture map, then keeps only the flows that pass through the classes a git
diff changed, marking those units in red.

Output is UseCaseMap-shaped JSON, rendered by `ImpactDiagram.html`.

Usage:
  create-impact-diagram.py [--project-root DIR] [--diff RANGE] [--output FILE]
                           [--component NAME] [--title T] [--subtitle S]
                           [--copy-visualizer PATH]
"""

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCANNER = os.path.normpath(
    os.path.join(HERE, "..", "UseCaseMap", "create-use-case-map.py")
)
VISUALIZER = os.path.join(HERE, "ImpactDiagram.html")


def load_scanner():
    """Import the use-case-map scanner as a module (its main() is guarded)."""
    if not os.path.isfile(SCANNER):
        print(f"FATAL: use-case-map scanner not found at {SCANNER}", file=sys.stderr)
        sys.exit(1)
    spec = importlib.util.spec_from_file_location("use_case_map", SCANNER)
    if spec is None or spec.loader is None:
        print(f"FATAL: could not load the use-case-map scanner at {SCANNER}", file=sys.stderr)
        sys.exit(1)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def changed_class_names(project_root, diff_range):
    """The class basenames of every .php file the diff touched."""
    result = subprocess.run(
        ["git", "-C", project_root, "diff", "--name-only", diff_range],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(
            f"FATAL: git diff --name-only {diff_range} failed: {result.stderr.strip()}",
            file=sys.stderr,
        )
        sys.exit(1)
    names = set()
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.endswith(".php"):
            names.add(os.path.splitext(os.path.basename(line))[0])
    return names


def unit_basename(node):
    """The class a unit names, from its title ("Class::method", "1.1 A - B")."""
    title = node.get("title")
    if not isinstance(title, str):
        return None
    token = title.split("::")[0].split(" - ")[-1].split("\\")[-1].strip()
    return token or None


def mark_and_has_changed(node, changed):
    """Mark this node's subtree and report whether any unit in it changed."""
    found = unit_basename(node) in changed
    if found:
        node["color"] = "changed"
    for child in node.get("items", []):
        if mark_and_has_changed(child, changed):
            found = True
    return found


def prune(sections, changed):
    """Keep only the flows (subsections) that carry a changed unit."""
    kept = []
    for section in sections:
        subs = [sub for sub in section.get("items", []) if mark_and_has_changed(sub, changed)]
        if subs:
            kept.append({**section, "items": subs})
    return kept


# --- Static SVG rendering (no browser, no Mermaid) ---------------------------

FILL = {
    "changed": "#ffc9c9", "cli": "#e8f5e9", "ctrl": "#e0f2f1", "uc": "#bbdefb",
    "handler": "#e3f2fd", "query": "#e8f5e9", "qhandler": "#e8f5e9", "port": "#fff3e0",
    "adapter": "#fce4ec", "http": "#f3e5f5", "event": "#ffe0b2", "listnr": "#f1f8e9",
    "cb": "#fff8e1", "indirect": "#eeeeee",
}
STROKE = {
    "changed": "#c92a2a", "cli": "#2e7d32", "ctrl": "#00897b", "uc": "#0d47a1",
    "handler": "#42a5f5", "query": "#43a047", "qhandler": "#43a047", "port": "#e65100",
    "adapter": "#c62828", "http": "#6a1b9a", "event": "#ef6c00", "listnr": "#558b2f",
    "cb": "#f9a825", "indirect": "#9e9e9e",
}

# A pencil ("code was edited") icon, Material's 24x24 edit glyph.
ICON_PENCIL = (
    "M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25z"
    "M20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 "
    "3.75 3.75 1.83-1.83z"
)
ICON_SIZE = 16


def _esc(text):
    return (
        (text or "")
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def render_svg(sections, title, subtitle):
    """A single static SVG of the flows: columns left-to-right, changed in red."""
    cell_w, unit_h, vgap, colgap = 250, 34, 8, 46
    margin = 28
    parts = [
        '<rect class="bg" x="0" y="0" width="100%" height="100%"/>',
        f'<text x="{margin}" y="{margin + 22}" class="title">{_esc(title)}</text>',
        f'<text x="{margin}" y="{margin + 44}" class="sub">{_esc(subtitle)}</text>',
    ]
    y = margin + 78
    max_x = margin + 400
    for section in sections:
        for sub in section.get("items", []):
            columns = sub.get("items", [])
            if not columns:
                continue
            parts.append(f'<text x="{margin}" y="{y}" class="flow">{_esc(sub.get("title", ""))}</text>')
            units_top = y + 16
            edges = []
            heights = []
            for index, column in enumerate(columns):
                x = margin + index * (cell_w + colgap)
                max_x = max(max_x, x + cell_w)
                cursor = units_top
                for unit in column.get("items", []):
                    color = unit.get("color", "indirect")
                    fill = FILL.get(color, "#eeeeee")
                    stroke = STROKE.get(color, "#9e9e9e")
                    changed = color == "changed"
                    parts.append(
                        f'<rect x="{x}" y="{cursor}" width="{cell_w}" height="{unit_h}" '
                        f'rx="6" fill="{fill}" stroke="{stroke}"/>'
                    )
                    label_x = x + 10
                    if changed:
                        scale = ICON_SIZE / 24
                        iy = cursor + (unit_h - ICON_SIZE) // 2
                        parts.append(
                            f'<g transform="translate({x + 8},{iy}) scale({scale})">'
                            f'<path d="{ICON_PENCIL}" fill="{stroke}"/></g>'
                        )
                        label_x = x + 8 + ICON_SIZE + 6
                    weight = ' font-weight="700"' if changed else ""
                    parts.append(
                        f'<text x="{label_x}" y="{cursor + 22}" class="unit"{weight}>'
                        f'{_esc(unit.get("title", ""))}</text>'
                    )
                    cursor += unit_h + vgap
                heights.append(cursor - units_top)
                edges.append((x, x + cell_w, units_top + (cursor - units_top) // 2))
            for i in range(len(edges) - 1):
                x1 = edges[i][1]
                x2 = edges[i + 1][0]
                ym = min(edges[i][2], edges[i + 1][2])
                parts.append(
                    f'<line x1="{x1}" y1="{ym}" x2="{x2 - 7}" y2="{ym}" class="edge" '
                    f'marker-end="url(#arrow)"/>'
                )
            y = units_top + (max(heights) if heights else 0) + 30
    height = y + margin
    width = max_x + margin
    style = (
        "<style>"
        ".bg{fill:#ffffde;}"
        ".title{font:700 20px sans-serif;fill:#212121;}"
        ".sub{font:13px sans-serif;fill:#616161;}"
        ".flow{font:600 14px sans-serif;fill:#343a40;}"
        ".unit{font:13px sans-serif;fill:#212121;}"
        ".edge{stroke:#adb5bd;stroke-width:1.5;}"
        "</style>"
    )
    defs = (
        '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" '
        'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        '<path d="M0,0 L10,5 L0,10 z" fill="#adb5bd"/></marker></defs>'
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">{defs}{style}'
        + "".join(parts)
        + "</svg>\n"
    )


def main():
    parser = argparse.ArgumentParser(
        description="Impact diagram — a use-case map scoped to a git diff"
    )
    parser.add_argument("--project-root", "-r", default=".")
    parser.add_argument(
        "--diff",
        "-d",
        default="HEAD",
        help="git range, e.g. origin/main...HEAD (default: HEAD = working tree)",
    )
    parser.add_argument("--output", "-o", default="", help="Output JSON (default: stdout)")
    parser.add_argument("--component", "-c", default="", help="Filter to a component")
    parser.add_argument("--title", "-t", default="")
    parser.add_argument("--subtitle", "-s", default="")
    parser.add_argument(
        "--copy-visualizer",
        default="",
        help="Copy the ImpactDiagram.html visualizer to the given path",
    )
    parser.add_argument(
        "--svg",
        default="",
        help="Also write a static SVG of the flows to the given path",
    )
    parser.add_argument(
        "--svg-app",
        default="",
        help="Write an SVG that embeds the HTML app's #app rendering (full browser "
        "fidelity, portable image-in-SVG; needs node + Chrome/Chromium)",
    )
    args = parser.parse_args()

    project_root = os.path.abspath(args.project_root)
    if not os.path.isdir(project_root):
        print(f"FATAL: project root not found: {project_root}", file=sys.stderr)
        sys.exit(1)

    changed = changed_class_names(project_root, args.diff)
    print(f"Diff {args.diff}: {len(changed)} changed class(es)", file=sys.stderr)
    if not changed:
        print(f"WARN: no changed PHP classes for '{args.diff}'", file=sys.stderr)

    scanner_module = load_scanner()
    print(f"Scanning: {project_root}", file=sys.stderr)
    scanner = scanner_module.GraphScanner(project_root, component=args.component or None)
    scanner.scan()
    result = scanner_module.UseCaseMapBuilder(scanner).build(
        title=args.title or "Impact diagram",
        subtitle=args.subtitle or f"Flows through classes changed in {args.diff}",
    )
    result["items"] = prune(result.get("items", []), changed)
    result["changed"] = sorted(changed)

    output = json.dumps(result, indent=2, ensure_ascii=False)
    if args.output:
        dest = os.path.abspath(args.output)
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "w") as handle:
            handle.write(output)
        print(f"Written: {dest} ({len(output)} bytes)", file=sys.stderr)
    else:
        print(output)

    if args.copy_visualizer:
        dest = os.path.abspath(args.copy_visualizer)
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        shutil.copy2(VISUALIZER, dest)
        print(f"Copied visualizer to: {dest}", file=sys.stderr)

    if args.svg:
        dest = os.path.abspath(args.svg)
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        svg = render_svg(result["items"], result["title"], result["subtitle"])
        with open(dest, "w") as handle:
            handle.write(svg)
        print(f"Wrote SVG: {dest}", file=sys.stderr)

    if args.svg_app:
        dest = os.path.abspath(args.svg_app)
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        json_for_app = (
            os.path.abspath(args.output)
            if args.output
            else os.path.join(os.path.dirname(dest) or ".", "impact-diagram.json")
        )
        if not args.output:
            with open(json_for_app, "w") as handle:
                handle.write(output)
        node = shutil.which("node")
        renderer = os.path.join(HERE, "render-app-svg.mjs")
        if not node:
            print("WARN: node not found — skipping the app SVG", file=sys.stderr)
        else:
            subprocess.run(
                [node, renderer, "--html", VISUALIZER, "--json", json_for_app, "--out", dest],
                check=True,
            )


if __name__ == "__main__":
    main()
