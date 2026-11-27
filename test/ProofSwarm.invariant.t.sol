// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProofSwarm} from "../src/ProofSwarm.sol";

/// @dev Drives the swarm through random sequences of every agent action. Calls that the contract refuses
///      are swallowed: the invariants are about what state any sequence can reach.
contract SwarmHandler is Test {
    ProofSwarm public immutable swarm;
    bytes32 public constant PIN = keccak256("pin");
    uint256 public constant UNITS = 8;

    address[] public workers;
    address[] public reviewers;
    address public coordinator;
    uint256 public nextFile = 1;
    uint64 public nextPullRequest = 1;

    constructor(ProofSwarm swarm_, address[] memory workers_, address[] memory reviewers_, address coordinator_) {
        swarm = swarm_;
        workers = workers_;
        reviewers = reviewers_;
        coordinator = coordinator_;
    }

    function unitId(uint256 n) public pure returns (bytes32) {
        return keccak256(abi.encode("unit", n));
    }

    function _unit(uint256 seed) private pure returns (bytes32) {
        return unitId(seed % UNITS);
    }

    function _worker(uint256 seed) private view returns (address) {
        return workers[seed % workers.length];
    }

    function lease(uint256 who, uint256 unit) external {
        vm.prank(_worker(who));
        try swarm.lease(_unit(unit)) {} catch {}
    }

    function renew(uint256 unit) external {
        bytes32 id = _unit(unit);
        vm.prank(swarm.leaseOf(id).agent);
        try swarm.renew(id) {} catch {}
    }

    function release(uint256 unit, uint8 reason) external {
        bytes32 id = _unit(unit);
        vm.prank(swarm.leaseOf(id).agent);
        try swarm.release(id, ProofSwarm.ReleaseReason(bound(reason, 1, 6)), bytes32(0)) {} catch {}
    }

    function expire(uint256 unit) external {
        try swarm.expireLease(_unit(unit)) {} catch {}
    }

    function submit(uint256 unit) external {
        bytes32 id = _unit(unit);
        ProofSwarm.UnitSpec memory spec = swarm.unitOf(id).spec;
        bytes32 file = keccak256(abi.encode("file", nextFile++));
        vm.prank(swarm.leaseOf(id).agent);
        try swarm.submitForReview(id, file, spec.statementHash, spec.targetHash, spec.importsHash, PIN) {} catch {}
    }

    function approve(uint256 who, uint256 unit) external {
        bytes32 id = _unit(unit);
        bytes32 file = swarm.submissionOf(id).fileHash;
        vm.prank(reviewers[who % reviewers.length]);
        try swarm.approve(id, file, keccak256("run")) {} catch {}
    }

    function reject(uint256 who, uint256 unit) external {
        bytes32 id = _unit(unit);
        bytes32 file = swarm.submissionOf(id).fileHash;
        vm.prank(reviewers[who % reviewers.length]);
        try swarm.reject(id, file, ProofSwarm.RejectReason.ContainsSorry, bytes32(0)) {} catch {}
    }

    function pullRequest(uint256 unit) external {
        bytes32 id = _unit(unit);
        vm.prank(swarm.leaseOf(id).agent);
        try swarm.recordPullRequest(id, nextPullRequest) {
            nextPullRequest += 1;
        } catch {}
    }

    function verdict(uint256 unit, bool accepted) external {
        vm.prank(coordinator);
        try swarm.recordVerdict(_unit(unit), accepted, keccak256("evidence")) {} catch {}
    }

    /// @dev The whole path in one call, so that runs reach verdicts: random single steps almost never line
    ///      up a lease, a file, two reviewers, a pull request and a verdict on the same unit.
    function prove(uint256 who, uint256 unit, bool accepted) external {
        bytes32 id = _unit(unit);
        address worker = _worker(who);
        ProofSwarm.UnitSpec memory spec = swarm.unitOf(id).spec;
        bytes32 file = keccak256(abi.encode("file", nextFile++));
        vm.prank(worker);
        try swarm.lease(id) {} catch {}
        vm.prank(worker);
        try swarm.submitForReview(id, file, spec.statementHash, spec.targetHash, spec.importsHash, PIN) {}
        catch {
            return;
        }
        for (uint256 i = 0; i < 2; ++i) {
            vm.prank(reviewers[(who + i) % reviewers.length]);
            swarm.approve(id, file, keccak256("run"));
        }
        vm.prank(worker);
        swarm.recordPullRequest(id, nextPullRequest);
        nextPullRequest += 1;
        if (who % 3 != 0) {
            vm.prank(coordinator);
            swarm.recordVerdict(id, accepted, keccak256("evidence"));
        }
    }

    function wait(uint256 time) external {
        vm.warp(block.timestamp + bound(time, 1, 50 minutes));
    }
}

contract ProofSwarmInvariantTest is Test {
    ProofSwarm internal swarm;
    SwarmHandler internal handler;
    bytes32[] internal accounts;

    function setUp() public {
        vm.warp(1_800_000_000);
        address owner = makeAddr("owner");
        address coordinator = makeAddr("coordinator");
        swarm = new ProofSwarm(owner);

        accounts.push(keccak256("account-a"));
        accounts.push(keccak256("account-b"));
        address[] memory workers = new address[](4);
        address[] memory reviewers = new address[](3);

        vm.startPrank(owner);
        swarm.authorizeAccount(accounts[0]);
        swarm.authorizeAccount(accounts[1]);
        swarm.authorizeAccount(keccak256("coordinator"));
        // Three agents share account a, so the five-lease limit is under pressure from several callers.
        for (uint256 i = 0; i < 4; ++i) {
            workers[i] = makeAddr(string.concat("worker-", vm.toString(i)));
            swarm.registerAgent(workers[i], ProofSwarm.Role.ProofDevelopment, accounts[i < 3 ? 0 : 1]);
        }
        for (uint256 i = 0; i < 3; ++i) {
            bytes32 account = keccak256(abi.encode("reviewer", i));
            swarm.authorizeAccount(account);
            reviewers[i] = makeAddr(string.concat("reviewer-", vm.toString(i)));
            swarm.registerAgent(reviewers[i], ProofSwarm.Role.IndependentReviewer, account);
        }
        swarm.registerAgent(coordinator, ProofSwarm.Role.Coordinator, keccak256("coordinator"));
        swarm.setApprovedBudget(1);
        swarm.setPinnedDependencies(keccak256("pin"));
        vm.stopPrank();

        handler = new SwarmHandler(swarm, workers, reviewers, coordinator);
        vm.startPrank(coordinator);
        for (uint256 n = 0; n < handler.UNITS(); ++n) {
            swarm.postUnit(
                handler.unitId(n),
                ProofSwarm.UnitSpec({
                    statementHash: keccak256(abi.encode("statement", n)),
                    targetHash: keccak256(abi.encode("target", n)),
                    importsHash: keccak256(abi.encode("imports", n)),
                    price: uint64(10 * (n + 1)),
                    level: ProofSwarm.Level.Warmup,
                    kind: ProofSwarm.Kind.Prove,
                    reductions: false
                })
            );
        }
        vm.stopPrank();
        targetContract(address(handler));
    }

    function _holdsLease(ProofSwarm.UnitStatus s) private pure returns (bool) {
        return s == ProofSwarm.UnitStatus.Leased || s == ProofSwarm.UnitStatus.InReview
            || s == ProofSwarm.UnitStatus.Validated;
    }

    /// @notice An account's lease counter equals the leases it actually holds and never exceeds five.
    function invariant_LeaseCountMatchesAndStaysWithinFive() public view {
        for (uint256 a = 0; a < accounts.length; ++a) {
            uint256 held;
            for (uint256 n = 0; n < handler.UNITS(); ++n) {
                bytes32 id = handler.unitId(n);
                if (_holdsLease(swarm.unitOf(id).status) && swarm.leaseOf(id).account == accounts[a]) held += 1;
            }
            assertEq(swarm.accountOf(accounts[a]).activeLeases, held);
            assertLe(held, swarm.MAX_ACTIVE_LEASES());
        }
    }

    /// @notice A lease record exists exactly for units in a leased state, and is never older than six hours
    ///         while live.
    function invariant_LeaseRecordsMatchUnitStates() public view {
        for (uint256 n = 0; n < handler.UNITS(); ++n) {
            bytes32 id = handler.unitId(n);
            ProofSwarm.Lease memory l = swarm.leaseOf(id);
            assertEq(l.agent != address(0), _holdsLease(swarm.unitOf(id).status));
            if (swarm.isLeaseLive(id)) {
                assertLe(block.timestamp, uint256(l.leasedAt) + 6 hours);
                assertLe(block.timestamp, uint256(l.lastBeat) + 45 minutes);
            }
        }
    }

    /// @notice Points are the prices of accepted units and nothing else; counters add up.
    function invariant_PointsComeOnlyFromAcceptedUnits() public view {
        uint256 points;
        uint256 accepted;
        for (uint256 n = 0; n < handler.UNITS(); ++n) {
            bytes32 id = handler.unitId(n);
            ProofSwarm.UnitStatus s = swarm.unitOf(id).status;
            ProofSwarm.Submission memory sub = swarm.submissionOf(id);
            if (s == ProofSwarm.UnitStatus.Accepted) {
                points += sub.price;
                accepted += 1;
                assertGt(sub.pullRequest, 0);
                assertGe(sub.approvals, swarm.reviewQuorum());
            }
            if (
                s == ProofSwarm.UnitStatus.InReview || s == ProofSwarm.UnitStatus.Validated
                    || s == ProofSwarm.UnitStatus.Submitted || s == ProofSwarm.UnitStatus.Accepted
            ) {
                assertTrue(swarm.fileUsed(sub.fileHash));
            } else {
                assertEq(sub.fileHash, bytes32(0));
            }
        }
        ProofSwarm.SwarmReport memory r = swarm.report();
        assertEq(r.points, points);
        assertEq(r.acceptedContributions, accepted);
        assertEq(swarm.accountOf(accounts[0]).points + swarm.accountOf(accounts[1]).points, points);
        assertLe(r.acceptedContributions + r.rejectedContributions, r.pullRequests);
        assertLe(r.pullRequests, r.validatedProofs);
        assertEq(r.pullRequests, uint256(handler.nextPullRequest()) - 1);
        assertLe(r.releases + r.expiries + r.pullRequests, r.leasesTaken);
    }
}
