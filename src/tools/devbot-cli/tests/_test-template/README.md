# kata-pokeapi_parser_refactoring

A kata to refactor an api parser

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
````

Install the dependencies
```shell
./composer install
```

You can run it with
```shell
./bin/run.php ivysaur bulbasaur pikachu ditto
```
