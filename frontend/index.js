import { ethers } from "./ethers-6.7.esm.min.js"
import { abi, contractAddress, chainIdMap } from "./constants.js"

let currentAccount = null;
let provider;
let signer;
let contract;

const connectButton = document.getElementById("connectButton")
const mapUsernameButton = document.getElementById("mapUsernameButton")
const createBountyButton = document.getElementById("createBountyButton")
const refreshStatusButton = document.getElementById("refreshStatusButton")
const resetContractButton = document.getElementById("resetContractButton")
const fundBountyButton = document.getElementById("fundBountyButton")

const githubUsernameInput = document.getElementById("githubUsername");
const repoOwnerInput = document.getElementById("repoOwner");
const repoNameInput = document.getElementById("repoName");
const issueNumberInput = document.getElementById("issueNumber");
const ethAmountInput = document.getElementById("ethAmount");
const ethAmountExtraInput = document.getElementById("ethAmountExtra");

connectButton.onclick = connect

function updateButtons(status) {
  [mapUsernameButton, createBountyButton, refreshStatusButton, resetContractButton, fundBountyButton].forEach(btn => {
    btn.disabled = status;
  });

  [githubUsernameInput, repoOwnerInput, repoNameInput, issueNumberInput, ethAmountInput, ethAmountExtraInput].forEach(input => {
    input.disabled = status;
  });
}

function pressButton(button, status) {
  button.classList.toggle("pressed", status)
}

updateButtons(true)
connectButton.innerHTML = "Connect Wallet"

if (window.ethereum) {
  window.ethereum.on("accountsChanged", async (accounts) => {
    const isConnected = connectButton.classList.contains("pressed");

    if (!isConnected) return; // Do nothing unless already connected

    if (accounts.length === 0) {
      // Wallet disconnected
      currentAccount = null;
      pressButton(connectButton, false);
      connectButton.innerHTML = "Connect Wallet";
      updateButtons(true);
    } else {
      // Wallet account changed while connected
      currentAccount = accounts[0];
      const chainId = await ethereum.request({ method: "eth_chainId" });
      const networkName = chainIdMap[chainId] || "Unknown Network";
      const short = currentAccount.slice(0, 7) + "..." + currentAccount.slice(-5);
      connectButton.innerHTML = `Connected: ${short} on ${networkName}`;
      provider = new ethers.BrowserProvider(window.ethereum);
      signer = await provider.getSigner();
      contract = new ethers.Contract(contractAddress, abi, signer);
    }
  });
}

async function connect() {
  if (typeof window.ethereum !== "undefined") {
    if (!currentAccount) {
      try {
        await ethereum.request({ method: "eth_requestAccounts" })
        const accounts = await ethereum.request({ method: "eth_accounts" })
        currentAccount = accounts[0]
        const chainId = await ethereum.request({ method: "eth_chainId" })
        const networkName = chainIdMap[chainId] || "Unknown Network"
        const short = currentAccount.slice(0, 7) + "..." + currentAccount.slice(-5)
        pressButton(connectButton, true)
        connectButton.innerHTML = `Connected: ${short} on ${networkName}`
        provider = new ethers.BrowserProvider(window.ethereum)
        signer = await provider.getSigner()
        contract = new ethers.Contract(contractAddress, abi, signer)
        updateButtons(false)
      } catch (error) {
        console.error(error)
      }
    } else {
      currentAccount = null
      pressButton(connectButton, false)
      connectButton.innerHTML = "Connect Wallet"
      updateButtons(true)
    }
  } else {
    connectButton.innerHTML = "Please install MetaMask"
  }
}


mapUsernameButton.onclick = async () => {
  const username = document.getElementById("githubUsername").value
  try {
    const tx = await contract.mapGithubUsernameToAddress(username)
    await tx.wait()
    alert("GitHub username mapped!")
  } catch (err) {
    console.error("Mapping error:", err)
  }
}

resetContractButton.onclick = async () => {
  try {
    const tx = await contract.resetContract()
    await tx.wait()
    alert("Contract reset!")
  } catch (err) {
    console.error("Error resetting contract", err)
  }
}

createBountyButton.onclick = async () => {
  const repoOwner = document.getElementById("repoOwner").value
  const repoName = document.getElementById("repoName").value
  const issueNumber = document.getElementById("issueNumber").value
  const amount = document.getElementById("ethAmount").value
  try {
    const tx = await contract.createAndFundBounty(repoOwner, repoName, issueNumber, {
      value: ethers.parseEther(amount),
    })
    await tx.wait()
    alert("Bounty funded!")
  } catch (err) {
    console.error("Bounty error:", err)
  }
}

fundBountyButton.onclick = async () => {
  const amount = document.getElementById("ethAmountExtra").value
  try {
    const tx = await contract.fundBounty({
      value: ethers.parseEther(amount)
    })
    await tx.wait()
    alert("Bounty funded!")
  } catch (err) {
    console.error("Bounty error:", err)
  }
}

let refreshIntervalId = null;

refreshStatusButton.onclick = async () => {
  try {
    const intervalSeconds = 5; // seconds
    const intervalMs = intervalSeconds * 1000; // milliseconds

    // Clear existing interval if one exists
    if (refreshIntervalId) {
      clearInterval(refreshIntervalId);
    }

    pressButton(refreshStatusButton, true)
    refreshStatusButton.innerHTML = `Refreshing every ${intervalSeconds} seconds`;

    // Initial fetch
    await refreshStatus();
    // Set repeating refresh loop
    refreshIntervalId = setInterval(refreshStatus, intervalMs);
    console.log(`Started auto-refresh every ${intervalSeconds} seconds`);
  } catch (err) {
      console.error("Auto-refresh setup error:", err);
  }
};

async function refreshStatus() {
  try {
    console.log(`Refreshing`);
    const [
      status,
      last_winnerUser,
      last_repoOwner,
      last_repo,
      last_issueNumber,
      last_claimTime,
      last_BountyAmount,
      repoOwner,
      repo,
      issueNumber,
      bountyAmount
    ] = await Promise.all([
      contract.getRaffleState(),
      contract.lastWinnerUser(),
      contract.last_repo_owner(),
      contract.last_repo(),
      contract.last_issueNumber(),
      contract.getLastTimeStamp(),
      contract.last_BountyAmount(),
      contract.getRepoOwner(),
      contract.getRepo(),
      contract.getIssueNumber(),
      contract.getBalance()
    ]);

    const stateMap = ["BASE", "EMPTY", "READY", "CALCULATING", "PAID"];
    const currentStatus = stateMap[status];
    document.getElementById("status").textContent = `Status: ${currentStatus}`;

    const idsPAID = [
      "lastClaimer",
      "lastBountyRepo",
      "lastBountyIssue",
      "lastClaimer",
      "lastClaimTime",
      "lastBountyAmount"
    ];

    for (const id of idsPAID) {
      const el = document.getElementById(id);
      if(currentStatus == "PAID"){
        el.style.display = "block";
      } else {
        el.style.display = "none";
      }
    }

    if(currentStatus == "PAID"){
      document.getElementById("lastClaimer").textContent = `Last Claimer: ${last_winnerUser}`;
      document.getElementById("lastBountyRepo").textContent = `Last Bounty repo: ${last_repoOwner}/${last_repo}`;
      document.getElementById("lastBountyIssue").textContent = `Last Bounty issue: ${last_issueNumber}`;
      const convertedLastTime = (new Date(Number(last_claimTime) * 1000)).toLocaleString(); // convert seconds to ms
      document.getElementById("lastClaimer").textContent = `Last Claimer: ${last_winnerUser}`;
      document.getElementById("lastClaimTime").textContent = `Last Claim Time: ${convertedLastTime}`;
      const readableAmountClaimed = ethers.formatEther(last_BountyAmount);
      document.getElementById("lastBountyAmount").textContent = `Last Amount Claimed: ${readableAmountClaimed} ether`;
    }

    const idsREADY = [
      "bountyRepo",
      "bountyIssue",
      "bountyAmount"
    ];

    for (const id of idsREADY) {
      const el = document.getElementById(id);
      if(currentStatus == "READY" || currentStatus == "CALCULATING"){
        el.style.display = "block";
      } else {
        el.style.display = "none";
      }
    }

    if(currentStatus == "READY" || currentStatus == "CALCULATING"){
      document.getElementById("bountyRepo").textContent = `Bounty repo: ${repoOwner}/${repo}`;
      document.getElementById("bountyIssue").textContent = `Bounty issue: ${issueNumber}`;
      const readableAmount = ethers.formatEther(bountyAmount);
      document.getElementById("bountyAmount").textContent = `Amount: ${readableAmount} ether`;
    }

  } catch (err) {
    console.error("Status fetch error:", err);
  }
};
