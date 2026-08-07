#!/usr/bin/env bash
# Writes INVENTORY_IMAGE, NOTIFICATIONS_IMAGE and ORDERS_IMAGE into one
# environment's terraform.tfvars.
#
# A variable that is not set leaves its line alone, so a run that rebuilt one
# service only touches that service.
set -euo pipefail

ENVIRONMENT="${1:?usage: set-images.sh <staging|prod>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS="${REPO_ROOT}/infra/envs/${ENVIRONMENT}/terraform.tfvars"

[ -f "$TFVARS" ] || { echo "unknown environment: ${ENVIRONMENT}" >&2; exit 1; }

for service in inventory notifications orders; do
  var="$(echo "$service" | tr '[:lower:]' '[:upper:]')_IMAGE"
  image="${!var:-}"
  [ -n "$image" ] || continue

  # Through a temp file rather than `sed -i`: GNU and BSD sed disagree on whether
  # -i takes a backup suffix, and macOS ships the BSD one.
  sed "s|^\([[:space:]]*${service}_image[[:space:]]*=[[:space:]]*\).*|\1\"${image}\"|" \
    "$TFVARS" > "${TFVARS}.tmp"
  mv "${TFVARS}.tmp" "$TFVARS"

  echo "  ${service} -> ${image}"
done
