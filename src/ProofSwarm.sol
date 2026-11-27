// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title ProofSwarm
/// @notice Coordination ledger for a swarm of at most 200 agents working on Lean 4 units handed out by an
///         external proof desk. It enforces the swarm's own rules (role allocation, five live leases per
///         account, 45 minute renewals, six hour lease lifetime, independent review, one proof file per pull
///         request, no duplicate submissions, an approved budget) and keeps the figures the swarm reports:
///         participating agents, validated proofs, accepted contributions, points and costs.
/// @dev    The contract holds no funds and calls no other contract. It cannot run Lean: a proof is represented
///         by hashes, and every statement about a proof is an attestation by a registered agent. Nothing
///         recorded here is a mathematical result; only the external checker decides that.
contract ProofSwarm {
    // ------------------------------------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------------------------------------

    enum Role {
        None,
        ProofDevelopment,
        CounterexampleResearch,
        ComputationalComplexity,
        LeanVerification,
        MathematicalReductions,
        TacticDevelopment,
        IndependentReviewer,
        Coordinator
    }

    enum UnitStatus {
        None,
        Open,
        Leased,
        InReview,
        Validated,
        Submitted,
        Accepted,
        Withdrawn
    }

    enum Level {
        Warmup,
        Solid,
        Hard,
        Open
    }

    enum Kind {
        Prove,
        Refute,
        Search,
        Cut,
        Value
    }

    enum ReleaseReason {
        None,
        HypothesisTooWeak,
        MissingLemma,
        StatementSeemsFalse,
        DoesNotElaborate,
        OutOfTime,
        Other,
        Reduced,
        Exhausted,
        Submitted
    }

    enum RejectReason {
        None,
        ContainsSorry,
        NativeDecide,
        UnauthorizedAxiom,
        AlteredStatement,
        WrongTheoremOrPath,
        ForbiddenImport,
        DoesNotBuild,
        Other
    }

    struct Agent {
        Role role;
        bool participated;
        bytes32 account;
        uint256 cost;
    }

    struct AccountStats {
        uint32 activeLeases;
        uint32 leasesTaken;
        uint32 released;
        uint32 expired;
        uint32 validated;
        uint32 reviewRejections;
        uint32 pullRequests;
        uint32 accepted;
        uint32 rejected;
        uint64 points;
        uint256 cost;
    }

    /// @param statementHash keccak256 of the exact Lean statement the desk posted.
    /// @param targetHash    keccak256 of the required file path and theorem name.
    /// @param importsHash   keccak256 of the list of imports the unit permits.
    /// @param price         the unit's price in points, as the desk computed it.
    /// @param reductions    whether the desk opened the unit to reductions.
    struct UnitSpec {
        bytes32 statementHash;
        bytes32 targetHash;
        bytes32 importsHash;
        uint64 price;
        Level level;
        Kind kind;
        bool reductions;
    }

    struct Unit {
        UnitStatus status;
        uint64 openedAt;
        address lastHolder;
        UnitSpec spec;
    }

    struct Lease {
        address agent;
        uint64 leasedAt;
        uint64 lastBeat;
        bytes32 account;
        uint64 price;
    }

    struct Submission {
        bytes32 fileHash;
        bytes32 account;
        address author;
        uint64 id;
        uint64 pullRequest;
        uint64 price;
        uint8 approvals;
    }

    struct SwarmReport {
        uint256 registeredAgents;
        uint256 participatingAgents;
        uint256 unitsPosted;
        uint256 leasesTaken;
        uint256 releases;
        uint256 expiries;
        uint256 validatedProofs;
        uint256 pullRequests;
        uint256 acceptedContributions;
        uint256 rejectedContributions;
        uint256 points;
        uint256 totalCost;
        uint256 approvedBudget;
    }

    // ------------------------------------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------------------------------------

    /// @notice Sum of the eight role caps.
    uint256 public constant MAX_AGENTS = 200;
    /// @notice Live leases one account may hold at a time.
    uint256 public constant MAX_ACTIVE_LEASES = 5;
    /// @notice A lease lapses unless renewed within this time of its last renewal.
    uint256 public constant RENEW_WINDOW = 45 minutes;
    /// @notice A lease lapses this long after it was taken, however often it was renewed.
    uint256 public constant MAX_LEASE_AGE = 6 hours;
    /// @notice After a release as OutOfTime or Other the same account waits this long for the same unit.
    uint256 public constant RELEASE_COOLDOWN = 1 hours;
    uint256 public constant MAX_PREFERENCE_WINDOW = 45 minutes;
    uint256 public constant MAX_REVIEW_QUORUM = 10;
    /// @notice The agent the mission prefers: IMD Agent #1927, whose IMD id is 50973. Its address is not
    ///         known to this contract until the owner sets `preferredAgent`.
    uint256 public constant PREFERRED_AGENT_NUMBER = 1927;
    uint256 public constant PREFERRED_AGENT_ID = 50973;

    // ------------------------------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------------------------------

    address public owner;

    /// @notice Approved budget, in the cost unit the owner chooses. Zero means not configured.
    uint256 public approvedBudget;
    /// @notice keccak256 of the pinned Lean toolchain and Mathlib revision. Zero means not configured.
    bytes32 public pinnedDependencies;
    /// @notice Address of the preferred agent. Zero means not configured: no unit is reserved.
    address public preferredAgent;
    /// @notice How long a newly opened unit is reserved for the preferred agent when it is available.
    uint64 public preferenceWindow = 5 minutes;
    /// @notice Approvals by distinct independent reviewer accounts a proof needs to be validated.
    uint8 public reviewQuorum = 2;

    uint256 public agentCount;
    mapping(Role => uint256) public roleCount;
    mapping(bytes32 => bool) public accountAuthorized;
    mapping(bytes32 => bool) public fileUsed;
    mapping(uint64 => bool) public pullRequestUsed;
    mapping(bytes32 => mapping(bytes32 => uint256)) public cooldownUntil;

    mapping(address => Agent) private _agents;
    mapping(bytes32 => AccountStats) private _accounts;
    mapping(bytes32 => Unit) private _units;
    mapping(bytes32 => Lease) private _leases;
    mapping(bytes32 => Submission) private _submissions;
    mapping(uint64 => mapping(bytes32 => bool)) private _reviewed;
    uint64 private _submissionNonce;
    SwarmReport private _totals;

    // ------------------------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------------------------

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ApprovedBudgetSet(uint256 previousBudget, uint256 newBudget);
    event PinnedDependenciesSet(bytes32 previousPin, bytes32 newPin);
    event ReviewQuorumSet(uint8 previousQuorum, uint8 newQuorum);
    event PreferredAgentSet(address indexed previousAgent, address indexed newAgent);
    event PreferenceWindowSet(uint64 previousWindow, uint64 newWindow);
    event AccountAuthorized(bytes32 indexed account);
    event AccountRevoked(bytes32 indexed account);
    event AgentRegistered(address indexed agent, Role role, bytes32 indexed account);
    event AgentRemoved(address indexed agent, Role role, bytes32 indexed account);
    event UnitPosted(bytes32 indexed unitId, UnitSpec spec);
    event UnitRepriced(bytes32 indexed unitId, uint64 previousPrice, uint64 newPrice);
    event UnitWithdrawn(bytes32 indexed unitId, address indexed coordinator, bytes32 evidence);
    event UnitLeased(
        bytes32 indexed unitId, address indexed agent, bytes32 indexed account, uint64 price, uint256 deadline
    );
    event LeaseRenewed(bytes32 indexed unitId, address indexed agent, uint256 deadline);
    event LeaseExpired(bytes32 indexed unitId, address indexed agent, bytes32 indexed account);
    event UnitReleased(
        bytes32 indexed unitId, address indexed agent, bytes32 indexed account, ReleaseReason reason, bytes32 evidence
    );
    event ProofSubmittedForReview(
        bytes32 indexed unitId, bytes32 indexed fileHash, address indexed author, uint64 submissionId
    );
    event ProofApproved(
        bytes32 indexed unitId, bytes32 indexed fileHash, address indexed reviewer, bytes32 checkerRunHash
    );
    event ProofRejected(
        bytes32 indexed unitId,
        bytes32 indexed fileHash,
        address indexed reviewer,
        RejectReason reason,
        bytes32 evidence
    );
    event ProofValidated(bytes32 indexed unitId, bytes32 indexed fileHash, uint8 approvals);
    event PullRequestRecorded(bytes32 indexed unitId, uint64 indexed pullRequest, bytes32 indexed fileHash);
    event VerdictRecorded(
        bytes32 indexed unitId, address indexed coordinator, bool accepted, uint64 points, bytes32 evidence
    );
    event CostReported(address indexed agent, bytes32 indexed account, uint256 amount, uint256 totalCost);

    // ------------------------------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------------------------------

    error NotOwner();
    error ZeroAddress();
    error ZeroValue();
    error OutOfBounds();
    error AccountNotAuthorized(bytes32 account);
    error AgentAlreadyRegistered(address agent);
    error AgentNotRegistered(address agent);
    error RoleFull(Role role);
    error InvalidRole();
    error WrongRole(Role actual);
    error BudgetNotConfigured();
    error BudgetExhausted(uint256 totalCost, uint256 approvedBudget);
    error PinsNotConfigured();
    error UnitExists(bytes32 unitId);
    error InvalidUnitSpec();
    error UnitNotInState(bytes32 unitId, UnitStatus actual);
    error LeaseLimitReached(bytes32 account);
    error ReleaseCooldownActive(uint256 notBefore);
    error ReservedForPreferredAgent(uint256 until);
    error NotLeaseHolder();
    error LeaseLapsed(uint256 deadline);
    error LeaseStillLive(uint256 deadline);
    error InvalidReleaseReason();
    error ReasonNotApplicable();
    error MissingEvidence();
    error DependencyPinMismatch();
    error AlteredStatement();
    error WrongTheoremOrPath();
    error ForbiddenImports();
    error DuplicateProofFile(bytes32 fileHash);
    error StaleReview(bytes32 currentFileHash);
    error ReviewerNotIndependent();
    error AlreadyReviewed();
    error InvalidRejectReason();
    error PullRequestAlreadyUsed(uint64 pullRequest);

    // ------------------------------------------------------------------------------------------------
    // Construction and ownership
    // ------------------------------------------------------------------------------------------------

    /// @param owner_ The swarm's owner. Never the deployer: a factory may deploy this contract.
    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ------------------------------------------------------------------------------------------------
    // Owner configuration
    // ------------------------------------------------------------------------------------------------

    /// @notice Sets the approved budget. Leasing is refused until it is set and once reported cost reaches it.
    function setApprovedBudget(uint256 newBudget) external onlyOwner {
        if (newBudget == 0) revert ZeroValue();
        emit ApprovedBudgetSet(approvedBudget, newBudget);
        approvedBudget = newBudget;
    }

    /// @notice Sets the hash of the pinned toolchain and Mathlib revision proofs must be built against.
    function setPinnedDependencies(bytes32 newPin) external onlyOwner {
        if (newPin == bytes32(0)) revert ZeroValue();
        emit PinnedDependenciesSet(pinnedDependencies, newPin);
        pinnedDependencies = newPin;
    }

    function setReviewQuorum(uint8 newQuorum) external onlyOwner {
        if (newQuorum == 0 || newQuorum > MAX_REVIEW_QUORUM) revert OutOfBounds();
        emit ReviewQuorumSet(reviewQuorum, newQuorum);
        reviewQuorum = newQuorum;
    }

    /// @notice Sets the address of the preferred agent (IMD Agent #1927, id 50973).
    function setPreferredAgent(address agent) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();
        emit PreferredAgentSet(preferredAgent, agent);
        preferredAgent = agent;
    }

    /// @notice Removes the preference, for when the preferred agent is not available.
    function clearPreferredAgent() external onlyOwner {
        emit PreferredAgentSet(preferredAgent, address(0));
        preferredAgent = address(0);
    }

    function setPreferenceWindow(uint64 newWindow) external onlyOwner {
        if (newWindow > MAX_PREFERENCE_WINDOW) revert OutOfBounds();
        emit PreferenceWindowSet(preferenceWindow, newWindow);
        preferenceWindow = newWindow;
    }

    /// @notice Authorizes a GitHub identity, named by `accountKey` of its handle.
    function authorizeAccount(bytes32 account) external onlyOwner {
        if (account == bytes32(0)) revert ZeroValue();
        accountAuthorized[account] = true;
        emit AccountAuthorized(account);
    }

    /// @notice Revokes a GitHub identity. Its agents can no longer act; their leases lapse on their own.
    function revokeAccount(bytes32 account) external onlyOwner {
        if (!accountAuthorized[account]) revert AccountNotAuthorized(account);
        accountAuthorized[account] = false;
        emit AccountRevoked(account);
    }

    /// @notice Registers an agent in a role, acting through an authorized account. Role caps are enforced.
    function registerAgent(address agent, Role role, bytes32 account) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();
        if (role == Role.None) revert InvalidRole();
        if (!accountAuthorized[account]) revert AccountNotAuthorized(account);
        Agent storage a = _agents[agent];
        if (a.role != Role.None) revert AgentAlreadyRegistered(agent);
        if (roleCount[role] >= roleCap(role)) revert RoleFull(role);
        roleCount[role] += 1;
        agentCount += 1;
        a.role = role;
        a.account = account;
        emit AgentRegistered(agent, role, account);
    }

    /// @notice Removes an agent. Leases it holds lapse on their own, as it can no longer renew them.
    function removeAgent(address agent) external onlyOwner {
        Agent storage a = _agents[agent];
        Role role = a.role;
        if (role == Role.None) revert AgentNotRegistered(agent);
        roleCount[role] -= 1;
        agentCount -= 1;
        a.role = Role.None;
        emit AgentRemoved(agent, role, a.account);
    }

    // ------------------------------------------------------------------------------------------------
    // Coordinators: mirror the desk
    // ------------------------------------------------------------------------------------------------

    /// @notice Records a unit the desk offers, with the hashes a proof of it is held to.
    function postUnit(bytes32 unitId, UnitSpec calldata spec) external {
        _touch(_requireRole(msg.sender, Role.Coordinator));
        if (unitId == bytes32(0)) revert ZeroValue();
        Unit storage u = _units[unitId];
        if (u.status != UnitStatus.None) revert UnitExists(unitId);
        if (
            spec.statementHash == bytes32(0) || spec.targetHash == bytes32(0) || spec.importsHash == bytes32(0)
                || spec.price == 0
        ) revert InvalidUnitSpec();
        u.status = UnitStatus.Open;
        u.openedAt = uint64(block.timestamp);
        u.spec = spec;
        _totals.unitsPosted += 1;
        emit UnitPosted(unitId, spec);
    }

    /// @notice Updates the price of an open unit. A lease keeps the price it was taken at.
    function repriceUnit(bytes32 unitId, uint64 newPrice) external {
        _touch(_requireRole(msg.sender, Role.Coordinator));
        if (newPrice == 0) revert ZeroValue();
        Unit storage u = _units[unitId];
        if (u.status != UnitStatus.Open) revert UnitNotInState(unitId, u.status);
        emit UnitRepriced(unitId, u.spec.price, newPrice);
        u.spec.price = newPrice;
    }

    /// @notice Stands a unit down, for when the desk withdrew it or someone outside the swarm proved it.
    function withdrawUnit(bytes32 unitId, bytes32 evidence) external {
        _touch(_requireRole(msg.sender, Role.Coordinator));
        if (evidence == bytes32(0)) revert MissingEvidence();
        Unit storage u = _units[unitId];
        UnitStatus status = u.status;
        if (status == UnitStatus.None || status == UnitStatus.Accepted || status == UnitStatus.Withdrawn) {
            revert UnitNotInState(unitId, status);
        }
        if (_holdsLease(status)) _clearLease(unitId, u);
        u.status = UnitStatus.Withdrawn;
        emit UnitWithdrawn(unitId, msg.sender, evidence);
    }

    /// @notice Records the official checker's verdict on a submitted pull request. Acceptance credits the
    ///         price frozen in the lease to the author's account.
    /// @param evidence Hash of the verdict's source, such as the merge commit or the checker run.
    function recordVerdict(bytes32 unitId, bool accepted, bytes32 evidence) external {
        Agent storage c = _requireRole(msg.sender, Role.Coordinator);
        if (evidence == bytes32(0)) revert MissingEvidence();
        Unit storage u = _units[unitId];
        if (u.status != UnitStatus.Submitted) revert UnitNotInState(unitId, u.status);
        Submission storage s = _submissions[unitId];
        if (c.account == s.account) revert ReviewerNotIndependent();
        _touch(c);
        AccountStats storage stats = _accounts[s.account];
        uint64 points;
        if (accepted) {
            points = s.price;
            u.status = UnitStatus.Accepted;
            stats.accepted += 1;
            stats.points += points;
            _totals.acceptedContributions += 1;
            _totals.points += points;
        } else {
            u.status = UnitStatus.Open;
            u.openedAt = uint64(block.timestamp);
            stats.rejected += 1;
            _totals.rejectedContributions += 1;
            delete _submissions[unitId];
        }
        emit VerdictRecorded(unitId, msg.sender, accepted, points, evidence);
    }

    // ------------------------------------------------------------------------------------------------
    // Working agents: leases
    // ------------------------------------------------------------------------------------------------

    /// @notice Takes an open unit. A lapsed lease on the unit is cleared first.
    function lease(bytes32 unitId) external {
        Agent storage a = _requireWorker(msg.sender);
        if (approvedBudget == 0) revert BudgetNotConfigured();
        if (_totals.totalCost >= approvedBudget) revert BudgetExhausted(_totals.totalCost, approvedBudget);
        Unit storage u = _units[unitId];
        if (_holdsLease(u.status) && !_live(_leases[unitId])) _expire(unitId, u);
        if (u.status != UnitStatus.Open) revert UnitNotInState(unitId, u.status);
        bytes32 account = a.account;
        AccountStats storage stats = _accounts[account];
        if (stats.activeLeases >= MAX_ACTIVE_LEASES) revert LeaseLimitReached(account);
        uint256 notBefore = cooldownUntil[unitId][account];
        if (block.timestamp < notBefore) revert ReleaseCooldownActive(notBefore);
        if (msg.sender != preferredAgent) {
            uint256 until = reservedUntil(unitId);
            if (block.timestamp < until) revert ReservedForPreferredAgent(until);
        }
        uint64 nowTs = uint64(block.timestamp);
        _leases[unitId] =
            Lease({agent: msg.sender, leasedAt: nowTs, lastBeat: nowTs, account: account, price: u.spec.price});
        u.status = UnitStatus.Leased;
        stats.activeLeases += 1;
        stats.leasesTaken += 1;
        _totals.leasesTaken += 1;
        _touch(a);
        emit UnitLeased(unitId, msg.sender, account, u.spec.price, _deadline(_leases[unitId]));
    }

    /// @notice Renews a live lease. It must be called within 45 minutes of the previous renewal, and it
    ///         cannot carry a lease past six hours of age.
    function renew(bytes32 unitId) external {
        _requireWorker(msg.sender);
        Lease storage l = _requireLiveHolder(unitId);
        l.lastBeat = uint64(block.timestamp);
        emit LeaseRenewed(unitId, msg.sender, _deadline(l));
    }

    /// @notice Hands a unit back with the reason it was not solved.
    /// @param evidence For Exhausted, the sha256 of the search program; otherwise optional.
    function release(bytes32 unitId, ReleaseReason reason, bytes32 evidence) external {
        Unit storage u = _units[unitId];
        if (!_holdsLease(u.status)) revert UnitNotInState(unitId, u.status);
        Lease storage l = _leases[unitId];
        if (l.agent != msg.sender) revert NotLeaseHolder();
        if (reason == ReleaseReason.None || reason == ReleaseReason.Submitted) revert InvalidReleaseReason();
        if (reason == ReleaseReason.Exhausted) {
            if (u.spec.kind != Kind.Search) revert ReasonNotApplicable();
            if (evidence == bytes32(0)) revert MissingEvidence();
        }
        if (reason == ReleaseReason.Reduced && !u.spec.reductions && u.spec.kind != Kind.Cut) {
            revert ReasonNotApplicable();
        }
        bytes32 account = l.account;
        if (reason == ReleaseReason.OutOfTime || reason == ReleaseReason.Other) {
            cooldownUntil[unitId][account] = block.timestamp + RELEASE_COOLDOWN;
        }
        _clearLease(unitId, u);
        _accounts[account].released += 1;
        _totals.releases += 1;
        emit UnitReleased(unitId, msg.sender, account, reason, evidence);
    }

    /// @notice Clears a lease that lapsed, so the unit is open again and the account's slot is free.
    function expireLease(bytes32 unitId) external {
        Unit storage u = _units[unitId];
        if (!_holdsLease(u.status)) revert UnitNotInState(unitId, u.status);
        Lease storage l = _leases[unitId];
        if (_live(l)) revert LeaseStillLive(_deadline(l));
        _expire(unitId, u);
    }

    // ------------------------------------------------------------------------------------------------
    // Working agents: proofs
    // ------------------------------------------------------------------------------------------------

    /// @notice Puts a proof file up for independent review. The author attests to the statement, the file
    ///         path and theorem name, the imports and the dependency pins the file was built against; each
    ///         must equal what the unit and the swarm are pinned to.
    function submitForReview(
        bytes32 unitId,
        bytes32 fileHash,
        bytes32 statementHash,
        bytes32 targetHash,
        bytes32 importsHash,
        bytes32 dependenciesHash
    ) external {
        _requireWorker(msg.sender);
        Unit storage u = _units[unitId];
        if (u.status != UnitStatus.Leased) revert UnitNotInState(unitId, u.status);
        Lease storage l = _requireLiveHolder(unitId);
        if (pinnedDependencies == bytes32(0)) revert PinsNotConfigured();
        if (dependenciesHash != pinnedDependencies) revert DependencyPinMismatch();
        if (statementHash != u.spec.statementHash) revert AlteredStatement();
        if (targetHash != u.spec.targetHash) revert WrongTheoremOrPath();
        if (importsHash != u.spec.importsHash) revert ForbiddenImports();
        if (fileHash == bytes32(0)) revert ZeroValue();
        if (fileUsed[fileHash]) revert DuplicateProofFile(fileHash);
        fileUsed[fileHash] = true;
        uint64 id = ++_submissionNonce;
        _submissions[unitId] = Submission({
            fileHash: fileHash,
            account: l.account,
            author: msg.sender,
            id: id,
            pullRequest: 0,
            price: l.price,
            approvals: 0
        });
        u.status = UnitStatus.InReview;
        emit ProofSubmittedForReview(unitId, fileHash, msg.sender, id);
    }

    /// @notice Records the pull request that carries a validated proof and ends the lease as submitted.
    ///         A pull request number can be recorded once: one new proof file per pull request.
    function recordPullRequest(bytes32 unitId, uint64 pullRequest) external {
        _requireWorker(msg.sender);
        Unit storage u = _units[unitId];
        if (u.status != UnitStatus.Validated) revert UnitNotInState(unitId, u.status);
        Lease storage l = _requireLiveHolder(unitId);
        if (pullRequest == 0) revert ZeroValue();
        if (pullRequestUsed[pullRequest]) revert PullRequestAlreadyUsed(pullRequest);
        pullRequestUsed[pullRequest] = true;
        Submission storage s = _submissions[unitId];
        s.pullRequest = pullRequest;
        bytes32 account = l.account;
        AccountStats storage stats = _accounts[account];
        stats.activeLeases -= 1;
        stats.pullRequests += 1;
        _totals.pullRequests += 1;
        u.lastHolder = msg.sender;
        u.status = UnitStatus.Submitted;
        delete _leases[unitId];
        emit PullRequestRecorded(unitId, pullRequest, s.fileHash);
        emit UnitReleased(unitId, msg.sender, account, ReleaseReason.Submitted, bytes32(uint256(pullRequest)));
    }

    /// @notice Adds to the cost an agent has incurred. Reports are never refused, so the total stays
    ///         accurate; once it reaches the approved budget no new lease is granted.
    function reportCost(uint256 amount) external {
        Agent storage a = _requireAgent(msg.sender);
        if (amount == 0) revert ZeroValue();
        a.cost += amount;
        _accounts[a.account].cost += amount;
        _totals.totalCost += amount;
        _touch(a);
        emit CostReported(msg.sender, a.account, amount, _totals.totalCost);
    }

    // ------------------------------------------------------------------------------------------------
    // Independent reviewers
    // ------------------------------------------------------------------------------------------------

    /// @notice Approves the file under review after running the official checker on it.
    /// @param fileHash       The file the reviewer checked; it must be the one under review.
    /// @param checkerRunHash Hash of the checker's output for that file.
    function approve(bytes32 unitId, bytes32 fileHash, bytes32 checkerRunHash) external {
        (Agent storage r, Unit storage u, Submission storage s) = _requireReview(unitId, fileHash);
        if (checkerRunHash == bytes32(0)) revert MissingEvidence();
        _reviewed[s.id][r.account] = true;
        s.approvals += 1;
        _touch(r);
        emit ProofApproved(unitId, fileHash, msg.sender, checkerRunHash);
        if (s.approvals >= reviewQuorum) {
            u.status = UnitStatus.Validated;
            _accounts[s.account].validated += 1;
            _totals.validatedProofs += 1;
            emit ProofValidated(unitId, fileHash, s.approvals);
        }
    }

    /// @notice Rejects the file under review. The unit returns to its holder, and that file can never be
    ///         put up again.
    function reject(bytes32 unitId, bytes32 fileHash, RejectReason reason, bytes32 evidence) external {
        (Agent storage r, Unit storage u, Submission storage s) = _requireReview(unitId, fileHash);
        if (reason == RejectReason.None) revert InvalidRejectReason();
        _accounts[s.account].reviewRejections += 1;
        _touch(r);
        u.status = UnitStatus.Leased;
        delete _submissions[unitId];
        emit ProofRejected(unitId, fileHash, msg.sender, reason, evidence);
    }

    // ------------------------------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------------------------------

    /// @notice The cap of each role: 60, 35, 30, 25, 20, 15, 10 and 5, which sum to 200.
    function roleCap(Role role) public pure returns (uint256) {
        if (role == Role.ProofDevelopment) return 60;
        if (role == Role.CounterexampleResearch) return 35;
        if (role == Role.ComputationalComplexity) return 30;
        if (role == Role.LeanVerification) return 25;
        if (role == Role.MathematicalReductions) return 20;
        if (role == Role.TacticDevelopment) return 15;
        if (role == Role.IndependentReviewer) return 10;
        if (role == Role.Coordinator) return 5;
        return 0;
    }

    /// @notice The key of a desk unit id such as "L-gct-101".
    function unitKey(string calldata unitName) external pure returns (bytes32) {
        return keccak256(bytes(unitName));
    }

    /// @notice The key of a GitHub handle. Pass the handle in lower case, without "@".
    function accountKey(string calldata handle) external pure returns (bytes32) {
        return keccak256(bytes(handle));
    }

    function agentOf(address agent) external view returns (Agent memory) {
        return _agents[agent];
    }

    function accountOf(bytes32 account) external view returns (AccountStats memory) {
        return _accounts[account];
    }

    function unitOf(bytes32 unitId) external view returns (Unit memory) {
        return _units[unitId];
    }

    function leaseOf(bytes32 unitId) external view returns (Lease memory) {
        return _leases[unitId];
    }

    function submissionOf(bytes32 unitId) external view returns (Submission memory) {
        return _submissions[unitId];
    }

    /// @notice The last second at which the unit's lease is live, or zero if it has none.
    function leaseDeadline(bytes32 unitId) external view returns (uint256) {
        Lease storage l = _leases[unitId];
        return l.agent == address(0) ? 0 : _deadline(l);
    }

    function isLeaseLive(bytes32 unitId) external view returns (bool) {
        return _live(_leases[unitId]);
    }

    /// @notice Until when the unit is reserved for the preferred agent, or zero when it is not: no preferred
    ///         agent is set, it is not a registered working agent on an authorized account, its account has
    ///         no free lease slot or is cooling down on this unit, or it was the unit's last holder.
    function reservedUntil(bytes32 unitId) public view returns (uint256) {
        address preferred = preferredAgent;
        if (preferred == address(0) || preferenceWindow == 0) return 0;
        Agent storage a = _agents[preferred];
        if (!_isWorker(a.role) || !accountAuthorized[a.account]) return 0;
        if (_accounts[a.account].activeLeases >= MAX_ACTIVE_LEASES) return 0;
        if (block.timestamp < cooldownUntil[unitId][a.account]) return 0;
        Unit storage u = _units[unitId];
        if (u.lastHolder == preferred) return 0;
        return uint256(u.openedAt) + preferenceWindow;
    }

    /// @notice The swarm's figures: agents, proofs, contributions, points and costs.
    function report() external view returns (SwarmReport memory r) {
        r = _totals;
        r.registeredAgents = agentCount;
        r.approvedBudget = approvedBudget;
    }

    // ------------------------------------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------------------------------------

    function _isWorker(Role role) private pure returns (bool) {
        return role != Role.None && role != Role.IndependentReviewer && role != Role.Coordinator;
    }

    function _holdsLease(UnitStatus status) private pure returns (bool) {
        return status == UnitStatus.Leased || status == UnitStatus.InReview || status == UnitStatus.Validated;
    }

    function _requireAgent(address who) private view returns (Agent storage) {
        Agent storage a = _agents[who];
        if (a.role == Role.None) revert AgentNotRegistered(who);
        if (!accountAuthorized[a.account]) revert AccountNotAuthorized(a.account);
        return a;
    }

    function _requireRole(address who, Role role) private view returns (Agent storage) {
        Agent storage a = _requireAgent(who);
        if (a.role != role) revert WrongRole(a.role);
        return a;
    }

    function _requireWorker(address who) private view returns (Agent storage) {
        Agent storage a = _requireAgent(who);
        if (!_isWorker(a.role)) revert WrongRole(a.role);
        return a;
    }

    function _requireLiveHolder(bytes32 unitId) private view returns (Lease storage) {
        Lease storage l = _leases[unitId];
        if (l.agent != msg.sender) revert NotLeaseHolder();
        if (!_live(l)) revert LeaseLapsed(_deadline(l));
        return l;
    }

    function _requireReview(bytes32 unitId, bytes32 fileHash)
        private
        view
        returns (Agent storage, Unit storage, Submission storage)
    {
        Agent storage r = _requireRole(msg.sender, Role.IndependentReviewer);
        Unit storage u = _units[unitId];
        if (u.status != UnitStatus.InReview) revert UnitNotInState(unitId, u.status);
        Lease storage l = _leases[unitId];
        if (!_live(l)) revert LeaseLapsed(_deadline(l));
        Submission storage s = _submissions[unitId];
        if (s.fileHash != fileHash) revert StaleReview(s.fileHash);
        if (r.account == s.account) revert ReviewerNotIndependent();
        if (_reviewed[s.id][r.account]) revert AlreadyReviewed();
        return (r, u, s);
    }

    function _deadline(Lease storage l) private view returns (uint256) {
        uint256 byBeat = uint256(l.lastBeat) + RENEW_WINDOW;
        uint256 byAge = uint256(l.leasedAt) + MAX_LEASE_AGE;
        return byBeat < byAge ? byBeat : byAge;
    }

    function _live(Lease storage l) private view returns (bool) {
        return l.agent != address(0) && block.timestamp <= _deadline(l);
    }

    function _touch(Agent storage a) private {
        if (!a.participated) {
            a.participated = true;
            _totals.participatingAgents += 1;
        }
    }

    function _expire(bytes32 unitId, Unit storage u) private {
        Lease storage l = _leases[unitId];
        address agent = l.agent;
        bytes32 account = l.account;
        _clearLease(unitId, u);
        _accounts[account].expired += 1;
        _totals.expiries += 1;
        emit LeaseExpired(unitId, agent, account);
    }

    /// @dev Ends the unit's lease without a pull request: the unit reopens, the account's slot is freed and
    ///      a file still waiting for review or a pull request becomes usable again.
    function _clearLease(bytes32 unitId, Unit storage u) private {
        Lease storage l = _leases[unitId];
        bytes32 fileHash = _submissions[unitId].fileHash;
        if (fileHash != bytes32(0)) {
            fileUsed[fileHash] = false;
            delete _submissions[unitId];
        }
        _accounts[l.account].activeLeases -= 1;
        u.lastHolder = l.agent;
        u.status = UnitStatus.Open;
        u.openedAt = uint64(block.timestamp);
        delete _leases[unitId];
    }
}
