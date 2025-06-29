## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

Live Testnet Tests

Test manual run from start to finish (not automation)

0. Create Functions Subscription at https://functions.chain.link/sepolia/
1. make deploy ARGS="--network sepolia"
   1a. Get contract address from output
2. Add contract address as a consumer of Functions Subscription
3. Update .env CONTRACT_ADDRESS, run source .env
4. make mapGithubUsername
5. make createAndFundBounty
6. make performUpkeep

Test Create and Delete bounty

1. make createAndFundBounty
2. make deleteAndRefundBounty

Test start to finish (with automation)

1. Register new custom logic upkeep, using contract address https://automation.chain.link/new-custom-logic
2. make mapGithubUsername
3. make createAndFundBounty
4. let functions / upkeep auto-run by chainlink automation.

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

forge test --mt testCanRequestAndFulfill -vvv --fork-url $SEPOLIA_RPC_URL

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

`make deploy ARGS="--network sepolia"`

Confirmed working source inputs (etherscan):
return Functions.encodeString("true");
stores "true" string as hex in s_lastResponse
terminal: cast --to-ascii 0x74727565
= true

Sent via cast (makefile) - etherscan removes quotes and messes with strings (except "true" or "false" because those happen to also be booleans when stripped)
return Functions.encodeString("hello");

^ above make command allows any source script to be passed in from script.js

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
