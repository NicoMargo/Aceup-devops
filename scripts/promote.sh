#!/usr/bin/env bash
# Promotes the images currently deployed to staging into the prod manifest.
#
# This does not deploy anything. It edits infra/envs/prod/terraform.tfvars so the
# change goes through a pull request, which is what makes promotion auditable:
# the repo records which version runs in prod, who promoted it and when, and a
# rollback is a revert of that commit.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FROM="${REPO_ROOT}/infra/envs/staging/terraform.tfvars"
TO="${REPO_ROOT}/infra/envs/prod/terraform.tfvars"

echo "promoting staging images into prod:"

for service in inventory notifications orders; do
  image=$(sed -n "s/^[[:space:]]*${service}_image[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$FROM")
  [ -n "$image" ] || { echo "could not read ${service}_image from staging" >&2; exit 1; }

  # Write through a temp file instead of `sed -i`: GNU and BSD sed disagree on
  # whether -i takes a backup suffix, and macOS ships the BSD one.
  sed "s|^\([[:space:]]*${service}_image[[:space:]]*=[[:space:]]*\).*|\1\"${image}\"|" "$TO" > "${TO}.tmp"
  mv "${TO}.tmp" "$TO"
  echo "  ${service} -> ${image}"
done

echo
echo "prod manifest updated. Commit it and open a pull request to promote."
git --no-pager diff --stat "$TO"
