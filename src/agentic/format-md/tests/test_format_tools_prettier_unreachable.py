"""A prettier that cannot be executed must fail loudly.

`shutil.which` can succeed and the exec still fail (the binary is removed in the
window between them, or PATH differs for the exec). That used to surface through
`FileNotFoundError` as main's *vanished-file* warning — "WARN: … is not a file or
directory" with exit 0 — which hides a broken installation behind a message about
the file. It must instead be reported as a formatting failure.

Direct unit coverage because the tool guards the availability check before it ever
formats, so no end-to-end path can reach this window.
"""

from __future__ import annotations

import importlib.util
import os
import unittest
from pathlib import Path
from unittest import mock

SRC = Path(__file__).resolve().parents[3]

# tool name -> (script path, text-formatting function)
TOOLS = {
    "format-md": (SRC / "agentic/format-md/tools/format-md.py", "format_md_text"),
    "format-json": (SRC / "agentic/format-json/tools/format-json.py", "format_json_text"),
    "format-yml": (SRC / "agentic/format-yml/tools/format-yml.py", "format_yaml_text"),
}


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader, f"cannot load {path}"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrettierUnreachableTest(unittest.TestCase):
    def test_each_tool_reports_a_prettier_it_cannot_execute(self) -> None:
        for name, (path, function) in TOOLS.items():
            with self.subTest(tool=name):
                module = _load(name.replace("-", "_"), path)
                # PATH without prettier: `which` would have said yes, the exec
                # cannot find it.
                with mock.patch.dict(os.environ, {"PATH": "/nonexistent"}):
                    with self.assertRaises(ValueError) as caught:
                        getattr(module, function)("a: 1\n")
                self.assertIn("prettier could not be executed", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
