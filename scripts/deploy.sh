#!/usr/bin/env bash
# Deploys one environment to floci-gcp Cloud Run.
#
# floci has no service-to-service DNS, so orders cannot resolve the other
# services' Cloud Run URLs. Deployment therefore runs in two phases: the
# dependency-free services first, then their host-published ports are
# discovered and injected into orders. On real GCP a single apply suffices,
# because the module's `uri` output is globally resolvable.
set -euo pipefail

ENVIRONMENT="${1:?usage: deploy.sh <staging|prod>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_IMAGE="hashicorp/terraform:1.15.8"
ENV_DIR="${REPO_ROOT}/infra/envs/${ENVIRONMENT}"
TFVARS="${ENV_DIR}/terraform.tfvars"

[ -f "$TFVARS" ] || { echo "unknown environment: ${ENVIRONMENT}" >&2; exit 1; }

PROJECT=$(sed -n 's/^[[:space:]]*project[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS")

# Terraform always runs containerised so its version is pinned, not inherited
# from whatever the host happens to have installed.
tf() {
  docker run --rm --network host --user "$(id -u):$(id -g)" \
    -v "${REPO_ROOT}/infra:/workspace" \
    -w "/workspace/envs/${ENVIRONMENT}" \
    "$TF_IMAGE" "$@"
}

# CI passes an immutable per-commit reference; local runs fall back to tfvars.
image_override=()
if [ -n "${IMAGE_TAG:-}" ]; then
  owner="${GHCR_OWNER:-nicomargo}"
  image_override=(-var "images={inventory=\"ghcr.io/${owner}/inventory:${IMAGE_TAG}\",notifications=\"ghcr.io/${owner}/notifications:${IMAGE_TAG}\",orders=\"ghcr.io/${owner}/orders:${IMAGE_TAG}\"}")
fi

service_name() {
  tf output -json service_names | jq -r ".$1"
}

published_port() {
  local service="$1" container
  container=$(docker ps --filter "name=cloudrun-${service}" --format '{{.Names}}' | head -1)
  [ -n "$container" ] || { echo "no running container for ${service}" >&2; return 1; }
  docker port "$container" | head -1 | sed 's/.*:\([0-9]*\)$/\1/'
}

echo "==> seeding secrets"
"${REPO_ROOT}/scripts/seed-secrets.sh" "$PROJECT"

echo "==> terraform init"
tf init -input=false

echo "==> phase 1: services without runtime dependencies"
tf apply -auto-approve -input=false "${image_override[@]}"

inventory_port=$(published_port "$(service_name inventory)")
notifications_port=$(published_port "$(service_name notifications)")

echo "==> phase 2: orders, wired to the discovered upstreams"
tf apply -auto-approve -input=false "${image_override[@]}" \
  -var "inventory_base_url=http://host.docker.internal:${inventory_port}" \
  -var "notifications_base_url=http://host.docker.internal:${notifications_port}"

orders_port=$(published_port "$(service_name orders)")

# Consumed by the integration tests so they never hardcode a port.
cat > "${REPO_ROOT}/.deploy-${ENVIRONMENT}.env" <<EOF
ORDERS_URL=http://localhost:${orders_port}
INVENTORY_URL=http://localhost:${inventory_port}
NOTIFICATIONS_URL=http://localhost:${notifications_port}
EOF

echo
echo "deployed ${ENVIRONMENT} (project ${PROJECT}):"
echo "  orders        http://localhost:${orders_port}"
echo "  inventory     http://localhost:${inventory_port}"
echo "  notifications http://localhost:${notifications_port}"
echo "  urls written to .deploy-${ENVIRONMENT}.env"
