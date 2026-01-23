## Documentation

**GitBounty is a Web3 app which allows GitHub users to create bounties on their Github issues.**

It uses smart contracts to automatically monitor the Github API with Chainlink Functions and Chainlink Automation.

Run the frontend in this repo to interface with the contract and create bounties of your Github issues.

1. Developers register their github username and wallet address in the registry.

2. Then, given an existing Github repo, with open issues available, a user can create a bounty on an issue by entering the repo owner, the repo name, and the issue number, and funding it with ETH. The bounty can be funded multiple times, by multiple users.

3. To earn the bounty, a developer can use a github account in the registry to create a branched PR which merges back into master, and references the bounty's issue number.

4. Once the branched PR has been merged into the main branch, the Bounty will automatically pay out to the author of the PR.

---

## Project Background

Open source collaboration is the backbone of modern software, but financial incentives can be misaligned or entirely absent. Maintainers struggle to get help on critical issues, contributors lack clear pathways to compensation, and sponsors have little transparency into what their funds achieve.

**GitBounty** solves this by turning GitHub issues into open, permissionless bounties. It creates a decentralised incentive layer for software collaboration.

It is a working implementation of a generalised protocol I designed for incentivising work, called the _Universal Bounty Protocol (UBP)_. It follows a four-stage structure:

request → work → verification → approval

**GitBounty** applies this model directly to GitHub development workflows:

- **Request**: The GitHub issue title and description serve as a formal request to modify a project’s code to meet specific criteria.
- **Work**: Developers respond by submitting code changes (e.g., pull requests) that aim to satisfy the request.
- **Verification**: Reviewers assess whether the submitted work meets the outlined requirements.
- **Approval**: A final decision-making process (e.g., PR review) determines whether the contributor is rewarded.

This structure allows open-source projects to define and enforce their own contribution standards, while enabling automated and transparent financial incentives on-chain.

### Ideas for the future

Looking forward, each stage of the UBP could be augmented or fully automated by AI. From generating work proposals to writing code and verifying correctness, this could create a powerful new paradigm: a decentralised, competitive market of work for AI software developer agents.

Bounty contracts could be ownable, tradable, and packaged into a new class of on-chain assets - earning fees for their holders and effectively financialising the online gig economy of software development.

---

## Overview of files

#### offchain/

gen_offchain_secrets.js

- Generates offchain-secrets.json file containing encrypted env-enc environment variable secret

encrypt_secrets_url.js

- Encrypts offchain-secrets.json amazon web bucket url, sends to chainlink DONS and exports ID and slot info as a .json 'secrets_slot_and_id.json' or 'config.json'

simulate_request.js

- Tests the Chainlink Functions request to GitHub API

#### src/

Gitbounty.sol

- Solidity contract to register username/address, hold bounty currency, and perform Chainlink Functions requests to the GitHub API

#### script/

DeployGitbounty.s.sol

- Deploys Gitbounty.sol using config from HelperConfig.s.sol

HelperConfig.s.sol

- Provides DeployGitbounty.s.sol with config appropriate to blockchain network being deployed on. Reads the secrets_slot_and_id.json/config.json

#### test/

GitbountyTest.t.sol

- Tests deployment and methods of GitBounty.sol (excluding Chainlink Functions request)

---

## Setup

#### Install

1. Update dependencies:

   `git submodule update --init --recursive`

2. Build:

   `forge clean`

   `forge build`

3. Navigate to offchain/

   `cd offchain`

4. Install the npm dependencies

   `brew install python@3.11`

   `PYTHON=/usr/local/bin/python3.11 npm install`

#### Chainlink Services

_Chainlink Functions_

1. Create a chainlink functions subscription and top it up with link token: https://functions.chain.link/sepolia/
2. Get the subscription ID and store it in config/eth-sepolia.json

_Chainlink Automation_

1. Create a chainlink automation upkeep and top it up with link token: https://automation.chain.link/
2. Get the subscription ID and store it in config/eth-sepolia.json

#### Environment variables

_.env Unencrypted Variables (config settings, public addresses)_

1. Navigate to project root
2. Rename .env.example to .env, and set the variables.
3. Any time .env is edited, save .env and run this to load it into the terminal session's context:

   `source .env`

_.env.enc Encrypted Variables (api secrets, private keys)_

1. Navigate to offchain/

   `cd offchain`

2. Set the env-enc password for the first time (or enter an existing password, if env.enc already exists)

   `npx env-enc set-pw`

3. Set the following keys/values as encrypted local variables

   `npx env-enc set`

```
GITHUB_SECRET -- set now
GITHUB_SECRET_URL -- set later
PRIVATE_KEY -- set now
SEPOLIA_RPC_URL -- set now
MAINNET_RPC_URL -- set now
ETHERSCAN_API_KEY -- set now
```

#### Offchain secrets setup

1. Navigate to offchain/

   `cd offchain`

2. Run gen_offchain_secrets.js

   `node gen_offchain_secrets.js`

- Generates offchain-secrets.json file containing encrypted GITHUB_SECRET from env-enc

3. Upload offchain-secrets.json to Amazon Web Bucket and copy the url
4. Set the Amazon Web Bucket URL as an encrypted local variable

   `npx env-enc set`

```
GITHUB_SECRET_URL
```

5. Run encrypt_secrets_url.js

   `node encrypt_secrets_url.js`

- Encrypts offchain-secrets.json amazon web bucket url and generates file 'encrypted-secrets-urls.sepolia.json' to be used by Deploy script later

6. Run simulate_request.js (optional)

   `node simulate_request.js`

- Tests the Chainlink Functions request to GitHub API

---

## Reference

.env
↓
gen_offchain_secrets.js
↓
offchain-secrets.json (encrypted)
↓
encrypt_secrets_url.js
↓
encrypted-secrets-urls.network.json
↓
HelperConfig.s.sol
↓
DeployGitbounty.s.sol
↓
Gitbounty.sol
↓
Chainlink DON
↓
GitHub API
↓
fulfillRequest()

.env
↓
gen_offchain_secrets.js
↓
offchain-secrets.json (encrypted)
↓
encrypt_secrets_url.js
↓
encrypted-secrets-urls.network.json
↓
HelperConfig.s.sol
↓
DeployGitbountyFactory.s.sol
↓
GitbountyFactory.sol
↓
Gitbounty.sol
↓
Chainlink DON
↓
GitHub API
↓
fulfillRequest()

Env-enc reference:

npx env-enc set-pw

- if no .env.enc exists, sets the password and creates new file
- if .env.enc exists, inputs the password to allow edits

npx env-enc view

- decrypts and lists all keys and values

npx env-enc set

- prompts for key and value input

npx env-enc remove <name>

- Removes a variable from the encrypted environment variable file

npx env-enc remove-all

- Deletes the encrypted environment variable file

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

Gitbounty.sol State Machine:
Open
Funded
...

---

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

Live Testnet Tests

Test manual run from start to finish (not automation)

0. Create Functions Subscription at https://functions.chain.link/sepolia/
1. `make deploy ARGS="--network sepolia"`
   1a. Get contract address from output
2. Add contract address as a consumer of Functions Subscription
3. Update .env CONTRACT_ADDRESS, run source .env
4. `make mapGithubUsername`
5. `make createAndFundBounty`
6. `make performUpkeep`

Test Create and Delete bounty

1. `make createAndFundBounty`
2. `make deleteAndRefundBounty`

Test start to finish (with automation)

1. Register new custom logic upkeep, using contract address https://automation.chain.link/new-custom-logic
2. `make mapGithubUsername`
3. `make createAndFundBounty`
4. let functions / upkeep auto-run by chainlink automation.

### Deploy

Navigate to the project root.

Check that the makefile can resolve secrets from .env.enc

`make checkSecrets`

Check that the makefile can resolve config args from .env

`make checkConfig`

Check that we are using Sepolia (Expected ID: 11155111)

`make checkNetwork`

Deploy the GitBounty implementation (to be cloned by Factory later)

`make deployBountyImpl`

Set the GitBounty implementation's address as GITBOUNTY_IMPL in .env

- Add to .env: `GITBOUNTY_IMPL=_______` <-- address

Reload .env variables into the current working session

`source .env`

Deploy the GitBountyFactory contract

`make deployFactory`

Set the GitBountyFactory's address as FACTORY_ADDRESS in .env

- Add to .env: `FACTORY_ADDRESS=_______` <-- address

Reload .env variables into the current working session

`source .env`

Add the GitBountyFactory's address as a consumer of your Chainlink Functions subscription: https://functions.chain.link/sepolia/____

Set your GitBounty arguments in .env (value 1000000000000000 = 0.001 eth)

```
REPO_OWNER=
REPO=
ISSUE_NUMBER=
BOUNTY_VALUE=
```

`source .env`

Deploy a GitBounty contract from your GitBountyFactory contract

`deployBounty`

Manually call Functions request and payment

`make performUpkeep`

#### Claim a bounty

Map a github username / wallet address in the GitBountyFactory user registry:

`make factoryMapUsername USERNAME=_______`

Submit a branched PR to the bounty's GitHub repo, and wait for it to be merged into master, then Chainlink Automation can automatically trigger API check and payout, or run the API check and payout manually:

`make factoryPerformSingle`

#### Interactions

Check a github username / wallet address is already mapped

`make factoryCheckUsernameMap USERNAME=_______`

Print the current bounty’s configured GitHub args (repo owner, repo name, issue number) from the child contract.

`make bountyArgs BOUNTY_ADDRESS=0x...`

Check whether the bounty is in a “ready to be paid out” state (isBountyReady()).

`make checkBountyReady BOUNTY_ADDRESS=0x...`

Simulate Chainlink Automation’s checkUpkeep against the Factory (returns (bool upkeepNeeded, bytes performData)).

`make factoryCheckUpkeep`

Manually trigger performUpkeep on the Factory for one bounty (encodes the single address into the bytes payload).

`make factoryPerformSingle BOUNTY_ADDRESS=0x...`

Manually trigger performUpkeep on the Factory for multiple bounties in one transaction.
Provide a comma-separated list of bounty addresses.

`make factoryPerformMany BOUNTY_ADDRESS=0xA...,0xB...,0xC...`

Check whether a specific bounty is eligible for automation processing (isEligible(address)).

`make factoryBountyIsEligible BOUNTY_ADDRESS=0x...`

Get a full eligibility breakdown for a bounty (registered/open/inFlight/timeOk/childReady/nextAttemptAt) via eligibilityBreakdown(...).

`make factoryEligibilityBreakdown BOUNTY_ADDRESS=0x...`

Resolve and print the event signatures for all logs in a transaction receipt (uses the Factory ABI + topic0 hashes).
Useful for quickly identifying which events fired.

`make checkEvent EVENT=0x...`

Confirm which Factory address a bounty is wired to (factory() on the child).

`make checkBountyHasFactory BOUNTY_ADDRESS=0x...`

Update Factory automation tuning parameters:

RETRY_INTERVAL — cooldown between attempts per bounty (seconds)

MAX_SCAN — max bounties scanned per upkeep

MAX_PERFORM — max bounties processed per upkeep

`make setAutomationParams RETRY_INTERVAL=300 MAX_SCAN=50 MAX_PERFORM=2`

Create and fund a bounty on an existing deployed child contract, sending BOUNTY_VALUE as msg.value and setting the GitHub issue coordinates.

`make createBountyExisting BOUNTY_ADDRESS=0x... REPO_OWNER=... REPO=... ISSUE_NUMBER=... BOUNTY_VALUE=...`

---

### Unsorted Notes

Clone the official chainlink functions examples repo in another directory.

- env-enc tool
- secrets encryption script
  then follow the steps to upload the encrypted secrets file (created using the script mentioned above) to amazon web bucket.
  Use the gen-offchain-secrets.js script from Chainlink's smart-contract-examples repo (under /functions-examples/...)
  This script can be customised to generate a json file for particular secrets you have in your env-enc file.
  For example, the default in that script is COINMARKETCAP_API_KEY - the script will grab out the value from env-enc file by this key and generate the json with it.

Then upload the json file to Amazon web bucket.
https://docs.aws.amazon.com/AmazonS3/latest/userguide/GetStartedWithS3.html#creating-bucket
https://docs.aws.amazon.com/AmazonS3/latest/userguide/uploading-an-object-bucket.html

link to uploaded json bucket

link direct to json file

link to uploader

Before chainlink offchain secrets tutorial:
node -v
v18.16.0

After:
node -v
v20 ?

TO TEST LOCAL SIMULATION AND LIVE CONTRACT USING GITBOUNTY SCRIPT AND GITHUB SECRET:
cd /Users/josef/Projects/Courses/chainlink-smart-contract-examples/smart-contract-examples/functions-examples
Create the \_gitbounty versions of request.js, source.js, gen_offchain_secrets.js -- done
generate new github secret on github
store new github secret in enc-env as GITHUB_SECRET
run gen_offchain_secrets_gitbounty.js - gets GITHUB_SECRET from your local env-enc, creates offchain-secrets.json
$ node /Users/josef/Projects/Courses/chainlink-smart-contract-examples/smart-contract-examples/functions-examples/examples/7-use-secrets-url/gen-offchain-secrets_gitbounty.js
follow instructions to upload the newly generated offchain-secrets json to amazon web bucket, get link
use link to update request_gitbounty.js script secretsUrls variable, so running the request script passes the url to the script being run in both local sim and on CL functions oracles
check if correct values returned by script

- note it creates it with the key 'apiKey', so in your CL functions script, the secret will be imported via key 'apiKey'
  offchain-secrets.json: upload this to an amazon web bucket via online instructions
  $ node examples/7-use-secrets-url/request_gitbounty.js
- run this, and it will simulate your request, then actually make the request.

#### Just completed

- Tested on sepolia creating 2 bounties via factory, changing maxPerform to 2, and manually performing upkeep on the two in one call, triggering two functions requests, which both suceeded and paid out from the bounty contracts successfully.

#### To do

- Document setup and deployment via offchain/, makefile commands and .env with source .env, give recommended .env values such as warnings disabled, variables I have now but with generated ones redacted for default generic .env to be put in readme.

- When bounty is completed, paid and reset/cleared, have it flagged as empty, so if a web user or makefile user wants to create a new bounty, it reuses an existing deployed empty contract owned by that user, instead of deploying a whole new bounty contract.

- Make foundry tests of factory and child

- Check if all variables that can be set/reset by creating or completing a bounty can be checked via getter. So we are able to test if everything gets reset.
- Check how bounty behaves with certain arguments set and some not etc. Such as repo set, but not repo_owner, or bounty value = 0
- implement User funding of Automation and Functions

  - only attempt bounties that have prepaid credits and use those credits as your internal economic gate then you (as operator) fund the Automation upkeep + Functions sub globally (LINK) and you set your fees so that overall you don’t lose money

- Add automation toggle helper to factory (to optionally turn off automation)

- Live testnet test routines:

  - Toggle off automation
  - Deploy 1 bounty
  - manually perform upkeep
  - Check fulfilment / payment / variable reset

  - Toggle off automation
  - Set maxPerform to 3
  - Deploy 3 identical bounties
  - manually perform upkeep on the 3 bounties
  - Check fulfilment / payment / variable reset

  - Toggle off automation
  - Set maxPerform to 2
  - Deploy 3 different bounties (1 complete, 2 incomplete)
  - get 2 'selected' bounties from checkUpKeep
  - manually perform upkeep on the 2 selected bounties
  - Check fulfilment / payment / variable reset (1 succeed, 1 fail)
  - immediately after, get 1 'selected' bounties from checkUpKeep (the other 2 have not had enough time passed)
  - manually perform upkeep on the 1 selected bounties
  - Check fulfilment / payment / variable reset (1 fail)
  - wait 5 min and complete the 2nd bounty in github
  - get 2 'selected' bounties from checkUpKeep
  - manually perform upkeep on the 2 selected bounties
  - Check fulfilment / payment / variable reset (1 succeed, 1 fail)
  - wait 5 min and complete the 3rd bounty in github
  - get 1 'selected' bounties from checkUpKeep
  - manually perform upkeep on the 1 selected bounties
  - Check fulfilment / payment / variable reset (1 succeed)

  - Leave on / Toggle on automation
  - repeat above, but allow automation to run upkeeps

- Make UI tracking of events and arrays, variables, bounty reward sending visualisation
- Make UI statistics about bounty variables
- Make UI to create and interact with bounties and watch their information live

Mapping identity is wide open → easy to “steal” a username mapping
mapGithubUsernameToAddress(string username) is open and permanently maps a username to the first caller.
That means anyone can front-run or preemptively map "some-winner" to their address before the real contributor maps it. Your “winner” is whatever the oracle returns (GitHub username), so if someone squats that username mapping, they get paid.
GitHub challenge (best for GitBounty):
User signs an EIP-191 message with their wallet.
They publish the signature (or a nonce) in a GitHub comment / gist / profile field.
Your Functions script verifies that the signature appears in GitHub under that username, and returns the wallet address directly (or returns username+signature that your contract verifies).
Then you don’t need open mapping at all.

Reentrancy surfaces (payout + refunds)
You do external ETH sends in three places:
withdrawBountyFund() → msg.sender.call{value: amount}("")
deleteAndRefundBounty() → loop of funder.call{value: amount}("")
fulfillRequest() payout → winner.call{value: amount}("")
You’re mostly doing Checks-Effects-Interactions (you zero contribution before the call; you clear/transition state before request, etc.). But you still have a few hazards:
deleteAndRefundBounty() is looping through funders and calling out; if any funder is a contract with a reverting fallback, the whole refund reverts → owner can get “stuck” unable to delete/refund.
Reentrancy into other functions is possible during payout/refunds (especially because mapGithubUsernameToAddress and fundBounty are open).
Fix pattern (strongly recommended):
Add a simple reentrancy guard (nonReentrant) to the three ETH-sending functions.
Move to a pull-payments model for mass refunds: record refundable balances and let users withdraw individually (no looped calls).
Minimal change: import OpenZeppelin ReentrancyGuard and add nonReentrant.
Better change: remove the for-loop refund and expose withdrawBountyFund() + ownerCancel() which only resets criteria and leaves withdrawals to users.

Theory:

- Your PR approver list is a multisig for releasing bounty funds
