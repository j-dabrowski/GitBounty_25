-include .env
export

# ---------------- env-enc (installed in offchain/) ----------------
OFFCHAIN_DIR ?= offchain/
ENV_ENC_PATH ?= .env.enc

# Helper: read a variable from offchain/.env.enc using env-enc installed in offchain/node_modules
define envenc
cd $(OFFCHAIN_DIR) && node -e 'const envEnc=require("@chainlink/env-enc"); envEnc.config({path:"$(ENV_ENC_PATH)"}); process.stdout.write(process.env.$(1)||"")'
endef

# Get secrets from offchain/.env.enc (everything else stored in .env)
SEPOLIA_RPC_URL   := $(shell $(call envenc,SEPOLIA_RPC_URL))
MAINNET_RPC_URL   := $(shell $(call envenc,MAINNET_RPC_URL))
ETHERSCAN_API_KEY := $(shell $(call envenc,ETHERSCAN_API_KEY))
PRIVATE_KEY       := $(shell $(call envenc,PRIVATE_KEY))

# Default Anvil key (used for local testing)
DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Default network
NETWORK ?= sepolia

# Setup network args
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

# ---------- Phony ----------

.PHONY: deployFactory deployBounty \
	factoryPerformSingle factoryCheckUpkeep factoryMapUsername \
	bountyCreateAndFund

.PHONY: checkSecrets checkConfig

# ---------- Check Secrets ----------

# Check that env-enc secrets resolve (does NOT print secret values)
checkSecrets:
	@echo "Checking env-enc secrets..."
	@ok=1; \
	for v in GITHUB_SECRET GITHUB_SECRET_URL SEPOLIA_RPC_URL MAINNET_RPC_URL ETHERSCAN_API_KEY PRIVATE_KEY; do \
		val="$$(cd $(OFFCHAIN_DIR) && node -e 'const envEnc=require("@chainlink/env-enc"); envEnc.config({path:"$(ENV_ENC_PATH)"}); process.stdout.write(process.env["'$$v'"]||"")')"; \
		if [ -z "$$val" ]; then echo "FAIL: $$v is empty"; ok=0; fi; \
	done; \
	if [ "$$ok" -eq 1 ]; then echo "OK: env-enc secrets resolved"; else exit 1; fi

# Check that .env config resolves (prints values)
checkConfig:
	@echo "Checking .env config variables..."
	@echo "--------------------------------"
	@echo "FOUNDRY_DISABLE_NIGHTLY_WARNING=$(FOUNDRY_DISABLE_NIGHTLY_WARNING)"
	@echo "GITBOUNTY_IMPL=$(GITBOUNTY_IMPL)"
	@echo "FACTORY_ADDRESS=$(FACTORY_ADDRESS)"
	@echo "BOUNTY_ADDRESS=$(BOUNTY_ADDRESS)"
	@echo "EVENT=$(EVENT)"
	@echo "REPO_OWNER=$(REPO_OWNER)"
	@echo "REPO=$(REPO)"
	@echo "ISSUE_NUMBER=$(ISSUE_NUMBER)"
	@echo "BOUNTY_VALUE=$(BOUNTY_VALUE)"
	@echo "--------------------------------"
	@missing=""; \
	for v in GITBOUNTY_IMPL FACTORY_ADDRESS BOUNTY_ADDRESS REPO_OWNER REPO ISSUE_NUMBER BOUNTY_VALUE; do \
		val="$$(eval echo \$$$${v})"; \
		if [ -z "$$val" ]; then missing="$$missing $$v"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "FAIL: missing or empty config values:"; \
		for m in $$missing; do echo "  - $$m"; done; \
		exit 1; \
	else \
		echo "OK: .env config resolved correctly"; \
	fi

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
