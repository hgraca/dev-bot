# src/agentic/mdctx/Dockerfile
# Shared mdctx MCP gateway: one container serves every harness instance on the
# machine over streamable-http, instead of each instance spawning its own
# `mdctx-mcp` stdio process.
#
# mcp-proxy (Python) bridges the stdio server to streamable-http at /mcp.
# Pins:
#   - mcp-proxy 0.12.0 is incompatible with mcp>=2 (the SDK moved request_ctx),
#     so mcp<2 is pinned alongside it.
#   - mdctx is pinned to the host CLI version so the index format matches the
#     index the host tools (search-memories, reindex) read and write.
FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir --break-system-packages "mcp-proxy==0.12.0" "mcp<2"

RUN npm install -g mdctx@0.1.0

# Bind 0.0.0.0 inside the container so the host port mapping can reach it; the
# host side maps 127.0.0.1 only (see docker-compose.yml).
EXPOSE 18501
CMD ["mcp-proxy", "--port=18501", "--host=0.0.0.0", "--", "mdctx-mcp"]