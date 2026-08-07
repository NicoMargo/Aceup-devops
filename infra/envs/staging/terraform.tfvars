project     = "floci-staging"
name_prefix = "staging-"

# This file is the manifest of what is deployed to this environment. A pipeline
# run overrides only the services it rebuilt; everything else stays on the image
# pinned here. Rollback is therefore a git revert, and promotion to prod is a
# copy of these values into the prod tfvars.

inventory_image     = "ghcr.io/nicomargo/inventory@sha256:a23ba0a83981902894210f267a4445c40539d8356638e594d4c92213035973a1"
notifications_image = "ghcr.io/nicomargo/notifications@sha256:19f849f456609f644d8fbe99fc79255231df39e5c8228b9ac517b81492364c20"
orders_image        = "ghcr.io/nicomargo/orders@sha256:de1fecd8225aecc1de98c96c4ef933d3b2b334940e8460755c92ef3e89f3804e"