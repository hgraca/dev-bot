#!/usr/bin/env python3
"""Unit tests for the claudecode session-usage adapter."""
import json
import os
import tempfile
import unittest

from session_usage import gather

SESSION_ID = "42983c8e-7a9d-4fc1-aaaa-64c7a3e89959"


def assistant(session_id, model, input_tokens, cache_read, cache_write, output):
    return {
        "type": "assistant",
        "sessionId": session_id,
        "message": {
            "model": model,
            "usage": {
                "input_tokens": input_tokens,
                "cache_read_input_tokens": cache_read,
                "cache_creation_input_tokens": cache_write,
                "output_tokens": output,
            },
        },
    }


class GatherTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self._dir.name, "projects")
        slug = os.path.join(self.projects, "-project")
        os.makedirs(slug)
        self.transcript = os.path.join(slug, f"{SESSION_ID}.jsonl")
        self.model = "claude-opus-5-5"

    def tearDown(self):
        self._dir.cleanup()

    def _write(self, lines):
        with open(self.transcript, "w", encoding="utf-8") as fh:
            for line in lines:
                fh.write(json.dumps(line) + "\n")

    def test_uses_the_last_assistant_usage(self):
        self._write(
            [
                {"type": "user", "sessionId": SESSION_ID, "message": {"content": "hi"}},
                assistant(SESSION_ID, self.model, 2, 100, 5, 7),
                assistant(SESSION_ID, self.model, 1, 300, 0, 9),
            ]
        )

        report = gather(SESSION_ID, self.projects)

        self.assertEqual(report["context_tokens"], 310)
        self.assertEqual(report["model"], self.model)
        self.assertEqual(report["session"], SESSION_ID)

    def test_transcript_without_usage_reports_no_usage(self):
        self._write([{"type": "user", "sessionId": SESSION_ID}])

        report = gather(SESSION_ID, self.projects)

        self.assertEqual(report["error"], "no-usage")

    def test_unknown_session_reports_an_error(self):
        self._write([assistant(SESSION_ID, self.model, 1, 1, 1, 1)])

        report = gather("absent-session", self.projects)

        self.assertEqual(report["error"], "unknown-session")

    def test_a_glob_or_path_session_id_is_rejected(self):
        self._write([assistant(SESSION_ID, self.model, 1, 1, 1, 1)])

        for bad in ("*", "../x", "a/b", ""):
            self.assertEqual(gather(bad, self.projects)["error"], "unknown-session")

    def test_blank_lines_and_bad_json_are_skipped(self):
        with open(self.transcript, "w", encoding="utf-8") as fh:
            fh.write("\n")
            fh.write("{not json\n")
            fh.write(json.dumps(assistant(SESSION_ID, self.model, 4, 40, 0, 6)) + "\n")

        report = gather(SESSION_ID, self.projects)

        self.assertEqual(report["context_tokens"], 50)


if __name__ == "__main__":
    unittest.main()
