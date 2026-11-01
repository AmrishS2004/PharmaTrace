/*
 * PharmaTrace frontend logic (draft).
 *
 * Responsibilities:
 *   - Connect to MetaMask and make sure the wallet is on Polygon Amoy.
 *   - Read the connected wallet's role and show only the matching sections.
 *   - Send transactions for each lifecycle step (register, ship, receive,
 *     dispense, recall) and show the result.
 *   - Let anyone verify a batch and see its full custody history.
 *
 * Before running: deploy contracts/PharmaTrace.sol with Remix and paste the
 * deployed address into CONTRACT_ADDRESS below.
 */

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000"; // TODO: set after deployment

// Polygon Amoy testnet details used when asking MetaMask to switch networks.
const AMOY = {
  chainId: "0x13882", // 80002
  chainName: "Polygon Amoy Testnet",
  nativeCurrency: { name: "POL", symbol: "POL", decimals: 18 },
  rpcUrls: ["https://rpc-amoy.polygon.technology"],
  blockExplorerUrls: ["https://amoy.polygonscan.com"],
};

// These must match the enums in contracts/IPharmaTrace.sol.
const ROLE_NAMES = ["None", "Manufacturer", "Distributor", "Pharmacy"];
const STATUS_NAMES = ["None", "Registered", "InTransit", "Received", "Dispensed", "Recalled"];

let provider; // read access through MetaMask
let signer;   // the connected account, used to send transactions
let contract; // PharmaTrace contract bound to the signer
let abi;      // loaded from abi/PharmaTrace.json

// ---------------------------------------------------------------------------
// Wallet connection
// ---------------------------------------------------------------------------

/** Connects MetaMask, switches to Amoy, loads the contract and the user's role. */
async function connectWallet() {
  if (!window.ethereum) {
    setStatus("MetaMask not found. Install it to use PharmaTrace.");
    return;
  }
  await window.ethereum.request({ method: "eth_requestAccounts" });
  await switchToAmoy();

  provider = new ethers.BrowserProvider(window.ethereum);
  signer = await provider.getSigner();
  abi = abi || (await (await fetch("abi/PharmaTrace.json")).json());
  contract = new ethers.Contract(CONTRACT_ADDRESS, abi, signer);

  const address = await signer.getAddress();
  const role = Number(await contract.getRole(address));
  const admin = await contract.admin();
  const isAdmin = admin.toLowerCase() === address.toLowerCase();

  document.getElementById("walletInfo").textContent =
    `${address} | Role: ${ROLE_NAMES[role]}${isAdmin ? " (admin)" : ""}`;
  showSectionsForRole(role, isAdmin);
}

/** Asks MetaMask to switch to Polygon Amoy, adding the network if needed. */
async function switchToAmoy() {
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: AMOY.chainId }] });
  } catch (err) {
    if (err.code === 4902) {
      await window.ethereum.request({ method: "wallet_addEthereumChain", params: [AMOY] });
    } else {
      throw err;
    }
  }
}

/** Shows only the forms the connected role is allowed to use. */
function showSectionsForRole(role, isAdmin) {
  const show = (id, visible) => (document.getElementById(id).hidden = !visible);
  show("adminSection", isAdmin);
  show("manufacturerSection", role === 1);
  show("shipSection", role === 1 || role === 2);
  show("receiveSection", role === 2 || role === 3);
  show("pharmacySection", role === 3);
}

// ---------------------------------------------------------------------------
// Write actions (each one sends a transaction through MetaMask)
// ---------------------------------------------------------------------------

/** Wraps a contract call: sends it, waits for it to be mined, reports the result. */
async function sendTx(label, txPromise) {
  try {
    setStatus(`${label}: waiting for MetaMask...`);
    const tx = await txPromise;
    setStatus(`${label}: submitted, waiting for confirmation...`);
    await tx.wait();
    setStatus(`${label}: confirmed (tx ${tx.hash})`);
  } catch (err) {
    // TODO: decode custom errors (WrongRole, NotCustodian, ...) into friendly messages.
    setStatus(`${label} failed: ${err.shortMessage || err.message}`);
  }
}

const val = (id) => document.getElementById(id).value.trim();
const toUnix = (dateStr) => Math.floor(new Date(dateStr).getTime() / 1000);

function grantRole()   { return sendTx("Grant role", contract.grantRole(val("roleAddress"), Number(val("roleSelect")))); }
function revokeRole()  { return sendTx("Revoke role", contract.revokeRole(val("roleAddress"))); }
function registerBatch() {
  return sendTx("Register", contract.registerBatch(val("regId"), val("regDrug"), toUnix(val("regMfgDate")), toUnix(val("regExpDate"))));
}
function shipBatch()     { return sendTx("Ship", contract.shipBatch(val("shipId"), val("shipTo"), val("shipNote"))); }
function receiveBatch()  { return sendTx("Receive", contract.receiveBatch(val("receiveId"))); }
function dispenseBatch() { return sendTx("Dispense", contract.dispenseBatch(val("dispenseId"))); }
function recallBatch()   { return sendTx("Recall", contract.recallBatch(val("recallId"), val("recallReason"))); }

// ---------------------------------------------------------------------------
// Verification (read-only, no gas needed)
// ---------------------------------------------------------------------------

/** Looks up a batch and renders its status and custody history. */
async function verifyBatch() {
  const id = val("verifyId");
  const result = document.getElementById("verifyResult");
  const list = document.getElementById("historyList");
  list.innerHTML = "";

  const [isRegistered, status, manufacturer, custodian, expiry] = await contract.verifyBatch(id);
  if (!isRegistered) {
    result.textContent = `Batch "${id}" is not registered. It may be counterfeit.`;
    return;
  }
  const expiryText = new Date(Number(expiry) * 1000).toLocaleDateString();
  result.textContent =
    `Status: ${STATUS_NAMES[Number(status)]} | Manufacturer: ${manufacturer} | Custodian: ${custodian} | Expires: ${expiryText}`;

  const history = await contract.getBatchHistory(id);
  for (const step of history) {
    const li = document.createElement("li");
    const when = new Date(Number(step.timestamp) * 1000).toLocaleString();
    li.textContent = `${when}: ${STATUS_NAMES[Number(step.status)]} by ${step.actor}${step.note ? ` (${step.note})` : ""}`;
    list.appendChild(li);
  }
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

function setStatus(msg) {
  document.getElementById("txStatus").textContent = msg;
}

document.getElementById("connectBtn").onclick = connectWallet;
document.getElementById("verifyBtn").onclick = verifyBatch;
document.getElementById("grantBtn").onclick = grantRole;
document.getElementById("revokeBtn").onclick = revokeRole;
document.getElementById("registerBtn").onclick = registerBatch;
document.getElementById("shipBtn").onclick = shipBatch;
document.getElementById("receiveBtn").onclick = receiveBatch;
document.getElementById("dispenseBtn").onclick = dispenseBatch;
document.getElementById("recallBtn").onclick = recallBatch;

// TODO (next milestone): listen to contract events (BatchShipped, BatchReceived, ...)
// with contract.on(...) so the page updates without refreshing.
// TODO: let consumers verify without connecting a wallet by using a public
// Amoy RPC provider for read-only calls.
