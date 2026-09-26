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
                "MYSQL_USER",
            ],
        )

    def test_references_appear_in_the_env_list(self):
        code, out, _ = render(
            {"hotels": {"type": "mysql", "env": {"MYSQL_HOST": "${HOTELS_DB_HOST}"}}}
        )

        self.assertEqual(code, 0)
        self.assertIn("HOTELS_DB_HOST", env_line(out))
        self.assertNotIn("MYSQL_HOST", env_line(out))

    def test_literals_contribute_no_env_name(self):
        # A literal is not a variable: it is inlined into tools.yaml, so it is
        # never passed through the container's environment.
        code, out, _ = render(
            {"hotels": {"type": "mysql", "env": {"MYSQL_HOST": "db.internal"}}}
        )

        self.assertEqual(code, 0)
        self.assertNotIn("MYSQL_HOST", env_line(out))
        self.assertNotIn("db.internal", env_line(out))

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
        # The entry after `command:` must be a list item, not a scalar string:
        # exec form. A shell string would need /bin/sh, which the distroless
        # image does not have.
        self.assertTrue(lines[idx + 1].startswith("      - "), lines[idx + 1])
        self.assertIn("- --config-folder", [line.strip() for line in lines])

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

    # ── sidecar datasources ──────────────────────────────────────────────────

    def test_sidecar_marker_is_always_replaced(self):
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        self.assertNotIn("__SIDECAR_SERVICES__", out)

    def test_sidecar_renders_its_own_http_service(self):
        code, out, err = render(
            {
                "search": {
                    "type": "opensearch",
                    "env": {"OPENSEARCH_URL": "https://os.example.com", "AWS_PROFILE": "${P}"},
                }
            }
        )

        self.assertEqual(code, 0, err)
        self.assertIn("  search:", out)
        self.assertIn("image: ghcr.io/astral-sh/uv:python3.12-trixie-slim", out)
        # A literal is quoted; a ${VAR} reference is left for compose to resolve.
        self.assertIn('      OPENSEARCH_URL: "https://os.example.com"', out)
        self.assertIn("      AWS_PROFILE: ${P}", out)
        # The pinned package and the allocated port reach the command.
        self.assertIn('"opensearch-mcp-server-py@0.12.0"', out)
        self.assertIn('"18520"', out)
        # The toolbox gateway is still rendered alongside it.
        self.assertIn("datasources-mcp:", out)

    def test_sidecar_ports_are_sorted_so_a_reinit_is_stable(self):
        catalogue = {
            "beta": {"type": "opensearch", "env": {}},
            "alpha": {"type": "opensearch", "env": {}},
        }

        _, out_a, _ = render(catalogue)
        _, out_b, _ = render(dict(reversed(list(catalogue.items()))))

        self.assertEqual(out_a, out_b)
        # Ports are assigned by sorted name, so beta takes the second one.
        self.assertIn("18520", out_a)
        self.assertIn("18521", out_a)

    def test_a_sidecar_without_a_pinned_version_fails_loudly(self):
        with tempfile.TemporaryDirectory() as tmp:
            template = os.path.join(tmp, "compose.tpl.yml")
            with open(template, "w", encoding="utf-8") as handle:
                handle.write(
                    "services:\n  x:\n    environment: __DATASOURCE_ENV__\n"
                    "# __SIDECAR_SERVICES__\n"
                )
            code, _, err = render(
                {"search": {"type": "opensearch", "env": {}}}, template=template
            )

        self.assertEqual(code, 1)
        self.assertIn("SIDECAR_UV_IMAGE", err)
        self.assertIn("OPENSEARCH_MCP_VERSION", err)


if __name__ == "__main__":
    unittest.main()
