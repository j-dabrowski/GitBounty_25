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

export const factoryAddress = "0xf6C968e06747B92881208c45285A7Cd2689A7a54";

export const factoryAbi = [
  "function bountyCount() view returns (uint256)",
  "function getBounties(uint256 start, uint256 limit) view returns (address[] bountyAddresses, uint256[] nextAttemptAts)"
];

export const bountyAbi = [
  `function getBountySnapshot() view returns (
      uint8 r_state,
      address r_owner,
      address r_factory,
      bool r_initialized,
      string r_repoOwner,
      string r_repo,
      string r_issueNumber,
      uint256 r_totalFunding,
      uint256 r_funderCount,
      address r_lastWinner,
      string r_lastWinnerUser,
      uint256 r_lastBountyAmount
  )`
];