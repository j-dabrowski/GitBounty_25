## Documentation

**GitBounty is a Web3 app which allows GitHub users to create bounties on their Github issues.**

It does this by using smart contracts to automatically monitor the Github API with Chainlink Functions and Chainlink Automation.

Contract live on eth-sepolia testnet:
https://sepolia.etherscan.io/address/0x3bA67d986720Dd6fA69871e7113fbC595345B21c

Run the frontend in this repo to interface with the contract and create bounties of your Github issues.

### General Usage

Developers to register their github username and wallet address in the registry.

Then, given an existing Github repo, with open issues available, a user can create a bounty on an issue by entering the details and funding it with ETH. The bounty can be funded multiple times, by multiple users.

Once a branched PR (linked to the bounty's issue) has been merged successfully into the main branch, the Bounty will automatically pay out to the author of the PR.

---

## Project Background

Open source collaboration is the backbone of modern software, but financial incentives are often misaligned or entirely absent. Maintainers struggle to get help on critical issues, contributors lack clear pathways to compensation, and sponsors have little transparency into what their funds achieve.

**GitBounty** solves this by turning GitHub issues into open, permissionless bounties. It creates a decentralised incentive layer for software collaboration.

It is a working implementation of a generalised protocol I designed for incentivising work, called the _Universal Bounty Protocol (UBP)_. It follows a four-stage structure:

request → work → verification → approval

**GitBounty** applies this model directly to GitHub development workflows:

- **Request**: The GitHub issue title and description serve as a formal request to modify a project’s code to meet specific criteria.
- **Work**: Developers respond by submitting code changes (e.g., pull requests) that aim to satisfy the request.
- **Verification**: Reviewers assess whether the submitted work meets the outlined requirements.
- **Approval**: A final decision-making process (e.g., merge or review consensus) determines whether the contributor is rewarded.

This structure allows open-source projects to define and enforce their own contribution standards, while enabling automated and transparent financial incentives on-chain.

With **GitBounty**, you can:

💸 Attach bounties to issues
Let anyone fund tasks they care about, not just repo maintainers.

🔍 Automate contribution verification
Uses smart contracts and Chainlink Functions to monitor the GitHub API and detect issue resolution or pull request merges.

⛓ Trustless payouts
Automatically sends rewards to contributors once work is verified, reducing friction and disputes.

🤝 Incentivise outside help
Attract contributors beyond your core team by providing clear, visible rewards.

🛡 Reduce grant misuse
Sponsors and DAOs can fund public goods with greater assurance that funds are tied to completed work.

Whether you're a solo dev maintaining a side project, a DAO funding critical infrastructure, or a contributor seeking paid opportunities, **GitBounty** creates a new incentive structure that rewards open source work transparently and automatically.

## What's next?

Looking forward, each stage of the UBP could be augmented or fully automated by AI. From generating work proposals to writing code and verifying correctness, this could create a powerful new paradigm: a decentralised, competitive market of work for AI software developer agents.

Bounty contracts could be ownable, tradable, and packaged into a new class of on-chain assets - earning fees for their holders and effectively financialising the online gig economy of software development.

## Technical Challenges

One major limitation was the lack of secure secret management within Chainlink Automation. Chainlink Functions requires a GitHub token to query the API, but Automation can't store or inject secrets directly.

To work around this, I embedded a read-only GitHub token with narrow permissions directly into the on-chain Functions JavaScript script. This allowed for full end-to-end automation without central servers or manual intervention, but at the cost of ideal security.

## Theoretical Design Challenges

While the Universal Bounty Protocol (UBP) aims to create a trust-minimised workflow, some stages, particularly approval, cannot be made fully trustless. The decision to merge a GitHub pull request remains subjective and human-driven.

To address this, GitBounty embraces flexible trust models by allowing each project to define its own PR approver structure. This could range from a single maintainer to a decentralised reviewer committee.

This led to a broader insight:

Many types of work can be formalised as proposal → work → verification → approval processes, each with different degrees of trust minimisation.

By clearly defining the trust boundaries and where discretion enters the process, users can better understand both the value and risk of each bounty.

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

```shell
`make deploy ARGS="--network sepolia"`
```

Register the contract address in a new Chainlink Automation Upkeep.

Register the contract address as a consumer of the Chainlink Functions subscription

### Offchain secrets

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
