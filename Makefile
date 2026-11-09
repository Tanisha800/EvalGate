# EvalGate developer commands. Run `make` or `make help` to list them.
.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help env up down check check-services psql

help: ## List available commands
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2}'

env: ## Create .env from .env.example (never overwrites an existing .env)
	@if [ -f .env ]; then echo ".env already exists – left untouched"; else cp .env.example .env && echo "created .env"; fi

up: ## Start Postgres + Redis and wait until they are healthy
	docker compose up -d --wait

down: ## Stop Postgres + Redis (data is kept)
	docker compose down

check: ## Check toolchain versions (Node, pnpm, uv, Python)
	@bash scripts/check-env.sh tools

check-services: ## Check Docker, Postgres and Redis (run `make up` first)
	@bash scripts/check-env.sh services

psql: ## Open a SQL shell in the local database
	@set -a; source .env; set +a; docker compose exec postgres psql -U $$POSTGRES_USER -d $$POSTGRES_DB
