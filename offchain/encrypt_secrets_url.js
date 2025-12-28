const fs = require("fs");
const path = require("path");
const { SecretsManager } = require("@chainlink/functions-toolkit");
const ethers = require("ethers");
require("@chainlink/env-enc").config();

async function main() {
  const routerAddress = "0xb83E47C2bC239B3bf370bc41e1459A34b41238D0";
  const donId = "fun-ethereum-sepolia-1";

  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) throw new Error("PRIVATE_KEY missing");

  const rpcUrl = process.env.SEPOLIA_RPC_URL;
  if (!rpcUrl) throw new Error("SEPOLIA_RPC_URL missing");

  const secretsUrl = process.env.GITHUB_SECRET_URL;
  if (!secretsUrl) throw new Error("GITHUB_SECRET_URL missing (S3 URL to offchain-secrets.json)");

  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
  const signer = new ethers.Wallet(privateKey, provider);

  const secretsManager = new SecretsManager({
    signer,
    functionsRouterAddress: routerAddress,
    donId,
  });
  await secretsManager.initialize();

  const encryptedSecretsUrls = await secretsManager.encryptSecretsUrls([secretsUrl]);

  const out = {
    network: "sepolia",
    donId,
    routerAddress,
    secretsUrls: [secretsUrl],
    encryptedSecretsUrls
  };

  const outPath = path.resolve(__dirname, "encrypted-secrets-urls.sepolia.json");
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));

  console.log("✅ Encrypted secrets URLs generated");
  console.log("Saved:", outPath);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
