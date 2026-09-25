#!/usr/bin/env python3
"""Assert the module's ops table matches what the language plugins declare.

The table lives — identically — in `skills/SKILL.md` and `docs.md`, and is the
agent- and human-facing list of refactorings. This check is the drift guard:

1. the two copies are identical;
2. every canonical op, and the languages declaring it, match the plugins' metas;
3. every `--kind` a plugin maps (a non-`*` key) is named in its op's row;
4. each plugin's `requires`/`risks` key sets equal the native ops its map exposes.

The kind check is a substring test — a row's description is prose, not a data
field — so it catches an unnamed kind, not a mis-described one.

Usage: python3 ops_table_check.py <module-dir>
"""

import json
import pathlib
import subprocess
import sys


def table_from(path):
    lines = path.read_text().splitlines()
    rows = []
    capturing = False
    for line in lines:
        if not capturing and "| languages" in line and line.lstrip().startswith("| refactor"):
            capturing = True
        if capturing:
            if not line.strip():
                break
            rows.append(line)
    return rows


def parse_rows(rows):
    """{op: (languages, description)} from the markdown rows (header + separator first)."""
    parsed = {}
    for line in rows[2:]:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 3:
            raise AssertionError("every ops row needs exactly 3 cells: %r" % line)
        op, languages, description = cells[0].strip("`"), cells[1], cells[2]
        if not description:
            raise AssertionError("%s needs a description" % op)
        parsed[op] = ({lang.strip() for lang in languages.split(",") if lang.strip()}, description)
    return parsed


def plugin_metas(module):
    metas = []
    for plugin in sorted((module / "langs").glob("*/plugin.sh")):
        metas.append(
            json.loads(
                subprocess.run(
                    ["bash", str(plugin), "meta"], capture_output=True, text=True, check=True
                ).stdout
            )
        )
    return metas


def main(argv):
    module = pathlib.Path(argv[1] if len(argv) > 1 else ".").resolve()

    skill = table_from(module / "skills" / "SKILL.md")
    docs = table_from(module / "docs.md")
    if not skill:
        print("ERROR: no ops table found in skills/SKILL.md", file=sys.stderr)
        return 1
    if skill != docs:
        print("ERROR: the ops table differs between SKILL.md and docs.md", file=sys.stderr)
        return 1

    parsed = parse_rows(skill)
    metas = plugin_metas(module)

    # 2 — ops and languages.
    expected = {}
    for meta in metas:
        for op in meta["ops"]:
            expected.setdefault(op, set()).add(meta["lang"])
    declared = {op: languages for op, (languages, _description) in parsed.items()}
    if declared != expected:
        print("ERROR: the ops table is out of sync with the plugins", file=sys.stderr)
        print("  table:   %s" % declared, file=sys.stderr)
        print("  plugins: %s" % expected, file=sys.stderr)
        return 1

    # 3 — kinds, and 4 — the per-native-op key sets.
    for meta in metas:
        for op, mapping in (meta.get("map") or {}).items():
            description = parsed.get(op, (set(), ""))[1]
            for kind in mapping:
                if kind != "*" and kind not in description:
                    print(
                        "ERROR: %s op '%s' maps kind '%s' but the table row never names it"
                        % (meta["lang"], op, kind),
                        file=sys.stderr,
                    )
                    return 1
        natives = {native for mapping in (meta.get("map") or {}).values() for native in mapping.values()}
        for field in ("requires", "risks"):
            if set(meta.get(field) or {}) != natives:
                print(
                    "ERROR: %s '%s' keys do not match the native ops in its map"
                    % (meta["lang"], field),
                    file=sys.stderr,
                )
                return 1

    print("ops table in sync: %d ops, %d rows" % (len(expected), len(skill)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
