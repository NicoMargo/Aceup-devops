# AceUp DevOps homework

A small TypeScript monorepo with three services, and the delivery system around
it: tests and images only for what changed, deploys to Cloud Run on the
[floci-gcp](https://floci.io/gcp/) emulator, and integration tests against what
was actually deployed.

The reasoning behind the decisions is in [DESIGN.md](DESIGN.md).

## What is here

```
starter/            the monorepo (npm workspaces)
  packages/         logger, types, secrets, http-client
  services/         orders, inventory, notifications
  scripts/          affected-packages.js — the dependency graph
infra/
  modules/          reusable Terraform: one service, and the platform
  envs/             staging and prod — variables only
scripts/            deploy, seed secrets, run tests
tests/integration/  tests that hit the deployed services over HTTP
```

## How it fits together

```
   PR or push to main
          |
   [ test ]  which packages changed? -> run only their tests + npm audit
          |
   [ build ] build images for affected services -> Trivy scan -> push to GHCR
          |
   [ deploy-staging ]
          |
          +-- start floci-gcp (Docker)
          +-- seed secrets into Secret Manager
          +-- terraform apply -> Cloud Run
          +-- integration tests over HTTP
```

The three services talk to each other:

```
   orders  --HTTP-->  inventory      (reserve stock, with an API token)
      |
      +---- HTTP -->  notifications  (send the confirmation)

   all three read their tokens from Secret Manager at startup
```

## Differential builds and deploys

`starter/scripts/affected-packages.js` reads every `package.json` in the
monorepo and builds the dependency graph. CI gives it the list of changed files
and it answers which packages and services are affected.

| You change | What is rebuilt |
|---|---|
| `services/orders/**` | orders |
| `packages/http-client/**` | orders (it is the only package that uses it) |
| `packages/logger/**` | all three services |
| lockfile, CI, root config | everything |

The last row is on purpose. If the file that decides what to build has changed,
we do not trust that decision.

`infra/envs/<env>/terraform.tfvars` holds the image of each service. A pipeline
run only overrides the services it rebuilt, so the file is always the record of
what runs where. Rollback is a git revert of that file, and promotion to prod is
copying the values across.

## Running it locally

You need **Docker** and **make**. Node, Terraform and floci all run in containers
with pinned versions — nothing else has to be installed. The scripts also use
`curl`, `jq`, `sed` and `base64`, which come with most systems.

The whole loop is one command:

```bash
make verify ENV=staging
```

That starts the emulator, seeds the secrets, deploys with Terraform, runs the
integration tests and checks the services fail closed without their secrets.

Step by step, if you want to see the parts:

```bash
make floci-up                     # start the emulator
make deploy ENV=staging           # seed secrets + terraform apply, prints the URLs
make integration-test ENV=staging
make test-secrets                 # services must not start without their secrets
make floci-down                   # stop the emulator
```

`make help` lists everything. The targets just call the scripts in `scripts/`,
so you can run those directly too.

If you have the floci CLI, `floci gcp start` replaces `make floci-up`.

`deploy.sh` writes the URLs to `.deploy-staging.env`:

```bash
source .deploy-staging.env
curl -s "$INVENTORY_URL/stock/SKU-TEE"
curl -s "$ORDERS_URL/orders" -H 'content-type: application/json' \
  -d '{"sku":"SKU-TEE","quantity":2,"customerEmail":"me@example.com"}'
curl -s "$INVENTORY_URL/stock/SKU-TEE"   # stock went down by 2
```

`prod` works the same way: `./scripts/deploy.sh prod`. It is a separate GCP
project, so the two environments do not share secrets or services.

### Working on the code

```bash
make install    # npm ci
make test       # unit tests for every workspace
make build      # compile everything
```

These run npm inside a `node:20-alpine` container, so the Node version is the
same for everyone and for CI. To work on one workspace only:

```bash
cd starter
npm test -w @aceup/orders-service
```

## How CI uses floci

floci is not a server somewhere. Every workflow run starts a fresh one inside
the GitHub Actions VM, deploys into it, tests it, and the VM is destroyed when
the job ends. Nothing is left over, and nothing from a previous run can affect
the next one.

That also means you cannot open the deployed services from your browser after a
CI run — the only thing that comes out is the log. That is why the integration
tests run inside the same VM.

CI runs the same `make` targets you run locally — `make floci-up`,
`make deploy ENV=staging`, `make integration-test ENV=staging`. There is no
separate CI-only path that could drift from what you tested by hand.

## Security checks in the pipeline

- GitHub Actions pinned to commit SHAs, not tags.
- `npm audit --audit-level=high` fails the run.
- Trivy scans each image **before** it is pushed. Fixable HIGH and CRITICAL fail
  the build. Exceptions live in `.trivyignore` with a reason and an expiry date.
- Only the build job can write packages; everything else is read only.
- No secret value is in the repo, in an image, or in a build argument. Tokens
  arrive as environment variables at runtime, and the seeding script never logs
  a value.

## Operations

```bash
# which revision is live
curl -s "http://localhost:4588/v2/projects/floci-staging/locations/us-central1/services" | jq

# roll back one service: put its previous image back in the tfvars and redeploy
git revert <commit>            # or edit infra/envs/staging/terraform.tfvars
./scripts/deploy.sh staging
```

Rollback is per service, because each service has its own image line in the
tfvars.

**Secret rotation:** add a new version of the secret, then deploy a new
revision. Services read the secret once at startup, so a running container keeps
the old value until it is replaced. Traffic only moves to the new revision once
it is healthy, so a wrong secret value means the deploy fails and the old
revision keeps serving.

Known limits are listed at the end of [DESIGN.md](DESIGN.md).
