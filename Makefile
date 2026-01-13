-include .env

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Required env:
# PRIVATE_KEY, SEPOLIA_RPC_URL, ETHERSCAN_API_KEY (if verifying)
# FACTORY_ADDRESS (after deployFactory)
# BOUNTY_ADDRESS (after deployChild)

ARGS ?=

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

.PHONY: deployFactory deployChild \
	factoryPerformSingle factoryCheckUpkeep factoryMapUsername \
	bountyCreateAndFund

deployFactory:
	forge script script/DeployGitbountyFactory.s.sol:DeployGitbountyFactory $(NETWORK_ARGS)

deployChild:
	forge script script/DeployGitbountyChild.s.sol:DeployGitbountyChild $(NETWORK_ARGS)

# ---------- Interactions ----------

# Manual upkeep attempt for exactly one bounty (avoids decoding checkUpkeep output)
factoryPerformSingle:
	@DATA=$$(cast abi-encode "f(address[])" "[$(BOUNTY_ADDRESS)]" | sed 's/^0x//'); \
	cast send $(FACTORY_ADDRESS) "performUpkeep(bytes)" 0x$$DATA \
		$$( [ "$(findstring --network sepolia,$(ARGS))" != "" ] && echo "--rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY)" || echo "--rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY)" ) \
		--gas-limit 2000000 -vvvv

factoryCheckUpkeep:
	cast call $(FACTORY_ADDRESS) "checkUpkeep(bytes)(bool,bytes)" 0x \
		$$( [ "$(findstring --network sepolia,$(ARGS))" != "" ] && echo "--rpc-url $(SEPOLIA_RPC_URL)" || echo "--rpc-url http://localhost:8545" )

# Your factory mapping function is: mapGithubUsernameToAddress(string) and maps to msg.sender
USERNAME ?=
factoryMapUsername:
	cast send $(FACTORY_ADDRESS) "mapGithubUsernameToAddress(string)" "$(USERNAME)" \
		$$( [ "$(findstring --network sepolia,$(ARGS))" != "" ] && echo "--rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY)" || echo "--rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY)" ) \
		--gas-limit 500000 -vvvv

OWNER ?=
REPO ?=
ISSUE ?=
VALUE ?= 0.0001ether
bountyCreateAndFund:
	cast send $(BOUNTY_ADDRESS) "createAndFundBounty(string,string,string)" "$(OWNER)" "$(REPO)" "$(ISSUE)" \
		--value $(VALUE) \
		$$( [ "$(findstring --network sepolia,$(ARGS))" != "" ] && echo "--rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY)" || echo "--rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY)" ) \
		--gas-limit 1000000 -vvvv
