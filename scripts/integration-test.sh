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

echo "running integration tests against ${ENVIRONMENT}"
docker run --rm --network host \
  -e ORDERS_URL -e INVENTORY_URL -e NOTIFICATIONS_URL \
  -v "${REPO_ROOT}/tests:/tests:ro" \
  "$NODE_IMAGE" node --test /tests/integration/api.test.mjs
