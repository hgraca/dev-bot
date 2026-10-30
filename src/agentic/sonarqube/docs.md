---
title: "SonarQube"
description: "Code quality and security — issues, quality gates, coverage, duplication and dependency risks."
mcps:
  sonarqube: "Code quality — issues, quality gates, coverage, duplication, dependency risks"
---

SonarQube integration: the official SonarQube MCP server plus the official
SonarQube agent skills. It works with SonarQube Cloud (EU and US) and with a
self-hosted SonarQube Server or Community Build.

## What it does

The module wires the official [`SonarSource/sonarqube-mcp-server`](https://github.com/SonarSource/sonarqube-mcp-server)
container over stdio, so the agent can list projects and issues, check quality
gates, inspect coverage and duplication, review security hotspots, and triage
dependency risks without leaving the session.

The MCP server ships **wired but not started** (`enabled: false`), and the
module is disabled globally by default. Nothing runs — no container, no tool
schemas in context — until you turn both on.

The official skills come from
[`SonarSource/sonarqube-agent-plugins`](https://github.com/SonarSource/sonarqube-agent-plugins)
and are cloned and linked by the external-modules machinery when the module is
enabled: `sonar-list-projects`, `sonar-list-issues`, `sonar-fix-issue`,
`sonar-quality-gate`, `sonar-analyze`, `sonar-coverage`, `sonar-duplication`,
`sonar-dependency-risks`, `sonar-triage-dependency-risks`, and the
`sonar-integrate` setup walkthrough.

## Enabling it

1. Enable the module for the project in `.devbot.project.jsonc`:

   ```jsonc
   { "modules": { "sonarqube": true } }
   ```

   (or remove `"sonarqube": false` from your global config). Run `devbot reinit`.

2. Export the instance settings in the shell that starts DevBot:

   | Variable          | Cloud (EU)                         | Cloud (US)                  | Server                     |
   | ----------------- | ---------------------------------- | --------------------------- | -------------------------- |
   | `SONARQUBE_TOKEN` | required — user token              | required — user token       | required — **user** token  |
   | `SONARQUBE_URL`   | optional (`https://sonarcloud.io`) | `https://sonarqube.us`      | required — your server URL |
   | `SONARQUBE_ORG`   | optional — organization key        | optional — organization key | not used                   |

   The token is read from the environment; it is never written to a config
   file.

3. Turn the MCP server on. On **opencode**, set `mcp.sonarqube.enabled` to
   `true` in `opencode.jsonc` (or toggle it in the harness) and restart.
   opencode keeps that value across reinits. **Claude Code** has no per-server
   on/off and omits a disabled server from `.mcp.json`; to use it there, set
   `"enabled": true` in this module's `mcp.json` in your dev-bot checkout.

## Configuration

| Variable                    | Purpose                                                                 |
| --------------------------- | ----------------------------------------------------------------------- |
| `SONARQUBE_TOKEN`           | Required. SonarQube user token.                                         |
| `SONARQUBE_URL`             | SonarQube Server URL, or `https://sonarqube.us` for Cloud US.           |
| `SONARQUBE_ORG`             | Cloud organization key; fixes the org for every call.                   |
| `SONARQUBE_PROJECT_KEY`     | Optional default project key; removes the parameter from tool schemas.  |
| `SONARQUBE_TOOLSETS`        | Comma-separated toolsets to load, e.g. `issues,quality-gates,coverage`. |
| `SONARQUBE_READ_ONLY`       | `true` disables write operations (for example issue transitions).       |
| `SONARQUBE_WORKSPACE_MOUNT` | `false` disables the read-only project mount used by analysis tools.    |
| `SONARQUBE_WORKSPACE_MODE`  | Mount mode: `ro` (default) or `rw` if an analysis call must write.      |
| `SONARQUBE_MCP_IMAGE`       | Full image reference overriding the pinned `versions.env` tag.          |

On Cloud, `SONARQUBE_ORG` is optional: with a single organization the server
resolves it, and with several the agent can list them and choose one per call.
Set it to pin every call to one organization.

The project directory is mounted at `/app/mcp-workspace`, so analysis tools read
files by relative path instead of receiving their content through the context
window. It is read-only by default; switch to `rw` only if an analysis call
needs to write there. Disable the mount for very large trees or when the harness
cwd is not the project root.

The image is pinned in `versions.env` and pulled lazily the first time the MCP
starts; `devbot update` moves the pin to the newest release. The server needs
Docker, and the connected SonarQube instance must be 2025.1 / Community Build
25.1 or later (Cloud is always supported). Because the launch is behind a
script, the "docker-only server" registration guard does not detect it: on a
machine without Docker the entry is still registered, but it is inert while
disabled and fails loudly at launch when enabled.

The official skills include `sonar-integrate`, which wires the separate
SonarQube CLI. DevBot already wires the MCP, so that skill is optional here.

## See also

- [MCP configuration](/mcp-config) — the canonical manifest schema, including per-server enablement
- [Module Reference](/module-reference) — full module directory
