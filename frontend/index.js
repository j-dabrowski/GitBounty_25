import { ethers } from "./ethers-6.7.esm.min.js";
import { factoryAddress, factoryAbi, bountyAbi, chainIdMap } from "./constants.js";

let currentAccount = null;
let provider;
let signer;
let factory;

const factoryAddressEl = document.getElementById("factoryAddress");
const factoryBountyCountEl = document.getElementById("factoryBountyCount");
const bountiesListEl = document.getElementById("bountiesList");


const repoOwnerInput = document.getElementById("repoOwnerInput");
const repoInput = document.getElementById("repoInput");
const issueNumberInput = document.getElementById("issueNumberInput");
const fundingEthInput = document.getElementById("fundingEthInput");
const createBountyStatus = document.getElementById("createBountyStatus");

// Buttons
const connectButton = document.getElementById("connectButton");
const refreshButton = document.getElementById("refreshButton");
const createBountyButton = document.getElementById("createBountyButton");

// Button click events
connectButton.onclick = connect;
refreshButton.onclick = loadFactoryView;
createBountyButton.onclick = createBountyFromUI;


function pressButton(button, status) {
  button.classList.toggle("pressed", status);
}

function shortAddr(addr) {
  if (!addr) return "";
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

function fmtTs(ts) {
  const n = Number(ts);
  if (!n) return "—";
  return new Date(n * 1000).toLocaleString();
}

function setConnectedUI(chainId) {
  const networkName = chainIdMap[chainId] || "Unknown Network";
  const short = currentAccount.slice(0, 7) + "..." + currentAccount.slice(-5);
  pressButton(connectButton, true);
  connectButton.innerHTML = `Connected: ${short} on ${networkName}`;
  refreshButton.disabled = false;
  createBountyButton.disabled = false;
}

function setDisconnectedUI() {
  currentAccount = null;
  pressButton(connectButton, false);
  connectButton.innerHTML = "Connect Wallet";
  refreshButton.disabled = true;
  createBountyButton.disabled = true;
  if (createBountyStatus) createBountyStatus.textContent = "";
  factoryAddressEl.textContent = "Address: ...";
  factoryBountyCountEl.textContent = "Bounties: ...";
  bountiesListEl.innerHTML = "";
}

if (window.ethereum) {
  window.ethereum.on("accountsChanged", async (accounts) => {
    const isConnected = connectButton.classList.contains("pressed");
    if (!isConnected) return;

    if (!accounts || accounts.length === 0) {
      setDisconnectedUI();
      return;
    }

    currentAccount = accounts[0];
    const chainId = await ethereum.request({ method: "eth_chainId" });

    provider = new ethers.BrowserProvider(window.ethereum);
    signer = await provider.getSigner();
    factory = new ethers.Contract(factoryAddress, factoryAbi, signer);

    setConnectedUI(chainId);
    await loadFactoryView();
  });
}

async function connect() {
  if (typeof window.ethereum === "undefined") {
    connectButton.innerHTML = "Please install MetaMask";
    return;
  }

  // toggle disconnect
  if (currentAccount) {
    setDisconnectedUI();
    return;
  }

  try {
    await ethereum.request({ method: "eth_requestAccounts" });
    const accounts = await ethereum.request({ method: "eth_accounts" });
    currentAccount = accounts[0];

    const chainId = await ethereum.request({ method: "eth_chainId" });

    provider = new ethers.BrowserProvider(window.ethereum);
    signer = await provider.getSigner();
    factory = new ethers.Contract(factoryAddress, factoryAbi, signer);

    setConnectedUI(chainId);
    await loadFactoryView();
  } catch (err) {
    console.error(err);
  }
}

const STATE_LABELS = ["BASE", "EMPTY", "READY", "CALCULATING", "PAID"];


async function loadFactoryView() {
  if (!factory) return;

  factoryAddressEl.textContent = `Address: ${factoryAddress}`;
  bountiesListEl.innerHTML = `<div class="bounty-row"><em>Loading bounties…</em></div>`;

  let count = 0;
  try {
    // ✅ correct function name for your deployed factory
    count = Number(await factory.bountyCount());
  } catch (err) {
    console.error("Error reading bounty count:", err);
    factoryBountyCountEl.textContent = `Bounties: (error)`;
    bountiesListEl.innerHTML = `<div class="bounty-row"><em>Error reading bounty count.</em></div>`;
    return;
  }

  factoryBountyCountEl.textContent = `Bounties: ${count}`;

  if (count === 0) {
    bountiesListEl.innerHTML = `<div class="bounty-row"><em>No bounties found.</em></div>`;
    return;
  }

  const pageSize = 25;
  const all = [];

  for (let start = 0; start < count; start += pageSize) {
    const limit = Math.min(pageSize, count - start);
    const [addresses, nextAts] = await factory.getBounties(start, limit);

    for (let i = 0; i < addresses.length; i++) {
      all.push({
        index: start + i,
        address: addresses[i],
        nextAttemptAt: nextAts[i], // comes from factory.getBounties
      });
    }
  }

  bountiesListEl.innerHTML = "";

  const settled = await Promise.allSettled(
    all.map(async (entry) => {
      const bounty = new ethers.Contract(entry.address, bountyAbi, signer);
      const snap = await bounty.getBountySnapshot();
      return { entry, snap };
    })
  );

  for (let i = 0; i < settled.length; i++) {
    const s = settled[i];
    if (s.status === "fulfilled") {
      bountiesListEl.appendChild(renderBountyRow(s.value.entry, s.value.snap));
    } else {
      console.error("Snapshot failed for", all[i].address, s.reason);
      bountiesListEl.appendChild(renderBountyRow(all[i], null, s.reason));
    }
  }
}

function safeGet(res, i, fallbackKey) {
  try {
    if (res && typeof res.length === "number" && i < res.length) return res[i];
  } catch (_) {}
  // fallback to named key if it exists
  if (fallbackKey && res && res[fallbackKey] !== undefined) return res[fallbackKey];
  return undefined;
}

function safeFormatEther(v) {
  try {
    if (v === null || v === undefined) return "—";
    return ethers.formatEther(v);
  } catch {
    return "—";
  }
}

function renderBountyRow(base, snap, err) {
  const row = document.createElement("div");
  row.className = "bounty-row";

  if (err || !snap) {
    const msg = (err && (err.shortMessage || err.message)) || "Unknown error";
    row.innerHTML = `
      <div><strong>#${base.index}</strong> <span class="mono">${base.address}</span></div>
      <div>Next attempt (factory): ${fmtTs(base.nextAttemptAt)}</div>
      <div><em>Error loading snapshot</em></div>
      <div class="mono">${msg}</div>
    `;
    return row;
  }

  const r_state = safeGet(snap, 0, "r_state");
  const r_owner = safeGet(snap, 1, "r_owner");
  const r_repoOwner = safeGet(snap, 4, "r_repoOwner") ?? safeGet(snap, 4, "r_repo_owner");
  const r_repo = safeGet(snap, 5, "r_repo");
  const r_issueNumber = safeGet(snap, 6, "r_issueNumber");
  const r_totalFunding = safeGet(snap, 7, "r_totalFunding");
  const r_funderCount = safeGet(snap, 8, "r_funderCount");
  const r_lastWinner = safeGet(snap, 9, "r_lastWinner");
  const r_lastWinnerUser = safeGet(snap, 10, "r_lastWinnerUser");
  const r_lastBountyAmount = safeGet(snap, 11, "r_lastBountyAmount");

  const stateNum = Number(r_state);
  const stateLabel = STATE_LABELS[stateNum] ?? (r_state !== undefined ? String(r_state) : "—");
  const isPaid = stateLabel === "PAID"; // or: stateNum === 4

  const paidRows = isPaid
    ? `
      <div>Last winner: <span class="mono">${r_lastWinner || "—"}</span> (${r_lastWinnerUser || "—"})</div>
      <div>Last bounty amount: ${safeFormatEther(r_lastBountyAmount)} ETH</div>
    `
    : ""; // hidden when not PAID

  row.innerHTML = `
    <div><strong>#${base.index}</strong> <span class="mono">${base.address}</span> (${shortAddr(base.address)})</div>
    <div><strong>${r_repoOwner || "—"}/${r_repo || "—"} #${r_issueNumber || "—"}</strong></div>
    <div>Owner: <span class="mono">${r_owner || "—"}</span></div>
    <div>State: ${stateLabel}</div>
    <div>Funding: ${safeFormatEther(r_totalFunding)} ETH</div>
    <div>Funders: ${r_funderCount ?? "—"}</div>
    <div>Next update: ${fmtTs(base.nextAttemptAt)}</div>
    ${paidRows}
  `;

  return row;
}

// Create bounty UI


function setCreateStatus(msg) {
  if (!createBountyStatus) return;
  createBountyStatus.textContent = msg || "";
  createBountyStatus.title = msg || "";
}

function readInput(el) {
  return (el?.value || "").trim();
}

async function createBountyFromUI() {
  if (!factory || !signer) {
    setCreateStatus("Connect wallet first.");
    return;
  }

  const repoOwner = readInput(repoOwnerInput);
  const repo = readInput(repoInput);
  const issueNumber = readInput(issueNumberInput);
  const fundingEth = readInput(fundingEthInput);

  if (!repoOwner || !repo || !issueNumber) {
    setCreateStatus("Repo owner, repo, and issue # are required.");
    return;
  }
  if (!fundingEth) {
    setCreateStatus("Funding is required (must be > 0).");
    return;
  }

  let value;
  try {
    value = ethers.parseEther(fundingEth);
    if (value <= 0n) throw new Error("Funding must be > 0");
  } catch {
    setCreateStatus("Invalid funding amount.");
    return;
  }

  createBountyButton.disabled = true;
  setCreateStatus("Sending transaction…");

  try {
    const tx = await factory.createBounty(repoOwner, repo, issueNumber, { value });
    setCreateStatus(`Tx sent: ${tx.hash}`);

    const receipt = await tx.wait();
    let bountyAddr = null;

    // Parse BountyDeployed event if present
    for (const log of receipt.logs || []) {
      try {
        const parsed = factory.interface.parseLog(log);
        if (parsed?.name === "BountyDeployed") {
          bountyAddr = parsed.args?.bounty;
          break;
        }
      } catch (_) {}
    }

    setCreateStatus(bountyAddr ? `Created: ${bountyAddr}` : "Confirmed. Refreshing…");
    await loadFactoryView();
  } catch (err) {
    console.error(err);
    setCreateStatus((err && (err.shortMessage || err.message)) || "Transaction failed");
  } finally {
    createBountyButton.disabled = !currentAccount;
  }
}
