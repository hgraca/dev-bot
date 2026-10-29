---
date: 2026-10-29
keywords: ["aws", "credential_source", "assume-role", "profile", "sts"]
trigger-on: ["aws-profile-role-chain"]
---

## `credential_source = Environment` feeds the role, but plain profile keys let the environment win

A profile with `role_arn` and `credential_source = Environment` assumes the role using the credentials already in the environment — verified: with `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` set, `aws sts get-caller-identity --profile <role-profile>` returns `arn:aws:sts::<acct>:assumed-role/<role>/...`, not the source user. The dangerous variant is a profile carrying plain access keys while the environment also has credentials: the environment wins, the assume-role never happens, and the caller silently acts as the source identity with its wider permissions — invisible until someone reads CloudTrail. Whenever a wrapper exports credentials and then calls `aws --profile`, resolve `sts get-caller-identity` through that profile first and refuse to proceed unless the ARN is an `assumed-role`.
