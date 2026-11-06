# legacy-goat-runtimes — stack driver. Picks whichever compose provider is installed.

COMPOSE_FILE := compose/compose.yaml
ENV_FILE     := compose/.env
APP_DIR      ?= ../legacy-goat
APP_BRANCH   ?= fixed
APP_PROFILE  ?= baseline
PROFILE_ENV  := profiles/$(APP_PROFILE).env

COMPOSE := $(shell \
	if docker compose version >/dev/null 2>&1; then echo "docker compose"; \
	elif podman compose version >/dev/null 2>&1; then echo "podman compose"; \
	elif command -v podman-compose >/dev/null 2>&1; then echo "podman-compose"; \
	elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; \
	else echo ""; fi)

CC := $(COMPOSE) -f $(COMPOSE_FILE) --env-file $(ENV_FILE) --env-file $(PROFILE_ENV)

.PHONY: help check-compose config checkout up up-build down logs ps test integration operations run-integration verify clean ground-truth check-alignment score

help:
	@echo "targets: config checkout up up-build down logs ps test integration operations verify ground-truth check-alignment score clean"
	@echo "vars:    APP_BRANCH=$(APP_BRANCH) (main|vulnerable|fixed)  APP_PROFILE=$(APP_PROFILE) (baseline|permissive)  APP_DIR=$(APP_DIR)"
	@echo "         APP_SRC=<tree> deploys a generated tree (a path the container runtime can mount) instead of APP_DIR"
	@echo "engine:  $(if $(COMPOSE),$(COMPOSE),NONE — install a compose provider, see README)"

check-compose:
	@test -n "$(COMPOSE)" || { \
	  echo "no compose provider found."; \
	  echo "install one: 'uv tool install podman-compose' or Docker's compose plugin."; \
	  exit 1; }

# Point the mounted app source at a branch. Vulnerable and fixed are blind; distribute one at a time.
checkout:
	git -C $(APP_DIR) checkout $(APP_BRANCH)

config: check-compose
	$(CC) config

# APP_SRC goes inline on the compose command: podman compose does not reliably see it otherwise.
up: check-compose
	$(if $(APP_SRC),APP_SRC=$(APP_SRC)) APP_BRANCH=$(APP_BRANCH) $(CC) up -d

up-build: check-compose
	$(if $(APP_SRC),APP_SRC=$(APP_SRC)) APP_BRANCH=$(APP_BRANCH) $(CC) up -d --build

down: check-compose
	$(CC) down

logs: check-compose
	$(CC) logs -f

ps: check-compose
	$(CC) ps

# Drive the transfer flow against the running stack and assert balances, report, and GL doc.
test:
	./test/run.sh

# Benign HAPPY-PATH suite: exercises every vulnerable section with legitimate input and asserts normal
# behavior (no exploit). Passes identically on the vulnerable and fixed versions. Needs the stack up.
integration:
	./test/integration.sh

# Teller operations (inquiry, statement, cash, holds) and their rules, via the gateway and the console.
operations:
	./test/operations.sh

# Deploy a given app version and run the happy-path suite against it. Prove both versions match:
#   make run-integration APP_SRC=/path/to/vulnerable-checkout
#   make run-integration APP_SRC=/path/to/fixed-checkout
run-integration:
	APP_SRC=$(APP_SRC) APP_PROFILE=$(APP_PROFILE) ./test/run-integration.sh

# Standardized scoring run for the CURRENT profile: the happy-path test plus every per-vuln trigger,
# each asserted to fire iff the manifest grades that instance exploitable under this profile.
verify: check-compose
	APP_BRANCH=$(APP_BRANCH) APP_PROFILE=$(APP_PROFILE) APP_DIR=$(APP_DIR) APP_SRC=$(APP_SRC) \
	  COMPOSE_CMD="$(CC)" ./test/verify.sh

# Blind-branch generation (clue-scan, gen-blind, publish) now lives in the legacy-goat repo's own
# tooling/ so its CI can push branches with GITHUB_TOKEN (no cross-repo secret). See legacy-goat/tooling.

# Regenerate benchmark/ground-truth.<profile>.sarif from benchmark/manifest.yaml (main only).
ground-truth:
	APP_DIR=$(APP_DIR) ./tooling/gen-ground-truth.sh

# Check every ground-truth region still holds its construct in TREE (default: the main checkout).
# Run it against a generated blind tree too: make check-alignment TREE=/path/to/vulnerable-tree
check-alignment:
	uv run --quiet --with pyyaml python3 tooling/check_alignment.py $(APP_DIR)/benchmark $(or $(TREE),$(APP_DIR))

# Score a scanner's SARIF against a profile's ground truth. Usage: make score SCANNER=out.sarif APP_PROFILE=permissive
score:
	@test -n "$(SCANNER)" || { echo "set SCANNER=<scanner.sarif>"; exit 2; }
	uv run --quiet --with pyyaml python3 tooling/score.py \
	  $(APP_DIR)/benchmark/ground-truth.$(APP_PROFILE).sarif "$(SCANNER)"

clean: check-compose
	$(CC) down -v --remove-orphans
