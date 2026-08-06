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

# Resolve each service's image independently. A service rebuilt by this
# pipeline run moves to the new immutable tag; every other service keeps
# whatever terraform.tfvars already pins. That file is therefore the manifest
# of what is deployed where, which also makes rollback a git revert and
# promotion a copy of values from one environment's tfvars to the other's.
tfvars_image() {
  sed -n "s/.*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$TFVARS"
}

# Accepts either "inventory orders" or "services/inventory services/orders".
affected_normalized=" $(echo "${AFFECTED_SERVICES:-}" | sed 's#services/##g') "

resolve_image() {
  local service="$1"

  if [ -z "${IMAGE_TAG:-}" ]; then
    tfvars_image "$service"
    return
  fi

  # No affected list means "this tag applies to everything" (manual deploys).
  if [ -n "${AFFECTED_SERVICES:-}" ] && [[ "$affected_normalized" != *" ${service} "* ]]; then
    tfvars_image "$service"
    return
  fi

  # OCI repository names must be lowercase; github.repository_owner is not.
  echo "ghcr.io/$(echo "${GHCR_OWNER:-nicomargo}" | tr '[:upper:]' '[:lower:]')/${service}:${IMAGE_TAG}"
}

inventory_image=$(resolve_image inventory)
notifications_image=$(resolve_image notifications)
orders_image=$(resolve_image orders)

images_var="images={inventory=\"${inventory_image}\",notifications=\"${notifications_image}\",orders=\"${orders_image}\"}"

echo "resolved images:"
echo "  inventory     ${inventory_image}"
echo "  notifications ${notifications_image}"
echo "  orders        ${orders_image}"

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
# Scoped with -target so the absence of the upstream URLs in this phase does not
# make orders' count evaluate to 0, which would destroy and recreate it on every
# single deploy. -target is normally a smell, but here it is precisely the point:
# this phase exists only to bring up the services orders depends on. Phase 2 is
# a full apply, so the final state always converges on the configuration.
tf apply -auto-approve -input=false -var "$images_var" \
  -target=module.platform.module.inventory \
  -target=module.platform.module.notifications

inventory_port=$(published_port "$(service_name inventory)")
notifications_port=$(published_port "$(service_name notifications)")

echo "==> phase 2: orders, wired to the discovered upstreams"
tf apply -auto-approve -input=false -var "$images_var" \
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
