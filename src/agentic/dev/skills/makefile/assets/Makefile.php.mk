########################################################################################################################
#
# ATTENTION
# Here are the targets specific to this project, this is commited to git and imported by the main `Makefile`.
# This is yours to change as needed.
# If you need targets specific to your personal workflow, add them to Makefile.local.mk
# If you need to override variables specific to your personal workflow, add them to Makefile.vars.local.mk
#
########################################################################################################################

#DEV_APP_IMG := "get-e/${PROJECT_NAME}-dev-php-fpm-8.4"
PARATEST_PROCESSES ?= 4 # you can override this value in Makefile.vars.local.mk

########################################################################################################################
# Required by the main makefile
########################################################################################################################

init-php:
	echo -e "\n\n====== Initializing local php files ====== \n"
	# php configs
	if [ ! -f .docker/php.overrides.ini ]; then cp .docker/php.overrides.ini.dist .docker/php.overrides.ini; fi
	if [ ! -f .docker/xdebug.overrides.ini ]; then cp .docker/xdebug.overrides.ini.dist .docker/xdebug.overrides.ini; fi
	# dev folders
	mkdir -p storage/cache/static_analysis
	mkdir -p storage/logs
	mkdir -p storage/xdebug
	chmod 777 -R storage/ 2&> /dev/null || true # if there are files in there created by www-data this will give error
	# worktree: rewrite DB names so each worktree gets isolated databases
	@if [ "$$(git rev-parse --git-dir 2>/dev/null)" != "$$(git rev-parse --git-common-dir 2>/dev/null)" ]; then \
		_slug=$$(basename "$$(pwd)" | tr '-' '_'); \
		echo -e "Worktree detected -- setting dev DB to $${_slug}, test DB to $${_slug}_phpunit\n"; \
		sed -i.bak \
			-e "s/^DB_DATABASE=.*/DB_DATABASE=$${_slug}/" \
			-e "s/^DB_MONGO_DATABASE=.*/DB_MONGO_DATABASE=$${_slug}/" \
			.env && rm -f .env.bak; \
		if [ -f .env.phpunit ]; then \
			sed -i.bak \
				-e "s/^DB_DATABASE=.*/DB_DATABASE=$${_slug}_phpunit/" \
				-e "s/^DB_MONGO_DATABASE=.*/DB_MONGO_DATABASE=$${_slug}_phpunit/" \
				.env.phpunit && rm -f .env.phpunit.bak; \
		fi; \
	fi
	echo -e "Done! \n"

init-hosts: ## Set up project services in hosts file
	echo -e "\n\n====== Ensure the project hosts are in the hosts file ====== \n"
ifeq ($(filter $(OS),Linux Darwin),$(OS)) # Linux|Mac
	@grep -qxF '127.0.0.1    ${PROJECT_NAME}.get-e.local' /etc/hosts || echo '127.0.0.1    ${PROJECT_NAME}.get-e.local' >> /etc/hosts
else # windows
	@powershell -Command \
		"if (-not (Select-String -Path '$$env:SystemRoot\System32\drivers\etc\hosts' -Pattern '127.0.0.1    ${PROJECT_NAME}.get-e.local' -Quiet)) { \
			Add-Content -Path '$$env:SystemRoot\System32\drivers\etc\hosts' -Value '127.0.0.1    ${PROJECT_NAME}.get-e.local' \
		}"
endif
	echo -e "Done! \n"

install-deps: .docker-wrap-$$@ ## Install the application backend dependencies
.install-deps:
	echo -e "\n\n====== Installing project backend dependencies ====== \n"
	("./scripts/composer-deps-in-sync.sh" && echo -e "Dependencies up to date.\n") || composer install

db-mariadb: .docker-wrap-$$@
.db-mariadb:
	echo -e "\n\n====== Recreating the DBs ${APP_ENV} ====== \n"
	php artisan db:create --drop --connection=mysql

db-mongodb: .docker-wrap-$$@
.db-mongodb:
	echo -e "\n\n====== Recreating the mongo DBs ${APP_ENV} ====== \n"
	php artisan db:drop --connection=mongodb

migrate-mariadb-mongodb: .docker-wrap-$$@
.migrate-mariadb-mongodb:
	echo -e "\n\n====== Creating and migrating the DBs ${APP_ENV} ====== \n"
	php artisan db:create --connection=mysql
	php artisan migrate

seed-db: .docker-wrap-$$@
.seed-db:
	echo -e "\n\n====== Seeding the DB ====== \n"
	php artisan db:seed

.test: .docker-wrap-$$@ ## Run all tests
..test:
	$(MAKE) .install-deps
	$(MAKE) .static
	$(MAKE) .unit
	$(MAKE) .crons

.static: .docker-wrap-$$@ ## Run all static analysis tools
..static:
	$(MAKE) .psr4
	$(MAKE) .rect
	$(MAKE) .lint
	$(MAKE) .cs
	$(MAKE) .stan
	$(MAKE) .arch
	$(MAKE) .dependency-analyser

.unit: .docker-wrap-$$@
TEST ?= ''
FILE ?= ''
..unit: ## Run tests inside the container, use `make .unit [TEST=ClassName::testMethod] [FILE=tests/Path/To/ClassName.php]` if you want to run only one test
ifneq ($(strip $(TEST)),'')
	echo -e "\n\n====== Unit test: $(TEST) ====== \n"
	php vendor/bin/phpunit --filter '$(TEST)'
else ifneq ($(FILE),'')
	echo -e "\n\n====== Unit test: $(FILE) ====== \n"
	php vendor/bin/phpunit $(FILE)
else
	$(MAKE) .install-deps
	APP_ENV=phpunit php artisan db:create --connection=mysql
	php artisan config:cache && echo "Cache can be built successfully"
	rm -f ./bootstrap/cache/*.php && echo "Cache removed successfully, so tests can run"
	echo -e "\n\n====== Unit tests (${PARATEST_PROCESSES} parallel workers) ====== \n"
	php artisan test --parallel --recreate-databases --processes=${PARATEST_PROCESSES}
endif

.ut: .docker-wrap-$$@ ## Run tests, without setting up DBs nor dependencies
..ut:
	vendor/bin/phpunit --display-all-issues


.ut-debug: .docker-wrap-$$@ ## Run tests, without setting up DBs nor dependencies
..ut-debug:
	vendor/bin/phpunit --debug --display-all-issues

TEST ?= ''
FILE ?= ''
t: ## Run a single test file or test method, ie `make t FILE=my/test/path.php` or `make t TEST=myTestMethod`
ifneq ($(strip $(TEST)),'')
	echo -e "\n\n====== Unit test: $(TEST) ====== \n"
	$(EXEC) vendor/bin/phpunit --display-deprecations --filter '$(TEST)'
else ifneq ($(FILE),'')
	echo -e "\n\n====== Unit test: $(FILE) ====== \n"
	$(EXEC) vendor/bin/phpunit --display-deprecations $(FILE)
else
	$(MAKE) ut
endif

.cov: coverage
coverage: .docker-wrap-$$@ ## Run tests with coverage
.coverage:
	$(MAKE) .install-deps
	echo -e "\n\n====== Unit tests with coverage ====== \n"
	php -d pcov.directory=${GITHUB_WORKSPACE} -d xdebug.mode=coverage vendor/bin/phpunit --coverage-text --coverage-clover storage/unit-tests/coverage.xml --log-junit storage/unit-tests/report.xml

dependency-analyser: ## Analyse dependencies to check if there are unused dependencies
	make .docker-wrap-$@;
.dependency-analyser:
	echo -e "\n\n====== Analysis dependencies ====== \n"
	vendor/bin/composer-dependency-analyser

.fix: .docker-wrap-$$@ ## Run all static analysis tools that fix code
..fix:
	$(MAKE) .rect
	$(MAKE) .cs

########################################################################################################################
# Project specific targets
########################################################################################################################

workers-all: .docker-wrap-$$@
.workers-all:
	echo -e "\n\n====== Running a worker handling all queues ====== \n"
	php artisan queue:work \
        --memory 1028 \
        --timeout=1260

.rect: .docker-wrap-$$@
..rect:
	echo -e "\n\n====== Rector fix ====== "
	vendor/bin/rector process

.lint: .docker-wrap-$$@
..lint:
	echo -e "\n\n====== Lint ====== \n"
	vendor/bin/phplint -c .phplint.yml --cache-dir=storage/cache/static_analysis/phplint

.cs: .docker-wrap-$$@
..cs:
	echo -e "\n\n====== CS fixer ====== \n"
	vendor/bin/php-cs-fixer fix --allow-risky=yes --config=./.php-cs-fixer.php --diff --verbose --show-progress=dots

.stan: .docker-wrap-$$@
..stan:
	echo -e "\n\n====== PHPStan ====== \n"
	mkdir -p storage/cache/static_analysis/phpstan-tmp
	vendor/bin/phpstan --memory-limit=2G analyze

.stan-baseline: .docker-wrap-$$@
..stan-baseline:
	echo -e "\n\n====== PHPStan baseline ====== \n"
	rm -f ./.phpstan-baseline.neon
	vendor/bin/phpstan --memory-limit=2G analyze --generate-baseline

.arch: .docker-wrap-$$@  ## Test architecture rules
..arch:
	echo -e "\n\n====== PHPArkitect ====== \n"
	vendor/bin/phparkitect check --use-baseline=phparkitect.baseline.json

.arch-baseline: .docker-wrap-$$@
..arch-baseline:
	echo -e "\n\n====== PHPArkitect baseline ====== \n"
	vendor/bin/phparkitect check --generate-baseline=phparkitect.baseline.json

.crons: .docker-wrap-$$@
..crons:
	echo -e "\n\n====== Cron tests ======  \n"
	php artisan schedule:list

psr4: .docker-wrap-$$@
.psr4:
	echo -e "\n\n====== Psr-4 violation check ======\n"
	@output=$$(composer du -o --no-scripts 2>&1); \
	if echo "$$output" | grep -q 'does not comply'; then \
		echo -e "Psr-4 violations detected! Please fix these files:\n"; \
		echo "$$output" | awk '{for(i=1;i<=NF;i++) if($$i=="in") print $$(i+1)}'; \
		echo ""; \
		exit 1; \
    else \
        echo -e "All good! \n"; \
	fi

########################################################################################################################
# Project CI targets
########################################################################################################################

ci-test:
	$(MAKE) ci-test-static_analysis
	$(MAKE) .ci-unit

ci-test-static_analysis:
	$(MAKE) .install-deps
	$(MAKE) .psr4
	$(MAKE) ..ci-rect
	$(MAKE) .lint
	$(MAKE) ..ci-cs
	$(MAKE) .stan
	$(MAKE) .arch
	$(MAKE) .dependency-analyser

.ci-rect: .docker-wrap-$$@
..ci-rect:
	echo -e "\n\n====== Rector check ====== \n"
	vendor/bin/rector process --dry-run

.ci-cs: .docker-wrap-$$@
..ci-cs:
	echo -e "\n\n====== CS checker ====== \n"
	vendor/bin/php-cs-fixer fix --allow-risky=yes --config=./.php-cs-fixer.php --diff --verbose --show-progress=dots --dry-run

.ci-db:
	echo -e "\n\n====== Preparing the DB ${APP_ENV} ====== \n"
	cat .env.phpunit.ci >> .env.phpunit # because phpunit will always load the `.env.phpunit` file
	APP_ENV='phpunit' make .db-mariadb

# CI: full test suite in parallel (DB-dependent suites)
# Uses `php artisan test --parallel` which creates isolated per-worker databases (phpunit_1, phpunit_2, ...)
ci-unit: .docker-wrap-$$@
.ci-unit: .ci-db
	cat .env.phpunit.ci >> .env.phpunit # because phpunit will always load the `.env.phpunit` file
	cat .env.phpunit > .env # because migrations will use .env
	php artisan config:cache && echo "Cache can be built successfully"
	rm -f ./bootstrap/cache/*.php && echo "Cache removed successfully, so tests can run"
	echo -e "\n\n====== CI parallel tests (${PARATEST_PROCESSES} workers) ======  \n"
	php artisan test --parallel --recreate-databases --processes=${PARATEST_PROCESSES} --stop-on-failure
	make .crons

ci-unit-coverage: .docker-wrap-$$@
.ci-unit-coverage: .ci-db
	cat .env.phpunit.ci >> .env.phpunit # because phpunit will always load the `.env.phpunit` file
	cat .env.phpunit > .env # because migrations will use .env
	php artisan config:cache && echo "Cache can be built successfully"
	rm -f ./bootstrap/cache/*.php && echo "Cache removed successfully, so tests can run"
	php artisan migrate
	echo -e "\n\n====== Unit tests with coverage ====== \n"
	php -d pcov.directory=${GITHUB_WORKSPACE} vendor/bin/phpunit --coverage-clover output/coverage.xml --log-junit output/report.xml

########################################################################################################################
# PHP specific targets
########################################################################################################################

xon: .docker-wrap-root-$$@  ## Turn on Xdebug from the host
.xon:
	./scripts/xdebug.sh on

xoff: .docker-wrap-root-$$@  ## Turn off Xdebug from the host
.xoff:
	./scripts/xdebug.sh off
