---
name: devbot:architecture-rules
description: "Architecture universal rules: priority order, security, forbidden patterns, code quality, design rules, defaults. Use this skill whenever making architectural decisions, reviewing code quality, checking security constraints, or when uncertain about design direction — even if you are only writing a single new file."
---

# Architecture Universal Rules

Architecture: Explicit Architecture (DDD + Hexagonal + CQRS), modular monolith

## When to Apply

- Making architectural decisions or reviewing design choices
- Checking security constraints or forbidden patterns
- Reviewing code quality or static analysis compliance
- When uncertain about design direction — consult defaults

## Priority Order

1. Stability
2. Security
3. Determinism
4. Extensibility
5. Feature growth

## Identifiers

UUID v7, generated in Domain. Never use auto-increment IDs in Domain logic.

## Security

**Mandatory:**

- No secrets in code. Credentials via `env()` only.
- Never read or reference `.env` files.
- No production DB operations. Scope to local/dev.
- Redact sensitive data in output: `REDACTED`, `user@example.com`, `TOKEN_REDACTED`.
- No hardcoded secrets or default credentials
- TLS required
- Restart policies, resource limits, and health checks defined
- All ingress via reverse proxy — no direct public ports

**Forbidden:**

- Exposed PostgreSQL or Redis ports
- Privileged containers
- Host networking
- `latest` image tags

## Forbidden Patterns

- Outbox pattern
- Anemic Domain models — entities must contain behavior, not just data
- Business logic in Controllers or Infrastructure

## Code Quality

- Static analysis tools enforce code quality
- Import classes instead of using fully qualified names (production and test code)
- Do not ignore static analysis issues — resolve them or escalate to human stakeholder
- Do not add issues to static analysis tools baselines — resolve them in codebase

## Design Rules

- Value Objects over primitives for domain concepts (names, IDs, scores, URLs, etc.)
- All domain classes must be `final` unless explicitly designed for extension (if allowed by programming language)
- Port contracts must use typed DTOs — never raw arrays crossing boundaries
- Port interfaces must not expose transport or infrastructure concepts (URLs, headers, connection strings)
- Application services returning data to presentation must return DTOs — never domain entities
- Exceptions crossing layer boundaries must be defined at port level
- Domain behavior must live on owning entity or aggregate, not in unrelated factory methods or standalone services
- Dependencies must be explicitly injected — not instantiated inside constructors or factory methods
- Domain constructors must normalize input (sort collections, trim/lowercase strings)
- Output formatting must be separate concern from application orchestration
- Infrastructure adapters must validate external data defensively before mapping to domain types
- Infrastructure adapters must validate URL schemes (require HTTPS) for external API URLs
- Encode external input before interpolating into URLs, SQL, or shell commands

## Migrations

- Database migrations ship in their own atomic commit — never bundled with the code that depends on them.
- Never introduce a backward-incompatible (BC) schema break. When a change would break the running code, split it into the expand → migrate → contract pattern (2–3 commits/PRs): additive migration first, then the new code, then a follow-up cleanup migration.
- Additive first, destructive last and alone — drops/renames get their own commit after no code references the old shape.
- See `deprecation-and-migration` for the expand/contract schema mechanics.

## Defaults When Uncertain

Prefer: stricter layer separation, Value Objects over primitives, explicit modeling, Domain purity.

## See also

- `devbot:address-retrospective` skill
- `devbot:rest-conventions` skill
