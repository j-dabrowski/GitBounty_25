-include .env
export

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

ARGS ?=

# forge script network args
NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

# cast helpers
RPC_ONLY := $$( [ "$(findstring --network sepolia,$(ARGS))" != "" ] && echo "--rpc-url $(SEPOLIA_RPC_URL)" || echo "--rpc-url http://localhost:8545" )
RPC_AND_KEY := $$( [ "$(findstring --network sepolia,$(ARGS))" != "" ] && echo "--rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY)" || echo "--rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY)" )

.PHONY: deployFactory deployBounty \
	factoryPerformSingle factoryCheckUpkeep factoryMapUsername \
	bountyCreateAndFund

deployFactory:
	forge script script/DeployGitbountyFactory.s.sol:DeployGitbountyFactory $(NETWORK_ARGS)

# Optional defaults (env wins because of ?=)
BOUNTY_VALUE ?= 1000000000000000 # 0.001 ETH in wei

deployBounty:
	forge script script/CreateBountyFromFactory.s.sol:CreateBountyFromFactory $(NETWORK_ARGS)

# ---------- Interactions ----------

factoryPerformSingle:
	@DATA=$$(cast abi-encode "address[]" "[$(BOUNTY_ADDRESS)]"); \
	cast send $(FACTORY_ADDRESS) "performUpkeep(bytes)" $$DATA \
		$(RPC_AND_KEY) \
		--gas-limit 2000000 -vvvv

factoryCheckUpkeep:
	cast call $(FACTORY_ADDRESS) "checkUpkeep(bytes)(bool,bytes)" 0x \
		$(RPC_ONLY)

USERNAME ?=
factoryMapUsername:
	cast send $(FACTORY_ADDRESS) "mapGithubUsernameToAddress(string)" "$(USERNAME)" \
		$(RPC_AND_KEY) \
		--gas-limit 500000 -vvvv

OWNER ?=
REPO ?=
ISSUE ?=

bountyCreateAndFund:
	cast send $(BOUNTY_ADDRESS) "createAndFundBounty(string,string,string)" "$(OWNER)" "$(REPO)" "$(ISSUE)" \
		--value $(BOUNTY_VALUE) \
		$(RPC_AND_KEY) \
		--gas-limit 1000000 -vvvv
