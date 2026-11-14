"""Handover cases for the v1 -> v2 config migration."""

import importlib.util
import os
import unittest

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "migrate_v1.py")


def load():
    spec = importlib.util.spec_from_file_location("migrate_v1", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def names(entries):
    out = []
    for entry in entries:
        if isinstance(entry, str):
            out.append(entry)
        elif isinstance(entry, dict):
            out.append(str(entry.get("package", "")))
        else:
            out.append("")
    return out


class HandoverPluginMergeTest(unittest.TestCase):
    def test_v2_registrations_survive_a_legacy_plugin_key(self):
        # A v1 init run leaves its `plugin` key beside v2's `plugins`; the
        # migration must not replace the v2 registrations with the legacy list.
        out, _report = load().migrate(
            {
                "plugins": ["@devbot/required-plugin"],
                "plugin": [["legacy-plugin", {"opt": 1}]],
            }
        )
        self.assertIn("@devbot/required-plugin", names(out["plugins"]))
        self.assertIn("legacy-plugin", names(out["plugins"]))

    def test_a_package_present_in_both_shapes_is_kept_once(self):
        out, _report = load().migrate(
            {
                "plugins": [{"package": "shared-plugin", "options": {"v2": True}}],
                "plugin": [["shared-plugin", {"opt": 1}]],
            }
        )
        self.assertEqual(names(out["plugins"]).count("shared-plugin"), 1)

    def test_v2_sections_survive_a_legacy_key(self):
        out, _report = load().migrate(
            {
                "agents": {"mine": {"system": "keep me"}},
                "providers": {"acme": {"package": "@acme/v2"}},
                "mcp": {"servers": {"keep": {"type": "remote"}}},
                "agent": {"legacy": {"prompt": "x"}},
            }
        )
        self.assertIn("mine", out["agents"])
        self.assertIn("legacy", out["agents"])
        self.assertIn("acme", out["providers"])
        self.assertEqual(out["mcp"], {"servers": {"keep": {"type": "remote"}}})

    def test_existing_plugins_survive_when_another_legacy_key_migrates(self):
        out, _report = load().migrate(
            {
                "plugins": [".opencode/plugins/pty"],
                "agent": {"legacy": {"prompt": "x"}},
            }
        )
        self.assertEqual(names(out["plugins"]), [".opencode/plugins/pty"])

    def test_a_local_plugin_path_is_reported_not_silently_dropped(self):
        out, report = load().migrate({"plugin": ["./x.ts"]})
        self.assertIn("./x.ts", names(out["plugins"]))
        self.assertTrue(any("local file" in line for line in report), report)


if __name__ == "__main__":
    unittest.main()
