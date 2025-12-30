-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

CONTRACT_ADDRESS ?= 
FUNCTIONS_SUB_ID ?= 5708
GITHUB_OWNER ?= j-dabrowski
GITHUB_REPO ?= Test_Repo_2025
GITHUB_ISSUE ?= 2
BOUNTY_VALUE ?= 0.001ether

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.2.2 && forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 && forge install foundry-rs/forge-std@v1.8.2 && forge install transmissions11/solmate@v6 && forge install smartcontractkit/chainlink@v2.24.0

install_no_commit :; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install transmissions11/solmate@v6 --no-commit && forge install smartcontractkit/chainlink@v2.24.0 --no-commit


# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

# make deploy ARGS="--network sepolia"
deploy:
	@forge script script/DeployGitbounty.s.sol:DeployGitbounty $(NETWORK_ARGS)

# Add CONTRACT_ADDRESS to .env or run like: make verify CONTRACT_ADDRESS=0xYourContractAddress
### NOTE: this verification command does not work - because of the chainlink contract imports like:
### @chainlink/v1/../../../shared/access/ConfirmedOwnerWithProposal.sol
### etherscan can't resolve this path to 'canonical path' like 
### lib/chainlink/shared/access/ConfirmedOwnerWithProposal.sol
### Unless the Chainlink repo normalized its import paths using alias-style imports (@chainlink/shared/...), this issue will persist.
### Instead, Flatten your contract and upload manually to Etherscan
verify:
	@forge verify-contract \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		--chain sepolia \
		--watch \
		$(CONTRACT_ADDRESS) \
		src/RaffleWithFunctions.sol:RaffleWithFunctions

verifyWithConstructor:
	@forge verify-contract \
  		$(CONTRACT_ADDRESS) \
  		src/RaffleWithFunctions.sol:RaffleWithFunctions \
  		--etherscan-api-key $(ETHERSCAN_API_KEY) \
  		--chain sepolia \
		--watch \
  		--constructor-args 0x 
# replace constructor args with constructor bytecode

sendRequestScript:
	@cast send $(CONTRACT_ADDRESS) \
		"sendRequestWithSource(uint64,string,string[])" \
		$(FUNCTIONS_SUB_ID) "$$(cat script.js)" '[]' \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--gas-limit 1000000

sendRequestScriptAndArgs:
	@cast send $(CONTRACT_ADDRESS) \
		"sendRequestWithSource(uint64,string,string[])" \
		$(FUNCTIONS_SUB_ID) "$$(cat script.js)" '["$(GITHUB_OWNER)", "$(GITHUB_REPO)", "$(GITHUB_ISSUE)"]' \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--gas-limit 1000000

mapGithubUsername:
	@cast send $(CONTRACT_ADDRESS) \
	 "mapGithubUsernameToAddress(string)" $(GITHUB_OWNER) \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--gas-limit 1000000

mapGithubUsernameCustom:
	@read -p "GitHub Username: " USERNAME; \
	cast send $(CONTRACT_ADDRESS) \
	"mapGithubUsernameToAddress(string)" $$USERNAME \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--gas-limit 1000000

createAndFundBounty:
	@cast send $(CONTRACT_ADDRESS) \
	"createAndFundBounty(string,string,string)" \
		$(GITHUB_OWNER) $(GITHUB_REPO) $(GITHUB_ISSUE) \
		--value $(BOUNTY_VALUE) \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--gas-limit 1000000

createAndFundBountyCustom:
	@read -p "Repo Owner: " OWNER; \
	read -p "Repo Name: " REPO; \
	read -p "Issue Number: " ISSUE; \
	read -p "Value (e.g. 0.001ether): " VALUE; \
	cast send $(CONTRACT_ADDRESS) \
	"createAndFundBounty(string,string,string)" \
		$$OWNER $$REPO $$ISSUE \
		--value $$VALUE \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--gas-limit 1000000

deleteAndRefundBounty:
	@cast send $(CONTRACT_ADDRESS) \
	"deleteAndRefundBounty()" \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--gas-limit 1000000

performUpkeep:
	@cast send $(CONTRACT_ADDRESS) \
	"performUpkeep(bytes)" 0x \
		--private-key $(PRIVATE_KEY) \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--gas-limit 1000000 \
		--json

checkUpkeep:
	@cast call $(CONTRACT_ADDRESS) \
	"checkUpkeep(bytes)(bool,bytes)" 0x \
  	--rpc-url $(SEPOLIA_RPC_URL)

createSubscription:
	@forge script script/Interactions.s.sol:CreateSubscription $(NETWORK_ARGS)

addConsumer:
	@forge script script/Interactions.s.sol:AddConsumer $(NETWORK_ARGS)

fundSubscription:
	@forge script script/Interactions.s.sol:FundSubscription $(NETWORK_ARGS)

