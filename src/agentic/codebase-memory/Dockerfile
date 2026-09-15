# src/agentic/codebase-memory/Dockerfile
# Shared codebase-memory MCP gateway: one container serves every harness
# instance on the machine over streamable-http, instead of each instance
# spawning its own `codebase-memory-mcp` stdio process.
#
# mcp-proxy (Python) bridges the stdio server to streamable-http at /mcp.
# Pins:
#   - mcp-proxy 0.12.0 is incompatible with mcp>=2 (the SDK moved request_ctx),
#     so mcp<2 is pinned alongside it.
#   - codebase-memory-mcp is pinned so the image is reproducible; bump it here.
#
# The server is stdio-only (no http transport of its own), hence the bridge.
# Its tools take `repo_path` per call, so the repos must be visible inside the
# container at their real absolute paths — see docker-compose.yml.
FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir --break-system-packages "mcp-proxy==0.12.0" "mcp<2"

RUN npm install -g codebase-memory-mcp@0.10.8

# Force the package's bin.js to install/verify its native runtime at BUILD time,
# so the first MCP call does not pay a download (or fail offline).
RUN codebase-memory-mcp config list >/dev/null

# Bind 0.0.0.0 inside the container so the host port mapping can reach it; the
# host side maps 127.0.0.1 only (see docker-compose.yml).
EXPOSE 18504
# --ui=false: the bundled graph UI binds a fixed loopback port (9749). dev-bot
# never uses the UI, and a shared gateway must not squat that port.
CMD ["mcp-proxy", "--port=18504", "--host=0.0.0.0", "--", "codebase-memory-mcp", "--ui=false"]