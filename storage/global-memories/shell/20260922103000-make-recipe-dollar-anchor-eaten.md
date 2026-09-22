---
date: 2026-09-22
keywords: ["shell", "makefile", "sed", "escaping", "regex"]
trigger-on: ["makefile-recipe-dollar-escaping", "sed-in-makefile"]
---

## A literal `$` in a Makefile recipe is consumed by Make — escape it as `$$`

In a GNU Make recipe `$` starts a variable reference, so a literal `$` must be written `$$`. A regex end-anchor written as `$/` is read as the (empty) variable `$/`, silently deleting **both** characters: `sed -i '/- arg: --tls-san $/{N;N;d}'` reached sed as `sed -i '/- arg: --tls-san {N;N;d}'` and failed with `sed: -e expression #1, char 25: unterminated address regex`. The failure names sed, not Make, so always confirm the expanded command with `make -n <target>` before debugging the tool — that is what exposed the eaten characters here. This broke every fresh `make up-signoz` in the observability repo whenever the variable guarding the sed was empty.
