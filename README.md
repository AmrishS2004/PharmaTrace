# PharmaTrace

A blockchain-based provenance system for pharmaceutical supply chains, built for CSE 540: Engineering Blockchain Applications (Team 19, Fall 2026).

**Team:** Nandita Ramakrishnan, Prithiv Vijayasekar, Amrish Sasikumar, Asmi Mangesh Kocharekar

## Project description

Medicines pass through manufacturers, distributors and pharmacies, and each of them usually keeps its own records. That makes it hard to confirm where a batch came from, who handled it, or whether a package is counterfeit.

PharmaTrace keeps one shared record on a blockchain. Each medicine batch gets a unique ID when the manufacturer registers it. Every step after that (shipment, receipt, dispensing and recall) is recorded by a Solidity smart contract on the Polygon Amoy testnet. Any participant, or a consumer holding the package, can look up the batch ID and see its full chain of custody without trusting a single company's database.

Main features:

- **Role-based permissions:** the admin assigns wallets as Manufacturer, Distributor or Pharmacy, and each function checks the caller's role.
- **Batch registration:** manufacturers register batches with an ID, drug name, manufacture date and expiry date.
- **Custody transfer:** a two-step ship and receive handoff, so custody only changes when the receiver confirms delivery. Batches can only move downstream (Manufacturer to Distributor to Pharmacy).
- **Status updates:** pharmacies mark batches as dispensed, and manufacturers can recall a batch.
- **Provenance verification:** anyone can check a batch ID. An unregistered ID is flagged as a possible counterfeit.
- **Event logging:** every step emits an event and is stored in an on-chain history.

## Repository structure

```
PharmaTrace/
├── contracts/
│   ├── IPharmaTrace.sol      # Interface: enums, structs, events, function signatures
│   └── PharmaTrace.sol       # Draft implementation of the contract
├── frontend/
│   ├── index.html            # Web interface with a section per role
│   ├── app.js                # MetaMask connection and contract calls (ethers.js)
│   ├── style.css             # Basic styling
│   └── abi/PharmaTrace.json  # Contract ABI used by the frontend
├── docs/
│   └── architecture.md       # Components, lifecycle and design decisions
└── README.md
```

## Dependencies

| Tool | Purpose |
| --- | --- |
| [Remix IDE](https://remix.ethereum.org) | Compile and deploy the contract in the browser |
| Solidity 0.8.20 or newer | Contract language (tested with 0.8.24) |
| [MetaMask](https://metamask.io) | Wallet for signing transactions |
| Polygon Amoy testnet | Test network, no real cryptocurrency needed |
| Test POL from the [Polygon faucet](https://faucet.polygon.technology) | Pays gas on Amoy |
| [ethers.js 6](https://docs.ethers.org/v6/) | Frontend library, loaded from a CDN, no install needed |
| Python 3 or any static file server | Serves the frontend locally |

No Node.js packages are required for the current draft.

## Setup

1. Install MetaMask in your browser and create at least four test accounts: admin, manufacturer, distributor and pharmacy.
2. Add Polygon Amoy to MetaMask. The frontend can add it for you, or add it manually:
   - Network name: Polygon Amoy Testnet
   - RPC URL: `https://rpc-amoy.polygon.technology`
   - Chain ID: `80002`
   - Currency symbol: `POL`
   - Explorer: `https://amoy.polygonscan.com`
3. Get test POL from the Polygon faucet for each account.

## Deploying the contract

1. Open [Remix](https://remix.ethereum.org) and upload both files from `contracts/`.
2. In the Solidity Compiler tab, pick version 0.8.20 or newer and compile `PharmaTrace.sol`.
3. In the Deploy tab, set Environment to **Injected Provider - MetaMask** and make sure MetaMask is on Amoy with the admin account selected.
4. Deploy `PharmaTrace`. The deploying account becomes the admin.
5. Copy the deployed contract address.
6. As the admin, call `grantRole` for each test account: `1` = Manufacturer, `2` = Distributor, `3` = Pharmacy.

You can also test everything without MetaMask by choosing the **Remix VM** environment, which gives you free test accounts.

## Running the frontend

1. Paste the deployed address into `CONTRACT_ADDRESS` at the top of `frontend/app.js`.
2. Serve the folder (the page loads the ABI with `fetch`, so opening the file directly will not work):
   ```
   cd frontend
   python3 -m http.server 8000
   ```
3. Open `http://localhost:8000` and click **Connect MetaMask**. The page shows only the forms for the connected account's role.

## Usage walkthrough

1. **Manufacturer** registers batch `PT-2026-0001` and ships it to a distributor's address.
2. **Distributor** confirms delivery with **Receive**, then ships it to a pharmacy (or another distributor).
3. **Pharmacy** confirms delivery, then marks the batch as **Dispensed**.
4. **Anyone** enters `PT-2026-0001` in **Verify a batch** to see its status, current holder and full history.

If something goes wrong with a batch, the original manufacturer can **Recall** it. A recalled batch can no longer be shipped or dispensed.

## Contract interface summary

| Function | Caller | What it does |
| --- | --- | --- |
| `grantRole(address, Role)` | Admin | Assigns a role to a wallet |
| `revokeRole(address)` | Admin | Removes a wallet's role |
| `registerBatch(batchId, drugName, manufactureDate, expiryDate)` | Manufacturer | Creates a new batch |
| `shipBatch(batchId, to, note)` | Current custodian | Starts a handoff to the next party |
| `receiveBatch(batchId)` | Pending receiver | Confirms delivery and takes custody |
| `dispenseBatch(batchId)` | Pharmacy holding the batch | Marks the batch as dispensed |
| `recallBatch(batchId, reason)` | Original manufacturer | Flags the batch as recalled |
| `verifyBatch(batchId)` | Anyone | Returns registration status, status, manufacturer, custodian, expiry |
| `getBatchHistory(batchId)` | Anyone | Returns every custody step, oldest first |

Full details are in [`contracts/IPharmaTrace.sol`](contracts/IPharmaTrace.sol) and [`docs/architecture.md`](docs/architecture.md).

## Project status

This is the design-milestone draft. The contract interface and core workflow are in place and compile without warnings. Planned next steps:

- Deploy to Amoy and record the contract address here.
- Unit tests for each role and for unauthorized actions.
- Friendlier error messages and live updates in the frontend.
- Decide how to handle expired batches.

## References

1. U.S. Food and Drug Administration, "Drug Supply Chain Security Act (DSCSA)," 2025.
2. S. S. Gomasta et al., "PharmaChain: Blockchain-based drug supply chain provenance verification system," *Heliyon*, vol. 9, no. 7, 2023.
3. A. Padma and M. Ramaiah, "Blockchain based solution for secure information sharing in pharma supply chain management," *Heliyon*, vol. 10, no. 22, 2024.
