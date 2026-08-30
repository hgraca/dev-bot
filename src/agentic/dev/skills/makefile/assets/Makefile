# Mute all `make` specific output. Comment this out to get some debug information.
.SILENT:
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory
SHELL=/bin/bash
EXEC_SHELL=/bin/bash
# if there is a file or folder with the name of the target, add to the phony list:
.PHONY: app
# SECONDEXPANSION is needed to be able to resolve `psr4: .docker-wrap-$$@` to `psr4: .docker-wrap-psr4`
.SECONDEXPANSION:

ARCH := $(shell uname -m)
OS := $(shell uname -s 2>/dev/null)
ROOT_PATH := $(CURDIR)
UID ?= "$(shell id -u)"
GID ?= "$(shell id -g)"

IS_TTY := $(shell [ -t 0 ] && echo 1)
ifeq ($(IS_TTY),1)
    TTY_FLAG := -t
else
    TTY_FLAG :=
endif

_IS_WORKTREE := $(shell [ "$$(git rev-parse --git-dir 2>/dev/null)" != "$$(git rev-parse --git-common-dir 2>/dev/null)" ] && echo 1 || echo 0)
_DIR_NAME := $(shell basename $(CURDIR) | tr '[:upper:]' '[:lower:]')
ifeq ($(_IS_WORKTREE),1)
  PROJECT_NAME := $(_DIR_NAME)
  TRAEFIK_SUBDOMAIN := $(_DIR_NAME)
else
  PROJECT_NAME ?= $(_DIR_NAME)
endif

ifneq ("$(wildcard Makefile.proj.mk)","")
  include Makefile.proj.mk
endif

ifneq ("$(wildcard Makefile.local.mk)","")
  include Makefile.local.mk
endif

ifneq ("$(wildcard Makefile.vars.local.mk)","")
  include Makefile.vars.local.mk
endif

ENV_VARS=env UID=${UID} GID=${GID} DEV_APP_IMG=${DEV_APP_IMG} JAVA_OPTS=${JAVA_OPTS} PROJECT_NAME=${PROJECT_NAME}
ifdef TRAEFIK_SUBDOMAIN
  ENV_VARS += TRAEFIK_SUBDOMAIN=${TRAEFIK_SUBDOMAIN}
endif

# use when the container is not booted yet
RUN=$(ENV_VARS) docker compose -f .docker/compose.dev.yml run --rm app
# use when the container is already booted
EXEC=docker exec -i $(TTY_FLAG) --workdir /app --user ${UID}:${GID} ${PROJECT_NAME}-app-1
EXEC_ROOT=docker exec -i $(TTY_FLAG) --workdir /app --user 0:0 ${PROJECT_NAME}-app-1
SH=$(EXEC) /bin/bash

IS_DOCKER := $(shell ./scripts/is-in-docker.sh)
.docker-wrap-%:
ifeq ($(IS_DOCKER),1)
	$(MAKE) ".$*" $(MAKEOVERRIDES)
else
	$(EXEC) $(MAKE) ".$*" $(MAKEOVERRIDES)
endif

.docker-wrap-root-%:
ifeq ($(IS_DOCKER),1)
	$(MAKE) ".$*" $(MAKEOVERRIDES)
else
	$(EXEC_ROOT) $(MAKE) ".$*" $(MAKEOVERRIDES)
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

up: ## Start the development environment, installs/updates all tools and dependencies
	echo -e "\n\n====== Ensuring host has all requirements... ====== \n"
	ROOT_PATH=${ROOT_PATH} ./scripts/host-requirements/run.sh
	$(MAKE) init
	echo -e "\n\n====== Bringing up project app container to install dependencies... ====== \n"
	$(ENV_VARS) docker compose -f .docker/compose.dev.yml up -d app # so we can install the dependencies, including the shared composer file
	$(MAKE) install
	echo -e "\n\n====== Bringing up shared containers... ====== \n"
	@if docker ps --filter "label=com.docker.compose.project=shared" --quiet | grep -q .; then \
		echo "Shared containers are already running, skipping."; \
	elif [ "$(_IS_WORKTREE)" = "1" ]; then \
		echo -e "\033[31mERROR: Shared containers are not running and this is a git worktree.\033[0m"; \
		echo -e "\033[31mStarting shared containers from a worktree would recreate their volumes with incorrect paths.\033[0m"; \
		echo -e "\033[31mPlease run 'make up' from the main repository first to start the shared containers.\033[0m"; \
		exit 1; \
	else \
		$(ENV_VARS) docker compose -f vendor/get-e/dev-tools/src/Docker/compose.shared.yml up -d --no-recreate; \
	fi
	echo -e "\n\n====== Waiting for Redis cluster to be ready... ====== \n"
	./scripts/wait-for-redis.sh
	echo -e "\n\n====== Bringing up project containers... ====== \n"
	$(ENV_VARS) docker compose -f .docker/compose.dev.yml up -d # needs to be after shared containers because it depends on them
	$(MAKE) migrate
	$(MAKE) seed
	$(MAKE) generate
	echo -e "\n\nNOTE: If your browser doesn't trust the certificate, ignore it, or install '.docker/traefik/ca/rootCA.pem'.\n\n"

down: ## Shut down the development environment
	$(ENV_VARS) docker compose -f .docker/compose.dev.yml down

down-all: ## Shut down the development environment including shared
ifeq ($(_IS_WORKTREE),1)
	@echo -e "\033[31mERROR: Cannot bring down shared containers from a worktree.\033[0m"
	@echo -e "\033[31mOther projects depend on them. Run 'make down-all' from the main repository.\033[0m"
	@exit 1
else
	$(MAKE) down
	$(ENV_VARS) docker compose -f vendor/get-e/dev-tools/src/Docker/compose.shared.yml down
endif

purge: ## Remove all containers and volumes of development environment
	$(ENV_VARS) docker compose -f .docker/compose.dev.yml down --volumes --remove-orphans

purge-all: ## Remove all containers and volumes of development environment including shared
ifeq ($(_IS_WORKTREE),1)
	@echo -e "\033[31mERROR: Cannot purge shared containers from a worktree.\033[0m"
	@echo -e "\033[31mThis would destroy shared volumes (databases) that all projects depend on.\033[0m"
	@echo -e "\033[31mRun 'make purge-all' from the main repository if you really need to.\033[0m"
	@exit 1
else
	@echo -e "\033[33mWARNING: This will destroy ALL shared containers AND their volumes (MariaDB, MongoDB data).\033[0m"
	@echo -e "\033[33mAll projects sharing these services will be affected.\033[0m"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "Aborted."; exit 1)
	$(MAKE) purge
	$(ENV_VARS) docker compose -f vendor/get-e/dev-tools/src/Docker/compose.shared.yml down --remove-orphans
	docker volume rm shared_mysql_data shared_mongo_data 2>/dev/null || true
endif

restart: down up ## Restart running containers

app: ## Login to the running application container
	$(EXEC) /bin/bash

root: ## Login to the running application container as root
	$(EXEC_ROOT) /bin/bash

CMD ?= /bin/bash
run:
	$(EXEC) /bin/bash -c "$(CMD)"

PREFIX := init-
init: $(shell for f in $(MAKEFILE_LIST); do grep -o ^$(PREFIX)[^:]* $$f; done | sort -u) ## Run the project init scripts

PREFIX := install-
install: $(shell for f in $(MAKEFILE_LIST); do grep -o ^$(PREFIX)[^:]* $$f; done | sort -u) ## Install the application dependencies

PREFIX := db-
db: $(shell for f in $(MAKEFILE_LIST); do grep -o ^$(PREFIX)[^:]* $$f; done | sort -u) ## Reset the DB

PREFIX := migrate-
migrate: $(shell for f in $(MAKEFILE_LIST); do grep -o ^$(PREFIX)[^:]* $$f; done | sort -u) ## Run the application migrations

PREFIX := seed-
seed: $(shell for f in $(MAKEFILE_LIST); do grep -o ^$(PREFIX)[^:]* $$f; done | sort -u) ## Run the application seeders

PREFIX := generate-
generate: $(shell for f in $(MAKEFILE_LIST); do grep -o ^$(PREFIX)[^:]* $$f; done | sort -u) ## Run code generators

PREFIX := workers-
workers: $(shell for f in $(MAKEFILE_LIST); do grep -o ^$(PREFIX)[^:]* $$f; done | sort -u) ## Run the worker(s) for handling async messages

test: .$$@ ## Run all tests as in the CI
static: .$$@ ## Run all static analysis as in the CI
unit: .$$@ ## Run all unit tests as in the CI
ut: .$$@ ## Run all unit tests as in the CI, without bootstrapping the DB
ut-debug: .$$@ ## Run all unit tests as in the CI, in debug mode, without bootstrapping the DB
cov: .$$@ ## Run all unit tests as in the CI, outputting the code coverage
fix: .$$@ ## Run all code fixers

rect: .$$@ ## Correct the code ut to the last version
lint: .$$@ ## Lint the code
cs: .$$@ ## Fix coding standards
stan: .$$@ ## Run static analysis
stan-baseline: .$$@ ## Create the static analysis checker baseline
arch: .$$@ ## Test the architecture rules
arch-baseline: .$$@ ## Create the architecture rules checker baseline
crons: .$$@ ## Test that the CRON schedules are correctly configured

init-env:
	echo -e "\n\n====== Initialize local files ====== \n"
	if [ ! -f .env ] && [ -f .env.dist ]; then cp .env.dist .env || echo ".env already exists, skipping copy."; fi
	if [ ! -f Makefile.local.mk ]; then echo "# You can place your own make targets in this file" > Makefile.local.mk; fi
	if [ ! -f Makefile.vars.local.mk ]; then echo "# You can place your own makefile variables overrides in this file" > Makefile.vars.local.mk; fi
	echo -e "Done! \n"

init-docker-network:
	echo -e "\n\n====== Ensure the get-e-dev docker network is created ====== \n"
	docker network inspect get-e-dev >/dev/null 2>&1 || docker network create get-e-dev
	echo -e "Done! \n"

init-docker-volumes:
	echo -e "\n\n====== Ensure the shared docker volumes are created ====== \n"
	docker volume inspect shared_mysql_data >/dev/null 2>&1 || docker volume create shared_mysql_data
	docker volume inspect shared_mongo_data >/dev/null 2>&1 || docker volume create shared_mongo_data
	echo -e "Done! \n"

init-shared-hosts: ## Set up shared services in hosts file
	echo -e "\n\n====== Ensure the shared hosts are in the hosts file ====== \n"
ifeq ($(filter $(OS),Linux Darwin),$(OS)) # Linux|Mac
	@grep -qxF '127.0.0.1    traefik.get-e.local' /etc/hosts || echo '127.0.0.1    traefik.get-e.local' >> /etc/hosts
	@grep -qxF '127.0.0.1    mailpit.get-e.local' /etc/hosts || echo '127.0.0.1    mailpit.get-e.local' >> /etc/hosts
	@grep -qxF '127.0.0.1    gotenberg.get-e.local' /etc/hosts || echo '127.0.0.1    gotenberg.get-e.local' >> /etc/hosts
else # windows
	@powershell -Command \
		"if (-not (Select-String -Path '$$env:SystemRoot\System32\drivers\etc\hosts' -Pattern '127.0.0.1    traefik.get-e.local' -Quiet)) { \
			Add-Content -Path '$$env:SystemRoot\System32\drivers\etc\hosts' -Value '127.0.0.1    traefik.get-e.local' \
		}"
	@powershell -Command \
		"if (-not (Select-String -Path '$$env:SystemRoot\System32\drivers\etc\hosts' -Pattern '127.0.0.1    mailpit.get-e.local' -Quiet)) { \
			Add-Content -Path '$$env:SystemRoot\System32\drivers\etc\hosts' -Value '127.0.0.1    mailpit.get-e.local' \
		}"
	@powershell -Command \
		"if (-not (Select-String -Path '$$env:SystemRoot\System32\drivers\etc\hosts' -Pattern '127.0.0.1    gotenberg.get-e.local' -Quiet)) { \
			Add-Content -Path '$$env:SystemRoot\System32\drivers\etc\hosts' -Value '127.0.0.1    gotenberg.get-e.local' \
		}"
endif
	echo -e "Done! \n"

docker-login: ## Login to AWS ECR so we can download the docker images
	echo -e "\n\n====== Logging in to AWS ECR ====== \n"
	aws configure sso
	aws ecr get-login-password --region eu-central-1 \
        | docker login --username AWS --password-stdin 599001845632.dkr.ecr.eu-central-1.amazonaws.com
dlogin: docker-login ## Alias for .docker-login, for backwards compatibility

lefthook-install: ## Install Lefthook
	echo -e "\n\n====== Installing Lefthook ====== \n"
	./.docker/install-lefthook.sh

hooks-install: ## Install Git hooks (uses lefthook from Docker)
	$(MAKE) lefthook-install
	echo -e "\n\n====== Installing Git hooks with Lefthook (Docker mode) ====== \n"
	chmod +x .docker/git-hooks/pre-commit .docker/git-hooks/pre-push
	cp .docker/git-hooks/pre-commit .git/hooks/pre-commit
	cp .docker/git-hooks/pre-push .git/hooks/pre-push
	echo "✔️  Git hooks installed successfully"

hooks-uninstall: ## Uninstall Git hooks
	echo -e "\n\n====== Uninstalling Git hooks ====== \n"
	rm -f .git/hooks/pre-commit .git/hooks/pre-push
	echo "✔️  Git hooks uninstalled successfully"

init-local-ca: install-local-ca ## Install the local CA in the host OS (runs automatically on make up)

install-local-ca: ## Install the local CA in the host OS (guarded for vendor availability)
	@if [ -f ./vendor/get-e/dev-tools/src/Docker/traefik/ca/rootCA.pem ]; then \
		echo -e "\n\n====== Installing local CA certificate ======\n"; \
		ROOT_PATH=${ROOT_PATH} ./scripts/host-requirements/local-ca/install.sh; \
	else \
		echo -e "\n\n====== Skipping local CA certificate (vendor/dev-tools not yet available) ======\n"; \
		echo "Run 'make install-local-ca' after 'make up' completes if you need the CA certificate."; \
	fi

BASE64_ENCODE_INPUT ?=.env.secrets
BASE64_ENCODE_OUTPUT ?=$(BASE64_ENCODE_INPUT).encoded
encode:
	@echo "📦 Encoding file: $(BASE64_ENCODE_INPUT)"
	@./scripts/functions/base64_encode.sh $(BASE64_ENCODE_INPUT) > $(BASE64_ENCODE_OUTPUT)
	@echo "✅ Encoded values written to $(BASE64_ENCODE_OUTPUT)"

BASE64_DECODE_INPUT ?=.env.secrets.encoded
BASE64_DECODE_OUTPUT ?=$(BASE64_DECODE_INPUT).decoded
decode:
	@echo "🔓 Decoding file: $(BASE64_DECODE_INPUT)"
	@./scripts/functions/base64_decode.sh $(BASE64_DECODE_INPUT) > $(BASE64_DECODE_OUTPUT)
	@echo "✅ Encoded values written to $(BASE64_DECODE_OUTPUT)"

REPO    ?= git@github.com:GET-E/dev-tools.git
DIR     ?= ../dev-tools.ai
CONTEXT ?= php.monolith
AGENT   ?= opencode
BRANCH  ?=
ai: ## Set up AI agent tooling by linking to the dev-tools repo (AGENT=opencode|claude BRANCH=optional-branch)
	echo -e "\n\n====== Setting up AI agent tooling ($(AGENT)) ====== \n"
	./scripts/setup-ai.sh "$(REPO)" "$(DIR)" "$(CONTEXT)" "$(AGENT)" "$(BRANCH)"
	echo -e "\nDone! \n"

ai-rm: ## Remove the symlinks created by the ai target (AGENT=opencode|claude)
	echo -e "\n\n====== Removing AI agent tooling symlinks ($(AGENT)) ====== \n"
	$(eval _AGENT_DIR  := $(if $(filter claude,$(AGENT)),.claude,.opencode))
	$(eval _AGENTS_FILE := $(if $(filter claude,$(AGENT)),CLAUDE.md,AGENTS.md))
	@for link in .ai/context $(_AGENT_DIR) $(_AGENTS_FILE) opencode.jsonc; do \
		if [ -L "$$link" ]; then \
			rm "$$link"; \
			echo "  removed $$link"; \
		else \
			echo "  $$link is not a symlink, skipping"; \
		fi \
	done
	@if [ -d .ai ] && [ -z "$$(ls -A .ai 2>/dev/null)" ]; then \
		rmdir .ai; \
		echo "  removed .ai (empty)"; \
	fi
	echo -e "\nDone! \n"

### <<<
