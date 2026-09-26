#!/usr/bin/env python3
# src/agentic/datasources/s3-mcp/server.py
# The read-only S3 sidecar: an MCP server over streamable HTTP at /mcp.
#
# The write path does not exist — the four tools below are the whole tool list,
# and each delegates to ops.py, which has no mutating call. Credentials come from
# the standard boto3 chain (environment first), so compose hands them to the
# container and nothing is read from disk.
#
# Started by the rendered datasources compose, one container per `s3` datasource:
#   server.py --host 127.0.0.1 --port <allocated>
#
# GATE: this file is only ever imported with boto3 + the mcp SDK installed (the
# image installs them); the logic it wires is tested through ops.py alone.

import argparse

import boto3
from mcp.server.fastmcp import FastMCP

import ops


def main() -> None:
    parser = argparse.ArgumentParser(description="Read-only S3 MCP server")
    parser.add_argument("--host", default="127.0.0.1", help="Interface to bind (streamable HTTP only)")
    parser.add_argument("--port", type=int, default=18700, help="Port to listen on")
    args = parser.parse_args()

    client = boto3.client("s3")
    server = FastMCP("s3-readonly", host=args.host, port=args.port)

    @server.tool()
    def list_buckets() -> dict:
        """List every S3 bucket the credentials can see."""
        return ops.list_buckets(client)

    @server.tool()
    def list_objects(bucket: str, prefix: str = "", max_keys: int = 100) -> dict:
        """List objects in a bucket, optionally under a prefix."""
        return ops.list_objects(client, bucket, prefix, max_keys)

    @server.tool()
    def head_object(bucket: str, key: str) -> dict:
        """Fetch an object's metadata (size, content type, etag) without its body."""
        return ops.head_object(client, bucket, key)

    @server.tool()
    def get_object(bucket: str, key: str) -> dict:
        """Read an object's body — refused, never truncated, above the size cap."""
        return ops.get_object(client, bucket, key)

    server.run(transport="streamable-http")


if __name__ == "__main__":
    main()
