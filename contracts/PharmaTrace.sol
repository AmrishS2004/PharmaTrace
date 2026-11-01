// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPharmaTrace.sol";

/**
 * @title PharmaTrace
 * @notice Draft implementation of the PharmaTrace provenance contract.
 *
 * How it fits together:
 *   1. Role management   - the deployer (admin) registers which wallets belong
 *                          to manufacturers, distributors and pharmacies.
 *   2. Batch registry    - a manufacturer registers a batch with a unique ID.
 *   3. Custody transfer  - batches move through a two-step ship/receive
 *                          handoff, so custody only changes when the receiver
 *                          confirms delivery.
 *   4. Status updates    - dispensing and recalls change the batch status.
 *   5. Provenance log    - every step is appended to an on-chain history and
 *                          emitted as an event for the web interface.
 *   6. Verification      - anyone (including consumers with no role) can look
 *                          up a batch ID and see its status and history.
 *
 * Status: draft for the design milestone. Core flow is implemented; items
 * marked TODO are planned for the next milestone.
 */
contract PharmaTrace is IPharmaTrace {
    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    /// Deployer of the contract. Only the admin can assign roles.
    address public immutable admin;

    /// Role assigned to each wallet.
    mapping(address => Role) private roles;

    /// Batches are stored by keccak256(batchId) so lookups by the string ID
    /// printed on the package are cheap and fixed size.
    mapping(bytes32 => Batch) private batches;

    /// Provenance trail for each batch, oldest step first.
    mapping(bytes32 => CustodyRecord[]) private histories;

    /// All registered batch keys, kept so the frontend can list batches.
    bytes32[] private batchKeys;

    // ------------------------------------------------------------------
    // Errors (cheaper than revert strings and easier to read in Remix)
    // ------------------------------------------------------------------

    error NotAdmin();
    error WrongRole(Role required, Role actual);
    error BatchAlreadyExists(string batchId);
    error BatchNotFound(string batchId);
    error NotCustodian();
    error NotPendingReceiver();
    error InvalidStatus(Status current);
    error InvalidRoute(Role fromRole, Role toRole);
    error InvalidInput(string reason);

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyRole(Role required) {
        Role actual = roles[msg.sender];
        if (actual != required) revert WrongRole(required, actual);
        _;
    }

    /// Resolves a batch ID to its storage key and reverts if it does not exist.
    modifier batchExists(string calldata batchId) {
        if (batches[_key(batchId)].status == Status.None) revert BatchNotFound(batchId);
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    // ------------------------------------------------------------------
    // Role management
    // ------------------------------------------------------------------

    /// @inheritdoc IPharmaTrace
    function grantRole(address account, Role role) external onlyAdmin {
        if (account == address(0)) revert InvalidInput("zero address");
        if (role == Role.None) revert InvalidInput("use revokeRole");
        roles[account] = role;
        emit RoleGranted(account, role, msg.sender);
    }

    /// @inheritdoc IPharmaTrace
    function revokeRole(address account) external onlyAdmin {
        Role previous = roles[account];
        roles[account] = Role.None;
        emit RoleRevoked(account, previous, msg.sender);
    }

    /// @inheritdoc IPharmaTrace
    function getRole(address account) external view returns (Role) {
        return roles[account];
    }

    // ------------------------------------------------------------------
    // Batch lifecycle
    // ------------------------------------------------------------------

    /// @inheritdoc IPharmaTrace
    function registerBatch(
        string calldata batchId,
        string calldata drugName,
        uint64 manufactureDate,
        uint64 expiryDate
    ) external onlyRole(Role.Manufacturer) {
        if (bytes(batchId).length == 0) revert InvalidInput("empty batchId");
        if (expiryDate <= manufactureDate) revert InvalidInput("expiry before manufacture");

        bytes32 key = _key(batchId);
        if (batches[key].status != Status.None) revert BatchAlreadyExists(batchId);

        batches[key] = Batch({
            batchId: batchId,
            drugName: drugName,
            manufacturer: msg.sender,
            currentCustodian: msg.sender,
            pendingCustodian: address(0),
            manufactureDate: manufactureDate,
            expiryDate: expiryDate,
            status: Status.Registered,
            registeredAt: block.timestamp
        });
        batchKeys.push(key);

        _record(key, Status.Registered, address(0), msg.sender, "registered");
        emit BatchRegistered(key, batchId, drugName, msg.sender);
    }

    /// @inheritdoc IPharmaTrace
    function shipBatch(string calldata batchId, address to, string calldata note)
        external
        batchExists(batchId)
    {
        bytes32 key = _key(batchId);
        Batch storage b = batches[key];

        if (b.currentCustodian != msg.sender) revert NotCustodian();
        // A batch can only leave a custodian once it is fully in their hands.
        if (b.status != Status.Registered && b.status != Status.Received) revert InvalidStatus(b.status);

        // Enforce the supply-chain route based on the roles of sender and receiver.
        Role fromRole = roles[msg.sender];
        Role toRole = roles[to];
        if (!_isAllowedRoute(fromRole, toRole)) revert InvalidRoute(fromRole, toRole);

        b.pendingCustodian = to;
        b.status = Status.InTransit;

        _record(key, Status.InTransit, msg.sender, to, note);
        emit BatchShipped(key, msg.sender, to, note);
    }

    /// @inheritdoc IPharmaTrace
    function receiveBatch(string calldata batchId) external batchExists(batchId) {
        bytes32 key = _key(batchId);
        Batch storage b = batches[key];

        if (b.status != Status.InTransit) revert InvalidStatus(b.status);
        if (b.pendingCustodian != msg.sender) revert NotPendingReceiver();

        address previous = b.currentCustodian;
        b.currentCustodian = msg.sender;
        b.pendingCustodian = address(0);
        b.status = Status.Received;

        _record(key, Status.Received, previous, msg.sender, "received");
        emit BatchReceived(key, previous, msg.sender);
    }

    /// @inheritdoc IPharmaTrace
    function dispenseBatch(string calldata batchId)
        external
        onlyRole(Role.Pharmacy)
        batchExists(batchId)
    {
        bytes32 key = _key(batchId);
        Batch storage b = batches[key];

        if (b.currentCustodian != msg.sender) revert NotCustodian();
        if (b.status != Status.Received) revert InvalidStatus(b.status);
        // TODO (next milestone): decide whether expired batches should be
        // blocked here, e.g. require(block.timestamp < b.expiryDate).

        b.status = Status.Dispensed;

        _record(key, Status.Dispensed, msg.sender, msg.sender, "dispensed");
        emit BatchDispensed(key, msg.sender);
    }

    /// @inheritdoc IPharmaTrace
    function recallBatch(string calldata batchId, string calldata reason)
        external
        onlyRole(Role.Manufacturer)
        batchExists(batchId)
    {
        bytes32 key = _key(batchId);
        Batch storage b = batches[key];

        // Only the manufacturer that registered the batch can recall it.
        if (b.manufacturer != msg.sender) revert NotCustodian();
        if (b.status == Status.Dispensed || b.status == Status.Recalled) revert InvalidStatus(b.status);

        b.status = Status.Recalled;
        b.pendingCustodian = address(0);

        _record(key, Status.Recalled, b.currentCustodian, b.currentCustodian, reason);
        emit BatchRecalled(key, msg.sender, reason);
    }

    // ------------------------------------------------------------------
    // Verification and queries
    // ------------------------------------------------------------------

    /// @inheritdoc IPharmaTrace
    function verifyBatch(string calldata batchId)
        external
        view
        returns (bool isRegistered, Status status, address manufacturer, address currentCustodian, uint64 expiryDate)
    {
        Batch storage b = batches[_key(batchId)];
        isRegistered = b.status != Status.None;
        return (isRegistered, b.status, b.manufacturer, b.currentCustodian, b.expiryDate);
    }

    /// @inheritdoc IPharmaTrace
    function getBatch(string calldata batchId) external view batchExists(batchId) returns (Batch memory) {
        return batches[_key(batchId)];
    }

    /// @inheritdoc IPharmaTrace
    function getBatchHistory(string calldata batchId)
        external
        view
        batchExists(batchId)
        returns (CustodyRecord[] memory)
    {
        // TODO (next milestone): add pagination if histories get long.
        return histories[_key(batchId)];
    }

    /// @inheritdoc IPharmaTrace
    function totalBatches() external view returns (uint256) {
        return batchKeys.length;
    }

    /// Returns the batch ID at a given index, so the frontend can list all batches.
    function batchIdAt(uint256 index) external view returns (string memory) {
        return batches[batchKeys[index]].batchId;
    }

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------

    /// Storage key for a batch ID.
    function _key(string calldata batchId) private pure returns (bytes32) {
        return keccak256(bytes(batchId));
    }

    /// Supply-chain routing rules. Batches flow downstream only:
    /// Manufacturer -> Distributor -> (other Distributors) -> Pharmacy.
    function _isAllowedRoute(Role fromRole, Role toRole) private pure returns (bool) {
        if (fromRole == Role.Manufacturer) return toRole == Role.Distributor;
        if (fromRole == Role.Distributor) return toRole == Role.Distributor || toRole == Role.Pharmacy;
        return false;
    }

    /// Appends one step to a batch's provenance trail.
    function _record(bytes32 key, Status status, address from, address to, string memory note) private {
        histories[key].push(
            CustodyRecord({status: status, actor: msg.sender, from: from, to: to, timestamp: block.timestamp, note: note})
        );
    }
}
