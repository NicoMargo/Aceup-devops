#!/usr/bin/env bash
# Deploys one environment to floci-gcp Cloud Run.
#
# floci gives Cloud Run services a *.run.localhost.floci.io URL, but does not
# make that name resolvable from inside the containers it launches, so orders
# cannot reach the other services that way. Deployment therefore runs in two
# phases: bring up the services orders depends on, discover the ports floci
# published for them on the host, then deploy orders pointing at those. On real
# GCP a single apply suffices, because the module's `uri` output resolves
# globally.
set -euo pipefail

ENVIRONMENT="${1:?usage: deploy.sh <staging|prod>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_IMAGE="hashicorp/terraform:1.15.8"
TFVARS="${REPO_ROOT}/infra/envs/${ENVIRONMENT}/terraform.tfvars"

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

# A service is overridden only if its image was passed in as INVENTORY_IMAGE,
# NOTIFICATIONS_IMAGE or ORDERS_IMAGE. Everything else stays on what
# terraform.tfvars pins, which is what keeps the deploy differential: the
# pipeline never needs to know the previous versions.
#
# CI passes digest references (repo@sha256:...), not tags. A tag can be moved to
# point at different content; a digest is a hash of the content itself.
image_args=()
for service in inventory notifications orders; do
  var="$(echo "$service" | tr '[:lower:]' '[:upper:]')_IMAGE"
  value="${!var:-}"
  if [ -n "$value" ]; then
    image_args+=(-var "${service}_image=${value}")
    echo "overriding ${service} -> ${value}"
  fi
done

# floci names containers floci-gcp-cloudrun-<service>-<revision>-<uuid>; anchor
# the match so one service can never be picked up by another's filter.
published_port() {
  local container
  container=$(docker ps --filter "name=^floci-gcp-cloudrun-$1-" --format '{{.Names}}' | head -1)
  [ -n "$container" ] || { echo "no running container for $1" >&2; return 1; }
  docker inspect "$container" \
    --format '{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}'
}

# Matching a container by name is inference, not proof. Ask the service what it
# is before writing its URL anywhere, so a bad mapping fails the deploy loudly
# instead of resurfacing later as confusing integration-test failures.
verify() {
  local port="$1" expected="$2" reported
  reported=$(curl -sS -m 5 "http://localhost:${port}/health" | jq -r '.service // ""')
  [ "$reported" = "$expected" ] || {
    echo "port ${port} reports '${reported}', expected '${expected}'" >&2
    return 1
  }
  echo "  ${expected} -> localhost:${port}"
}

echo "==> seeding secrets"
"${REPO_ROOT}/scripts/seed-secrets.sh" "$PROJECT"

echo "==> terraform init"
tf init -input=false

echo "==> phase 1: services without runtime dependencies"
# Scoped with -target so the absence of the upstream URLs in this phase does not
# make orders' count evaluate to 0, which would destroy and recreate it on every
# deploy. Phase 2 is a full apply, so the final state still converges on the
# configuration.
tf apply -auto-approve -input=false "${image_args[@]}" \
  -target=module.platform.module.inventory \
  -target=module.platform.module.notifications

inventory_port=$(published_port "${ENVIRONMENT}-inventory")
notifications_port=$(published_port "${ENVIRONMENT}-notifications")

echo "==> verifying discovered endpoints"
verify "$inventory_port" inventory
verify "$notifications_port" notifications

echo "==> phase 2: orders, wired to the discovered upstreams"
tf apply -auto-approve -input=false "${image_args[@]}" \
  -var "inventory_base_url=http://host.docker.internal:${inventory_port}" \
  -var "notifications_base_url=http://host.docker.internal:${notifications_port}"

orders_port=$(published_port "${ENVIRONMENT}-orders")
verify "$orders_port" orders

# Consumed by the integration tests so they never hardcode a port.
cat > "${REPO_ROOT}/.deploy-${ENVIRONMENT}.env" <<EOF
ORDERS_URL=http://localhost:${orders_port}
INVENTORY_URL=http://localhost:${inventory_port}
NOTIFICATIONS_URL=http://localhost:${notifications_port}
EOF

echo
echo "deployed ${ENVIRONMENT} (project ${PROJECT}) — urls in .deploy-${ENVIRONMENT}.env"
