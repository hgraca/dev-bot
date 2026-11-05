#!/usr/bin/env python3
"""Unit tests for the diagnostics strip's batching and backup reservation."""

import os
import sqlite3
import tempfile
import unittest
from unittest import mock

from strip_opencode_diagnostics import (
    BATCH_BYTES,
    BATCH_ROWS,
    _batches,
    _candidates,
    _reserve_backup,
)


class BatchesTest(unittest.TestCase):
    def test_a_large_payload_gets_a_batch_of_its_own(self):
        # 18 MB parts: a row count alone would put 250 of them in one write.
        rows = [(i, 18 * 1024 * 1024, 0) for i in range(10)]
        batches = list(_batches(rows))
        self.assertEqual([len(batch) for batch in batches], [1] * len(rows))

    def test_a_batch_is_capped_by_row_count(self):
        rows = [(i, 16, 0) for i in range(BATCH_ROWS * 2 + 1)]
        batches = list(_batches(rows))
        self.assertTrue(all(len(batch) <= BATCH_ROWS for batch in batches))
        self.assertEqual(len(batches), 3)

    def test_a_batch_is_capped_by_bytes(self):
        rows = [(i, BATCH_BYTES // 3, 0) for i in range(9)]
        batches = list(_batches(rows))
        self.assertEqual([len(batch) for batch in batches], [3, 3, 3])

    def test_every_row_appears_exactly_once_in_order(self):
        rows = [(i, BATCH_BYTES // 4, 0) for i in range(11)]
        flat = [rowid for batch in _batches(rows) for rowid in batch]
        self.assertEqual(flat, [rowid for rowid, _, _ in rows])


class PayloadSizeTest(unittest.TestCase):
    def test_candidates_measure_utf8_bytes_not_characters(self):
        text = '{"diagnostics":"' + "\u4e2d" * 1000 + '"}'
        con = sqlite3.connect(":memory:")
        con.execute("CREATE TABLE part(id TEXT, data TEXT)")
        con.execute("INSERT INTO part VALUES('a', ?)", (text,))

        rows = _candidates(con, "part")

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][1], len(text.encode("utf-8")))


class BackupReservationTest(unittest.TestCase):
    def _database(self, directory):
        path = os.path.join(directory, "opencode.db")
        open(path, "w").close()
        os.chmod(path, 0o600)
        return path

    def test_reserves_unique_names_with_the_database_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(directory)
            with mock.patch(
                "strip_opencode_diagnostics.time.strftime", return_value="20260101T000000"
            ):
                first = _reserve_backup(db)
                second = _reserve_backup(db)

            assert first is not None and second is not None
            self.assertNotEqual(first, second)
            for path in (first, second):
                self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
                self.assertTrue(os.path.isfile(path))

    def test_a_filesystem_error_propagates(self):
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(directory)
            with mock.patch(
                "strip_opencode_diagnostics.os.open",
                side_effect=PermissionError("read-only"),
            ):
                with self.assertRaises(OSError):
                    _reserve_backup(db)


if __name__ == "__main__":
    unittest.main()
