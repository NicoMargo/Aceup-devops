project     = "floci-prod"
name_prefix = "prod-"

# This file is the manifest of what is deployed to this environment. A pipeline
# run overrides only the services it rebuilt; everything else stays on the image
# pinned here. Rollback is therefore a git revert, and promotion from staging is
# a copy of the staging tfvars values into this file.
inventory_image     = "ghcr.io/nicomargo/inventory:658d57be7734feba8930a341a25aea7a91e8339c"
notifications_image = "ghcr.io/nicomargo/notifications:658d57be7734feba8930a341a25aea7a91e8339c"
orders_image        = "ghcr.io/nicomargo/orders:658d57be7734feba8930a341a25aea7a91e8339c"
