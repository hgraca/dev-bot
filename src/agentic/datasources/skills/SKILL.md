---
name: devbot:datasources
description: "Use this skill whenever you need to query or explore a project's databases — MySQL, MariaDB, Postgres or MongoDB — through the shared MCP Toolbox gateway. Covers the free-form query tools, reaching every database on one instance, and why the database credential is the only barrier to writes."
---

# datasources — Database Access

A **shared, machine-wide MCP Toolbox container** gives agents free-form query
access to the databases a project has opted into. One container serves every
project; each datasource is declared once in `.devbot.global.jsonc` and enabled
per project by name in `.devbot.project.jsonc`.

## What you get

A datasource appears to you as an MCP server named after it, exposing exactly
one tool. For a SQL datasource the tool takes a single argument, `sql`:

```
datasources-mariadb-dev_mariadb-dev_execute_sql  { "sql": "SELECT 1" }
```

One statement per call. For MongoDB the tool takes a whole aggregation
pipeline, and the collection is a parameter you choose.

## Exploring

There is no `list_tables` tool — the query tool reaches everything, so
introspect with SQL (or, on MongoDB, with a pipeline):

| Want                      | SQL                                                                              |
| ------------------------- | -------------------------------------------------------------------------------- |
| Databases on the instance | `SHOW DATABASES`                                                                 |
| Tables in a database      | `SELECT table_name FROM information_schema.tables WHERE table_schema = 'hotels'` |
| A table's shape           | `DESCRIBE hotels.bookings`                                                       |
| Size and row counts       | `information_schema.tables` (`data_length`, `table_rows`)                        |
| A query's plan            | `EXPLAIN SELECT ...`                                                             |

**One instance often holds many databases.** When a datasource has no default
schema there is nothing to `USE`, so qualify names — `SELECT ... FROM
otherdb.sometable`. A bare table name will fail.

## Writes are not blocked — the credential is the only barrier

Nothing in this module restricts what a datasource can do. A datasource pointed
at a user with write grants **can write**, and that is deliberate: the same
config serves dev (writes wanted) and prod (read-only user) by differing only
in credentials. So:

- **Never assume a datasource is read-only.** Check before running anything
  destructive, and prefer the `-prod` datasource for reading production data.
- Prefer `SELECT`; treat `INSERT`/`UPDATE`/`DELETE`/DDL as requiring the user's
  intent for that environment.
- Upstream calls `execute-sql` a _"developer assistant workflow with
  human-in-the-loop"_ tool, and that is how to treat it.

## When a datasource seems to be missing

A datasource the gateway cannot initialize is deliberately **absent** — toolbox
refuses to start with such a source, so it is left out of the config. dev-bot
does not probe with a connection of its own: it runs the real toolbox against
each declared source and keeps only what that accepts, so a wrong credential or
a blocked host is excluded too, not just a down database.

- No tool for a database you expected usually means **the database is down**,
  not a misconfiguration. Boot the environment and run `devbot up` again.
- The set is decided once, at startup: a database that comes up later is not
  picked up until the next `devbot up`. Nothing retries in the background.
- Reasons are printed on `devbot up`, and the gateway's own log shows config
  rejections.

## Configuring

```jsonc
// .devbot.global.jsonc — declared once
"datasources": {
  "hotels-dev": {
    "type": "mysql",
    "env": {
      "MYSQL_HOST": "localhost",                    // literal
      "MYSQL_PASSWORD": "${HOTELS_DEV_DB_PASSWORD}" // reference — never on disk
    }
  }
}

// .devbot.project.jsonc — opt in by name
"datasources": ["hotels-dev"]
```

Add one and reinit (`devbot reinit`; the next bare `devbot` start does it).
`type` is one of `mysql`, `postgres`, `sqlite`, `mongodb`, `redis`; MariaDB uses
`mysql`. Every value is either a literal or a `${VAR}` reference resolved from
the environment — put anything secret behind a reference so it exists in no
file at all.

**Redis** takes the command and its arguments as one array:
`["GET", "some-key"]`, `["HGETALL", "cart:42"]`, `["SCAN", "0", "MATCH", "user:*"]`.
The array becomes the command, so anything Redis understands works.

MongoDB notes: one datasource covers **one database** (its aggregate tool
requires one), declared as `MONGODB_DATABASE`.
