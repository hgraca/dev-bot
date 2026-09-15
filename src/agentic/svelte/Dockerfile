# src/agentic/svelte/Dockerfile
# Shared Svelte MCP gateway: one container serves every harness instance on the
# machine over streamable-http, instead of each instance spawning its own
# `npx -y @sveltejs/mcp` stdio process.
#
# mcp-proxy (Python) bridges the stdio server to streamable-http at /mcp.
# Pins:
#   - mcp-proxy 0.12.0 is incompatible with mcp>=2 (the SDK moved request_ctx),
#     so mcp<2 is pinned alongside it.
#   - @sveltejs/mcp is pinned so the image is reproducible; bump it here.
#
# The server is stateless with respect to the project: documentation is bundled
# and the autofixer receives the code to analyse in the tool call, so a single
# shared container serves every project on the machine.
FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir --break-system-packages "mcp-proxy==0.12.0" "mcp<2"

RUN npm install -g @sveltejs/mcp@0.1.26

# Bind 0.0.0.0 inside the container so the host port mapping can reach it; the
# host side maps 127.0.0.1 only (see docker-compose.yml).
EXPOSE 18503
CMD ["mcp-proxy", "--port=18503", "--host=0.0.0.0", "--", "svelte-mcp"]