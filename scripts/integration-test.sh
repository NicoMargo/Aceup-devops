#!/usr/bin/env bash
# Runs the integration tests against an already-deployed environment.
# Node runs containerised and the tests use only built-ins, so nothing needs to
# be installed on the host and no dependency install step is required.
set -euo pipefail

ENVIRONMENT="${1:?usage: integration-test.sh <staging|prod>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_IMAGE="node:20-alpine"
ENV_FILE="${REPO_ROOT}/.deploy-${ENVIRONMENT}.env"

[ -f "$ENV_FILE" ] || {
  echo "missing ${ENV_FILE} — run scripts/deploy.sh ${ENVIRONMENT} first" >&2
  exit 1
}

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

# The env file holds localhost URLs, which are right for a human running curl on
# the host. Inside the container the host is host.docker.internal — and that also
# works on Docker Desktop, where --network host would not reach the Mac at all.
echo "running integration tests against ${ENVIRONMENT}"
docker run --rm \
  --add-host host.docker.internal:host-gateway \
  -e ORDERS_URL="${ORDERS_URL/localhost/host.docker.internal}" \
  -e INVENTORY_URL="${INVENTORY_URL/localhost/host.docker.internal}" \
  -e NOTIFICATIONS_URL="${NOTIFICATIONS_URL/localhost/host.docker.internal}" \
  -v "${REPO_ROOT}/tests:/tests:ro" \
  "$NODE_IMAGE" node --test /tests/integration/api.test.mjs
