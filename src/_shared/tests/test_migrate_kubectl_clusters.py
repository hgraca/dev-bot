"""Tests for migrate_kubectl_clusters.py.

The catalogue moves from an array of `{name, context, region}` to an object keyed
by the AWS EKS cluster name. The rewrite is textual: the global config is
user-owned and carries comments, so re-serialising it is not an option.
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from migrate_kubectl_clusters import migrate  # noqa: E402
from read_jsonc import load_jsonc  # noqa: E402

BASE = '''{
  // the machine-wide catalogue
  "harness": "opencode-v2",
  "kubectl": {
    "profile": "devbot-agent",
    "credential_env": {
      "AWS_ACCESS_KEY_ID": "${AWS_KEY}",
      "AWS_SECRET_ACCESS_KEY": "${AWS_SECRET}"
    },
    "clusters": [
      { "name": "gete", "context": "gete-prod-ro", "region": "eu-central-1" },
      { "name": "gete-dev", "context": "gete-staging-rw", "region": "eu-central-1" }
    ]
  },
  "datasources": {
    "mariadb-dev": { "type": "mysql" }
  }
}
'''


class MigrateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, ".devbot.global.jsonc")
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(BASE)

    def tearDown(self):
        self.tmp.cleanup()

    def _text(self):
        with open(self.path, encoding="utf-8") as handle:
            return handle.read()

    def _write(self, text):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def test_up_keys_the_catalogue_by_cluster_name(self):
        self.assertTrue(migrate(self.path))
        clusters = load_jsonc(self.path)["kubectl"]["clusters"]
        self.assertEqual(sorted(clusters), ["gete", "gete-dev"])
        self.assertEqual(
            clusters["gete"],
            {"context": "gete-prod-ro", "region": "eu-central-1"},
        )

    def test_up_drops_the_name_redundant_with_the_key(self):
        migrate(self.path)
        for key, entry in load_jsonc(self.path)["kubectl"]["clusters"].items():
            self.assertNotIn("name", entry, key)

    def test_up_leaves_every_other_key_and_the_comments_alone(self):
        migrate(self.path)
        text = self._text()
        self.assertIn("// the machine-wide catalogue", text)
        self.assertIn('"profile": "devbot-agent"', text)
        self.assertIn('"AWS_SECRET_ACCESS_KEY": "${AWS_SECRET}"', text)
        self.assertIn('"mariadb-dev": { "type": "mysql" }', text)

    def test_up_is_idempotent(self):
        self.assertTrue(migrate(self.path))
        before = self._text()
        self.assertFalse(migrate(self.path))
        self.assertEqual(before, self._text())

    def test_down_restores_the_array(self):
        migrate(self.path)
        self.assertTrue(migrate(self.path, down=True))
        clusters = load_jsonc(self.path)["kubectl"]["clusters"]
        self.assertIsInstance(clusters, list)
        self.assertEqual([entry["name"] for entry in clusters], ["gete", "gete-dev"])
        self.assertEqual(clusters[1]["context"], "gete-staging-rw")

    def test_round_trip_restores_the_original(self):
        original = load_jsonc(self.path)
        migrate(self.path)
        migrate(self.path, down=True)
        self.assertEqual(original, load_jsonc(self.path))

    def test_down_keeps_the_aws_cluster_name_over_the_label(self):
        # The array has no label field, and the AWS cluster name is what keeps the
        # cluster reachable after a downgrade, so the key wins.
        self._write(
            '{\n  "kubectl": {\n    "clusters": {\n'
            '      "gete-prd": { "name": "gete", "context": "gete-prod-ro" }\n'
            "    }\n  }\n}\n"
        )
        migrate(self.path, down=True)
        entry = load_jsonc(self.path)["kubectl"]["clusters"][0]
        self.assertEqual(entry["name"], "gete-prd")
        self.assertEqual(entry["context"], "gete-prod-ro")

    def test_a_bom_prefixed_config_migrates(self):
        # The reader accepts a BOM; the span scanner must too, or the file reports
        # unchanged and init later refuses the legacy array it still holds.
        raw = open(self.path, "rb").read()
        with open(self.path, "wb") as handle:
            handle.write(b"\xef\xbb\xbf" + raw)
        self.assertTrue(migrate(self.path))
        clusters = load_jsonc(self.path)["kubectl"]["clusters"]
        self.assertEqual(sorted(clusters), ["gete", "gete-dev"])

    def test_the_rewrite_keeps_the_config_mode(self):
        os.chmod(self.path, 0o600)
        migrate(self.path)
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)

    def test_a_config_without_clusters_is_untouched(self):
        self._write('{\n  "kubectl": { "profile": "devbot-agent" }\n}\n')
        before = self._text()
        self.assertFalse(migrate(self.path))
        self.assertEqual(before, self._text())

    def test_a_config_without_a_kubectl_node_is_untouched(self):
        self._write('{\n  "harness": "opencode-v2"\n}\n')
        before = self._text()
        self.assertFalse(migrate(self.path))
        self.assertEqual(before, self._text())

    def test_an_empty_array_becomes_an_empty_object(self):
        self._write('{\n  "kubectl": {\n    "clusters": []\n  }\n}\n')
        self.assertTrue(migrate(self.path))
        self.assertEqual(load_jsonc(self.path)["kubectl"]["clusters"], {})

    def test_comments_inside_the_array_do_not_break_the_span(self):
        self._write(
            "{\n  \"kubectl\": {\n    \"clusters\": [\n"
            "      // production, read-only\n"
            "      { \"name\": \"gete\", \"region\": \"eu-central-1\" }\n"
            "    ]\n  }\n}\n"
        )
        self.assertTrue(migrate(self.path))
        self.assertEqual(
            load_jsonc(self.path)["kubectl"]["clusters"],
            {"gete": {"region": "eu-central-1"}},
        )


if __name__ == "__main__":
    unittest.main()
