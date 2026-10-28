# Mute all `make` specific output. Comment this out to get some debug information.
.SILENT:
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory
SHELL=/bin/bash
EXEC_SHELL=/bin/bash
# Declare all non-file targets as phony so a same-named file or directory in the
# repo root never shadows them (e.g. a stray `test` dir would otherwise make
# `make test` silently report "up to date" and run nothing).
.PHONY: help install update uninstall up down restart test test-bats test-bats-slice test-ts test-py lint logs docs docs-gather app
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
# Disable commit/tag signing for the test suite. The developer's global
# commit.gpgsign=true would otherwise make every throwaway-repo commit invoke
# gpg — slow, and it prompts to unlock the key (or fails under load). GIT_CONFIG_*
# injects this like `git -c`, so it reaches every git subprocess the suite spawns.
HERMETIC_GIT=GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=tag.gpgSign GIT_CONFIG_VALUE_1=false

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

# The "./" in the bun invocation below makes bun treat the argument as a path.
# A bare `bun test src/` is a filter, and matching one walks the whole checkout
# (storage/ alone is hundreds of thousands of files) before any test runs.
test: test-bats test-ts test-py ## Run the full test suite

# CI runs the BATS suite as N parallel jobs (a build matrix in ci.yml) to bring
# the wall clock down to about a third of a full run. bin/test-slices.sh
# computes the slices from the files git knows about, never from a list, so a
# new test file cannot be silently skipped; bin/tests/ci_slices_tests.bats
# guards both that partition and the handoff to bats below.
# SLICES is how many jobs the workflow starts — keep it in step with the matrix.
SLICES ?= 3

test-bats-slice: ## Run one CI slice of the BATS suite (set SLICE to 1, 2 or 3)
	@tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	bin/test-slices.sh "$${SLICE:-}" "$(SLICES)" > "$$tmp" || exit 2; \
	if [ -n "$${FILES_ONLY:-}" ]; then cat "$$tmp"; exit 0; fi; \
	echo "  bats: slice $${SLICE}/$(SLICES), $$(wc -l < "$$tmp") files"; \
	$(MAKE) test-bats BATS_FILES_FILE="$$tmp"

# FILES_ONLY above prints the slice instead of running it — the guard test reads
# the partition that way. BATS_FILES_FILE is the same seam for `test-bats`: a
# newline-separated list of files to run instead of the whole bin/ and src/ tree.
test-bats: ## Run the BATS suite (BATS_FILES_FILE points at a list to narrow it)
	@echo -e "\n\033[1m\033[34m━━━ Running tests... ━━━\033[0m"
	# bats is installed as three separate npm packages. A machine can have bats
	# without the libraries, and then every test fails in setup() with
	# "Could not find library 'bats-support'" rather than a useful failure.
	# Check each one, so the suite self-heals instead of looking broken.
	@missing=""; \
	command -v bats &>/dev/null || missing="bats"; \
	lib_root="$$(npm root -g 2>/dev/null || true)"; \
	for lib in bats-assert bats-support; do \
		if [ -z "$$lib_root" ] || [ ! -d "$$lib_root/$$lib" ]; then \
			missing="$$missing $$lib"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "  missing:$$missing — installing via npm..."; \
		if ! npm install -g $$missing &>/dev/null; then \
			printf 'FATAL: could not install:%s\n' "$$missing" >&2; \
			exit 1; \
		fi; \
		echo "  installed:$$missing"; \
	fi
	# stdin from /dev/null: harness inits legitimately prompt when stdin is a
	# TTY (claudecode asks before changing an existing default agent), so a
	# suite run from a terminal would block on that read instead of asserting.
	# Parallel BATS: GNU parallel is preferred, rush is the fallback — see
	# README, Development. Without BATS_FILES_FILE, bin/ runs first on purpose:
	# the update suites (bin/tests/update_*_tests.bats) are the heaviest cluster,
	# so starting them early keeps them off the critical path. A slice arrives
	# already ordered heaviest-first.
	# DEV_BOT_TEST_JOBS overrides the derived job count (1 forces a serial run).
	@targets=(); \
	if [ -n "$${BATS_FILES_FILE:-}" ]; then \
		mapfile -t targets < "$$BATS_FILES_FILE"; \
	else \
		targets=(-r bin/ src/); \
	fi; \
	jobs="$${DEV_BOT_TEST_JOBS:-}"; \
	if [ -z "$$jobs" ]; then \
		jobs="$$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"; \
	fi; \
	case "$$jobs" in ''|*[!0-9]*|0) jobs=4;; esac; \
	if [ "$$jobs" -gt 8 ]; then jobs=8; fi; \
	runner=""; \
	if [ "$$jobs" -gt 1 ]; then \
		if parallel --version 2>/dev/null | grep -q 'GNU parallel'; then \
			runner="parallel"; \
		elif command -v rush >/dev/null 2>&1; then \
			runner="rush"; \
		fi; \
	fi; \
	if [ "$$runner" = "parallel" ]; then \
		echo "  bats: $$jobs parallel jobs"; \
		$(HERMETIC_GIT) BATS_LIB_PATH="$$(npm root -g)" bats -T --jobs "$$jobs" --no-parallelize-within-files "$${targets[@]}" </dev/null; \
	elif [ "$$runner" = "rush" ]; then \
		echo "  bats: $$jobs parallel jobs (rush)"; \
		$(HERMETIC_GIT) BATS_LIB_PATH="$$(npm root -g)" bats -T --jobs "$$jobs" --parallel-binary-name rush --no-parallelize-within-files "$${targets[@]}" </dev/null; \
	else \
		if [ "$$jobs" -gt 1 ]; then \
			echo "  WARN: GNU parallel/rush not found — BATS runs serially (slow)."; \
			echo "        Install GNU parallel or rush (see README, Development)."; \
		fi; \
		$(HERMETIC_GIT) BATS_LIB_PATH="$$(npm root -g)" bats -T "$${targets[@]}" </dev/null; \
	fi

test-ts: ## Run the bun (TypeScript) test suite
	@echo -e "\n\033[1m\033[34m━━━ Running bun tests... ━━━\033[0m"
	@if ! command -v bun &>/dev/null; then \
		echo "  bun not found — install via: curl -fsSL https://bun.sh/install | bash"; \
		exit 1; \
	fi
	@$(HERMETIC_GIT) bun test ./src/

test-py: ## Run the python test suite
	@echo -e "\n\033[1m\033[34m━━━ Running python tests... ━━━\033[0m"
	@if ! command -v python3 &>/dev/null; then \
		echo "  python3 not found — install python3 to run the python tests"; \
		exit 1; \
	fi
	@failed=0; \
	while IFS= read -r f; do \
		echo "  python3 -m unittest $$f"; \
		(cd "$$(dirname "$$f")" && $(HERMETIC_GIT) python3 -m unittest "$$(basename "$$f" .py)") || failed=1; \
	done < <(find src -name 'test_*.py' -not -path '*/node_modules/*' 2>/dev/null | sort); \
	[ $${failed} -eq 0 ]

# Keep the prettier flags in sync with the format-* hooks
# (src/agentic/format-*/tools/*.py): they define the project's standard.
# Shellcheck scope excludes .bats: BATS is its own syntax and does not parse as
# shell. The .bash helpers and the extensionless bin/devbot are included.
lint: ## Run the linters (shellcheck, prettier, py_compile)
	echo -e "\n\033[1m\033[34m━━━ Running linters... ━━━\033[0m"
	@failed=0; \
	if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "ERROR: shellcheck not found — install it first (apt install shellcheck or a release binary)"; \
		failed=1; \
	else \
		scripts=(); \
		while IFS= read -r f; do scripts+=("$$f"); done < <(git ls-files '*.sh' '*.bash' 'bin/devbot' 'bin/devbot-*'); \
		if [ $${#scripts[@]} -eq 0 ]; then \
			echo "ERROR: no shell scripts found — git ls-files returned nothing"; \
			failed=1; \
		elif shellcheck -x --severity=warning "$${scripts[@]}"; then \
			echo "  shellcheck: clean"; \
		else \
			failed=1; \
		fi; \
	fi; \
	if ! command -v prettier >/dev/null 2>&1; then \
		echo "ERROR: prettier not found — install it first (npm install -g prettier)"; \
		failed=1; \
	elif ! command -v node >/dev/null 2>&1; then \
		echo "ERROR: node not found — prettier requires node"; \
		failed=1; \
	else \
		md=(); while IFS= read -r f; do md+=("$$f"); done < <(git ls-files '*.md' | grep -vE '(^|/)(storage|tests)/'); \
		json=(); while IFS= read -r f; do json+=("$$f"); done < <(git ls-files '*.json' '*.jsonc' | grep -vE '(^|/)(storage|tests)/'); \
		yml=(); while IFS= read -r f; do yml+=("$$f"); done < <(git ls-files '*.yml' '*.yaml' | grep -vE '(^|/)(storage|tests)/'); \
		if [ $${#md[@]} -eq 0 ]; then \
			echo "ERROR: no markdown files found — git ls-files returned nothing"; failed=1; \
		elif ! prettier --parser markdown --print-width 999 --embedded-language-formatting off --ignore-path /dev/null --check "$${md[@]}"; then \
			failed=1; \
		else \
			echo "  prettier md: clean"; \
		fi; \
		if [ $${#json[@]} -eq 0 ]; then \
			echo "ERROR: no json files found — git ls-files returned nothing"; failed=1; \
		elif ! prettier --parser json --print-width 80 --ignore-path /dev/null --check "$${json[@]}"; then \
			failed=1; \
		else \
			echo "  prettier json: clean"; \
		fi; \
		if [ $${#yml[@]} -eq 0 ]; then \
			echo "ERROR: no yaml files found — git ls-files returned nothing"; failed=1; \
		elif ! prettier --parser yaml --print-width 999 --ignore-path /dev/null --check "$${yml[@]}"; then \
			failed=1; \
		else \
			echo "  prettier yml: clean"; \
		fi; \
	fi; \
	if ! command -v python3 >/dev/null 2>&1; then \
		echo "ERROR: python3 not found — install python3"; \
		failed=1; \
	else \
		pycache="$$(mktemp -d)"; \
		pyfailed=0; \
		while IFS= read -r f; do PYTHONPYCACHEPREFIX="$$pycache" python3 -m py_compile "$$f" || pyfailed=1; done < <(git ls-files '*.py'); \
		rm -r "$$pycache" 2>/dev/null || true; \
		if [ $${pyfailed} -eq 0 ]; then \
			echo "  py_compile: clean"; \
		else \
			failed=1; \
		fi; \
	fi; \
	exit $${failed}

logs:
	tail -f "$$(ls -t ~/.local/share/opencode/log/*.log | head -1)" -n 100


docs: docs-gather ## Bring up the website, can be browsed at http://127.0.0.1:4000/dev-bot/
	cd docs && bundle install && bundle exec jekyll serve

docs-gather:
	src/agentic/docs/tools/gather-module-docs.sh
