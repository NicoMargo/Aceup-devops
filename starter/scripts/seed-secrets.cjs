const { SecretManagerServiceClient } = require("@google-cloud/secret-manager");
  const grpc = require("@grpc/grpc-js");

  const PROJECT_ID = "floci-local";
  const EMULATOR_ENDPOINT = "localhost";

  const client = new SecretManagerServiceClient({
    apiEndpoint: EMULATOR_ENDPOINT,
    port: 4588,
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
    console.log(`added version to: ${secretId}`);
  }

  async function main() {
    await ensureSecret("inventory-api-token", "dev-inventory-token");
    await ensureSecret("notifications-api-token", "dev-notifications-token");
  }
  
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
