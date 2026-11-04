# AWS access in this project

AWS is reached through the AWS MCP servers wired for this project as
`aws-<connection>` — one per connection this project has wired. Use those tools
for every AWS interaction.

- Never run the `aws` CLI, and never call AWS from a shell script: those use
  whatever credentials the machine holds, not the connection's pinned identity.
- If no `aws-<connection>` tool is in your toolset, ask the user to enable it
  (`mcp.aws-<connection>.enabled: true` in `opencode.jsonc`) and restart. Never
  fall back to the CLI — this overrides the fallback in the AWS rules below.
