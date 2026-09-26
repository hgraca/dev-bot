#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_s3_ops.py
# Unit tests for the read-only S3 sidecar's operations.
#
# The ops layer takes a client, so everything here runs with a fake — no boto3,
# no credentials, no network. The MCP/HTTP shell in server.py is exercised by the
# committed container, not here.
# =============================================================================

import base64
import os
import sys
import unittest

S3_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "s3-mcp"
)
sys.path.insert(0, S3_DIR)

import ops  # noqa: E402


class _Body:
    def __init__(self, data):
        self._data = data
        self.read_calls = 0
        self.read_sizes = []

    def read(self, size=-1):
        self.read_calls += 1
        self.read_sizes.append(size)
        return self._data if size is None or size < 0 else self._data[:size]


class _FakeS3:
    """The boto3 client surface ops.py uses, and a record of what was asked."""

    def __init__(self, *, buckets=(), objects=None, body=b"", size=None, content_type=None):
        self._buckets = list(buckets)
        self._objects = objects or []
        self._body = _Body(body)
        self._size = len(body) if size is None else size
        self._content_type = content_type
        self.calls = []

    def list_buckets(self):
        self.calls.append(("list_buckets",))
        return {"Buckets": [{"Name": name} for name in self._buckets]}

    def list_objects_v2(self, Bucket, Prefix="", MaxKeys=100):
        self.calls.append(("list_objects_v2", Bucket, Prefix, MaxKeys))
        return {"Contents": self._objects, "IsTruncated": len(self._objects) >= MaxKeys}

    def head_object(self, Bucket, Key):
        self.calls.append(("head_object", Bucket, Key))
        return {
            "ContentLength": self._size,
            "ContentType": self._content_type,
            "LastModified": "2026-01-02T03:04:05Z",
            "ETag": '"abc"',
        }

    def get_object(self, Bucket, Key):
        self.calls.append(("get_object", Bucket, Key))
        return {"ContentLength": self._size, "Body": self._body}


class TestS3Ops(unittest.TestCase):
    def test_list_buckets_returns_the_names(self):
        result = ops.list_buckets(_FakeS3(buckets=["alpha", "beta"]))

        self.assertEqual(result, {"buckets": ["alpha", "beta"]})

    def test_list_objects_maps_key_size_and_truncation(self):
        s3 = _FakeS3(objects=[{"Key": "a/b.txt", "Size": 12}])

        result = ops.list_objects(s3, "bkt", prefix="a/", max_keys=1)

        self.assertEqual(result["bucket"], "bkt")
        self.assertEqual(result["prefix"], "a/")
        self.assertTrue(result["truncated"])
        self.assertEqual(result["objects"][0], {"key": "a/b.txt", "size": 12, "last_modified": ""})

    def test_head_object_returns_metadata_without_a_body(self):
        s3 = _FakeS3(body=b"ignored", content_type="text/plain")

        result = ops.head_object(s3, "bkt", "k")

        self.assertEqual(result["content_type"], "text/plain")
        self.assertEqual(s3._body.read_calls, 0)

    def test_get_object_returns_text(self):
        result = ops.get_object(_FakeS3(body=b'{"a": 1}'), "bkt", "k")

        self.assertEqual(result["text"], '{"a": 1}')

    def test_get_object_returns_base64_for_binary(self):
        payload = bytes(range(256))

        result = ops.get_object(_FakeS3(body=payload), "bkt", "k")

        self.assertNotIn("text", result)
        self.assertEqual(base64.b64decode(result["base64"]), payload)

    def test_get_object_refuses_an_object_above_the_cap(self):
        s3 = _FakeS3(body=b"x" * 10, size=10)

        result = ops.get_object(s3, "bkt", "k", max_bytes=5)

        self.assertIn("error", result)
        self.assertIn("5-byte", result["error"])
        # The object was never read past the cap — one bounded read, not the body.
        self.assertEqual(s3._body.read_sizes, [6])

    def test_get_object_bounds_a_body_whose_length_is_absent(self):
        # ContentLength is what the old check trusted; the cap must not depend on it.
        s3 = _FakeS3(body=b"y" * 100, size=None)
        s3._size = None

        result = ops.get_object(s3, "bkt", "k", max_bytes=5)

        self.assertIn("error", result)
        self.assertEqual(s3._body.read_sizes, [6])

    def test_max_get_bytes_reads_the_env_override(self):
        os.environ["S3_MCP_MAX_GET_BYTES"] = "2048"
        try:
            self.assertEqual(ops.max_get_bytes(), 2048)
        finally:
            del os.environ["S3_MCP_MAX_GET_BYTES"]

    def test_max_get_bytes_defaults_when_unset(self):
        os.environ.pop("S3_MCP_MAX_GET_BYTES", None)

        self.assertEqual(ops.max_get_bytes(), ops.DEFAULT_MAX_GET_BYTES)

    def test_max_get_bytes_rejects_a_malformed_or_nonpositive_value(self):
        for bad in ("not-a-number", "0", "-5"):
            with self.subTest(value=bad):
                os.environ["S3_MCP_MAX_GET_BYTES"] = bad
                try:
                    with self.assertRaises(ValueError):
                        ops.max_get_bytes()
                finally:
                    del os.environ["S3_MCP_MAX_GET_BYTES"]

    def test_the_ops_layer_exposes_exactly_the_read_only_calls(self):
        # The read-only guarantee is structural: the exported set IS the contract,
        # so assert it exactly rather than scanning names for suspicious words (a
        # scan would miss insert_/remove_/apply_/patch_).
        exported = {
            name
            for name in dir(ops)
            if not name.startswith("_") and callable(getattr(ops, name))
        }

        self.assertEqual(
            exported, {"list_buckets", "list_objects", "head_object", "get_object", "max_get_bytes"}
        )


if __name__ == "__main__":
    unittest.main()
