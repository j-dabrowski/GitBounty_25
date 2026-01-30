import { ethers } from "./ethers-6.7.esm.min.js";
import { factoryAddress, factoryAbi, bountyAbi, chainIdMap, READ_RPC_URLS } from "./constants.js";

/* =====================================================================
    GLOBAL RUNTIME STATE
    Set on connect / accountsChanged, cleared on disconnect
===================================================================== */
let currentAccount = null;

// Write+Read (wallet only)
let browserProvider;
let signer;
let writeFactory;

let readProvider;
let readFactory;

// BOUNTY STATE LABELS
const BOUNTY_STATE = ["BASE", "EMPTY", "READY", "CALCULATING", "PAID"];

/* =====================================================================
    DOM REFERENCES
===================================================================== */

// READONLY UI ELEMENTS 
const factoryAddressEl = document.getElementById("factoryAddress");
const factoryBountyCountEl = document.getElementById("factoryBountyCount");
const bountiesListEl = document.getElementById("bountiesList");

// CREATE BOUNTY FORM REFERENCES
const repoOwnerInput = document.getElementById("repoOwnerInput");
const repoInput = document.getElementById("repoInput");
const issueNumberInput = document.getElementById("issueNumberInput");
const fundingEthInput = document.getElementById("fundingEthInput");
const createBountyStatus = document.getElementById("createBountyStatus");

// BUTTONS
const connectButton = document.getElementById("connectButton");
const refreshButton = document.getElementById("refreshButton");
const createBountyButton = document.getElementById("createBountyButton");

/* =====================================================================
    EVENTS
===================================================================== */
connectButton.onclick = connect;
refreshButton.onclick = loadBountiesView;
createBountyButton.onclick = createBountyFromUI;

/* =====================================================================
    UI HELPERS
===================================================================== */

// BUTTON STATE TOGGLE
function pressButton(button, status) {
  button.classList.toggle("pressed", status);
}

// ADDRESS SHORTENER
function shortAddr(addr) {
  if (!addr) return "";
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

// TIMESTAMPS
function formatTimestamp(ts) {
  const n = Number(ts);
  if (!n) return "—";
  return new Date(n * 1000).toLocaleString();
}

/* =====================================================================
    ACCOUNT HELPERS
===================================================================== */

async function initReadProvider() {
  try {
    let provider;

    if (window.ethereum) {
      provider = new ethers.BrowserProvider(window.ethereum);
    } else {
      for (const url of READ_RPC_URLS) {
        try {
          const providerTest = new ethers.JsonRpcProvider(url);
          await providerTest.getBlockNumber(); // sanity check
          provider = providerTest;
          break;
        } catch (_) {}
      }
    }

    if (!provider) {
      throw new Error("No working read RPC available (all READ_RPC_URLS failed).");
    }

    // 2. Install globals
    readProvider = provider;
    readFactory = new ethers.Contract(factoryAddress, factoryAbi, readProvider);

    return true;
  } catch (e) {
    console.error(e);
    bountiesListEl.innerHTML = `
      <div class="bounty-row"><em>${e.message}</em></div>
    `;
    return false;
  }
}

/* =====================================================================
    UI FUNCTIONS
===================================================================== */

function initFactoryHeaderUI() {
  factoryAddressEl.textContent = `Address: ${factoryAddress}`;
  factoryBountyCountEl.textContent = "Bounties: ..."; // default, updated later
}

// UI STATE — CONNECTED VIEW
// Updates button labels and enables actions once wallet is connected
function setConnectedUI(chainId) {
  const networkName = chainIdMap[chainId] || "Unknown Network";
  const short = shortAddr(currentAccount);
  pressButton(connectButton, true);
  connectButton.innerHTML = `Connected: ${short} on ${networkName}`;
  refreshButton.disabled = false;
  createBountyButton.disabled = false;
}

// UI STATE — DISCONNECTED / RESET VIEW
// Clears wallet state and resets UI back to “not connected”
function setDisconnectedUI() {
  currentAccount = null;
  pressButton(connectButton, false);
  connectButton.innerHTML = "Connect Wallet";
  createBountyButton.disabled = true;
  if (createBountyStatus) createBountyStatus.textContent = "";
}

// METAMASK EVENT HANDLING - ACCOUNT SWITCH
// Keeps the UI up to date when the user changes accounts in MetaMask
handleAccountChange();

function handleAccountChange() {
  if (!window.ethereum) return;

  window.ethereum.on("accountsChanged", async (accounts) => {
    const isConnected = connectButton.classList.contains("pressed");
    if (!isConnected) return;

    if (!accounts || accounts.length === 0) {
      setDisconnectedUI();
      return;
    }

    try {
      const ok = await setupFromEthereum({ shouldRequestAccounts: false });
      if (!ok) {
        setDisconnectedUI();
        return;
      }
    } catch (err) {
      console.error(err);
    }
  });
}

// SETUP WALLET-ETHEREUM CONNECTION
async function setupFromEthereum({ shouldRequestAccounts = false } = {}) {
  if (!window.ethereum) {
    connectButton.innerHTML = "Please install MetaMask";
    return false;
  }

  if (shouldRequestAccounts) {
    await window.ethereum.request({ method: "eth_requestAccounts" });
  }

  const accounts = await window.ethereum.request({ method: "eth_accounts" });
  if (!accounts || accounts.length === 0) return false;

  currentAccount = accounts[0];

  const chainId = await window.ethereum.request({ method: "eth_chainId" });

  browserProvider = new ethers.BrowserProvider(window.ethereum);
  signer = await browserProvider.getSigner();
  writeFactory = new ethers.Contract(factoryAddress, factoryAbi, signer);

  setConnectedUI(chainId);
  return true;
}


// WALLET CONNECT / DISCONNECT (TOGGLE)
// Connects to MetaMask, sets up provider/signer/factory contract instance
// If already connected, acts as a “disconnect” (UI-only reset)
async function connect() {
  // toggle disconnect (UI-only)
  if (currentAccount) {
    setDisconnectedUI();
    return;
  }

  try {
    const ok = await setupFromEthereum({ shouldRequestAccounts: true });
    if (!ok) {
      setDisconnectedUI(); // or just show "No account selected"
      return;
    }
    await loadBountiesView({ write: true });
  } catch (err) {
    console.error(err);
  }
}

function setListLoading(isLoading) {
  bountiesListEl.classList.toggle("is-loading", isLoading);
}

function setRefreshLoading(isLoading) {
  refreshButton.classList.toggle("is-loading", isLoading);
}

function startDelayedRefreshSpinner(nonce, delayMs = 200) {
  const id = setTimeout(() => {
    if (nonce === bountiesLoadNonce) setRefreshLoading(true);
  }, delayMs);

  return () => clearTimeout(id);
}

function startDelayedLoading(nonce, delayMs = 200) {
  const id = setTimeout(() => {
    // only show loading if this request is still the latest
    if (nonce === bountiesLoadNonce) setListLoading(true);
  }, delayMs);

  // return a cancel function
  return () => clearTimeout(id);
}

/* =====================================================================
    DATA FUNCTIONS
===================================================================== */

// LOAD AND RENDER ALL BOUNTIES
// Reads factory bountyCount + paginates getBounties(start, limit)
// For each bounty: fetches getBountySnapshot() and renders a UI row
// Uses Promise.allSettled to render partial results even if some fail
let bountiesLoadNonce = 0;

async function loadBountiesView({ write = false } = {}) {
  const factory = write && writeFactory ? writeFactory : readFactory;
  const provider = write && browserProvider ? browserProvider : readProvider;

  if (!factory) return;

  const nonce = ++bountiesLoadNonce;

  factoryAddressEl.textContent = `Address: ${factoryAddress}`;

  // Delay UI "loading" indicators so fast loads don't flash
  const cancelListTimer = startDelayedLoading(nonce, 200); // your existing delayed list loader
  const cancelSpinTimer = startDelayedRefreshSpinner(nonce, 200); // new

  try {
    // ---- read count
    let count;
    try {
      count = Number(await factory.bountyCount());
    } catch (err) {
      console.error("Error reading bounty count:", err);
      factoryBountyCountEl.textContent = `Bounties: (error)`;
      return;
    }

    // If a newer refresh started, don't update UI with stale results
    if (nonce !== bountiesLoadNonce) return;

    factoryBountyCountEl.textContent = `Bounties: ${count}`;

    if (count === 0) {
      // atomic swap keeps things stable
      bountiesListEl.replaceChildren(
        (() => {
          const d = document.createElement("div");
          d.className = "bounty-row";
          d.innerHTML = `<em>No bounties found.</em>`;
          return d;
        })()
      );
      return;
    }

    // ---- collect addresses
    const pageSize = 25;
    const all = [];

    for (let start = 0; start < count; start += pageSize) {
      const limit = Math.min(pageSize, count - start);
      const [addresses, nextAts] = await factory.getBounties(start, limit);

      for (let i = 0; i < addresses.length; i++) {
        all.push({
          index: start + i,
          address: addresses[i],
          nextAttemptAt: nextAts[i],
        });
      }
    }

    if (nonce !== bountiesLoadNonce) return;

    // ---- fetch snapshots
    const settled = await Promise.allSettled(
      all.map(async (entry) => {
        const bounty = new ethers.Contract(entry.address, bountyAbi, provider);
        const snap = await bounty.getBountySnapshot();
        return { entry, snap };
      })
    );

    if (nonce !== bountiesLoadNonce) return;

    // ---- build new list off-DOM
    const frag = document.createDocumentFragment();

    for (let i = 0; i < settled.length; i++) {
      const s = settled[i];
      if (s.status === "fulfilled") {
        frag.appendChild(renderBountyRow(s.value.entry, s.value.snap));
      } else {
        console.error("Snapshot failed for", all[i].address, s.reason);
        frag.appendChild(renderBountyRow(all[i], null, s.reason));
      }
    }

    // ---- single swap (no flicker)
    bountiesListEl.replaceChildren(frag);
  } finally {
    cancelListTimer();
    cancelSpinTimer();
    // only the latest call should control loading state
    if (nonce === bountiesLoadNonce) {
      setListLoading(false);
      setRefreshLoading(false);
    }
  }
}


/* =====================================================================
   SNAPSHOT SAFETY — POSITIONAL + NAMED FIELD ACCESS
   - Supports both tuple arrays and named return objects from ethers ABI
   - Lets UI survive snapshot shape changes during contract iteration
   ===================================================================== */
function safeGet(res, i, fallbackKey) {
  try {
    if (res && typeof res.length === "number" && i < res.length) return res[i];
  } catch (_) {}
  // fallback to named key if it exists
  if (fallbackKey && res && res[fallbackKey] !== undefined) return res[fallbackKey];
  return undefined;
}

/* =====================================================================
   FORMAT HELPERS — SAFE ETHER DISPLAY
   - Prevents UI crashes if a value is missing or not BigInt-compatible
   ===================================================================== */
function safeFormatEther(v) {
  try {
    if (v === null || v === undefined) return "—";
    return ethers.formatEther(v);
  } catch {
    return "—";
  }
}

/* =====================================================================
   RENDERING — SINGLE BOUNTY ROW
   - Converts (factory index + snapshot data) into a DOM row element
   - Hides “paid-only” fields unless bounty is in PAID state
   - Falls back to an error-row when snapshot load fails
   ===================================================================== */
function renderBountyRow(base, snap, err) {
  const row = document.createElement("div");
  row.className = "bounty-row";

  if (err || !snap) {
    const msg = (err && (err.shortMessage || err.message)) || "Unknown error";
    row.innerHTML = `
      <div><strong>#${base.index}</strong> <span class="mono">${base.address}</span></div>
      <div>Next attempt (factory): ${formatTimestamp(base.nextAttemptAt)}</div>
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
  const stateLabel = BOUNTY_STATE[stateNum] ?? (r_state !== undefined ? String(r_state) : "—");
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
    <div>Next update: ${formatTimestamp(base.nextAttemptAt)}</div>
    ${paidRows}
  `;

  return row;
}

/* =====================================================================
   CREATE BOUNTY — STATUS UI
   - Single place to write status text (and tooltip) for the create flow
   ===================================================================== */
function setCreateStatus(msg) {
  if (!createBountyStatus) return;
  createBountyStatus.textContent = msg || "";
  createBountyStatus.title = msg || "";
}

/* =====================================================================
   CREATE BOUNTY — INPUT NORMALIZATION
   - Small helper to trim inputs consistently (safe for missing elements)
   ===================================================================== */
function readInput(el) {
  return (el?.value || "").trim();
}

/* =====================================================================
   CREATE BOUNTY — MAIN FLOW (UI -> TX -> PARSE EVENT -> REFRESH)
   - Validates inputs, converts ETH to wei (parseEther)
   - Sends factory.createBounty(repoOwner, repo, issueNumber, { value })
   - Waits for receipt, tries to parse BountyDeployed event for address
   - Refreshes the factory view on success
   ===================================================================== */
async function createBountyFromUI() {
  if (!writeFactory || !signer) {
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
    const tx = await writeFactory.createBounty(repoOwner, repo, issueNumber, { value });
    setCreateStatus(`Tx sent: ${tx.hash}`);

    const receipt = await tx.wait();
    let bountyAddr = null;

    // Parse BountyDeployed event if present
    for (const log of receipt.logs || []) {
      try {
        const parsed = writeFactory.interface.parseLog(log);
        if (parsed?.name === "BountyDeployed") {
          bountyAddr = parsed.args?.bounty;
          break;
        }
      } catch (_) {}
    }

    setCreateStatus(bountyAddr ? `Created: ${bountyAddr}` : "Confirmed. Refreshing…");
    await loadBountiesView();
  } catch (err) {
    console.error(err);
    setCreateStatus((err && (err.shortMessage || err.message)) || "Transaction failed");
  } finally {
    createBountyButton.disabled = !currentAccount;
  }
}


async function startup() {
  if (!window.ethereum) {
    connectButton.disabled = true;
    connectButton.innerHTML = "MetaMask not installed";
  }

  initFactoryHeaderUI();

  const ok = await initReadProvider();
  if (ok) {
    await loadBountiesView();
  }
}

startup();

// vercel
//const url = `/api/issues?owner=${owner}&repo=${repo}&page=1&per_page=30`;
//const data = await fetch(url).then(r => r.json());

