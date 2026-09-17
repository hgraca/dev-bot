#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_available_catalogue.py
# Unit tests for the availability filter.
#
# A listening socket stands in for a reachable database, so the tests need no
# real server and no credentials.
# =============================================================================

import json
import os
import socket
import subprocess
import sys
import threading
import unittest

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILTER = os.path.join(MODULE_DIR, "available_catalogue.py")

MYSQL_ENV_KEYS = {
    "MYSQL_HOST": "T_HOST",
    "MYSQL_PORT": "T_PORT",
    "MYSQL_DATABASE": "T_DB",
    "MYSQL_USER": "T_USER",
    "MYSQL_PASSWORD": "T_PASS",
}


class TestAvailableCatalogue(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.listener = socket.socket()
        cls.listener.bind(("127.0.0.1", 0))
        cls.listener.listen(16)
        cls.live_port = cls.listener.getsockname()[1]

        # A real server accepts its connections. Without an accept loop the
        # kernel's accept queue fills and later probes fail — which would make
        # these tests flaky rather than test the filter.
        cls._stopping = threading.Event()

        def accept_loop():
            while not cls._stopping.is_set():
                try:
                    conn, _ = cls.listener.accept()
                except OSError:
                    return
                conn.close()

        cls._thread = threading.Thread(target=accept_loop, daemon=True)
        cls._thread.start()

        spare = socket.socket()
        spare.bind(("127.0.0.1", 0))
        cls.dead_port = spare.getsockname()[1]
        spare.close()

    @classmethod
    def tearDownClass(cls):
        cls._stopping.set()
        cls.listener.close()

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

    def mysql(self, port=None):
        return {
            "db": {"type": "mysql", "env": dict(MYSQL_ENV_KEYS)},
        }, {
            "T_HOST": "127.0.0.1",
            "T_PORT": str(port if port is not None else self.live_port),
            "T_DB": "d",
            "T_USER": "u",
            "T_PASS": "p",
        }

    def test_keeps_a_reachable_datasource(self):
        catalogue, env = self.mysql()

        code, out, _ = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["db"])

    def test_drops_an_unreachable_datasource(self):
        catalogue, env = self.mysql(port=self.dead_port)

        code, out, err = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("unreachable", err)

    def test_drops_a_datasource_missing_a_required_var(self):
        catalogue, env = self.mysql()
        del env["T_DB"]

        code, out, err = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("T_DB", err)

    def test_an_empty_required_var_counts_as_missing(self):
        catalogue, env = self.mysql()
        env["T_DB"] = ""

        code, out, err = self.run_filter(catalogue, env)

        self.assertEqual(json.loads(out), {})
        self.assertIn("T_DB", err)

    def test_keeps_an_env_complete_sqlite_datasource(self):
        # sqlite has no server, so env-completeness alone decides.
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

    def test_drops_a_non_numeric_port(self):
        catalogue, env = self.mysql()
        env["T_PORT"] = "not-a-port"

        code, out, err = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("unreachable", err)

    def test_only_the_usable_subset_is_emitted(self):
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

    def test_bad_arguments_are_an_error(self):
        code, _, err = self.run_filter({}, args=["--nope"])

        self.assertEqual(code, 1)
        self.assertIn("usage:", err)


if __name__ == "__main__":
    unittest.main()
