#!/usr/bin/env python3
"""Unit tests for the shared session-usage CLI and renderer."""
import contextlib
import io
import json
import os
import sqlite3
import tempfile
import unittest
from unittest import mock

import session_usage

SESSION_ID = "ses_fixture"


def build_db(path, total=277304):
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE session (
            id text PRIMARY KEY,
            directory text NOT NULL,
            model text,
            tokens_input integer DEFAULT 0 NOT NULL
        );
        CREATE TABLE part (
            id text PRIMARY KEY,
            session_id text NOT NULL,
            time_created integer NOT NULL,
            data text NOT NULL
        );
        """
    )
    conn.execute(
        "INSERT INTO session (id, directory, model) VALUES (?, ?, ?)",
        (
            SESSION_ID,
            "/project",
            json.dumps({"id": "deepseek-flash", "providerID": "deepseek"}),
        ),
    )
    conn.execute(
        "INSERT INTO part (id, session_id, time_created, data) VALUES (?, ?, ?, ?)",
        ("prt_1", SESSION_ID, 1000, json.dumps({"type": "step-finish", "tokens": {"total": total}})),
    )
    conn.commit()
    conn.close()


class MainTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.db = os.path.join(self._dir.name, "opencode.db")
        build_db(self.db)
        self.catalog = os.path.join(self._dir.name, "models.json")
        with open(self.catalog, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "deepseek": {
                        "models": {
                            "deepseek-flash": {"limit": {"context": 1048576}},
                        }
                    }
                },
                fh,
            )
        self.project = os.path.join(self._dir.name, "project")
        os.makedirs(self.project)
        self.env = {
            "OPENCODE_DB_PATH": self.db,
            "OPENCODE_MODELS_JSON": self.catalog,
            "CLAUDE_PROJECTS_DIR": os.path.join(self._dir.name, "claude"),
        }

    def tearDown(self):
        self._dir.cleanup()

    def run_cli(self, argv, env=None):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, {**self.env, **(env or {})}, clear=False):
            for key in ("DEV_BOT_SESSION_ID",):
                if key not in (env or {}):
                    os.environ.pop(key, None)
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = session_usage.main(argv)
        return rc, out.getvalue(), err.getvalue()

    def test_json_reports_tokens_limit_and_percent(self):
        rc, out, _ = self.run_cli(
            ["--harness", "opencode", "--session", SESSION_ID, "--json"]
        )

        self.assertEqual(rc, 0)
        self.assertEqual(
            json.loads(out),
            {
                "session": SESSION_ID,
                "harness": "opencode",
                "model": "deepseek/deepseek-flash",
                "context_tokens": 277304,
                "context_limit": 1048576,
                "percent": 26.4,
            },
        )

    def test_text_is_one_human_line(self):
        rc, out, _ = self.run_cli(["--harness", "opencode", "--session", SESSION_ID])

        self.assertEqual(rc, 0)
        self.assertEqual(
            out.strip(),
            "context 277,304 / 1,048,576 (26.4%) — deepseek/deepseek-flash · ses_fixture",
        )

    def test_session_falls_back_to_the_environment_variable(self):
        rc, out, _ = self.run_cli(
            ["--harness", "opencode", "--json"],
            env={"DEV_BOT_SESSION_ID": SESSION_ID},
        )

        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)["session"], SESSION_ID)

    def test_session_falls_back_to_the_harness_marker_file(self):
        logs = os.path.join(self.project, ".agents", "logs")
        os.makedirs(logs)
        with open(os.path.join(logs, "session-opencode"), "w", encoding="utf-8") as fh:
            fh.write(SESSION_ID + "\n")

        rc, out, _ = self.run_cli(
            ["--harness", "opencode", "--json", "--project-dir", self.project]
        )

        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)["session"], SESSION_ID)

    def test_missing_session_is_an_error_with_the_hint(self):
        rc, out, err = self.run_cli(["--harness", "opencode"])

        self.assertEqual(rc, 1)
        self.assertEqual(out, "")
        self.assertIn("ERROR:", err)
        self.assertIn("--session", err)
        self.assertIn("DEV_BOT_SESSION_ID", err)

    def test_unknown_session_is_an_error(self):
        rc, out, err = self.run_cli(
            ["--harness", "opencode", "--session", "ses_absent"]
        )

        self.assertEqual(rc, 1)
        self.assertEqual(out, "")
        self.assertIn("unknown session", err)

    def test_unknown_model_leaves_the_percentage_null(self):
        with open(self.catalog, "w", encoding="utf-8") as fh:
            json.dump({"deepseek": {"models": {}}}, fh)

        rc, out, _ = self.run_cli(
            ["--harness", "opencode", "--session", SESSION_ID, "--json"]
        )

        self.assertEqual(rc, 0)
        payload = json.loads(out)
        self.assertIsNone(payload["context_limit"])
        self.assertIsNone(payload["percent"])

    def test_an_escaping_devbot_dir_falls_back_to_agents(self):
        with open(
            os.path.join(self.project, ".devbot.project.jsonc"), "w", encoding="utf-8"
        ) as fh:
            fh.write('{"devbot_dir":"../outside"}\n')
        logs = os.path.join(self.project, ".agents", "logs")
        os.makedirs(logs)
        with open(os.path.join(logs, "session-opencode"), "w", encoding="utf-8") as fh:
            fh.write(SESSION_ID + "\n")

        rc, out, _ = self.run_cli(
            ["--harness", "opencode", "--json", "--project-dir", self.project],
            env={"DEV_BOT_SESSION_ID": ""},
        )

        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)["session"], SESSION_ID)

    def test_explicit_session_beats_the_environment(self):
        rc, out, _ = self.run_cli(
            ["--harness", "opencode", "--session", SESSION_ID, "--json"],
            env={"DEV_BOT_SESSION_ID": "ses_absent"},
        )

        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)["session"], SESSION_ID)

    def test_environment_beats_the_marker(self):
        logs = os.path.join(self.project, ".agents", "logs")
        os.makedirs(logs)
        with open(os.path.join(logs, "session-opencode"), "w", encoding="utf-8") as fh:
            fh.write("ses_absent\n")

        rc, out, _ = self.run_cli(
            ["--harness", "opencode", "--json", "--project-dir", self.project],
            env={"DEV_BOT_SESSION_ID": SESSION_ID},
        )

        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out)["session"], SESSION_ID)

    def test_unknown_limit_text_says_unknown(self):
        with open(self.catalog, "w", encoding="utf-8") as fh:
            json.dump({"deepseek": {"models": {}}}, fh)

        rc, out, _ = self.run_cli(["--harness", "opencode", "--session", SESSION_ID])

        self.assertEqual(rc, 0)
        self.assertIn("(limit unknown)", out)

    def test_missing_database_is_a_loud_error(self):
        rc, out, err = self.run_cli(
            ["--harness", "opencode", "--session", SESSION_ID],
            env={"OPENCODE_DB_PATH": os.path.join(self._dir.name, "absent.db")},
        )

        self.assertEqual(rc, 1)
        self.assertEqual(out, "")
        self.assertIn("cannot read", err)

    def test_claudecode_runs_end_to_end(self):
        projects = os.path.join(self._dir.name, "claude")
        slug = os.path.join(projects, "-project")
        os.makedirs(slug)
        line = {
            "type": "assistant",
            "sessionId": "claude-session",
            "message": {
                "model": "claude-opus-5-5",
                "usage": {
                    "input_tokens": 300,
                    "cache_read_input_tokens": 148000,
                    "cache_creation_input_tokens": 500,
                    "output_tokens": 1,
                },
            },
        }
        with open(
            os.path.join(slug, "claude-session.jsonl"), "w", encoding="utf-8"
        ) as fh:
            fh.write(json.dumps(line) + "\n")
        with open(self.catalog, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "anthropic": {
                        "models": {"claude-opus-5-5": {"limit": {"context": 1000000}}}
                    }
                },
                fh,
            )

        rc, out, _ = self.run_cli(
            ["--harness", "claudecode", "--session", "claude-session", "--json"]
        )

        self.assertEqual(rc, 0)
        self.assertEqual(
            json.loads(out),
            {
                "session": "claude-session",
                "harness": "claudecode",
                "model": "anthropic/claude-opus-5-5",
                "context_tokens": 148801,
                "context_limit": 1000000,
                "percent": 14.9,
            },
        )

    def test_unknown_harness_is_an_error(self):
        rc, out, err = self.run_cli(
            ["--harness", "carrier-pigeon", "--session", SESSION_ID]
        )

        self.assertEqual(rc, 1)
        self.assertEqual(out, "")
        self.assertIn("unsupported harness", err)


if __name__ == "__main__":
    unittest.main()
