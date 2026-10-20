---
date: 2026-10-20
keywords: ["ci", "github-actions", "make-test", "fresh-checkout"]
---

# Making `make test` run on a fresh checkout

`.github/workflows/ci.yml` must prepare three gitignored things before `make test` on a stock checkout: copy the shipped global config (`cp .devbot.global.dist.jsonc .devbot.global.jsonc`) because the commands and harness tests copy the runtime file and about a dozen fail without it; create an empty `.env` (`touch .env`) because the compose-fragment tests run `docker compose config`, which loads the env file referenced by ollama and litellm; and run `bash src/tools/devbot-cli/init.sh "$PWD"` to materialize the `.agents/tools` symlink farm, because `devbot list tools` reads the project farm, not `src/`. Also set git identity (`git config --global user.name/email`) for tests that commit.

Run the suite with `DEV_BOT_ROOT` set to the checkout root. The harness `ensure_agents_md` tests source a copied `init.sh` under `set -u` and fail when it is unset, while the memory-symlink tests expect it to point at the checkout. On a 2-core GitHub runner the BATS stage is several times the local 8-job time; allow 30 minutes.
