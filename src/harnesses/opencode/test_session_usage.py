#!/usr/bin/env python3
"""Unit tests for the opencode session-usage adapter."""
import json
import os
import sqlite3
import tempfile
import unittest

from session_usage import gather

SESSION_ID = "ses_fixture"


def build_db(path, steps, model=None, session_id=SESSION_ID):
    """Create a minimal opencode database with the columns the adapter reads."""
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
            session_id,
            "/project",
            json.dumps(model) if model is not None else None,
        ),
    )
    for index, (kind, payload) in enumerate(steps):
        conn.execute(
            "INSERT INTO part (id, session_id, time_created, data) VALUES (?, ?, ?, ?)",
            (
                f"prt_{index}",
                session_id,
                1000 + index,
                json.dumps({"type": kind, **payload}),
            ),
        )
    conn.commit()
    conn.close()


class GatherTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.db = os.path.join(self._dir.name, "opencode.db")

    def tearDown(self):
        self._dir.cleanup()

    def test_uses_the_latest_step_finish_total(self):
        build_db(
            self.db,
            [
                ("step-finish", {"tokens": {"total": 100}}),
                ("text", {"text": "ignored"}),
                ("step-finish", {"tokens": {"total": 277304}}),
            ],
            model={"id": "deepseek-flash", "providerID": "deepseek"},
        )

        report = gather(SESSION_ID, self.db)

        self.assertEqual(report["context_tokens"], 277304)
        self.assertEqual(report["model"], "deepseek-flash")
        self.assertEqual(report["provider"], "deepseek")
        self.assertEqual(report["session"], SESSION_ID)

    def test_unknown_session_reports_an_error(self):
        build_db(self.db, [("step-finish", {"tokens": {"total": 1}})])

        report = gather("ses_absent", self.db)

        self.assertEqual(report["error"], "unknown-session")

    def test_session_without_a_step_finish_reports_no_usage(self):
        build_db(self.db, [("text", {"text": "still thinking"})])

        report = gather(SESSION_ID, self.db)

        self.assertEqual(report["error"], "no-usage")

    def test_reads_modelID_when_the_metadata_uses_it(self):
        build_db(
            self.db,
            [("step-finish", {"tokens": {"total": 42}})],
            model={"modelID": "deepseek-flash", "providerID": "deepseek"},
        )

        report = gather(SESSION_ID, self.db)

        self.assertEqual(report["model"], "deepseek-flash")
        self.assertEqual(report["provider"], "deepseek")

    def test_time_created_tie_prefers_the_later_row(self):
        build_db(self.db, [])
        conn = sqlite3.connect(self.db)
        for index, total in ((0, 10), (1, 20)):
            conn.execute(
                "INSERT INTO part (id, session_id, time_created, data) VALUES (?, ?, ?, ?)",
                (
                    f"tie_{index}",
                    SESSION_ID,
                    5000,
                    json.dumps({"type": "step-finish", "tokens": {"total": total}}),
                ),
            )
        conn.commit()
        conn.close()

        self.assertEqual(gather(SESSION_ID, self.db)["context_tokens"], 20)

    def test_missing_database_reports_an_error(self):
        report = gather(SESSION_ID, os.path.join(self._dir.name, "absent.db"))

        self.assertEqual(report["error"], "no-database")


if __name__ == "__main__":
    unittest.main()
