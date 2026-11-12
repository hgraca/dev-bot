#!/usr/bin/env python3
"""Unit tests for the shared model-context-limit resolver."""
import json
import os
import tempfile
import unittest
from unittest import mock

from model_limit import resolve

CATALOG = {
    "deepseek": {
        "models": {
            "deepseek-flash": {
                "id": "deepseek-flash",
                "canonical_model_id": "deepseek/deepseek-flash",
                "limit": {"context": 1048576, "output": 65536},
            }
        }
    },
    "anthropic": {
        "models": {
            "claude-opus-5-5": {
                "id": "claude-opus-5-5",
                "canonical_model_id": "anthropic/claude-opus-5-5",
                "limit": {"context": 1000000},
            }
        }
    },
}


class ResolveTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.catalog = os.path.join(self._dir.name, "models.json")
        with open(self.catalog, "w", encoding="utf-8") as fh:
            json.dump(CATALOG, fh)

    def tearDown(self):
        self._dir.cleanup()

    def test_exact_provider_and_model(self):
        self.assertEqual(resolve("deepseek", "deepseek-flash", self.catalog), 1048576)

    def test_same_id_under_another_provider_is_not_used(self):
        # Hosting the same id elsewhere can mean a different context window.
        self.assertIsNone(resolve("claude", "claude-opus-5-5", self.catalog))

    def test_canonical_id_matches_across_providers(self):
        with open(self.catalog, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "gateway": {
                        "models": {
                            "claude-opus-5-5": {
                                "canonical_model_id": "anthropic/claude-opus-5-5",
                                "limit": {"context": 1000000},
                            }
                        }
                    }
                },
                fh,
            )
        self.assertEqual(resolve("anthropic", "claude-opus-5-5", self.catalog), 1000000)

    def test_unknown_model_is_none(self):
        self.assertIsNone(resolve("deepseek", "not-a-model", self.catalog))

    def test_missing_catalog_is_none(self):
        missing = os.path.join(self._dir.name, "absent.json")
        self.assertIsNone(resolve("deepseek", "deepseek-flash", missing))

    def test_corrupt_catalog_is_none(self):
        with open(self.catalog, "w", encoding="utf-8") as fh:
            fh.write("{not json")
        self.assertIsNone(resolve("deepseek", "deepseek-flash", self.catalog))

    def test_limit_without_a_context_key_is_none(self):
        with open(self.catalog, "w", encoding="utf-8") as fh:
            json.dump({"p": {"models": {"m": {"limit": {"output": 10}}}}}, fh)
        self.assertIsNone(resolve("p", "m", self.catalog))

    def test_catalog_is_found_under_xdg_cache_home(self):
        cache = os.path.join(self._dir.name, "cache")
        os.makedirs(os.path.join(cache, "opencode"))
        with open(os.path.join(cache, "opencode", "models.json"), "w", encoding="utf-8") as fh:
            json.dump(CATALOG, fh)

        with mock.patch.dict(
            os.environ, {"XDG_CACHE_HOME": cache}, clear=False
        ):
            os.environ.pop("OPENCODE_MODELS_JSON", None)
            self.assertEqual(resolve("deepseek", "deepseek-flash"), 1048576)


if __name__ == "__main__":
    unittest.main()
