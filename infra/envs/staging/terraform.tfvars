project     = "floci-staging"
name_prefix = "staging-"

# This file is the manifest of what is deployed to this environment. A pipeline
# run overrides only the services it rebuilt; everything else stays on the image
# pinned here. Rollback is therefore a git revert, and promotion to prod is a
# copy of these values into the prod tfvars.

inventory_image     = "ghcr.io/nicomargo/inventory@sha256:ed8c75912e916c5fa8f66f445491161723a60d5ace40d85b9852061f354105c0"
notifications_image = "ghcr.io/nicomargo/notifications@sha256:eadceefea3015196e92f94976f6f99406b4a26b5edf74c6a3ca107fc2e0b6eb5"
orders_image        = "ghcr.io/nicomargo/orders@sha256:dff908c4f47654b7a1210c781c6d8444504f64b4c9fbb9045db9ec2260b2daa1"