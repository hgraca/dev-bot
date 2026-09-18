#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_available_catalogue.py
# Unit tests for the availability filter.
#
# The filter is now a pure environment check — it opens no connections.
# Reachability belongs to the toolbox oracle and is covered by
# test_validate_catalogue.py, so nothing here needs a socket or a server.
# =============================================================================

import json
import os
import subprocess
import sys
import unittest

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILTER = os.path.join(MODULE_DIR, "available_catalogue.py")

MYSQL_ENV_KEYS = (
    "MYSQL_HOST",
    "MYSQL_PORT",
    "MYSQL_DATABASE",
    "MYSQL_USER",
    "MYSQL_PASSWORD",
)


class TestAvailableCatalogue(unittest.TestCase):
    def run_filter(self, catalogue, env=None, args=None):
        # A clean environment, so an unrelated variable on the developer's
        # machine cannot make a test pass.
        environment = {"PATH": os.environ.get("PATH", "")}
        environment.update(env or {})
        proc = subprocess.run(
            [sys.executable, FILTER] + (args or []),
            input=json.dumps(catalogue),
            capture_output=True,
            text=True,
            env=environment,
        )
        return proc.returncode, proc.stdout, proc.stderr

    def mysql(self):
        """A mysql datasource whose values are all ${VAR} references."""
        return (
            {
                "db": {
                    "type": "mysql",
                    "env": {key: "${" + key + "}" for key in MYSQL_ENV_KEYS},
                }
            },
            {
                "MYSQL_HOST": "127.0.0.1",
                "MYSQL_PORT": "3306",
                "MYSQL_DATABASE": "d",
                "MYSQL_USER": "u",
                "MYSQL_PASSWORD": "p",
            },
        )

    def test_keeps_an_env_complete_mysql_datasource(self):
        catalogue, env = self.mysql()

        code, out, _ = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["db"])

    def test_drops_a_datasource_missing_a_required_var(self):
        catalogue, env = self.mysql()
        del env["MYSQL_PASSWORD"]

        code, out, err = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("MYSQL_PASSWORD", err)

    def test_an_empty_required_var_counts_as_missing(self):
        catalogue, env = self.mysql()
        env["MYSQL_PASSWORD"] = ""

        code, out, err = self.run_filter(catalogue, env)

        self.assertEqual(json.loads(out), {})
        self.assertIn("MYSQL_PASSWORD", err)

    def test_database_is_not_required_for_mysql(self):
        # One instance holds several DBs; no default schema is a valid setup.
        catalogue, env = self.mysql()
        del env["MYSQL_DATABASE"]

        code, out, _ = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["db"])

    def test_keeps_an_env_complete_sqlite_datasource(self):
        code, out, _ = self.run_filter(
            {"scratch": {"type": "sqlite", "env": {"SQLITE_DATABASE": "S_DB"}}},
            {"S_DB": "/data/scratch.db"},
        )

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["scratch"])

    def test_drops_a_sqlite_datasource_without_its_database(self):
        code, out, err = self.run_filter({"scratch": {"type": "sqlite", "env": {}}})

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("SQLITE_DATABASE", err)

    def test_a_datasource_with_no_env_key_is_handled(self):
        # `env` is optional; this must not raise.
        code, out, err = self.run_filter({"scratch": {"type": "sqlite"}})

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("SQLITE_DATABASE", err)

    def test_a_literal_satisfies_a_required_field(self):
        # A literal can never be missing, so it never gates a datasource out —
        # and it needs no environment variable at all.
        code, out, _ = self.run_filter(
            {
                "db": {
                    "type": "mysql",
                    "env": {
                        "MYSQL_HOST": "127.0.0.1",
                        "MYSQL_PORT": "3306",
                        "MYSQL_USER": "root",
                        "MYSQL_PASSWORD": "literal-pass",
                    },
                }
            }
        )

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["db"])

    def test_mongodb_database_is_required(self):
        # mongodb-aggregate requires a database and the field has no default,
        # so a datasource without one must never reach the gateway config.
        code, out, err = self.run_filter(
            {"events": {"type": "mongodb", "env": {"MONGODB_URI": "mongodb://127.0.0.1:27017/db"}}}
        )

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("MONGODB_DATABASE", err)

    def test_redis_address_is_required(self):
        code, out, err = self.run_filter({"cache": {"type": "redis", "env": {}}})

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("REDIS_ADDRESS", err)

    def test_redis_optional_credentials_do_not_gate(self):
        # No username/password declared and none in the environment: the source
        # omits them, so the datasource is still a candidate.
        code, out, _ = self.run_filter(
            {"cache": {"type": "redis", "env": {"REDIS_ADDRESS": "127.0.0.1:6379"}}}
        )

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["cache"])

    def test_only_the_candidate_subset_is_emitted(self):
        catalogue, env = self.mysql()
        catalogue["scratch"] = {"type": "sqlite", "env": {"SQLITE_DATABASE": "S_DB"}}
        env["S_DB"] = "/data/scratch.db"

        code, out, _ = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(sorted(json.loads(out)), ["db", "scratch"])

    def test_invalid_catalogue_is_an_error(self):
        code, out, err = self.run_filter({"db": {"type": "oracle", "env": {}}})

        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("unknown type", err)

    def test_arguments_are_rejected(self):
        code, _, err = self.run_filter({}, args=["--nope"])

        self.assertEqual(code, 1)
        self.assertIn("usage:", err)


if __name__ == "__main__":
    unittest.main()
