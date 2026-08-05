const { SecretManagerServiceClient } = require("@google-cloud/secret-manager");
const grpc = require("@grpc/grpc-js");

const PROJECT_ID = process.env.GCP_PROJECT_ID ?? "floci-local";
const EMULATOR_HOST = process.env.SECRET_MANAGER_EMULATOR_HOST ?? "localhost:4588";

// Values come from the environment so CI can inject them from GitHub Secrets.
// The defaults are throwaway local-development tokens, never real credentials.
const SECRETS = {
  "inventory-api-token": process.env.INVENTORY_API_TOKEN ?? "dev-inventory-token",
  "notifications-api-token": process.env.NOTIFICATIONS_API_TOKEN ?? "dev-notifications-token",
};

const [host, port] = EMULATOR_HOST.split(":");

const client = new SecretManagerServiceClient({
  apiEndpoint: host,
  port: Number(port),
  sslCreds: grpc.credentials.createInsecure(),
});

async function ensureSecret(secretId, value) {
  const parent = `projects/${PROJECT_ID}`;

  try {
    await client.createSecret({
      parent,
      secretId,
      secret: { replication: { automatic: {} } },
    });
    console.log(`created secret: ${secretId}`);
  } catch (err) {
    if (err.code === 6) {
      // gRPC code 6 = ALREADY_EXISTS
      console.log(`secret already exists: ${secretId}`);
    } else {
      throw err;
    }
  }

  await client.addSecretVersion({
    parent: `${parent}/secrets/${secretId}`,
    payload: { data: Buffer.from(value, "utf8") },
  });
  // Never log the value itself.
  console.log(`added version to: ${secretId}`);
}

async function main() {
  console.log(`seeding secrets into project ${PROJECT_ID} via ${EMULATOR_HOST}`);
  for (const [secretId, value] of Object.entries(SECRETS)) {
    await ensureSecret(secretId, value);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
