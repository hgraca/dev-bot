---
date: 2026-08-31
keywords: ["php", "saml", "mariadb", "collation", "entity-id"]
trigger-on: ["saml-entity-id-collation"]
---

## SAML entity IDs are case-sensitive — use a binary collation on the column

SAML `entityID` values are case-sensitive identifiers, but a column created with the MySQL/MariaDB default `utf8mb4_unicode_ci` collation treats them case-insensitively: a UNIQUE index and lookups (`WHERE idp_entity_id = ?`) conflate IDs that differ only by case. When storing IdP/SP entity IDs (or any SAML identifier you match on), declare the column with a case-sensitive collation: `$table->string('idp_entity_id', 255)->nullable()->unique()->collation('utf8mb4_bin');` in the migration. Apply the same reasoning to `sp_entity_id` if it is ever matched server-side.
