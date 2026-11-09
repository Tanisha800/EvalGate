#!/usr/bin/env bash
# Verifies the local development environment.
#
# Usage:
#   bash scripts/check-env.sh tools      # Node, pnpm, uv, Python versions (no Docker needed)
#   bash scripts/check-env.sh services   # Docker, Postgres, Redis (run `make up` first)
#
# The exit code is the number of failed checks, so 0 means everything is fine.
# The only thing this script writes is a temporary Redis key, which it deletes again.

set -uo pipefail
cd "$(dirname "$0")/.."   # always run from the repository root

failed_checks=0

pass() { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✘\033[0m %s\n" "$1"; failed_checks=$((failed_checks + 1)); }
section() { printf "\n\033[1m%s\033[0m\n" "$1"; }


check_tools() {
  section "Toolchain"

  # Node: the major version must match .nvmrc (e.g. "22" → v22.x.y).
  local wanted_node actual_node
  wanted_node="$(cat .nvmrc)"
  actual_node="$(node -v 2>/dev/null || echo "not installed")"
  if [[ "$actual_node" == v${wanted_node}.* ]]; then
    pass "node $actual_node"
  else
    fail "node $actual_node (want v${wanted_node}.x – run: nvm use)"
  fi

  # pnpm: must match the exact version pinned in package.json ("packageManager").
  local wanted_pnpm actual_pnpm
  wanted_pnpm="$(sed -n 's/.*"packageManager": "pnpm@\([^"]*\)".*/\1/p' package.json)"
  actual_pnpm="$(pnpm -v 2>/dev/null || echo "not installed")"
  if [[ "$actual_pnpm" == "$wanted_pnpm" ]]; then
    pass "pnpm $actual_pnpm"
  else
    fail "pnpm $actual_pnpm (want $wanted_pnpm)"
  fi

  # uv manages our Python versions and virtual environments.
  if uv --version >/dev/null 2>&1; then
    pass "$(uv --version)"
  else
    fail "uv not installed"
  fi

  # Python: ask uv to find an interpreter matching .python-version (e.g. "3.11").
  local wanted_python python_path
  wanted_python="$(cat .python-version)"
  python_path="$(uv python find "$wanted_python" 2>/dev/null)"
  if [[ -n "$python_path" ]]; then
    pass "python $("$python_path" -c 'import platform; print(platform.python_version())') ($python_path)"
  else
    fail "python $wanted_python not found (run: uv python install $wanted_python)"
  fi
}


# Runs redis-cli inside the Redis container and strips Windows-style line endings.
redis_command() {
  docker compose exec -T redis redis-cli "$@" 2>/dev/null | tr -d '\r'
}


check_services() {
  section "Docker"
  if ! docker info >/dev/null 2>&1; then
    fail "Docker is not running – start Docker Desktop"
    return   # nothing else can be checked without Docker
  fi
  local cpu_count memory_bytes
  read -r cpu_count memory_bytes < <(docker info --format '{{.NCPU}} {{.MemTotal}}')
  pass "Docker running (${cpu_count} CPUs, $((memory_bytes / 1048576)) MiB VM memory)"

  if [[ ! -f .env ]]; then
    fail ".env missing – run: make env"
    return   # docker compose cannot read its settings without .env
  fi
  pass ".env present"

  section "Containers"
  local service health
  for service in postgres redis; do
    health="$(docker compose ps --format '{{.Health}}' "$service" 2>/dev/null)"
    if [[ "$health" == "healthy" ]]; then
      pass "$service healthy"
    else
      fail "$service not healthy (state: ${health:-not running}) – run: make up"
    fi
  done

  section "Postgres"
  # Load POSTGRES_USER / POSTGRES_DB from .env so we can connect.
  set -a; source .env; set +a
  local postgres_version
  postgres_version="$(docker compose exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc 'select version()' 2>/dev/null)"
  if [[ "$postgres_version" == "PostgreSQL 16"* ]]; then
    pass "query works: ${postgres_version%% on *}"
  else
    fail "could not query Postgres"
  fi

  section "Redis"
  local redis_version
  redis_version="$(redis_command INFO server | sed -n 's/^redis_version://p')"
  if [[ "$redis_version" == 7.* ]]; then pass "redis $redis_version"; else fail "redis version: ${redis_version:-unknown}"; fi

  # Redis will be our job queue, so these two settings matter (see docker-compose.yml).
  if [[ "$(redis_command CONFIG GET maxmemory-policy | tail -1)" == "noeviction" ]]; then
    pass "maxmemory-policy = noeviction (queued jobs are never silently dropped)"
  else
    fail "maxmemory-policy is not noeviction"
  fi
  if [[ "$(redis_command CONFIG GET appendonly | tail -1)" == "yes" ]]; then
    pass "appendonly = yes (queued jobs survive a restart)"
  else
    fail "appendonly is disabled"
  fi

  check_redis_streams_round_trip

  section "Container memory"
  docker stats --no-stream --format '  {{.Name}}: {{.MemUsage}}' $(docker compose ps -q) 2>/dev/null
}


# Simulates one job going through a queue: a producer adds a message, a consumer
# reads it as part of a consumer group, then acknowledges it. Afterwards no message
# may be left "pending" (read but not acknowledged).
check_redis_streams_round_trip() {
  local stream_key="evalgate:check:$$"   # $$ = this script's process id, so the key is unique
  local message_id acknowledged pending_count

  redis_command XGROUP CREATE "$stream_key" checkers '$' MKSTREAM >/dev/null
  redis_command XADD "$stream_key" '*' job ping >/dev/null
  # XREADGROUP prints: stream name, message id, field, value – line 2 is the id.
  message_id="$(redis_command XREADGROUP GROUP checkers consumer-1 COUNT 1 STREAMS "$stream_key" '>' | sed -n 2p)"
  acknowledged="$(redis_command XACK "$stream_key" checkers "$message_id")"
  pending_count="$(redis_command XPENDING "$stream_key" checkers | head -1)"
  redis_command DEL "$stream_key" >/dev/null

  if [[ "$acknowledged" == "1" && "$pending_count" == "0" ]]; then
    pass "streams round-trip: XADD → XREADGROUP → XACK"
  else
    fail "streams round-trip failed (acknowledged=$acknowledged, pending=$pending_count)"
  fi
}


case "${1:-tools}" in
  tools)    check_tools ;;
  services) check_services ;;
  *)        echo "usage: $0 [tools|services]"; exit 64 ;;
esac

echo
if (( failed_checks == 0 )); then
  printf "\033[32mAll checks passed.\033[0m\n"
else
  printf "\033[31m%d check(s) failed.\033[0m\n" "$failed_checks"
fi
exit "$failed_checks"
