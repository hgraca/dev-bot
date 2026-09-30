#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_demand.py
# Unit tests for the sidecar demand helper: which sidecars a set of project
# opt-in lists actually wants.
# =============================================================================

import json
import os
import subprocess
import sys
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


if __name__ == "__main__":
    unittest.main()
