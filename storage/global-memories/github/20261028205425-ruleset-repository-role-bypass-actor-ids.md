---
date: 2026-10-28
keywords: ["github", "ruleset", "bypass_actors", "RepositoryRole", "branch-protection"]
aliases: ["ruleset role id", "bypass actor id", "rulesets role database id"]
trigger-on: ["github-ruleset-bypass-actor"]
---

## Ruleset `RepositoryRole` bypass-actor ids are 2=maintain, 4=write, 5=admin

The `actor_id` values for `bypass_actors` of type `RepositoryRole` in branch rulesets are undocumented, and the obvious guess is wrong. GitHub's legacy permission ordering (`1 read, 2 triage, 3 write, 4 maintain, 5 admin`) does **not** apply: submitting `actor_id: 3` for "write" is rejected with `422 Validation Failed — "Actor base role does not have write permissions"`. Measured against the live API, the ids are `2 = maintain`, `4 = write`, `5 = admin`. Read and triage cannot be bypass actors at all — GitHub requires the actor's base role to hold write permission, so any id below write fails the same way. Since the mapping is not in the OpenAPI spec, verify rather than trust: create a throwaway `enforcement: "disabled"` ruleset with the candidate id, read it back, then delete it — or read an existing ruleset through GraphQL (`repository.ruleset(databaseId:) { bypassActors { nodes { repositoryRoleDatabaseId repositoryRoleName } } }`), which returns the human-readable `repositoryRoleName` and is the definitive check. Always verify the stored role by name after writing, because a wrong id fails closed (nobody can bypass) rather than loudly.
