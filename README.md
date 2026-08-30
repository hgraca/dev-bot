# DevBot

Everything for agentic software development.

## Clone

Start by installing opencode or claudecode, and then:

```shell
git clone git@github.com:GET-E/dev-bot.git && cd dev-bot
```

## Configure & Install

The default configuration is in `.devbot.global.dist.jsonc`, and when installing it will be copied to `.devbot.global.jsonc`.

If you want a different configuration, you can create the `.devbot.global.jsonc` yourself and change it as you wish.

Configs you might want to change:

- `disabled_modules`: list of modules and tools to skip during install/update/init
- `guards`: add or remove guards for commands that the LLM might want to run
- `modules`: add external git repos with extra `agents`, `commands` or `skills` that you might want to import

Then you can install:

```shell
make install
```

## Start development with DevBot

This is done automatically when opencode starts.
Brings up DevBot docker containers, at least Ollama.

```shell
devbot up
```

## Initialize a project

```shell
cd path/to/my/project
devbot init
```

or

```shell
devbot init path/to/my/project
```

## Start opencode

```shell
opencode
```

Or to continue the last session

```shell
opencode -c
```

## Create a bootstrap description of the project

This grants agents the essential context from the start.
This is only needed if the report doesn't exist yet at `.agents/memory/active/project.md`

After starting opencode, run the command.

```shell
/create-codebase-report
```

## Stop development with DevBot

Brings down DevBot docker containers.

```shell
devbot down
```

## Update regularly

```shell
devbot update
```

## Documentation

- [Configuration — devbot.jsonc](docs/configuration.md)
- [Modules — internal, tools, and external](docs/module-reference.md)
