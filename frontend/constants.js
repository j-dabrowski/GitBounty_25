export const chainIdMap = {
  "0x1": "Ethereum Mainnet",
  "0x5": "Goerli Testnet",
  "0xaa36a7": "Sepolia Testnet",
  "0x89": "Polygon Mainnet",
  "0x13881": "Mumbai Testnet",
  "0xa": "Optimism",
  "0x66eed": "Arbitrum Testnet",
  "0x144": "Blast Sepolia",
};

export const READ_RPC_URLS = [
  "https://rpc.sepolia.org",
  "https://rpc.ankr.com/eth_sepolia",
  "https://ethereum-sepolia.publicnode.com",
  "https://sepolia.drpc.org",
];

export const API_ORIGIN = "";

export const factoryAddress = "0x5daD63916C4e6F2322F77621dbb61E015F467Aeb";

export const factoryAbi = [
  "function bountyCount() view returns (uint256)",
  "function getBounties(uint256 start, uint256 limit) view returns (address[] bountyAddresses, uint256[] nextAttemptAts)",
  "function createBounty(string _repoOwner, string _repo, string _issueNumber) payable returns (address bountyAddr)",
  "event BountyDeployed(address indexed bounty, address indexed bountyOwner)"
];

export const bountyAbi = [
  {
    "inputs": [],
    "name": "getBountySnapshot",
    "outputs": [
      {
        "internalType": "struct BountySnapshot",
        "name": "s",
        "type": "tuple",
        "components": [
          { "internalType": "enum GitbountyState", "name": "state", "type": "uint8" },
          { "internalType": "address", "name": "owner", "type": "address" },
          { "internalType": "address", "name": "factory", "type": "address" },
          { "internalType": "bool", "name": "initialized", "type": "bool" },

          { "internalType": "string", "name": "repoOwner", "type": "string" },
          { "internalType": "string", "name": "repo", "type": "string" },
          { "internalType": "string", "name": "issueNumber", "type": "string" },

          { "internalType": "uint256", "name": "totalFunding", "type": "uint256" },
          { "internalType": "uint256", "name": "funderCount", "type": "uint256" },

          { "internalType": "address", "name": "lastWinner", "type": "address" },
          { "internalType": "string", "name": "lastWinnerUser", "type": "string" },

          { "internalType": "string", "name": "last_repo_owner", "type": "string" },
          { "internalType": "string", "name": "last_repo", "type": "string" },
          { "internalType": "string", "name": "last_issueNumber", "type": "string" },

          { "internalType": "uint256", "name": "lastBountyAmount", "type": "uint256" }
        ]
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
];