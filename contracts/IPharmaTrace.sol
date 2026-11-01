// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPharmaTrace
 * @notice Interface for the PharmaTrace provenance contract.
 *
 * PharmaTrace tracks pharmaceutical batches as they move from a manufacturer,
 * through one or more distributors, to a pharmacy. Every batch gets a unique ID,
 * and every important event (registration, shipment, receipt, dispensing, recall)
 * is stored on-chain so any participant or consumer can verify where a batch
 * came from and who has held it.
 *
 * This file only defines the shared types, events and function signatures.
 * The implementation lives in PharmaTrace.sol.
 */
interface IPharmaTrace {
    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------

    /// Roles a wallet address can hold. Consumers do not need a role,
    /// because verifying a batch is a read-only call anyone can make.
    enum Role {
        None,
        Manufacturer,
        Distributor,
        Pharmacy
    }

    /// Lifecycle of a batch. A batch normally moves
    /// Registered -> InTransit -> Received -> (InTransit -> Received)* -> Dispensed.
    /// Recalled can be set by the manufacturer at any point before Dispensed.
    enum Status {
        None,
        Registered,
        InTransit,
        Received,
        Dispensed,
        Recalled
    }

    /// Current state of a batch.
    struct Batch {
        string batchId;          // human-readable ID printed on the package, e.g. "PT-2026-0001"
        string drugName;         // product name, e.g. "Amoxicillin 500mg"
        address manufacturer;    // wallet that registered the batch
        address currentCustodian;// wallet currently holding the batch
        address pendingCustodian;// receiver of an in-progress shipment, zero if none
        uint64 manufactureDate;  // unix timestamp
        uint64 expiryDate;       // unix timestamp
        Status status;
        uint256 registeredAt;    // block timestamp of registration
    }

    /// One entry in a batch's provenance history.
    struct CustodyRecord {
        Status status;   // status after this step
        address actor;   // wallet that triggered the step
        address from;    // custodian before the step
        address to;      // custodian (or pending custodian) after the step
        uint256 timestamp;
        string note;     // optional free text, e.g. shipment reference or recall reason
    }

    // ------------------------------------------------------------------
    // Events (the frontend listens to these to show live updates)
    // ------------------------------------------------------------------

    event RoleGranted(address indexed account, Role role, address indexed grantedBy);
    event RoleRevoked(address indexed account, Role previousRole, address indexed revokedBy);

    event BatchRegistered(bytes32 indexed batchKey, string batchId, string drugName, address indexed manufacturer);
    event BatchShipped(bytes32 indexed batchKey, address indexed from, address indexed to, string note);
    event BatchReceived(bytes32 indexed batchKey, address indexed from, address indexed to);
    event BatchDispensed(bytes32 indexed batchKey, address indexed pharmacy);
    event BatchRecalled(bytes32 indexed batchKey, address indexed manufacturer, string reason);

    // ------------------------------------------------------------------
    // Role management (admin only)
    // ------------------------------------------------------------------

    /// Assign a supply-chain role to a wallet. Only the admin (deployer) can call this.
    function grantRole(address account, Role role) external;

    /// Remove a wallet's role. Only the admin can call this.
    function revokeRole(address account) external;

    /// Look up the role of any wallet.
    function getRole(address account) external view returns (Role);

    // ------------------------------------------------------------------
    // Batch lifecycle (write functions)
    // ------------------------------------------------------------------

    /// Manufacturer creates a new batch. The caller becomes both the
    /// manufacturer and the first custodian. Fails if the ID already exists.
    function registerBatch(
        string calldata batchId,
        string calldata drugName,
        uint64 manufactureDate,
        uint64 expiryDate
    ) external;

    /// Current custodian sends the batch to the next party. This starts a
    /// two-step handoff: custody only moves once the receiver confirms.
    /// Allowed routes: Manufacturer -> Distributor, Distributor -> Distributor,
    /// Distributor -> Pharmacy.
    function shipBatch(string calldata batchId, address to, string calldata note) external;

    /// The pending receiver confirms delivery, which makes them the custodian.
    function receiveBatch(string calldata batchId) external;

    /// A pharmacy holding the batch marks it as dispensed to patients.
    /// This is the final state.
    function dispenseBatch(string calldata batchId) external;

    /// The original manufacturer flags a batch as recalled (for example, a
    /// quality problem). A recalled batch can no longer be shipped or dispensed.
    function recallBatch(string calldata batchId, string calldata reason) external;

    // ------------------------------------------------------------------
    // Verification and queries (read-only, anyone can call)
    // ------------------------------------------------------------------

    /// Quick check a consumer or pharmacy can run on a batch ID.
    /// `isRegistered` is false for IDs that were never registered, which is
    /// a sign of a possible counterfeit.
    function verifyBatch(string calldata batchId)
        external
        view
        returns (bool isRegistered, Status status, address manufacturer, address currentCustodian, uint64 expiryDate);

    /// Full current record of a batch.
    function getBatch(string calldata batchId) external view returns (Batch memory);

    /// Complete provenance trail, oldest step first.
    function getBatchHistory(string calldata batchId) external view returns (CustodyRecord[] memory);

    /// Number of batches registered so far.
    function totalBatches() external view returns (uint256);
}
