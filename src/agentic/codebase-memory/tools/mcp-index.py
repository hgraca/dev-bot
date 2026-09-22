#!/usr/bin/env python3
"""Ask the codebase-memory gateway to index a repository, over MCP.

Used by tools/index-project.sh. The session-start hook can no longer run the
`codebase-memory-mcp` CLI on the host: the index store lives on a Docker named
volume, which only the gateway can write. So indexing has to go through the
gateway's streamable-http endpoint.

Streamable HTTP hands out a session id on `initialize` and requires it back on
every later request — a call without it is rejected with
"Bad Request: Missing session ID". The response is plain JSON here (no SSE).

Usage: mcp-index.py <mcp-url> <repo-path>
"""

import json
import sys
import urllib.error
import urllib.request

_HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
}
_INIT_TIMEOUT = 10
# The server indexes synchronously and a cold repository can take minutes.
_CALL_TIMEOUT = 1800


def _post(url, payload, session_id=None, timeout=_INIT_TIMEOUT):
    headers = dict(_HEADERS)
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    request = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), headers=headers
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, response.headers.get("Mcp-Session-Id"), response.read()


def _close_session(url, session_id):
    """Drop the server-side session. mcp-proxy keeps every session it hands out
    until it is told to close it, so a long-lived gateway would otherwise
    accumulate one per index."""
    if not session_id:
        return
    request = urllib.request.Request(
        url,
        method="DELETE",
        headers={**_HEADERS, "Mcp-Session-Id": session_id},
    )
    try:
        urllib.request.urlopen(request, timeout=_INIT_TIMEOUT).close()
    except (urllib.error.HTTPError, urllib.error.URLError, OSError):
        pass


def index(url, repo_path):
    _, session_id, _ = _post(
        url,
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "index-project", "version": "1"},
            },
        },
    )
    try:
        _post(url, {"jsonrpc": "2.0", "method": "notifications/initialized"}, session_id)
        status, _, body = _post(
            url,
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {
                    "name": "index_repository",
                    "arguments": {"repo_path": repo_path},
                },
            },
            session_id,
            timeout=_CALL_TIMEOUT,
        )
    finally:
        _close_session(url, session_id)
    print(body.decode("utf-8", errors="replace")[:2000])
    if status != 200:
        print(f"ERROR: index_repository returned HTTP {status}", file=sys.stderr)
        return 1
    # A JSON-RPC success can still carry a failed tool result — the hook logs
    # this return code, so it must not report success for a failed index.
    try:
        result = json.loads(body).get("result") or {}
    except ValueError:
        # An unreadable body is a break in the transport contract, not a
        # success we failed to parse.
        print("ERROR: gateway returned a non-JSON body (see the logged result)", file=sys.stderr)
        return 1
    if result.get("isError"):
        print("ERROR: index_repository reported an error (see the logged result)", file=sys.stderr)
        return 1
    return 0


def main(argv):
    if len(argv) != 3:
        print("ERROR: usage: mcp-index.py <mcp-url> <repo-path>", file=sys.stderr)
        return 2
    url, repo_path = argv[1], argv[2]
    try:
        return index(url, repo_path)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        print(f"ERROR: gateway returned HTTP {exc.code}: {detail}", file=sys.stderr)
        return 1
    except (urllib.error.URLError, OSError) as exc:
        print(f"ERROR: gateway unreachable at {url}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
