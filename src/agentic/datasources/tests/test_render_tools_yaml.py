#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_render_tools_yaml.py
# Unit tests for the tools.yaml generator.
# =============================================================================

import json
import os
import subprocess
import sys
import unittest

RENDERER = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "render_tools_yaml.py"
)


def render(catalogue):
    """Run the generator over a catalogue dict. Returns (exit_code, stdout, stderr)."""
    proc = subprocess.run(
        [sys.executable, RENDERER],
        input=json.dumps(catalogue),
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def docs_of(stdout):
    """Split the rendered tools.yaml into its YAML documents."""
    return [d.strip() for d in stdout.split("\n---\n") if d.strip() and not d.lstrip().startswith("#")]


class TestRenderToolsYaml(unittest.TestCase):
    def test_emits_source_tool_and_toolset_per_datasource(self):
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        kinds = [d.splitlines()[0] for d in docs_of(out)]
        self.assertEqual(kinds, ["kind: source", "kind: tool", "kind: toolset"])

    def test_tool_name_is_namespaced_by_datasource(self):
        code, out, _ = render(
            {
                "hotels": {"type": "mysql", "env": {}},
                "driver": {"type": "mysql", "env": {}},
            }
        )

        self.assertEqual(code, 0)
        self.assertIn("name: hotels_execute_sql", out)
        self.assertIn("name: driver_execute_sql", out)

    def test_toolset_name_is_the_datasource_name(self):
        # The toolset name is the URL segment: /mcp/<datasource>.
        code, out, _ = render({"hotels-dev": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        toolset = [d for d in docs_of(out) if d.startswith("kind: toolset")][0]
        self.assertIn("name: hotels-dev", toolset)

    def test_env_mapping_replaces_the_toolbox_var_name(self):
        code, out, _ = render(
            {"hotels": {"type": "mysql", "env": {"MYSQL_HOST": "HOTELS_DEV_DB_HOST"}}}
        )

        self.assertEqual(code, 0)
        # The engine default is preserved alongside the operator's var name.
        self.assertIn("host: ${HOTELS_DEV_DB_HOST:localhost}", out)
        self.assertNotIn("${MYSQL_HOST", out)

    def test_undeclared_fields_use_the_toolbox_var_name(self):
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        self.assertIn("host: ${MYSQL_HOST:localhost}", out)
        self.assertIn("port: ${MYSQL_PORT:3306}", out)

    def test_required_fields_carry_no_default(self):
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        self.assertIn("database: ${MYSQL_DATABASE}\n", out)
        self.assertIn("password: ${MYSQL_PASSWORD}\n", out)

    def test_postgres_uses_its_own_field_names_and_tool(self):
        code, out, _ = render({"reporting": {"type": "postgres", "env": {}}})

        self.assertEqual(code, 0)
        self.assertIn("type: postgres\n", out)
        self.assertIn("port: ${POSTGRES_PORT:5432}", out)
        self.assertIn("type: postgres-execute-sql", out)

    def test_sqlite_uses_the_database_path_field(self):
        code, out, _ = render({"scratch": {"type": "sqlite", "env": {}}})

        self.assertEqual(code, 0)
        self.assertIn("type: sqlite\n", out)
        self.assertIn("database: ${SQLITE_DATABASE}\n", out)
        self.assertIn("type: sqlite-execute-sql", out)

    def test_no_read_only_field_is_ever_emitted(self):
        # There is deliberately no read-only affordance. Upstream enforces
        # read-only at the protocol level only for Cloud SQL / AlloyDB /
        # BigQuery; on the self-hosted engines the scope of the database user's
        # credential is the only real defence. Emitting the flag would imply a
        # guarantee the module cannot keep.
        code, out, _ = render({"hotels": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 0)
        self.assertNotIn("readOnly", out)

    def test_read_only_key_is_rejected_with_an_explanation(self):
        code, out, err = render({"hotels": {"type": "mysql", "env": {}, "read_only": True}})

        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("read_only", err)
        self.assertIn("credential", err)

    def test_unknown_datasource_key_is_rejected(self):
        code, _, err = render({"hotels": {"type": "mysql", "env": {}, "writable": False}})

        self.assertEqual(code, 1)
        self.assertIn("writable", err)

    def test_unknown_engine_is_an_error(self):
        code, out, err = render({"legacy": {"type": "oracle", "env": {}}})

        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertTrue(err.startswith("ERROR:"), err)
        self.assertIn("unknown type 'oracle'", err)

    def test_unknown_env_key_is_an_error(self):
        # Catches a typo'd field instead of silently emitting a bogus source.
        code, _, err = render(
            {"hotels": {"type": "mysql", "env": {"MYSQL_HOTS": "HOTELS_DB_HOST"}}}
        )

        self.assertEqual(code, 1)
        self.assertIn("MYSQL_HOTS", err)

    def test_invalid_datasource_name_is_an_error(self):
        code, _, err = render({"Hotels DB": {"type": "mysql", "env": {}}})

        self.assertEqual(code, 1)
        self.assertIn("must match", err)

    def test_empty_catalogue_renders_a_comment_only(self):
        code, out, _ = render({})

        self.assertEqual(code, 0)
        self.assertNotIn("kind:", out)

    def test_malformed_catalogue_is_an_error(self):
        proc = subprocess.run(
            [sys.executable, RENDERER], input="not json", capture_output=True, text=True
        )

        self.assertEqual(proc.returncode, 1)
        self.assertIn("not valid JSON", proc.stderr)


if __name__ == "__main__":
    unittest.main()
