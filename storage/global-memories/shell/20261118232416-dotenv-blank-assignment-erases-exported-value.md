---
date: 2026-11-18
keywords: ["shell", "dotenv", ".env", "set -a", "source"]
aliases: ["env file precedence", "blank placeholder", "template erases credentials"]
trigger-on: ["dotenv-template-load", "source-env-file", "compose-env-interpolation"]
---

## A blank assignment in a sourced .env reassigns the variable to empty

`NAME=` in an env file is not "leave `NAME` alone": `source`/`.` assigns the empty string, so a template that ships every optional credential blank silently erases a value the operator exported in their shell or profile — and `set -a` then exports the empty value to every child. The symptom is a credential that is set everywhere except in the one process that needs it: `docker compose` interpolation resolves `${VAR}` to empty, a launcher reports the reference as "resolves to nothing", a datasource is judged env-incomplete and dropped. Two robust fixes: ship the template with those lines commented out instead of blank, or make the loader rewrite a blank assignment to a self-reference (`NAME="${NAME}"`) before sourcing when the environment already holds a non-empty value. The rewrite must happen **while the file is read**, because `${NAME}` references later in the same file expand at that moment — e.g. `AWS_PROD_RO_ACCESS_KEY_ID=${AWS_KEY}` is already empty by the time a post-source restore could run. Keep the implied precedence explicit: a filled entry still beats the shell, exactly as plain `source` always did.
