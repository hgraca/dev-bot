---
date: 2026-10-26
keywords: ["aws", "codepipeline", "secrets", "codebuild", "iam"]
aliases: ["GetPipeline plaintext", "action EnvironmentVariables", "codebuild env vars"]
trigger-on: ["codepipeline-secrets", "codebuild-buildspec"]
---

## CodePipeline returns action environment variables in plaintext

`codepipeline:GetPipeline` returns every action's `configuration.EnvironmentVariables` **with values** — so a token stored there is readable by anyone holding that read permission, including a read-only agent role granted it to inspect deployments. The same is true of CodeBuild project env vars of type `PLAINTEXT` (visible through `codebuild:BatchGetProjects`). Keep credentials in Secrets Manager/Parameter Store and reference them from the buildspec's `env.secrets-manager`/`env.parameter-store` blocks; before granting someone read access to pipelines, know that it is also read access to their secrets.
