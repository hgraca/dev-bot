#!/usr/bin/env python3
# src/agentic/datasources/s3-mcp/ops.py
# Read-only S3 operations, deliberately separate from the MCP layer.
#
# Every function takes an S3 client, so the read-only contract — WHICH calls
# exist, and the object size cap — is unit-testable without boto3, credentials
# or a network. server.py is the only place that builds a client.
#
# There is no write path here by construction: no put/delete/copy function
# exists to be reached, and a test asserts that.

import base64
import os

# Above this, an object body is refused rather than returned.
DEFAULT_MAX_GET_BYTES = 1_000_000

# The operator's override for that cap.
CAP_ENV = "S3_MCP_MAX_GET_BYTES"


def max_get_bytes() -> int:
    """The read cap: CAP_ENV when set, else the default.

    A malformed or non-positive value RAISES rather than being quietly ignored —
    the cap is the only thing between an agent and an arbitrarily large object,
    so falling back silently would widen it without saying so.
    """
    raw = os.environ.get(CAP_ENV, "").strip()
    if not raw:
        return DEFAULT_MAX_GET_BYTES
    try:
        value = int(raw)
    except ValueError as exc:
        raise ValueError(f"{CAP_ENV}={raw!r} is not an integer") from exc
    if value <= 0:
        raise ValueError(f"{CAP_ENV}={value} must be positive")
    return value


def list_buckets(s3) -> dict:
    """Every bucket the credentials can see."""
    response = s3.list_buckets()
    return {"buckets": [bucket["Name"] for bucket in response.get("Buckets", [])]}


def list_objects(s3, bucket: str, prefix: str = "", max_keys: int = 100) -> dict:
    """Objects in a bucket, optionally under a prefix."""
    response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix, MaxKeys=max_keys)
    return {
        "bucket": bucket,
        "prefix": prefix,
        "truncated": bool(response.get("IsTruncated")),
        "objects": [
            {
                "key": obj["Key"],
                "size": obj.get("Size"),
                "last_modified": str(obj.get("LastModified", "")),
            }
            for obj in response.get("Contents", [])
        ],
    }


def head_object(s3, bucket: str, key: str) -> dict:
    """Object metadata, without fetching its body."""
    response = s3.head_object(Bucket=bucket, Key=key)
    return {
        "bucket": bucket,
        "key": key,
        "size": response.get("ContentLength"),
        "content_type": response.get("ContentType"),
        "last_modified": str(response.get("LastModified", "")),
        "etag": response.get("ETag"),
    }


def get_object(s3, bucket: str, key: str, max_bytes: int | None = None) -> dict:
    """An object's body — refused, never silently truncated, above the cap.

    The cap is enforced by READING AT MOST `max_bytes + 1` bytes, not by trusting
    ContentLength: an object whose length the response omits is still bounded, and
    a large object transfers no more than the cap. A truncated body would reach
    the caller looking like a whole file, so an over-cap object is refused by
    size instead.
    """
    limit = DEFAULT_MAX_GET_BYTES if max_bytes is None else max_bytes

    response = s3.get_object(Bucket=bucket, Key=key)
    data = response["Body"].read(limit + 1)

    if len(data) > limit:
        return {
            "bucket": bucket,
            "key": key,
            "size": response.get("ContentLength"),
            "error": (
                f"object is larger than the {limit}-byte read cap; "
                f"raise {CAP_ENV} to read it"
            ),
        }

    try:
        return {"bucket": bucket, "key": key, "size": len(data), "text": data.decode("utf-8")}
    except UnicodeDecodeError:
        return {
            "bucket": bucket,
            "key": key,
            "size": len(data),
            "base64": base64.b64encode(data).decode("ascii"),
        }
