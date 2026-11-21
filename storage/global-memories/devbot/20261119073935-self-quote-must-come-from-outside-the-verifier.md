---
date: 2026-11-19
keywords: ["devbot", "self-verification", "audit", "agent-persona", "prompt"]
aliases: ["quote a rule back", "prove the persona loaded", "self-quote check", "instruction delivery"]
trigger-on: ["devbot-audit-command", "agent-self-verification"]
---

## A "quote a rule back" check must quote text the verifier does not itself repeat

An agent asked to prove it loaded its persona by quoting a rule can pass from the wrong source: the instruction that asks the question is itself in the agent's context, so anything it restates is quotable by an agent that never received the profile body. Dev-bot's `/devbot/audit` §0c first asked for "an exact terminal marker or the delegation template's prompt opener" — both appear verbatim later in `audit.md` itself, which made the following `grep` prove nothing. The working form requires a **full sentence from a section the verifier does not reproduce** (there, a rule from `## Session budget (MUST)`), greps it with `grep -F`, and pairs it with an id-side signal the persona cannot fake — the host log's `agent=<id>`. Rule for any self-verification prompt (audit commands, smoke-test skills, "confirm you read the brief" checks): the proof must come from a source outside the verifier, and the check must name that source.
