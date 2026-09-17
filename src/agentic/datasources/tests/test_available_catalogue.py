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
        # Values are ${VAR} REFERENCES, so the tests drive them from the
        # environment exactly as an operator would.
        return (
            {
                "db": {
                    "type": "mysql",
                    "env": {key: "${" + val + "}" for key, val in MYSQL_ENV_KEYS.items()},
                }
            },
            {
                "T_HOST": "127.0.0.1",
                "T_PORT": str(port if port is not None else self.live_port),
                "T_DB": "d",
                "T_USER": "u",
                "T_PASS": "p",
            },
        )

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
        del env["T_PASS"]

        code, out, err = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("T_PASS", err)

    def test_an_empty_required_var_counts_as_missing(self):
        catalogue, env = self.mysql()
        env["T_PASS"] = ""

        code, out, err = self.run_filter(catalogue, env)

        self.assertEqual(json.loads(out), {})
        self.assertIn("T_PASS", err)

    def test_database_is_not_required_for_mysql(self):
        # One instance holds several DBs; no default schema is a valid setup.
        catalogue, env = self.mysql()
        del env["T_DB"]

        code, out, _ = self.run_filter(catalogue, env)

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["db"])

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

    def test_a_literal_satisfies_a_required_field(self):
        # A literal can never be missing, so it must never gate a datasource
        # out — and it needs no environment variable at all.
        code, out, _ = self.run_filter(
            {
                "db": {
                    "type": "mysql",
                    "env": {
                        "MYSQL_HOST": "127.0.0.1",
                        "MYSQL_PORT": self.live_port,
                        "MYSQL_USER": "root",
                        "MYSQL_PASSWORD": "literal-pass",
                    },
                }
            }
        )

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["db"])

    def test_a_literal_host_is_probed(self):
        # A literal is a real value, so the probe uses it — an unreachable
        # literal host must still exclude the datasource.
        code, out, err = self.run_filter(
            {
                "db": {
                    "type": "mysql",
                    "env": {
                        "MYSQL_HOST": "127.0.0.1",
                        "MYSQL_PORT": self.dead_port,
                        "MYSQL_USER": "root",
                        "MYSQL_PASSWORD": "p",
                    },
                }
            }
        )

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("unreachable", err)

    def test_probes_a_mongodb_uri(self):
        # The whole connection is one URI, so host and port come from parsing
        # it. Credentials and query options are part of the real thing.
        code, out, _ = self.run_filter(
            {
                "events": {
                    "type": "mongodb",
                    "env": {
                        "MONGODB_URI": f"mongodb://user:pw@127.0.0.1:{self.live_port}/events?retryWrites=true",
                        "MONGODB_DATABASE": "events",
                    },
                }
            }
        )

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["events"])

    def test_mongodb_database_is_required(self):
        # mongodb-aggregate requires a database and the field has no default,
        # so a datasource without one must be kept out of the gateway config.
        code, out, err = self.run_filter(
            {"events": {"type": "mongodb", "env": {"MONGODB_URI": "mongodb://127.0.0.1:1/db"}}}
        )

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("MONGODB_DATABASE", err)

    def test_a_mongodb_uri_without_a_host_is_not_usable(self):
        code, out, err = self.run_filter(
            {
                "events": {
                    "type": "mongodb",
                    "env": {"MONGODB_URI": "not-a-uri", "MONGODB_DATABASE": "d"},
                }
            }
        )

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("no host", err)

    def test_probes_a_redis_address(self):
        # redis names the endpoint in one `address` value rather than host/port.
        code, out, _ = self.run_filter(
            {"cache": {"type": "redis", "env": {"REDIS_ADDRESS": f"127.0.0.1:{self.live_port}"}}}
        )

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["cache"])

    def test_redis_optional_credentials_do_not_gate(self):
        # No username/password declared and none in the environment: the source
        # omits them, so the datasource is still usable.
        code, out, _ = self.run_filter(
            {"cache": {"type": "redis", "env": {"REDIS_ADDRESS": f"127.0.0.1:{self.live_port}"}}}
        )

        self.assertEqual(code, 0)
        self.assertEqual(list(json.loads(out)), ["cache"])

    def test_a_redis_address_without_a_port_uses_the_default(self):
        # A bare host still probes — on 6379, where nothing is listening here.
        code, out, err = self.run_filter(
            {"cache": {"type": "redis", "env": {"REDIS_ADDRESS": "127.0.0.1-not-here"}}}
        )

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {})
        self.assertIn("unreachable", err)

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
