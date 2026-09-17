#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_render_compose.py
# Unit tests for the docker-compose renderer.
# =============================================================================

import json
import os
import subprocess
import sys
import tempfile
import unittest

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RENDERER = os.path.join(MODULE_DIR, "render_compose.py")
TEMPLATE = os.path.join(MODULE_DIR, "compose.tpl.yml")


def render(catalogue, template=TEMPLATE):
    proc = subprocess.run(
        [sys.executable, RENDERER, template],
        input=json.dumps(catalogue),
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def env_line(out):
    """The rendered `environment:` entry, parsed back into a list."""
    for line in out.splitlines():
        stripped = line.strip()
        if stripped.startswith("environment:"):
            return json.loads(stripped.split("environment:", 1)[1].strip())
    raise AssertionError(f"no environment line in output:\n{out}")


class TestRenderCompose(unittest.TestCase):
    def test_marker_is_always_replaced(self):
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        self.assertNotIn("__DATASOURCE_ENV__", out)

    def test_passes_through_the_engine_default_names(self):
        # Undeclared fields fall back to the engine's own variable names, so an
        # operator who simply exports MYSQL_HOST still reaches the container.
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        self.assertEqual(
            env_line(out),
            [
                "MYSQL_DATABASE",
                "MYSQL_HOST",
                "MYSQL_PASSWORD",
                "MYSQL_PORT",
                "MYSQL_QUERY_PARAMS",
                "MYSQL_USER",
            ],
        )

    def test_declared_names_replace_the_engine_defaults(self):
        code, out, _ = render(
            {"hotels": {"type": "mysql", "env": {"MYSQL_HOST": "HOTELS_DB_HOST"}}}
        )

        self.assertEqual(code, 0)
        self.assertIn("HOTELS_DB_HOST", env_line(out))
        self.assertNotIn("MYSQL_HOST", env_line(out))

    def test_names_are_never_values(self):
        # The one hard rule: only the operator's variable NAMES are written.
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        self.assertNotIn("secret", out)

    def test_no_datasources_renders_an_empty_list(self):
        code, out, _ = render({})

        self.assertEqual(code, 0)
        self.assertEqual(env_line(out), [])

    def test_command_uses_the_exec_form(self):
        # The toolbox image is distroless: a shell-form command string would
        # fail for want of /bin/sh. Guard against a regression to a string.
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        lines = out.splitlines()
        idx = lines.index("    command:")
        self.assertEqual(lines[idx + 1].strip(), "- --config")

    def test_template_without_the_marker_is_an_error(self):
        with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False) as handle:
            handle.write("name: devbot\n")
            path = handle.name
        try:
            code, out, err = render({"hotels": {"type": "mysql", "env": {}}}, template=path)
        finally:
            os.unlink(path)

        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertTrue(err.startswith("ERROR:"), err)

    def test_missing_template_is_an_error(self):
        code, out, err = render({}, template="/nonexistent/compose.tpl.yml")

        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("cannot read template", err)

    def test_missing_template_argument_is_an_error(self):
        proc = subprocess.run(
            [sys.executable, RENDERER], input="{}", capture_output=True, text=True
        )

        self.assertEqual(proc.returncode, 1)
        self.assertIn("usage:", proc.stderr)


if __name__ == "__main__":
    unittest.main()
