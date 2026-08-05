#!/usr/bin/env bash
# Seeds the application secrets into a floci-gcp project via the Secret Manager
# REST API. Values come from the environment so CI can inject them from GitHub
# Secrets; the defaults are throwaway local-development tokens.
set -euo pipefail

PROJECT="${1:?usage: seed-secrets.sh <project-id>}"
ENDPOINT="${FLOCI_ENDPOINT:-http://localhost:4588}"

INVENTORY_TOKEN="${INVENTORY_API_TOKEN:-dev-inventory-token}"
NOTIFICATIONS_TOKEN="${NOTIFICATIONS_API_TOKEN:-dev-notifications-token}"

seed() {
  local id="$1" value="$2" encoded

  # Creating an existing secret returns an error we can safely ignore, which is
  # what makes re-running the pipeline on the same environment a no-op.
  curl -sS -o /dev/null -X POST \
    "${ENDPOINT}/v1/projects/${PROJECT}/secrets?secretId=${id}" \
    -H 'content-type: application/json' \
    -d '{"replication":{"automatic":{}}}' || true

  encoded=$(printf '%s' "$value" | base64 -w0)

  curl -sS -o /dev/null -X POST \
    "${ENDPOINT}/v1/projects/${PROJECT}/secrets/${id}:addVersion" \
    -H 'content-type: application/json' \
    -d "{\"payload\":{\"data\":\"${encoded}\"}}"

  # Log the secret id only, never the value.
  echo "  seeded ${id}"
}

echo "seeding secrets into project ${PROJECT}"
seed inventory-api-token "$INVENTORY_TOKEN"
seed notifications-api-token "$NOTIFICATIONS_TOKEN"
