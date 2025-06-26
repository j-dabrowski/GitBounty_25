-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

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
	@forge script script/DeployRaffleWithFunctions.s.sol:DeployRaffleWithFunctions $(NETWORK_ARGS)

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
  		--constructor-args 0x000000000000000000000000000000000000000000000000002386f26fc10000000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000009ddfaca8183c41ad55329bdeed9f6a8d53168b1b787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae0c8dfe9ddf94a354fd64655b3300814e4cb3a125fd21505a101055785b5bccee000000000000000000000000000000000000000000000000000000000007a120000000000000000000000000b83e47c2bc239b3bf370bc41e1459a34b41238d066756e2d657468657265756d2d7365706f6c69612d3100000000000000000000

sendRequestScript:
	@cast send 0x185471a23eEaE802fc8286752B2899163534e6F6 \
		"sendRequestWithSource(uint64,string,string[])" \
		5133 "$$(cat script.js)" '[]' \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--gas-limit 1000000

sendRequestScriptAndArgs:
	@cast send 0x185471a23eEaE802fc8286752B2899163534e6F6 \
		"sendRequestWithSource(uint64,string,string[])" \
		5133 "$$(cat script.js)" '["j-dabrowski", "Test_Repo_2025", "1"]' \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--gas-limit 1000000

createSubscription:
	@forge script script/Interactions.s.sol:CreateSubscription $(NETWORK_ARGS)

addConsumer:
	@forge script script/Interactions.s.sol:AddConsumer $(NETWORK_ARGS)

fundSubscription:
	@forge script script/Interactions.s.sol:FundSubscription $(NETWORK_ARGS)

