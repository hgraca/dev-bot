---
date: 2026-09-29
keywords: ["sqlite", "foreign_keys", "pragma", "cascade"]
trigger-on: ["sqlite-cascade-delete", "sqlite-pragma"]
---

## SQLite does not enforce ON DELETE CASCADE unless foreign_keys is ON

`PRAGMA foreign_keys` defaults to **OFF** on every connection, so a schema full of `ON DELETE CASCADE` constraints is inert in a plain `sqlite3.connect()` — deleting a parent silently orphans the children instead of cascading. Any script that relies on declared cascades must issue `con.execute("PRAGMA foreign_keys=ON")` immediately after connecting and _before_ `BEGIN` (the pragma is a no-op inside a transaction). Symptom to recognise: the delete reports success and removes exactly the rows you named, while dependent rows remain — no error, no warning, and a later `VACUUM` reclaims far less than expected.
