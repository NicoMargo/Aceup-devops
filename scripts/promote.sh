#!/usr/bin/env bash
# Promotes the images currently pinned for staging into the prod manifest.
#
# This does not deploy anything. It edits infra/envs/prod/terraform.tfvars so the
# change goes through a pull request, which is what makes promotion auditable:
# the repo records which version runs in prod, who promoted it and when, and a
# rollback is a revert of that commit.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING="${REPO_ROOT}/infra/envs/staging/terraform.tfvars"

read_image() {
  sed -n "s/^[[:space:]]*$1_image[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$STAGING"
}

inventory=$(read_image inventory)
notifications=$(read_image notifications)
orders=$(read_image orders)

for service in inventory notifications orders; do
  [ -n "${!service}" ] || { echo "could not read ${service}_image from staging" >&2; exit 1; }
done

echo "promoting staging images into prod:"

INVENTORY_IMAGE="$inventory" \
NOTIFICATIONS_IMAGE="$notifications" \
ORDERS_IMAGE="$orders" \
  "${REPO_ROOT}/scripts/set-images.sh" prod

echo
echo "prod manifest updated. Commit it and open a pull request to promote."
git --no-pager diff --stat "${REPO_ROOT}/infra/envs/prod/terraform.tfvars"
