#!/usr/bin/env python3
"""The devbot-tools server forwards only ``args`` — enforce that contract.

Every tool discovered by ``tools-mcp`` is invoked as
``tools/call {name, arguments: {args: [...]}}``: the server serializes that one
array onto the wrapper's command line and drops every other property. A meta
declaring ``files``, ``path`` or ``pattern`` therefore advertises a parameter the
server never delivers, and the tool fails with "no argument given" through MCP
while working perfectly from a shell — which is how it survived review once.

Usage:
    python3 -m unittest test_tool_meta_contract.py -v
"""

import json
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[4]  # repo root


def meta_of(script: pathlib.Path) -> dict | None:
    """The tool's mcp-meta document, or None when it declares none."""
    try:
        result = subprocess.run(
            ["bash", str(script), "mcp-meta"], capture_output=True, text=True, timeout=60
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None


class ToolMetaContractTest(unittest.TestCase):
    def test_every_tool_exposes_only_the_args_array(self):
        offenders = []
        checked = 0
        for script in sorted(ROOT.glob("src/**/*.mcp.sh")):
            meta = meta_of(script)
            if not meta:
                continue
            properties = ((meta.get("parameters") or {}).get("properties")) or {}
            if not properties:
                continue  # an in-process handler takes no arguments
            checked += 1
            if list(properties) != ["args"] or (properties.get("args") or {}).get("type") != "array":
                offenders.append(f"{script.relative_to(ROOT)}: {sorted(properties)}")
        self.assertGreater(checked, 20, "the scan found no tools — stale glob")
        self.assertEqual(offenders, [], "these tools declare parameters the server drops")

    # Required-ness is deliberately not asserted: several tools take no
    # arguments at all, and the server forwards an omitted args as no argv.

if __name__ == "__main__":
    unittest.main()
