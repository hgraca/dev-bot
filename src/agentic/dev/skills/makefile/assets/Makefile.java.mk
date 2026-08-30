########################################################################################################################
#
# ATTENTION
# Here are the targets specific to this project, this is commited to git and imported by the main `Makefile`.
# This is yours to change as needed.
# If you need targets specific to your personal workflow, add them to Makefile.local.mk
# If you need to override variables specific to your personal workflow, add them to Makefile.vars.local.mk
#
########################################################################################################################

# Increase of default heap size
JAVA_OPTS=-Xmx8g

########################################################################################################################
# Required by the main makefile
########################################################################################################################

init-env:
	echo -e "\n\n====== Initializing local env ====== \n"
	if [ ! -f .env ]; then cp .env.dist .env || echo ".env already exists, skipping copy."; fi
	echo -e "Done! \n"

# this needs to be done on `init-` because then running `install-local-ca` the dev-tools need to be there already
init-dev-tools: .docker-wrap-$$@ ## Install the application backend dependencies
.init-dev-tools:
	echo -e "\n\n====== Initializing dev-tools ====== \n"
	bash ./scripts/install-dev-tools.sh
