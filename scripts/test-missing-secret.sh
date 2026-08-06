#!/usr/bin/env bash
# Proves the services fail closed when a required secret is unavailable.
#
# Two levels of evidence:
#   default   the container exits non-zero — the root cause, ~5s
#   --full    a Cloud Run revision never becomes ready — the production-visible
#             manifestation, ~4 min (floci's readiness timeout)
#
# Both matter: the services load secrets in main() before app.listen(), so a
# missing secret is never a graceful HTTP error, it is a process that never
# serves traffic. On Cloud Run that means a revision stuck unhealthy and, in a
# real rollout, traffic staying on the previous revision.
set -euo pipefail

FULL=0
[ "${1:-}" = "--full" ] && FULL=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENDPOINT="${FLOCI_ENDPOINT:-http://localhost:4588}"
TFVARS="${REPO_ROOT}/infra/envs/staging/terraform.tfvars"
EMPTY_PROJECT="floci-no-secrets-here"

IMAGE=$(sed -n 's/^[[:space:]]*inventory_image[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS")
[ -n "$IMAGE" ] || { echo "could not resolve the inventory image from ${TFVARS}" >&2; exit 1; }

echo "==> container-level: inventory must refuse to start without its secret"

# --stop-timeout rather than the `timeout` command: macOS does not ship one.
# The container exits on its own anyway; this is only a guard against a hang.
set +e
output=$(docker run --rm --stop-timeout 60 \
  --add-host host.docker.internal:host-gateway \
  -e GCP_PROJECT_ID="$EMPTY_PROJECT" \
  -e SECRET_MANAGER_EMULATOR_HOST=host.docker.internal:4588 \
  "$IMAGE" 2>&1)
exit_code=$?
set -e

if [ "$exit_code" -eq 0 ]; then
  echo "FAIL: the container started even though the secret is absent" >&2
  exit 1
fi

if ! grep -q "failed to start inventory" <<<"$output"; then
  echo "FAIL: exited non-zero but not for the expected reason:" >&2
  echo "$output" >&2
  exit 1
fi

echo "    ok — exited ${exit_code} with 'failed to start inventory'"

if [ "$FULL" -eq 0 ]; then
  echo
  echo "skipping the Cloud Run readiness check (run with --full to include it)"
  exit 0
fi

echo "==> cloud run level: a revision must never become ready (~4 min)"

SERVICE="probe-missing-secret"
BASE="${ENDPOINT}/v2/projects/${EMPTY_PROJECT}/locations/us-central1/services"

cleanup() { curl -sS -o /dev/null -X DELETE "${BASE}/${SERVICE}" || true; }
trap cleanup EXIT

curl -sS -o /dev/null -X POST "${BASE}?serviceId=${SERVICE}" \
  -H 'content-type: application/json' \
  -d "{\"template\":{\"containers\":[{\"image\":\"${IMAGE}\",\"ports\":[{\"containerPort\":8081}],\"env\":[{\"name\":\"GCP_PROJECT_ID\",\"value\":\"${EMPTY_PROJECT}\"},{\"name\":\"SECRET_MANAGER_EMULATOR_HOST\",\"value\":\"host.docker.internal:4588\"}]}]}}"

# CONDITION_PENDING means floci is still starting the container, so poll until
# a terminal state is reached rather than until the field is merely populated.
state=""
for _ in $(seq 1 60); do
  sleep 10
  # terminalCondition comes first in the response, so the first CONDITION_* match
  # is its state. grep keeps jq off the list of host requirements.
  state=$(curl -sS "${BASE}/${SERVICE}" | grep -o 'CONDITION_[A-Z]*' | head -1)
  case "$state" in
    CONDITION_FAILED | CONDITION_SUCCEEDED) break ;;
  esac
  echo "    revision still settling (state='${state:-unknown}')..."
done

case "$state" in
  CONDITION_FAILED)
    echo "    ok — revision never became ready, as expected"
    ;;
  CONDITION_SUCCEEDED)
    echo "FAIL: the revision became ready without its secret" >&2
    exit 1
    ;;
  *)
    echo "FAIL: revision did not settle within the polling window (state='${state}')" >&2
    exit 1
    ;;
esac
