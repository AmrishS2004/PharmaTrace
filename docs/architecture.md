# PharmaTrace Architecture

## Components

| Layer | Component | Where it runs | Responsibility |
| --- | --- | --- | --- |
| Off-chain | Web interface (`frontend/`) | User's browser | Forms for each role, batch verification page |
| Off-chain | MetaMask | User's browser | Holds keys, signs transactions |
| On-chain | `PharmaTrace.sol` | Polygon Amoy testnet | Roles, batch records, custody transfers, history, events |

Only provenance data is stored on-chain: batch ID, drug name, dates, status, custodian and the history of custody steps. Everything else (UI, input checks for usability) stays off-chain.

## Contract components

| Component | Functions | Who can call |
| --- | --- | --- |
| Role management | `grantRole`, `revokeRole`, `getRole` | Admin (deployer); `getRole` is public |
| Batch registry | `registerBatch` | Manufacturer |
| Custody transfer | `shipBatch`, `receiveBatch` | Current custodian ships, named receiver confirms |
| Status updates | `dispenseBatch`, `recallBatch` | Pharmacy dispenses; original manufacturer recalls |
| Verification | `verifyBatch`, `getBatch`, `getBatchHistory`, `totalBatches`, `batchIdAt` | Anyone |

## Batch lifecycle

```
registerBatch          shipBatch           receiveBatch        dispenseBatch
 (Manufacturer)  -->  (custodian)   -->   (receiver)    -->   (Pharmacy)
  Registered          InTransit           Received            Dispensed
                          ^                   |
                          |___ shipBatch _____|   (Distributor to Distributor or Pharmacy)

recallBatch (original Manufacturer): any state except Dispensed  -->  Recalled
```

## Allowed shipping routes

| From | To |
| --- | --- |
| Manufacturer | Distributor |
| Distributor | Distributor, Pharmacy |
| Pharmacy | (none, pharmacies dispense) |

## Why a two-step handoff

`shipBatch` alone does not move custody. The receiver has to call `receiveBatch`, so a sender cannot push responsibility onto someone who never got the goods, and the history shows both the shipment and the confirmed delivery.

## Planned for later milestones

- Decide whether expired batches should be blocked from dispensing.
- Pagination for long histories.
- Live updates in the UI from contract events.
- Read-only verification without a wallet, through a public RPC.
- Optional off-chain storage (for example IPFS) for documents like certificates, with only a hash on-chain.
