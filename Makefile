# Mute all `make` specific output. Comment this out to get some debug information.
.SILENT:
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory
SHELL=/bin/bash
EXEC_SHELL=/bin/bash
# Declare all non-file targets as phony so a same-named file or directory in the
# repo root never shadows them (e.g. a stray `test` dir would otherwise make
# `make test` silently report "up to date" and run nothing).
.PHONY: help install update uninstall up down restart test logs docs app
# SECONDEXPANSION is needed to be able to resolve `psr4: .docker-wrap-$$@` to `psr4: .docker-wrap-psr4`
.SECONDEXPANSION:

ARCH := $(shell uname -m)
OS := $(shell uname -s 2>/dev/null)
ROOT_PATH := $(shell pwd)
UID ?= "$(shell id -u)"
GID ?= "$(shell id -g)"

ifneq ("$(wildcard Makefile.local.mk)","")
  include Makefile.local.mk
endif

ifneq ("$(wildcard Makefile.vars.local.mk)","")
  include Makefile.vars.local.mk
endif

_DIR_NAME := $(shell basename $(CURDIR))
ifeq ($(_IS_WORKTREE),1)
  ifdef PROJECT_NAME
    PROJECT_NAME := $(_DIR_NAME)-$(PROJECT_NAME)
  else
    PROJECT_NAME := $(_DIR_NAME)
  endif
else
  PROJECT_NAME ?= $(_DIR_NAME)
endif
ENV_VARS=env UID=${UID} GID=${GID} DEV_APP_IMG=${DEV_APP_IMG} JAVA_OPTS=${JAVA_OPTS} PROJECT_NAME=${PROJECT_NAME}

# use when the container is not booted yet
RUN=$(ENV_VARS) docker compose run --rm app
# use when the container is already booted
EXEC=docker exec -it --workdir /app --user ${UID}:${GID} ${PROJECT_NAME}-app-1
EXEC_ROOT=docker exec -it --workdir /app --user 0:0 ${PROJECT_NAME}-app-1
SH=$(EXEC) /bin/bash

.docker-wrap-%:
ifeq ($(IS_DOCKER),1)
	$(MAKE) ".$*"
else
	$(EXEC) $(MAKE) ".$*"
endif

.docker-wrap-root-%:
ifeq ($(IS_DOCKER),1)
	$(MAKE) ".$*"
else
	$(EXEC_ROOT) $(MAKE) ".$*"
endif

# .DEFAULT: If the command does not exist in this makefile
# default: If no command was specified
.DEFAULT default:
	if [ -f ./Makefile.custom.mk ]; then \
	    $(MAKE) -f Makefile.custom.mk "$@"; \
	else \
	    if [ "$@" != "default" ]; then echo "Command '$@' not found."; fi; \
	    $(MAKE) help; \
	    if [ "$@" != "default" ]; then exit 2; fi; \
	fi

help:  ## Show this help
	@echo
	@echo "Usage:"
	@echo "     [ENV=VALUE] [...] make [command] [ARG=VALUE]"
	@echo "     make my-target"
	@echo "     NAMESPACE=\"dummy-app-namespace\" RELEASE_NAME=\"another-dummy-app\" make my-target"
	@echo
	@echo
	@echo "Available commands:"
	@echo
	@for file in Makefile Makefile.proj.mk Makefile.local.mk; do \
		if [ -f $$file ]; then \
			echo "$$file"; \
			echo ""; \
			grep -E '^[^#[:space:]].*:' $$file | \
			grep -vE '^default|^\.|^_|=' | \
			awk -F: '{\
				target=$$1; \
				match($$0, /##[[:space:]]*(.*)/); \
				desc = RSTART ? substr($$0, RSTART+3, RLENGTH-3) : ""; \
				printf "  \033[36m%-50s\033[0m %s\n", target, desc \
			}'; \
			echo; \
		fi \
	done

install: ## Install all tools (first-time setup or reinstall)
	bash install.sh

update: ## Update and all its dependencies
	bash bin/update.sh

uninstall: ## Completely remove from this system (destructive — shows confirmation prompt)
	bash bin/uninstall.sh

up: ## Boot services (does not install — use 'make install' for first-time setup)
	bash bin/up.sh

down: ## Shut down services
	bash bin/devbot down

restart: ## Stop then start
	echo -e "\n\033[1m\033[34m━━━ Restarting services... ━━━\033[0m"
	$(MAKE) down
	$(MAKE) up

build-test-image:
	cd tests/test-project && docker build --no-cache -t devbot-test .

test: ## Run the full test suite
	echo -e "\n\033[1m\033[34m━━━ Running tests... ━━━\033[0m"
	@if ! command -v bats &>/dev/null; then \
		echo "  bats not found — installing via npm..."; \
		npm install -g bats bats-assert bats-support &>/dev/null; \
		echo "  bats installed."; \
	fi
	BATS_LIB_PATH="$$(npm root -g)" bats -T -r src/ bin/
	@echo -e "\n\033[1m\033[34m━━━ Running bun tests... ━━━\033[0m"
	@if ! command -v bun &>/dev/null; then \
		echo "  bun not found — install via: curl -fsSL https://bun.sh/install | bash"; \
		exit 1; \
	fi
	@bun test src/
	@echo -e "\n\033[1m\033[34m━━━ Running python tests... ━━━\033[0m"
	@if ! command -v python3 &>/dev/null; then \
		echo "  python3 not found — install python3 to run the python tests"; \
		exit 1; \
	fi
	@failed=0; \
	while IFS= read -r f; do \
		echo "  python3 -m unittest $$f"; \
		(cd "$$(dirname "$$f")" && python3 -m unittest "$$(basename "$$f" .py)") || failed=1; \
	done < <(find src -name 'test_*.py' -not -path '*/node_modules/*' 2>/dev/null | sort); \
	[ $${failed} -eq 0 ]

logs:
	tail -f "$$(ls -t ~/.local/share/opencode/log/*.log | head -1)" -n 100


docs:
	cd docs && bundle install && bundle exec jekyll serve
