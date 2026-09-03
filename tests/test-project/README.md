# kata-pokeapi_parser_refactoring

A kata to refactor an api parser<!-- devbot-audit-probe -->

## Test devbot

Build once (a `devbot-test` image):

```shell
docker build -t devbot-test .
```

then either of these — **they can run in parallel** (different terminals):

```shell
./test-cc.sh # ClaudeCode
./test-oc.sh # OpenCode
```

Each launcher runs its container against an **isolated per-run copy** of this
fixture (mounted at `/app`), with its own pid-suffixed container name — so cc
and oc never race over `.devbot.project.jsonc`, the harness wiring dirs, the
nested `.git`, or the audit-report NN sequence. The host composer cache is
mounted into the container (auto-detected: Linux `~/.cache/composer`, macOS
`~/Library/Caches/composer`, or composer's own `cache-dir`) so `composer
install` never re-downloads packages.

On exit the launcher syncs the run's durable outputs back into this real
fixture:

- the audit report → `.agents/memory/thinking/devbot-audit-<nextNN>.md`
  (NN is the next free number on the real tree, so parallel runs never clash)
- the run's devbot logs + staged harness logs →
  `.agents/logs/<report-id>/`

Manual one-off (older style, not isolated):

```shell
docker run -it --rm -v "$PWD:/app" -v "$HOME/.ssh:/root/.ssh:ro" -w /app ubuntu bash
```

## Coding Challenge

You are given a list of Pokemon names.

Using the API provided at https://pokeapi.co/, list these attributes for each Pokemon:
Name
Base_experience
Species
Current level.

You can calculate their current level using their base_experience and their species' growth rate.
Example output
Given the 4 Pokemon Ivysaur, Bulbasaur, Pikachu, and Ditto, we should generate the following output:

```text
ivysaur 142 ivysaur 5
bulbasaur 64 bulbasaur 3
pikachu 112 pikachu 4
ditto 101 ditto 4
```

## How to run

If you need a docker container:

```shell
docker run -it --rm -w /app -v "$PWD":/app -v ~/.config/composer:/.composer -e COMPOSER_HOME=/.composer php:8.4-cli bash
apt-get update
apt-get install zip git
```

Install the dependencies

```shell
./composer install
```

You can run it with

```shell
./bin/run.php ivysaur bulbasaur pikachu ditto
```
