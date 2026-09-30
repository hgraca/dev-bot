#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_demand.py
# Unit tests for the sidecar demand helper: which sidecars a set of project
# opt-in lists actually wants.
# =============================================================================

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEMAND = os.path.join(MODULE_DIR, "demand.py")
sys.path.insert(0, MODULE_DIR)

import demand  # noqa: E402


CATALOGUE = {
    "hotels": {"type": "mysql", "env": {}},
    "opensearch-prod": {"type": "opensearch", "env": {}},
    "s3-prod": {"type": "s3", "env": {}},
}


def run_cli(args, catalogue=CATALOGUE):
    proc = subprocess.run(
        [sys.executable, DEMAND, *args],
        input=json.dumps(catalogue),
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def _write(path, body):
    with open(path, "w") as handle:
        handle.write(body)


class TestDemandedSidecars(unittest.TestCase):
    def test_demands_a_referenced_sidecar(self):
        self.assertEqual(
            demand.demanded_sidecars(CATALOGUE, [["opensearch-prod"]]),
            {"opensearch-prod"},
        )

    def test_unions_across_opt_in_lists(self):
        self.assertEqual(
            demand.demanded_sidecars(CATALOGUE, [["opensearch-prod"], ["s3-prod"]]),
            {"opensearch-prod", "s3-prod"},
        )

    def test_a_toolbox_engine_is_never_a_sidecar(self):
        self.assertEqual(demand.demanded_sidecars(CATALOGUE, [["hotels"]]), set())

    def test_an_unknown_name_is_ignored(self):
        self.assertEqual(demand.demanded_sidecars(CATALOGUE, [["nope"]]), set())

    def test_no_opt_in_demands_nothing(self):
        self.assertEqual(demand.demanded_sidecars(CATALOGUE, []), set())


class TestFilterDemandedSidecars(unittest.TestCase):
    def test_drops_an_undemanded_sidecar_and_keeps_the_rest(self):
        filtered = demand.filter_demanded_sidecars(CATALOGUE, [["opensearch-prod"]])
        self.assertEqual(set(filtered), {"hotels", "opensearch-prod"})

    def test_keeps_every_toolbox_entry_regardless_of_demand(self):
        filtered = demand.filter_demanded_sidecars(CATALOGUE, [["s3-prod"]])
        self.assertIn("hotels", filtered)
        self.assertIn("s3-prod", filtered)
        self.assertNotIn("opensearch-prod", filtered)

    def test_no_demand_leaves_only_toolbox_engines(self):
        filtered = demand.filter_demanded_sidecars(CATALOGUE, [])
        self.assertEqual(set(filtered), {"hotels"})

    def test_preserves_catalogue_order(self):
        filtered = demand.filter_demanded_sidecars(CATALOGUE, [["s3-prod"]])
        self.assertEqual(list(filtered), ["hotels", "s3-prod"])


class TestCli(unittest.TestCase):
    def test_names_prints_the_demanded_sidecars(self):
        code, out, _ = run_cli(["--names", "opensearch-prod"])
        self.assertEqual(code, 0)
        self.assertEqual(out.split(), ["opensearch-prod"])

    def test_names_prints_nothing_when_nothing_is_demanded(self):
        code, out, _ = run_cli(["--names"])
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "")

    def test_filter_prints_the_reduced_catalogue(self):
        code, out, _ = run_cli(["--filter", "opensearch-prod"])
        self.assertEqual(code, 0)
        self.assertEqual(set(json.loads(out)), {"hotels", "opensearch-prod"})

    def test_an_unknown_mode_fails_loudly(self):
        code, _, err = run_cli(["--bogus"])
        self.assertEqual(code, 1)
        self.assertIn("ERROR:", err)


class TestProjectOptins(unittest.TestCase):
    def test_reads_the_opt_in_list(self):
        with tempfile.TemporaryDirectory() as d:
            _write(
                os.path.join(d, ".devbot.project.jsonc"),
                '{"datasources": ["opensearch-prod", "s3-prod"]}\n',
            )
            self.assertEqual(demand.project_optins(d), ["opensearch-prod", "s3-prod"])

    def test_a_missing_project_dir_opts_into_nothing(self):
        self.assertEqual(demand.project_optins("/no/such/dir"), [])

    def test_a_non_list_value_opts_into_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            _write(os.path.join(d, ".devbot.project.jsonc"), '{"datasources": "oops"}\n')
            self.assertEqual(demand.project_optins(d), [])


class TestStaticOptinNames(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.listed = os.path.join(self.root, "listed")
        self.current = os.path.join(self.root, "current")
        os.makedirs(self.listed)
        os.makedirs(self.current)
        self.global_config = os.path.join(self.root, ".devbot.global.jsonc")

    def test_a_listed_project_demands_its_datasources(self):
        _write(
            os.path.join(self.listed, ".devbot.project.jsonc"),
            '{"datasources": ["search"]}\n',
        )
        _write(self.global_config, json.dumps({"projects": [self.listed]}))

        self.assertEqual(demand.static_optin_names(self.global_config), ["search"])

    def test_the_explicit_project_is_added(self):
        _write(
            os.path.join(self.current, ".devbot.project.jsonc"),
            '{"datasources": ["s3-prod"]}\n',
        )
        _write(self.global_config, json.dumps({"projects": []}))

        self.assertEqual(
            demand.static_optin_names(self.global_config, self.current), ["s3-prod"]
        )

    def test_a_listed_path_that_does_not_exist_is_skipped(self):
        _write(self.global_config, json.dumps({"projects": ["/no/such/dir"]}))

        self.assertEqual(demand.static_optin_names(self.global_config), [])

    def test_a_missing_global_config_still_reads_the_explicit_project(self):
        _write(
            os.path.join(self.current, ".devbot.project.jsonc"),
            '{"datasources": ["s3-prod"]}\n',
        )

        self.assertEqual(
            demand.static_optin_names(
                os.path.join(self.root, "absent.jsonc"), self.current
            ),
            ["s3-prod"],
        )


class TestStaticCli(unittest.TestCase):
    def test_static_filter_drops_a_sidecar_nobody_lists(self):
        with tempfile.TemporaryDirectory() as d:
            listed = os.path.join(d, "listed")
            os.makedirs(listed)
            _write(
                os.path.join(listed, ".devbot.project.jsonc"),
                '{"datasources": ["s3-prod"]}\n',
            )
            config = os.path.join(d, ".devbot.global.jsonc")
            _write(config, json.dumps({"projects": [listed]}))

            code, out, _ = run_cli(["--static-filter", config])

        self.assertEqual(code, 0)
        self.assertEqual(set(json.loads(out)), {"hotels", "s3-prod"})


if __name__ == "__main__":
    unittest.main()
