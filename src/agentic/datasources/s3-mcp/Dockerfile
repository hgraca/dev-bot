# src/agentic/datasources/s3-mcp/Dockerfile
# The read-only S3 sidecar image.
#
# Built by the rendered datasources compose, which passes this directory as the
# build context — so the server and its ops module are the only inputs besides
# the base image and the two pins below.
#
# The uv image carries python + uv, matching how the module runs its other
# sidecars (uvx at container start), but here the dependencies are baked in so a
# `devbot up` does not re-resolve them on every start.
FROM ghcr.io/astral-sh/uv:python3.12-trixie-slim

WORKDIR /app
COPY ops.py server.py ./

# Pinned deliberately: the tool surface IS the SDK's, so an unpinned install could
# change an agent's available tools between two `devbot up` runs.
RUN uv pip install --system "mcp==1.30.0" "boto3==1.43.103"

CMD ["python", "server.py"]
