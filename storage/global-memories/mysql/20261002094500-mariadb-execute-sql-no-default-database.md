---
date: 2026-10-02
keywords: ["mysql", "mariadb", "execute-sql", "schema", "datasources"]
trigger-on: ["mysql-execute-sql-no-default-database", "mariadb-no-database-selected"]
---

## MariaDB `execute_sql` answers "No database selected" until names are qualified or a default schema is set

The shared datasources gateway runs each `execute_sql` statement on a connection with no default schema unless the datasource sets one, and one MySQL/MariaDB instance usually holds several databases. A bare table name then fails with `Error 1046 (3D000): No database selected` — that error means "no default schema on this connection", not "the table does not exist". Set `MYSQL_DATABASE` on the datasource to give it a default schema, or fully qualify every reference (`SELECT ... FROM db.table`); a `USE` issued in one call does not carry to the next.
