#!/usr/bin/env bash
# A child process has its own heap, so this tool
# cannot snapshot the server — mcp-meta routes it.
case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"heap-snapshot","description":"Write a V8 heap snapshot of the devbot-tools MCP server process itself (the Bun heap that serves these tools). Use for memory investigations of the agent tooling.","inProcess":"server-heap-snapshot","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"Optional: output path. Defaults to <tmpdir>/devbot-heap-<timestamp>.heapsnapshot"}}}}
JSON
    exit 0
    ;;
esac

echo "ERROR: heap-snapshot runs in-process; the server must dispatch it (inProcess), not spawn it" >&2
exit 1
