project     = "floci-staging"
name_prefix = "staging-"

# This file is the manifest of what is deployed to this environment. A pipeline
# run overrides only the services it rebuilt; everything else stays on the image
# pinned here. Rollback is therefore a git revert, and promotion to prod is a
# copy of these values into the prod tfvars.

inventory_image     = "ghcr.io/nicomargo/inventory@sha256:6231f27e26e8da16dc1bc18a3625c671401e4b64e5c2a4593ff98e9b37ab9ae8"
notifications_image = "ghcr.io/nicomargo/notifications@sha256:44f131ce0f28e8e1098c24348cc06439c5cb1f77863c56110c72cee3e0fdc32a"
orders_image        = "ghcr.io/nicomargo/orders@sha256:7ecfd2ea3fea76cff7021bf973cdb612581e0d1e51da4888aa2eea15b3fe5328"