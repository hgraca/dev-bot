#!/usr/bin/env python3
"""Reconcile the permission.external_directory map in an opencode.jsonc file.

Guarantees the block is deny-first and carries "/tmp/**" plus the opencode log
and config dirs, so the agent can read the harness log/config (audit-51 §8b,
audit-56 §8b). Only that block is rewritten — the rest of the file, including
comments, is preserved.

Usage:
  reconcile_external_directory.py <opencode.jsonc>

Stdout:
  "1"  — the file was changed
  "0"  — the file was already current, or there is no block to reconcile

Exit codes:
  0 — success or skip
  1 — unreadable file / write failure
"""

import json
import os
import re
import sys


def _line_indent(text, index):
    """Leading whitespace of the line containing `index`."""
    line_start = text.rfind("\n", 0, index) + 1
    prefix = text[line_start:index]
    return prefix[: len(prefix) - len(prefix.lstrip())]


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 1
    config = argv[1]

    try:
        with open(config, encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        print(f"skip: {config} not found", file=sys.stderr)
        print("0")
        return 0
    except OSError as exc:
        print(f"error: cannot read {config}: {exc}", file=sys.stderr)
        return 1

    # HOME is baked at reinit time (host/container specific), matching how the
    # other absolute allows are written.
    home = os.environ.get("HOME", "")
    log_allow = home + "/.local/share/opencode/log/**"
    cfg_allow = home + "/.config/opencode/**"

    block_m = re.search(r'"external_directory"\s*:\s*\{([^}]*)\}', text, re.S)
    tmp_present = '"/tmp/**"' in text

    # Legacy single-star /tmp glob → the recursive form.
    if '"/tmp/*"' in text and not tmp_present:
        try:
            with open(config, "w", encoding="utf-8") as fh:
                fh.write(text.replace('"/tmp/*"', '"/tmp/**"', 1))
        except OSError as exc:
            print(f"error: cannot write {config}: {exc}", file=sys.stderr)
            return 1
        print("1")
        return 0

    if not block_m:
        print("0")
        return 0

    try:
        entries = json.loads("{" + block_m.group(1) + "}")
    except ValueError:
        print("0")
        return 0

    if (
        tmp_present
        and block_m.group(1).startswith("\n")
        and list(entries.keys())[:1] == ["*"]
        and log_allow in entries
        and cfg_allow in entries
    ):
        print("0")
        return 0

    # Rebuild deny-first so the specific allows are evaluated last and win.
    ordered = {}
    if "*" in entries:
        ordered["*"] = entries["*"]
    for key, value in entries.items():
        if key != "*":
            ordered[key] = value
    if not tmp_present:
        ordered["/tmp/**"] = "allow"
    if log_allow and log_allow not in ordered:
        ordered[log_allow] = "allow"
    if cfg_allow and cfg_allow not in ordered:
        ordered[cfg_allow] = "allow"

    # Emit the block with the key's own indentation so the braces never glue to
    # the first/last entry (audit-65 FAIL-1) and re-reads stay stable.
    key_indent = _line_indent(text, block_m.start())
    entry_indent = key_indent + "  "
    entries_text = (",\n" + entry_indent).join(
        f'"{k}": "{v}"' for k, v in ordered.items()
    )
    new_inner = f"\n{entry_indent}{entries_text}\n{key_indent}"
    new_text = text[: block_m.start(1)] + new_inner + text[block_m.end(1) :]

    try:
        with open(config, "w", encoding="utf-8") as fh:
            fh.write(new_text)
    except OSError as exc:
        print(f"error: cannot write {config}: {exc}", file=sys.stderr)
        return 1
    print("1")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
