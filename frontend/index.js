import { ethers } from "./ethers-6.7.esm.min.js";
import { factoryAddress, factoryAbi, bountyAbi, chainIdMap, READ_RPC_URLS, API_ORIGIN } from "./constants.js";

/* =====================================================================
   0) CONFIG + CONSTANTS
===================================================================== */

const apiOrigin = API_ORIGIN || window.location.origin;

// BOUNTY STATE LABELS (must match contract enum order)
const BOUNTY_STATE = ["BASE", "EMPTY", "READY", "CALCULATING", "PAID"];

/* =====================================================================
   1) GLOBAL RUNTIME STATE
   Set on connect / accountsChanged, cleared on disconnect
===================================================================== */

let currentAccount = null;

// Write+Read (wallet only)
let browserProvider;
let signer;
let writeFactory;

// Read-only fallback provider
let readProvider;
let readFactory;

// Issue selection state
let selectedIssue = null; // { owner, repo, number, title, body }

/* =====================================================================
   2) DOM REFERENCES
===================================================================== */

// READONLY UI ELEMENTS
const factoryAddressEl = document.getElementById("factoryAddress");
const factoryBountyCountEl = document.getElementById("factoryBountyCount");
const bountiesListEl = document.getElementById("bountiesList");

// BUTTONS
const connectButton = document.getElementById("connectButton");
if (!hasInjectedWallet()) {
  connectButton.disabled = true;
  connectButton.textContent = "MetaMask not installed";
  connectButton.title = "Install MetaMask to connect a wallet";
}

const refreshButton = document.getElementById("refreshButton");

// ISSUE BROWSER REFERENCES
const issuesOwnerInput = document.getElementById("issuesOwnerInput");
const issuesRepoInput = document.getElementById("issuesRepoInput");
const issuesStateSelect = document.getElementById("issuesStateSelect");
const loadIssuesButton = document.getElementById("loadIssuesButton");
const createFromSelectedButton = document.getElementById("createFromSelectedButton");
const issuesStatus = document.getElementById("issuesStatus");
const issuesListEl = document.getElementById("issuesList");
const issuesFundingEthInput = document.getElementById("issuesFundingEthInput");

// POPOVER
const bountyPopoverEl = document.getElementById("bountyDetailsPopover");
let popoverOutsideHandlerBound = false;

/* =====================================================================
   3) EVENTS / WIRING
===================================================================== */

connectButton.onclick = connect;
refreshButton.onclick = loadBountiesView;

if (loadIssuesButton) loadIssuesButton.onclick = loadIssuesFromUI;
if (createFromSelectedButton) createFromSelectedButton.onclick = createBountyFromSelected;

// Keep UI synced with MetaMask account switching
handleAccountChange();

/* =====================================================================
   4) SMALL UI + FORMAT HELPERS
===================================================================== */

// Button pressed state
function pressButton(button, status) {
  button.classList.toggle("pressed", status);
}

// Address shortener
function shortAddr(addr) {
  if (!addr) return "";
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

// Timestamps
function formatTimestamp(ts) {
  const n = Number(ts);
  if (!n) return "—";
  return new Date(n * 1000).toLocaleString();
}

// Safe HTML escaping (innerHTML)
function escapeHtml(str) {
  return String(str)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

// For title="" attributes etc
function escapeAttr(s) {
  return escapeHtml(s).replaceAll("\n", " ");
}

// Small helper to trim inputs consistently
function readInput(el) {
  return (el?.value || "").trim();
}

/* =====================================================================
   5) SNAPSHOT SAFETY + VALUE FORMATTERS
===================================================================== */

// Supports both tuple arrays and named return objects from ethers ABI
function safeGet(res, i, fallbackKey) {
  try {
    if (res && typeof res.length === "number" && i < res.length) return res[i];
  } catch (_) {}
  if (fallbackKey && res && res[fallbackKey] !== undefined) return res[fallbackKey];
  return undefined;
}

// Prevent UI crashes if a value is missing or not BigInt-compatible
function safeFormatEther(v) {
  try {
    if (v === null || v === undefined) return "—";
    return ethers.formatEther(v);
  } catch {
    return "—";
  }
}

/* =====================================================================
   6) UI STATE + CONTROLS
===================================================================== */

function initFactoryHeaderUI() {
  factoryAddressEl.textContent = `Address: ${factoryAddress}`;
  factoryBountyCountEl.textContent = "Bounties: ...";
}

function setConnectedUI(chainId) {
  const networkName = chainIdMap[chainId] || "Unknown Network";
  const short = shortAddr(currentAccount);

  pressButton(connectButton, true);
  connectButton.innerHTML = `Connected: ${short} on ${networkName}`;

  updateCreateControls();
}

function setDisconnectedUI() {
  currentAccount = null;
  selectedIssue = null;

  pressButton(connectButton, false);
  connectButton.innerHTML = "Connect Wallet";

  if (createFromSelectedButton) createFromSelectedButton.disabled = true;

  setIssuesStatus("");
  if (createFromSelectedButton) createFromSelectedButton.textContent = "Create bounty";

  document.querySelectorAll(".issue-row.selected").forEach((el) => el.classList.remove("selected"));
}

function updateCreateControls() {
  const isConnected = !!(currentAccount && writeFactory && signer);
  const fundingEth = readInput(issuesFundingEthInput);

  let hasPositiveFunding = false;
  try {
    if (fundingEth) {
      const v = ethers.parseEther(fundingEth);
      hasPositiveFunding = v > 0n;
    }
  } catch {
    hasPositiveFunding = false;
  }

  const canCreateSelected = isConnected && !!selectedIssue && hasPositiveFunding;
  if (createFromSelectedButton) createFromSelectedButton.disabled = !canCreateSelected;
}

/* =====================================================================
   7) PROVIDERS + WALLET / ACCOUNT HELPERS
===================================================================== */

async function probeRpc(url, ms = 1500) {
  const provider = new ethers.JsonRpcProvider(
    url,
    { name: "sepolia", chainId: 11155111 } // pin network
  );

  try {
    await Promise.race([
      provider.getBlockNumber(),
      new Promise((_, rej) => setTimeout(() => rej(new Error("RPC timeout")), ms)),
    ]);
    return provider; // keep this one
  } catch (err) {
    // IMPORTANT: stop ethers retry loop
    try { provider.destroy(); } catch (_) {}
    throw err;
  }
}

function withTimeout(promise, ms, label = "timeout") {
  return Promise.race([
    promise,
    new Promise((_, rej) => setTimeout(() => rej(new Error(label)), ms)),
  ]);
}

async function initReadProvider() {
  try {
    let provider;

    if (window.ethereum) {
      provider = new ethers.BrowserProvider(window.ethereum);
    } else {
      for (const url of READ_RPC_URLS) {
        try {
          provider = await probeRpc(url, 1500);
          break;
        } catch (_) {}
      }
    }

    if (!provider) throw new Error("No working read RPC available.");

    readProvider = provider;
    readFactory = new ethers.Contract(factoryAddress, factoryAbi, readProvider);
    return true;
  } catch (e) {
    console.error(e);
    return false;
  }
}

function hasInjectedWallet() {
  return typeof window.ethereum !== "undefined";
}

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
      if (!ok) setDisconnectedUI();
    } catch (err) {
      console.error(err);
    }
  });
}

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

// Wallet connect / disconnect (UI-only reset on disconnect)
async function connect() {
  if (currentAccount) {
    setDisconnectedUI();
    return;
  }

  try {
    const ok = await setupFromEthereum({ shouldRequestAccounts: true });
    if (!ok) {
      setDisconnectedUI();
      return;
    }
    await loadBountiesView({ write: true });
  } catch (err) {
    console.error(err);
  }
}

/* =====================================================================
   8) LOADING / SPINNER HELPERS
===================================================================== */

function setListLoading(isLoading) {
  bountiesListEl.classList.toggle("is-loading", isLoading);
}

function setRefreshLoading(isLoading) {
  refreshButton.classList.toggle("is-loading", isLoading);
}

let bountiesLoadNonce = 0;

function startDelayedRefreshSpinner(nonce, delayMs = 200) {
  const id = setTimeout(() => {
    if (nonce === bountiesLoadNonce) setRefreshLoading(true);
  }, delayMs);
  return () => clearTimeout(id);
}

function startDelayedLoading(nonce, delayMs = 200) {
  const id = setTimeout(() => {
    if (nonce === bountiesLoadNonce) setListLoading(true);
  }, delayMs);
  return () => clearTimeout(id);
}

function setIssuesLoading(isLoading) {
  if (!issuesListEl) return;
  issuesListEl.classList.toggle("is-loading", isLoading);
}

function setIssuesStatus(msg) {
  if (!issuesStatus) return;
  issuesStatus.textContent = msg || "";
  issuesStatus.title = msg || "";
}

/* =====================================================================
   9) ISSUE CACHE + API HELPERS
===================================================================== */

// key: "owner/repo" => Map(issueNumber -> { title, html_url })
const issueCache = new Map();

// key: "owner/repo" => { fetchedAt, done, inFlight }
const repoFetchState = new Map();

function cacheIssues(owner, repo, items) {
  if (!owner || !repo) return;
  const key = `${owner}/${repo}`;

  let map = issueCache.get(key);
  if (!map) {
    map = new Map();
    issueCache.set(key, map);
  }

  for (const it of items || []) {
    if (!it?.number) continue;
    map.set(Number(it.number), { title: it.title || "", html_url: it.html_url || "" });
  }
}

function getCachedIssueTitle(owner, repo, issueNumber) {
  if (!owner || !repo || issueNumber == null) return null;
  const key = `${owner}/${repo}`;
  return issueCache.get(key)?.get(Number(issueNumber))?.title || null;
}

function getCachedIssueUrl(owner, repo, issueNumber) {
  if (!owner || !repo || issueNumber == null) return null;
  const key = `${owner}/${repo}`;
  return issueCache.get(key)?.get(Number(issueNumber))?.html_url || null;
}

async function fetchIssuesFromApi({ owner, repo, state = "open", per_page = 50, page = 1 } = {}) {
  const url = new URL("/api/issues", window.location.origin);
  url.searchParams.set("owner", owner);
  url.searchParams.set("repo", repo);
  url.searchParams.set("state", state);
  url.searchParams.set("per_page", String(per_page));
  url.searchParams.set("page", String(page));

  const res = await fetch(url.toString(), { headers: { Accept: "application/json" } });
  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const msg = data?.error
      ? `${data.error}${data.details ? ": " + data.details : ""}`
      : `HTTP ${res.status}`;
    const err = new Error(msg);
    err.status = res.status;
    err.data = data;
    throw err;
  }

  const items = Array.isArray(data.issues) ? data.issues : [];
  return { items, data };
}

async function runWithLimit(tasks, limit = 3) {
  const results = [];
  let i = 0;

  async function worker() {
    while (i < tasks.length) {
      const idx = i++;
      results[idx] = await tasks[idx]();
    }
  }

  const workers = Array.from({ length: Math.min(limit, tasks.length) }, worker);
  await Promise.all(workers);
  return results;
}

/**
 * Prefetch issue titles for repos found in bounty snapshots.
 * This keeps the bounty rows compact (we can show the issue title without extra per-row fetches).
 */
async function prefetchIssuesForBounties(snaps) {
  const repos = new Map(); // key => { owner, repo }
  for (const snap of snaps || []) {
    if (!snap) continue;

    // BountySnapshot struct (supports tuple + named keys)
    const stateNum = Number(safeGet(snap, 0, "state"));
    const stateLabel = BOUNTY_STATE[stateNum] ?? "—";
    const isPaid = stateLabel === "PAID";

    const repoOwnerNow = safeGet(snap, 4, "repoOwner");
    const repoNow = safeGet(snap, 5, "repo");

    const repoOwnerLast = safeGet(snap, 11, "last_repo_owner");
    const repoLast = safeGet(snap, 12, "last_repo");

    const repoOwner = (isPaid ? repoOwnerLast : repoOwnerNow) || repoOwnerNow || repoOwnerLast;
    const repo = (isPaid ? repoLast : repoNow) || repoNow || repoLast;

    if (!repoOwner || !repo) continue;

    const key = `${repoOwner}/${repo}`;
    repos.set(key, { owner: repoOwner, repo });
  }

  const repoList = Array.from(repos.values());
  if (repoList.length === 0) return;

  const now = Date.now();
  const TTL_MS = 5 * 60 * 1000;

  const tasks = repoList.map(({ owner, repo }) => async () => {
    const key = `${owner}/${repo}`;

    const st = repoFetchState.get(key);
    const fresh = st?.fetchedAt && now - st.fetchedAt < TTL_MS;
    if (fresh) return { key, skipped: true };

    // de-dupe concurrent fetches
    if (st?.inFlight) return st.inFlight;

    const promise = (async () => {
      try {
        const { items } = await fetchIssuesFromApi({ owner, repo, state: "all", per_page: 50, page: 1 });
        const issuesOnly = (Array.isArray(items) ? items : []).filter((it) => !it.pull_request);
        cacheIssues(owner, repo, issuesOnly);
        repoFetchState.set(key, { fetchedAt: Date.now(), done: true, inFlight: null });
        return { key, count: issuesOnly.length };
      } catch (e) {
        repoFetchState.set(key, { fetchedAt: Date.now(), done: false, inFlight: null });
        return { key, error: (e && e.message) || String(e) };
      }
    })();

    repoFetchState.set(key, { fetchedAt: st?.fetchedAt || 0, done: st?.done || false, inFlight: promise });
    return promise;
  });

  await runWithLimit(tasks, 3);
}

/* =====================================================================
   10) ISSUE BROWSER UI (LOAD / RENDER / SELECT)
===================================================================== */

async function loadIssuesFromUI() {
  if (!issuesOwnerInput || !issuesRepoInput || !issuesListEl) return;

  const owner = readInput(issuesOwnerInput);
  const repo = readInput(issuesRepoInput);
  const state = (issuesStateSelect?.value || "open").trim();

  if (!owner || !repo) {
    setIssuesStatus("Enter repo owner + repo.");
    return;
  }

  setIssuesLoading(true);
  setIssuesStatus("Loading issues…");
  selectedIssue = null;
  if (createFromSelectedButton) createFromSelectedButton.textContent = "Create bounty";
  updateCreateControls();

  try {
    const { items } = await fetchIssuesFromApi({ owner, repo, state, per_page: 50, page: 1 });

    cacheIssues(owner, repo, items);

    if (items.length === 0) {
      setIssuesStatus("No issues found.");
      issuesListEl.replaceChildren(
        Object.assign(document.createElement("div"), {
          className: "bounty-row",
          innerHTML: `<em>No issues found.</em>`,
        })
      );
      return;
    }

    const frag = document.createDocumentFragment();
    for (const issue of items) frag.appendChild(renderIssueRow({ owner, repo, issue }));
    issuesListEl.replaceChildren(frag);

    setIssuesStatus(`Loaded ${items.length} issues.`);
  } catch (err) {
    console.error(err);
    const msg = (err && (err.shortMessage || err.message)) || "Failed to load issues";
    setIssuesStatus(msg);
    issuesListEl.replaceChildren(
      Object.assign(document.createElement("div"), {
        className: "bounty-row",
        innerHTML: `<em>${escapeHtml(msg)}</em>`,
      })
    );
  } finally {
    setIssuesLoading(false);
    updateCreateControls();
  }
}

function renderIssueRow({ owner, repo, issue }) {
  const row = document.createElement("div");
  row.className = "issue-row";

  const labels = (issue.labels || [])
    .slice(0, 6)
    .map((l) => (typeof l === "string" ? l : l?.name))
    .filter(Boolean)
    .join(", ");

  const body = (issue.body || "").trim();

  row.innerHTML = `
    <div class="issue-title">#${issue.number} — ${escapeHtml(issue.title || "")}</div>
    <div class="issue-meta">
      <span>state: ${issue.state || "—"}</span>
      <span>author: ${escapeHtml(issue.user?.login || "—")}</span>
      <span>comments: ${issue.comments ?? 0}</span>
      ${labels ? `<span>labels: ${escapeHtml(labels)}</span>` : ""}
    </div>
    ${body ? `<div class="issue-body">${escapeHtml(body)}</div>` : ""}
  `;

  row.addEventListener("click", () => selectIssue({ owner, repo, issue }, row));
  return row;
}

function selectIssue({ owner, repo, issue }, rowEl) {
  selectedIssue = { owner, repo, number: issue.number, title: issue.title, body: issue.body };

  document.querySelectorAll(".issue-row.selected").forEach((el) => el.classList.remove("selected"));
  rowEl?.classList.add("selected");

  setIssuesStatus(`Selected #${issue.number}: ${issue.title || ""}`);

  if (createFromSelectedButton) {
    createFromSelectedButton.textContent = `Create bounty for #${issue.number}`;
  }

  updateCreateControls();
}

/* =====================================================================
   11) CREATE BOUNTY (FROM SELECTED ISSUE)
===================================================================== */

async function createBountyFromSelected() {
  if (!writeFactory || !signer) {
    setIssuesStatus("Connect wallet first.");
    return;
  }
  if (!selectedIssue) {
    setIssuesStatus("Select an issue first.");
    return;
  }

  const fundingEth = readInput(issuesFundingEthInput);
  if (!fundingEth) {
    setIssuesStatus("Funding is required (must be > 0).");
    return;
  }

  let value;
  try {
    value = ethers.parseEther(fundingEth);
    if (value <= 0n) throw new Error("Funding must be > 0");
  } catch {
    setIssuesStatus("Invalid funding amount.");
    return;
  }

  if (createFromSelectedButton) createFromSelectedButton.disabled = true;
  setIssuesStatus("Sending transaction...");

  try {
    const { owner, repo, number } = selectedIssue;

    const tx = await writeFactory.createBounty(owner, repo, String(number), { value });
    setIssuesStatus(`Tx sent: ${tx.hash}`);

    const receipt = await tx.wait();
    let bountyAddr = null;

    for (const log of receipt.logs || []) {
      try {
        const parsed = writeFactory.interface.parseLog(log);
        if (parsed?.name === "BountyDeployed") {
          bountyAddr = parsed.args?.bounty;
          break;
        }
      } catch (_) {}
    }

    setIssuesStatus(bountyAddr ? `Created: ${bountyAddr}` : "Confirmed. Refreshing…");
    await loadBountiesView({ write: true });
  } catch (err) {
    console.error(err);
    setIssuesStatus((err && (err.shortMessage || err.message)) || "Transaction failed");
  } finally {
    updateCreateControls();
  }
}

/* =====================================================================
   12) BOUNTIES: LOAD + RENDER
===================================================================== */

async function loadBountiesView({ write = false } = {}) {
  const factory = write && writeFactory ? writeFactory : readFactory;
  const provider = write && browserProvider ? browserProvider : readProvider;

  if (!factory) return;

  const nonce = ++bountiesLoadNonce;

  factoryAddressEl.textContent = `Address: ${factoryAddress}`;

  const cancelListTimer = startDelayedLoading(nonce, 200);
  const cancelSpinTimer = startDelayedRefreshSpinner(nonce, 200);

  try {
    let count;
    try {
      count = Number(await factory.bountyCount());
    } catch (err) {
      console.error("Error reading bounty count:", err);
      factoryBountyCountEl.textContent = `Bounties: (error)`;
      return;
    }

    if (nonce !== bountiesLoadNonce) return;

    factoryBountyCountEl.textContent = `Bounties: ${count}`;

    if (count === 0) {
      bountiesListEl.replaceChildren(
        Object.assign(document.createElement("div"), {
          className: "bounty-row",
          innerHTML: `<em>No bounties found.</em>`,
        })
      );
      return;
    }

    // Collect addresses
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

    // Fetch snapshots
    const settled = await Promise.allSettled(
      all.map(async (entry) => {
        const bounty = new ethers.Contract(entry.address, bountyAbi, provider);
        const snap = await bounty.getBountySnapshot();
        return { entry, snap };
      })
    );

    if (nonce !== bountiesLoadNonce) return;

    // Prefetch issue titles for ALL repos found in snapshots
    const snaps = [];
    for (const s of settled) {
      if (s.status === "fulfilled" && s.value?.snap) snaps.push(s.value.snap);
    }

    if (snaps.length > 0) {
      try {
        await prefetchIssuesForBounties(snaps);
      } catch (e) {
        console.warn("prefetchIssuesForBounties failed:", e);
      }
    }

    // Build new list off-DOM
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

    bountiesListEl.replaceChildren(frag);
  } finally {
    cancelListTimer();
    cancelSpinTimer();

    if (nonce === bountiesLoadNonce) {
      setListLoading(false);
      setRefreshLoading(false);
    }
  }
}

/* =====================================================================
   13) BOUNTY ROW RENDERING + DETAILS POPOVER
===================================================================== */

function renderBountyRow(base, snap, err) {
  const row = document.createElement("div");
  row.className = "bounty-row bounty-row-compact";

  // Error row
  if (err || !snap) {
    const msg = (err && (err.shortMessage || err.message)) || "Unknown error";
    row.classList.add("bounty-state-empty");

    row.innerHTML = `
      <div class="bounty-compact-title"><strong>#${base.index}</strong> — <span class="mono">(snapshot error)</span></div>
      <div class="bounty-compact-funding">—</div>
      <div class="bounty-compact-repo"><span class="mono">${shortAddr(base.address)}</span></div>
      <button class="button kde bounty-compact-more" type="button" title="Details">⋯</button>
    `;

    const btn = row.querySelector(".bounty-compact-more");
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      openBountyDetailsPopover(btn, {
        title: `Bounty #${base.index} (snapshot error)`,
        rows: [
          ["Address", base.address],
          ["Next update", formatTimestamp(base.nextAttemptAt)],
          ["Error", msg],
        ],
      });
    });

    return row;
  }

  // Snapshot fields (BountySnapshot struct)
  const r_state = safeGet(snap, 0, "state");
  const r_owner = safeGet(snap, 1, "owner");

  const r_repoOwner = safeGet(snap, 4, "repoOwner");
  const r_repo = safeGet(snap, 5, "repo");
  const r_issueNumber = safeGet(snap, 6, "issueNumber");

  const r_totalFunding = safeGet(snap, 7, "totalFunding");
  const r_funderCount = safeGet(snap, 8, "funderCount");

  const r_lastWinner = safeGet(snap, 9, "lastWinner");
  const r_lastWinnerUser = safeGet(snap, 10, "lastWinnerUser");

  const r_last_repoOwner = safeGet(snap, 11, "last_repo_owner");
  const r_last_repo = safeGet(snap, 12, "last_repo");
  const r_last_issueNumber = safeGet(snap, 13, "last_issueNumber");
  const r_lastBountyAmount = safeGet(snap, 14, "lastBountyAmount");

  const stateNum = Number(r_state);
  const stateLabel = BOUNTY_STATE[stateNum] ?? (r_state !== undefined ? String(r_state) : "—");
  const isPaid = stateLabel === "PAID";

  // If the bounty is closed/completed, show the *last_* repo/issue values instead
  const displayRepoOwner = (isPaid ? r_last_repoOwner : r_repoOwner) || r_repoOwner || r_last_repoOwner;
  const displayRepo = (isPaid ? r_last_repo : r_repo) || r_repo || r_last_repo;
  const displayIssueNumber = (isPaid ? r_last_issueNumber : r_issueNumber) || r_issueNumber || r_last_issueNumber;

  const stateClass =
    stateLabel === "READY"
      ? "bounty-state-ready"
      : stateLabel === "CALCULATING"
      ? "bounty-state-calculating"
      : stateLabel === "PAID"
      ? "bounty-state-paid"
      : stateLabel === "EMPTY"
      ? "bounty-state-empty"
      : "bounty-state-base";

  row.classList.add(stateClass);

  // Issue title from cache (populated via loadIssuesFromUI or prefetchIssuesForBounties)
  const issueTitle = getCachedIssueTitle(displayRepoOwner, displayRepo, displayIssueNumber) || "(title unavailable)";

  const issueStr = `#${displayIssueNumber ?? "—"} — ${issueTitle}`;
  const repoStr = `${displayRepoOwner || "—"}/${displayRepo || "—"}`;

  row.innerHTML = `
    <div class="bounty-compact-title" title="${escapeAttr(issueStr)}">
      <strong>#${displayIssueNumber ?? "—"}</strong> — ${escapeHtml(issueTitle)}
    </div>

    <div class="bounty-compact-funding" title="Total funding">
      ${safeFormatEther(r_totalFunding)} ETH
    </div>

    <div class="bounty-compact-repo" title="${escapeAttr(repoStr)}">
      ${escapeHtml(repoStr)}
    </div>

    <button class="button kde bounty-compact-more" type="button" title="Details">⋯</button>
  `;

  const btn = row.querySelector(".bounty-compact-more");
  btn.addEventListener("click", (e) => {
    e.stopPropagation();

    const detailsRows = [
      ["Bounty index", String(base.index)],
      ["Bounty address", base.address],
      ["Repo", repoStr],
      ["Issue", `#${displayIssueNumber ?? "—"}`],
      ["State", stateLabel],
      ["Funding", `${safeFormatEther(r_totalFunding)} ETH`],
      ["Funders", r_funderCount ?? "—"],
      ["Owner", r_owner || "—"],
      ["Next update", formatTimestamp(base.nextAttemptAt)],
    ];

    if (isPaid) {
      detailsRows.push(
        ["(Last) Repo", `${r_last_repoOwner || "—"}/${r_last_repo || "—"}`],
        ["(Last) Issue", `#${r_last_issueNumber ?? "—"}`],
        ["Last winner", r_lastWinner || "—"],
        ["Winner user", r_lastWinnerUser || "—"],
        ["Last bounty", `${safeFormatEther(r_lastBountyAmount)} ETH`]
      );
    }

    openBountyDetailsPopover(btn, {
      title: `${repoStr} #${displayIssueNumber ?? "—"}`,
      subtitle: issueTitle,
      rows: detailsRows,
      // link: getCachedIssueUrl?.(r_repoOwner, r_repo, r_issueNumber) || null,
    });
  });

  return row;
}

function openBountyDetailsPopover(anchorBtnEl, data) {
  if (!bountyPopoverEl) return;

  const title = data.title || "Details";
  const subtitle = data.subtitle
    ? `<div class="mono" style="opacity:.9; margin-bottom:8px;">${escapeHtml(data.subtitle)}</div>`
    : "";

  const rowsHtml = (data.rows || [])
    .map(([k, v]) => `<div class="details-k">${escapeHtml(k)}</div><div class="details-v">${escapeHtml(v)}</div>`)
    .join("");

  bountyPopoverEl.innerHTML = `
    <div style="font-weight:700; margin-bottom:6px;">${escapeHtml(title)}</div>
    ${subtitle}
    <div class="details-grid">${rowsHtml}</div>
  `;

  bountyPopoverEl.hidden = false;

  const btnRect = anchorBtnEl.getBoundingClientRect();
  const popW = Math.min(520, window.innerWidth - 24);
  bountyPopoverEl.style.width = popW + "px";

  const margin = 10;
  let left = Math.min(btnRect.right - popW, window.innerWidth - popW - margin);
  left = Math.max(margin, left);

  let top = btnRect.bottom + 8;
  const maxTop = window.innerHeight - bountyPopoverEl.offsetHeight - margin;
  if (top > maxTop) top = Math.max(margin, btnRect.top - bountyPopoverEl.offsetHeight - 8);

  bountyPopoverEl.style.left = `${left}px`;
  bountyPopoverEl.style.top = `${top}px`;

  bountyPopoverEl.addEventListener("pointerdown", (e) => e.stopPropagation());

  if (!popoverOutsideHandlerBound) {
    popoverOutsideHandlerBound = true;
    window.addEventListener("pointerdown", () => {
      if (!bountyPopoverEl.hidden) bountyPopoverEl.hidden = true;
    });
  }
}

/* =====================================================================
   14) STARTUP
===================================================================== */

async function startup() {
  setRefreshLoading(true);
  setListLoading(true);

  initFactoryHeaderUI();

  const ok = await initReadProvider();

  if (ok) {
    await loadBountiesView();
  } else {
    setRefreshLoading(false);
    setListLoading(false);
  }
}

startup();
