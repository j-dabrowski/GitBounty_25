-include .env
export

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

ARGS ?=

NETWORK ?= sepolia

ifeq ($(NETWORK),sepolia)
NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) \
                --private-key $(PRIVATE_KEY) \
                --broadcast \
                --verify \
                --etherscan-api-key $(ETHERSCAN_API_KEY) \
                -vvvv
RPC_ONLY := --rpc-url $(SEPOLIA_RPC_URL)
RPC_AND_KEY := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY)
else
NETWORK_ARGS := --rpc-url http://localhost:8545 \
                --private-key $(DEFAULT_ANVIL_KEY) \
                --broadcast
RPC_ONLY := --rpc-url http://localhost:8545
RPC_AND_KEY := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY)
endif

.PHONY: deployFactory deployBounty \
	factoryPerformSingle factoryCheckUpkeep factoryMapUsername \
	bountyCreateAndFund

# ---------- Deploy ----------

checkNetwork:
	@echo "RPC: $$(echo $(RPC_ONLY))"
	@cast chain-id $(RPC_ONLY)

deployBountyImpl:
	forge script script/DeployGitbountyImpl.s.sol:DeployGitbountyImpl $(NETWORK_ARGS)

deployFactory:
	forge script script/DeployGitbountyFactory.s.sol:DeployGitbountyFactory $(NETWORK_ARGS)

# Optional defaults (env wins because of ?=)
BOUNTY_VALUE ?= 1000000000000000 # 0.001 ETH in wei

deployBounty:
	forge script script/CreateBountyFromFactory.s.sol:CreateBountyFromFactory $(NETWORK_ARGS)

# ---------- Interactions ----------
USERNAME ?=
BOUNTY_ADDRESS ?=
# Usage: make factoryMapUsername USERNAME=your_github_username
factoryMapUsername:
	@if [ -z "$(USERNAME)" ]; then \
		echo "Error: USERNAME not set. Usage: make factoryMapUsername USERNAME=your_github_username"; \
		exit 1; \
	fi
	cast send $(FACTORY_ADDRESS) "mapGithubUsernameToAddress(string)" "$(USERNAME)" \
		$(RPC_AND_KEY) \
		--gas-limit 500000 -vvvv

factoryCheckUsernameMap:
	@if [ -z "$(USERNAME)" ]; then \
		echo "Error: USERNAME not set. Usage: make factoryCheckUsernameMap USERNAME=your_github_username"; \
		exit 1; \
	fi
	cast call $(FACTORY_ADDRESS) "getAddressFromUsername(string)" "$(USERNAME)" \
		$(RPC_ONLY)

bountyArgs:
	@if [ -z "$(BOUNTY_ADDRESS)" ]; then \
		echo "Error: BOUNTY_ADDRESS not set. Usage: make bountyArgs BOUNTY_ADDRESS=0x..."; \
		exit 1; \
	fi
	cast call $(BOUNTY_ADDRESS) "getArgs()(string,string,string)" $(RPC_ONLY)

checkBountyReady:
	cast call $(BOUNTY_ADDRESS) "isBountyReady()(bool)" $(RPC_ONLY)

factoryCheckUpkeep:
	cast call $(FACTORY_ADDRESS) "checkUpkeep(bytes)(bool,bytes)" 0x \
		$(RPC_ONLY)

factoryPerformSingle:
	@if [ -z "$(BOUNTY_ADDRESS)" ]; then \
		echo "Error: BOUNTY_ADDRESS not set"; \
		exit 1; \
	fi
	@DATA=$$(cast abi-encode "f(address[])" "[$(BOUNTY_ADDRESS)]"); \
	cast send $(FACTORY_ADDRESS) "performUpkeep(bytes)" $$DATA \
		$(RPC_AND_KEY) \
		--gas-limit 2000000 -vvvv

factoryPerformMany:
	@if [ -z "$(BOUNTY_ADDRESS)" ]; then \
		echo "Error: BOUNTY_ADDRESS not set (comma-separated)"; \
		exit 1; \
	fi
	@CLEAN=$$(echo "$(BOUNTY_ADDRESS)" | tr -d ' '); \
	ARR="[$$CLEAN]"; \
	echo "Performing upkeep for bounties: $$ARR"; \
	DATA=$$(cast abi-encode "f(address[])" "$$ARR"); \
	cast send $(FACTORY_ADDRESS) "performUpkeep(bytes)" $$DATA \
		$(RPC_AND_KEY) \
		--gas-limit 3000000 -vvvv

factoryBountyIsEligible:
	@if [ -z "$(BOUNTY_ADDRESS)" ]; then \
		echo "Error: BOUNTY_ADDRESS not set. Usage: make factoryBountyIsEligible BOUNTY_ADDRESS=0x..."; \
		exit 1; \
	fi
	cast call $(FACTORY_ADDRESS) \
		"isEligible(address)(bool)" \
		$(BOUNTY_ADDRESS) \
		$(RPC_ONLY)

factoryEligibilityBreakdown:
	@if [ -z "$(BOUNTY_ADDRESS)" ]; then \
		echo "Error: BOUNTY_ADDRESS not set. Usage: make factoryEligibilityBreakdown BOUNTY_ADDRESS=0x..."; \
		exit 1; \
	fi
	cast call $(FACTORY_ADDRESS) \
		"eligibilityBreakdown(address)(bool,bool,bool,bool,bool,uint256)" \
		$(BOUNTY_ADDRESS) \
		$(RPC_ONLY)

checkEvent:
	@if [ -z "$(EVENT)" ]; then \
		echo "Error: EVENT (tx hash) not set"; \
		exit 1; \
	fi
	@ABI=out/GitbountyFactory.sol/GitbountyFactory.json; \
	echo "Transaction:" $(EVENT); \
	echo "---------------------------"; \
	cast receipt $(EVENT) $(RPC_ONLY) --json \
	| jq -r '.logs | to_entries[] | "\(.key) \(.value.topics[0])"' \
	| while read -r IDX TOPIC0; do \
		echo "Log #$$IDX"; \
		echo "  Event signature hash: $$TOPIC0"; \
		SIG=$$(jq -r '.abi[] | select(.type=="event") | "\(.name)(\(.inputs|map(.type)|join(",")))"' $$ABI \
			| while IFS= read -r s; do \
				h=$$(cast keccak "$$s"); \
				if [ "$$h" = "$$TOPIC0" ]; then echo "$$s"; break; fi; \
			done); \
		if [ -z "$$SIG" ]; then \
			echo "  Resolved from ABI: <unknown event>"; \
		else \
			echo "  Resolved from ABI: $$SIG"; \
		fi; \
		echo ""; \
	done

checkBountyHasFactory:
	cast call $(BOUNTY_ADDRESS) "factory()(address)" $(RPC_ONLY)

# Usage: make setAutomationParams RETRY_INTERVAL=300 MAX_SCAN=50 MAX_PERFORM=2
setAutomationParams:
	@if [ -z "$(FACTORY_ADDRESS)" ]; then \
		echo "Error: FACTORY_ADDRESS not set"; exit 1; \
	fi
	@if [ -z "$(RETRY_INTERVAL)" ] || [ -z "$(MAX_SCAN)" ] || [ -z "$(MAX_PERFORM)" ]; then \
		echo "Error: RETRY_INTERVAL, MAX_SCAN, and MAX_PERFORM must be set"; exit 1; \
	fi
	cast send $(FACTORY_ADDRESS) \
		"setAutomationParams(uint256,uint256,uint256)" \
		$(RETRY_INTERVAL) $(MAX_SCAN) $(MAX_PERFORM) \
		$(RPC_ONLY) \
		--private-key $(PRIVATE_KEY)

OWNER ?=
REPO ?=
ISSUE ?=

createBountyExisting:
	cast send $(BOUNTY_ADDRESS) "createAndFundBounty(string,string,string)" "$(REPO_OWNER)" "$(REPO)" "$(ISSUE_NUMBER)" \
		--value $(BOUNTY_VALUE) \
		$(RPC_AND_KEY) \
		--gas-limit 1000000 -vvvv
