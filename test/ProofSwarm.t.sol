// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProofSwarm} from "../src/ProofSwarm.sol";

abstract contract SwarmFixture is Test {
    ProofSwarm internal swarm;

    uint256 internal constant T0 = 1_800_000_000;
    uint256 internal constant BUDGET = 1_000_000;
    bytes32 internal constant PIN = keccak256("toolchain and mathlib pin");
    bytes32 internal constant ACC_A = keccak256("account-a");
    bytes32 internal constant ACC_B = keccak256("account-b");
    bytes32 internal constant ACC_R1 = keccak256("reviewer-one");
    bytes32 internal constant ACC_R2 = keccak256("reviewer-two");
    bytes32 internal constant ACC_C = keccak256("coordinator");
    bytes32 internal constant RUN = keccak256("ACCEPTED (check)");

    address internal owner = makeAddr("owner");
    address internal factory = makeAddr("factory");
    address internal w1 = makeAddr("worker-1-account-a");
    address internal w2 = makeAddr("worker-2-account-a");
    address internal w3 = makeAddr("worker-3-account-b");
    address internal r1 = makeAddr("reviewer-1");
    address internal r2 = makeAddr("reviewer-2");
    address internal rA = makeAddr("reviewer-on-account-a");
    address internal c1 = makeAddr("coordinator-1");
    address internal cA = makeAddr("coordinator-on-account-a");
    address internal stranger = makeAddr("stranger");

    function setUp() public virtual {
        vm.warp(T0);
        vm.prank(factory);
        swarm = new ProofSwarm(owner);
        vm.startPrank(owner);
        swarm.authorizeAccount(ACC_A);
        swarm.authorizeAccount(ACC_B);
        swarm.authorizeAccount(ACC_R1);
        swarm.authorizeAccount(ACC_R2);
        swarm.authorizeAccount(ACC_C);
        swarm.registerAgent(w1, ProofSwarm.Role.ProofDevelopment, ACC_A);
        swarm.registerAgent(w2, ProofSwarm.Role.CounterexampleResearch, ACC_A);
        swarm.registerAgent(w3, ProofSwarm.Role.LeanVerification, ACC_B);
        swarm.registerAgent(r1, ProofSwarm.Role.IndependentReviewer, ACC_R1);
        swarm.registerAgent(r2, ProofSwarm.Role.IndependentReviewer, ACC_R2);
        swarm.registerAgent(rA, ProofSwarm.Role.IndependentReviewer, ACC_A);
        swarm.registerAgent(c1, ProofSwarm.Role.Coordinator, ACC_C);
        swarm.registerAgent(cA, ProofSwarm.Role.Coordinator, ACC_A);
        swarm.setApprovedBudget(BUDGET);
        swarm.setPinnedDependencies(PIN);
        vm.stopPrank();
    }

    function _id(uint256 n) internal pure returns (bytes32) {
        return keccak256(abi.encode("unit", n));
    }

    function _statement(uint256 n) internal pure returns (bytes32) {
        return keccak256(abi.encode("statement", n));
    }

    function _target(uint256 n) internal pure returns (bytes32) {
        return keccak256(abi.encode("path and theorem", n));
    }

    function _imports(uint256 n) internal pure returns (bytes32) {
        return keccak256(abi.encode("imports", n));
    }

    function _file(uint256 n) internal pure returns (bytes32) {
        return keccak256(abi.encode("file", n));
    }

    function _spec(uint256 n, uint64 price) internal pure returns (ProofSwarm.UnitSpec memory) {
        return ProofSwarm.UnitSpec({
            statementHash: _statement(n),
            targetHash: _target(n),
            importsHash: _imports(n),
            price: price,
            level: ProofSwarm.Level.Solid,
            kind: ProofSwarm.Kind.Prove,
            reductions: false
        });
    }

    function _post(uint256 n) internal returns (bytes32 id) {
        id = _id(n);
        vm.prank(c1);
        swarm.postUnit(id, _spec(n, 100));
    }

    function _postSpec(uint256 n, ProofSwarm.UnitSpec memory spec) internal returns (bytes32 id) {
        id = _id(n);
        vm.prank(c1);
        swarm.postUnit(id, spec);
    }

    function _lease(address who, uint256 n) internal returns (bytes32 id) {
        id = _id(n);
        vm.prank(who);
        swarm.lease(id);
    }

    function _submit(address who, uint256 n, bytes32 file) internal {
        vm.prank(who);
        swarm.submitForReview(_id(n), file, _statement(n), _target(n), _imports(n), PIN);
    }

    function _approveBoth(uint256 n, bytes32 file) internal {
        vm.prank(r1);
        swarm.approve(_id(n), file, RUN);
        vm.prank(r2);
        swarm.approve(_id(n), file, RUN);
    }

    /// @dev Post, lease, submit, validate and record a pull request for unit n.
    function _toSubmitted(address who, uint256 n, uint64 pr) internal returns (bytes32 id) {
        id = _post(n);
        _lease(who, n);
        _submit(who, n, _file(n));
        _approveBoth(n, _file(n));
        vm.prank(who);
        swarm.recordPullRequest(id, pr);
    }

    function _status(bytes32 id) internal view returns (ProofSwarm.UnitStatus) {
        return swarm.unitOf(id).status;
    }

    function _notInState(bytes32 id, ProofSwarm.UnitStatus s) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ProofSwarm.UnitNotInState.selector, id, s);
    }

    function _wrongRole(ProofSwarm.Role r) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ProofSwarm.WrongRole.selector, r);
    }
}

contract ProofSwarmConfigTest is SwarmFixture {
    function test_OwnerIsTheArgumentNotTheDeployer() public view {
        assertEq(swarm.owner(), owner);
        assertTrue(swarm.owner() != factory);
    }

    function test_ZeroOwnerRefused() public {
        vm.expectRevert(ProofSwarm.ZeroAddress.selector);
        new ProofSwarm(address(0));
    }

    function test_FreshSwarmIsUnconfigured() public {
        ProofSwarm fresh = new ProofSwarm(owner);
        assertEq(fresh.approvedBudget(), 0);
        assertEq(fresh.pinnedDependencies(), bytes32(0));
        assertEq(fresh.preferredAgent(), address(0));
        assertEq(fresh.reviewQuorum(), 2);
        assertEq(fresh.preferenceWindow(), 5 minutes);
        assertEq(fresh.agentCount(), 0);
    }

    function test_RoleCapsSumToTwoHundred() public view {
        uint256 sum;
        for (uint8 r = 1; r <= 8; ++r) {
            sum += swarm.roleCap(ProofSwarm.Role(r));
        }
        assertEq(sum, 200);
        assertEq(sum, swarm.MAX_AGENTS());
        assertEq(swarm.roleCap(ProofSwarm.Role.None), 0);
        assertEq(swarm.roleCap(ProofSwarm.Role.ProofDevelopment), 60);
        assertEq(swarm.roleCap(ProofSwarm.Role.CounterexampleResearch), 35);
        assertEq(swarm.roleCap(ProofSwarm.Role.ComputationalComplexity), 30);
        assertEq(swarm.roleCap(ProofSwarm.Role.LeanVerification), 25);
        assertEq(swarm.roleCap(ProofSwarm.Role.MathematicalReductions), 20);
        assertEq(swarm.roleCap(ProofSwarm.Role.TacticDevelopment), 15);
        assertEq(swarm.roleCap(ProofSwarm.Role.IndependentReviewer), 10);
        assertEq(swarm.roleCap(ProofSwarm.Role.Coordinator), 5);
    }

    function test_PreferredAgentConstants() public view {
        assertEq(swarm.PREFERRED_AGENT_NUMBER(), 1927);
        assertEq(swarm.PREFERRED_AGENT_ID(), 50973);
    }

    function test_FullAllocationThenEveryRoleIsFull() public {
        ProofSwarm full = new ProofSwarm(owner);
        vm.startPrank(owner);
        full.authorizeAccount(ACC_A);
        uint160 next = 0x100000;
        for (uint8 r = 1; r <= 8; ++r) {
            ProofSwarm.Role role = ProofSwarm.Role(r);
            uint256 cap = full.roleCap(role);
            for (uint256 i = 0; i < cap; ++i) {
                full.registerAgent(address(next++), role, ACC_A);
            }
            assertEq(full.roleCount(role), cap);
        }
        assertEq(full.agentCount(), 200);
        for (uint8 r = 1; r <= 8; ++r) {
            vm.expectRevert(abi.encodeWithSelector(ProofSwarm.RoleFull.selector, ProofSwarm.Role(r)));
            full.registerAgent(address(next++), ProofSwarm.Role(r), ACC_A);
        }
        // Removing one frees exactly one place in its role.
        full.removeAgent(address(uint160(0x100000)));
        assertEq(full.agentCount(), 199);
        full.registerAgent(address(next++), ProofSwarm.Role.ProofDevelopment, ACC_A);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.RoleFull.selector, ProofSwarm.Role.ProofDevelopment));
        full.registerAgent(address(next++), ProofSwarm.Role.ProofDevelopment, ACC_A);
        vm.stopPrank();
    }

    function test_RegisterAgentFailures() public {
        vm.prank(stranger);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.registerAgent(stranger, ProofSwarm.Role.ProofDevelopment, ACC_A);

        vm.startPrank(owner);
        vm.expectRevert(ProofSwarm.ZeroAddress.selector);
        swarm.registerAgent(address(0), ProofSwarm.Role.ProofDevelopment, ACC_A);
        vm.expectRevert(ProofSwarm.InvalidRole.selector);
        swarm.registerAgent(stranger, ProofSwarm.Role.None, ACC_A);
        bytes32 unknown = keccak256("unknown");
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AccountNotAuthorized.selector, unknown));
        swarm.registerAgent(stranger, ProofSwarm.Role.ProofDevelopment, unknown);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AgentAlreadyRegistered.selector, w1));
        swarm.registerAgent(w1, ProofSwarm.Role.TacticDevelopment, ACC_B);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AgentNotRegistered.selector, stranger));
        swarm.removeAgent(stranger);
        vm.stopPrank();
    }

    function test_OwnerSettersEmitAndStore() public {
        vm.startPrank(owner);
        vm.expectEmit();
        emit ProofSwarm.ApprovedBudgetSet(BUDGET, 5);
        swarm.setApprovedBudget(5);
        assertEq(swarm.approvedBudget(), 5);

        bytes32 pin2 = keccak256("new pin");
        vm.expectEmit();
        emit ProofSwarm.PinnedDependenciesSet(PIN, pin2);
        swarm.setPinnedDependencies(pin2);
        assertEq(swarm.pinnedDependencies(), pin2);

        vm.expectEmit();
        emit ProofSwarm.ReviewQuorumSet(2, 3);
        swarm.setReviewQuorum(3);
        assertEq(swarm.reviewQuorum(), 3);

        vm.expectEmit();
        emit ProofSwarm.PreferredAgentSet(address(0), w3);
        swarm.setPreferredAgent(w3);
        assertEq(swarm.preferredAgent(), w3);
        vm.expectEmit();
        emit ProofSwarm.PreferredAgentSet(w3, address(0));
        swarm.clearPreferredAgent();
        assertEq(swarm.preferredAgent(), address(0));

        vm.expectEmit();
        emit ProofSwarm.PreferenceWindowSet(5 minutes, 45 minutes);
        swarm.setPreferenceWindow(45 minutes);
        assertEq(swarm.preferenceWindow(), 45 minutes);

        bytes32 acc = keccak256("new-account");
        vm.expectEmit();
        emit ProofSwarm.AccountAuthorized(acc);
        swarm.authorizeAccount(acc);
        vm.expectEmit();
        emit ProofSwarm.AccountRevoked(acc);
        swarm.revokeAccount(acc);
        assertFalse(swarm.accountAuthorized(acc));

        vm.expectEmit();
        emit ProofSwarm.OwnershipTransferred(owner, stranger);
        swarm.transferOwnership(stranger);
        assertEq(swarm.owner(), stranger);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.setApprovedBudget(6);
        vm.stopPrank();
    }

    function test_OwnerSettersRefuseBadValues() public {
        vm.startPrank(owner);
        vm.expectRevert(ProofSwarm.ZeroValue.selector);
        swarm.setApprovedBudget(0);
        vm.expectRevert(ProofSwarm.ZeroValue.selector);
        swarm.setPinnedDependencies(bytes32(0));
        vm.expectRevert(ProofSwarm.OutOfBounds.selector);
        swarm.setReviewQuorum(0);
        vm.expectRevert(ProofSwarm.OutOfBounds.selector);
        swarm.setReviewQuorum(11);
        vm.expectRevert(ProofSwarm.ZeroAddress.selector);
        swarm.setPreferredAgent(address(0));
        vm.expectRevert(ProofSwarm.OutOfBounds.selector);
        swarm.setPreferenceWindow(45 minutes + 1);
        vm.expectRevert(ProofSwarm.ZeroValue.selector);
        swarm.authorizeAccount(bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AccountNotAuthorized.selector, keccak256("nobody")));
        swarm.revokeAccount(keccak256("nobody"));
        vm.expectRevert(ProofSwarm.ZeroAddress.selector);
        swarm.transferOwnership(address(0));
        vm.stopPrank();
    }

    function test_OnlyOwnerOnEverySetter() public {
        vm.startPrank(stranger);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.setApprovedBudget(1);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.setPinnedDependencies(PIN);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.setReviewQuorum(1);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.setPreferredAgent(stranger);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.clearPreferredAgent();
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.setPreferenceWindow(1);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.authorizeAccount(ACC_A);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.revokeAccount(ACC_A);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.removeAgent(w1);
        vm.expectRevert(ProofSwarm.NotOwner.selector);
        swarm.transferOwnership(stranger);
        vm.stopPrank();
    }

    function test_Keys() public view {
        assertEq(swarm.unitKey("L-gct-101"), keccak256("L-gct-101"));
        assertEq(swarm.accountKey("some-handle"), keccak256("some-handle"));
    }
}

contract ProofSwarmUnitTest is SwarmFixture {
    function test_PostUnit() public {
        bytes32 id = _id(1);
        vm.expectEmit();
        emit ProofSwarm.UnitPosted(id, _spec(1, 100));
        vm.prank(c1);
        swarm.postUnit(id, _spec(1, 100));
        ProofSwarm.Unit memory u = swarm.unitOf(id);
        assertEq(uint8(u.status), uint8(ProofSwarm.UnitStatus.Open));
        assertEq(u.openedAt, T0);
        assertEq(u.spec.statementHash, _statement(1));
        assertEq(u.spec.price, 100);
        assertEq(swarm.report().unitsPosted, 1);
        assertEq(swarm.report().participatingAgents, 1);
    }

    function test_PostUnitFailures() public {
        vm.prank(w1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.ProofDevelopment));
        swarm.postUnit(_id(1), _spec(1, 100));
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AgentNotRegistered.selector, stranger));
        swarm.postUnit(_id(1), _spec(1, 100));

        vm.startPrank(c1);
        vm.expectRevert(ProofSwarm.ZeroValue.selector);
        swarm.postUnit(bytes32(0), _spec(1, 100));
        vm.expectRevert(ProofSwarm.InvalidUnitSpec.selector);
        swarm.postUnit(_id(1), _spec(1, 0));
        ProofSwarm.UnitSpec memory spec = _spec(1, 100);
        spec.statementHash = bytes32(0);
        vm.expectRevert(ProofSwarm.InvalidUnitSpec.selector);
        swarm.postUnit(_id(1), spec);
        spec = _spec(1, 100);
        spec.targetHash = bytes32(0);
        vm.expectRevert(ProofSwarm.InvalidUnitSpec.selector);
        swarm.postUnit(_id(1), spec);
        spec = _spec(1, 100);
        spec.importsHash = bytes32(0);
        vm.expectRevert(ProofSwarm.InvalidUnitSpec.selector);
        swarm.postUnit(_id(1), spec);

        swarm.postUnit(_id(1), _spec(1, 100));
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.UnitExists.selector, _id(1)));
        swarm.postUnit(_id(1), _spec(1, 100));
        vm.stopPrank();
    }

    function test_RepriceOnlyWhileOpenAndLeaseKeepsItsPrice() public {
        bytes32 id = _post(1);
        vm.prank(c1);
        swarm.repriceUnit(id, 250);
        _lease(w1, 1);
        assertEq(swarm.leaseOf(id).price, 250);
        vm.prank(c1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Leased));
        swarm.repriceUnit(id, 1);
        vm.prank(c1);
        vm.expectRevert(ProofSwarm.ZeroValue.selector);
        swarm.repriceUnit(id, 0);
        vm.prank(w1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.ProofDevelopment));
        swarm.repriceUnit(id, 1);
    }
}

contract ProofSwarmLeaseTest is SwarmFixture {
    function test_Lease() public {
        bytes32 id = _post(1);
        vm.expectEmit();
        emit ProofSwarm.UnitLeased(id, w1, ACC_A, 100, T0 + 45 minutes);
        vm.prank(w1);
        swarm.lease(id);
        ProofSwarm.Lease memory l = swarm.leaseOf(id);
        assertEq(l.agent, w1);
        assertEq(l.account, ACC_A);
        assertEq(l.leasedAt, T0);
        assertEq(l.price, 100);
        assertEq(swarm.leaseDeadline(id), T0 + 45 minutes);
        assertTrue(swarm.isLeaseLive(id));
        assertEq(swarm.accountOf(ACC_A).activeLeases, 1);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Leased));
    }

    function test_LeaseRefusedUntilBudgetIsConfigured() public {
        ProofSwarm fresh = new ProofSwarm(owner);
        vm.startPrank(owner);
        fresh.authorizeAccount(ACC_A);
        fresh.authorizeAccount(ACC_C);
        fresh.registerAgent(w1, ProofSwarm.Role.ProofDevelopment, ACC_A);
        fresh.registerAgent(c1, ProofSwarm.Role.Coordinator, ACC_C);
        vm.stopPrank();
        vm.prank(c1);
        fresh.postUnit(_id(1), _spec(1, 100));
        vm.prank(w1);
        vm.expectRevert(ProofSwarm.BudgetNotConfigured.selector);
        fresh.lease(_id(1));
        vm.prank(owner);
        fresh.setApprovedBudget(10);
        vm.prank(w1);
        fresh.lease(_id(1));
        assertEq(fresh.leaseOf(_id(1)).agent, w1);
    }

    function test_LeaseRefusedOnceBudgetIsSpent() public {
        _post(1);
        _post(2);
        _lease(w1, 1);
        vm.prank(w1);
        swarm.reportCost(BUDGET - 1);
        _lease(w2, 2);
        vm.prank(r1);
        swarm.reportCost(1);
        _post(3);
        vm.prank(w3);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.BudgetExhausted.selector, BUDGET, BUDGET));
        swarm.lease(_id(3));
        // Work already leased may finish: renewals are not blocked.
        vm.prank(w1);
        swarm.renew(_id(1));
        // The owner raises the budget and leasing resumes.
        vm.prank(owner);
        swarm.setApprovedBudget(BUDGET + 1);
        _lease(w3, 3);
    }

    function test_ReportCost() public {
        vm.expectEmit();
        emit ProofSwarm.CostReported(w1, ACC_A, 40, 40);
        vm.prank(w1);
        swarm.reportCost(40);
        vm.prank(w2);
        swarm.reportCost(2);
        vm.prank(r1);
        swarm.reportCost(8);
        assertEq(swarm.agentOf(w1).cost, 40);
        assertEq(swarm.accountOf(ACC_A).cost, 42);
        assertEq(swarm.report().totalCost, 50);
        assertEq(swarm.report().approvedBudget, BUDGET);
        vm.prank(w1);
        vm.expectRevert(ProofSwarm.ZeroValue.selector);
        swarm.reportCost(0);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AgentNotRegistered.selector, stranger));
        swarm.reportCost(1);
    }

    function test_LeaseFailuresByCaller() public {
        bytes32 id = _post(1);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AgentNotRegistered.selector, stranger));
        swarm.lease(id);
        vm.prank(r1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.IndependentReviewer));
        swarm.lease(id);
        vm.prank(c1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.Coordinator));
        swarm.lease(id);
        vm.prank(w1);
        vm.expectRevert(_notInState(_id(99), ProofSwarm.UnitStatus.None));
        swarm.lease(_id(99));
    }

    function test_RevokedAccountAndRemovedAgentCannotAct() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.prank(owner);
        swarm.revokeAccount(ACC_A);
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AccountNotAuthorized.selector, ACC_A));
        swarm.renew(id);
        vm.prank(owner);
        swarm.authorizeAccount(ACC_A);
        vm.prank(w1);
        swarm.renew(id);
        vm.prank(owner);
        swarm.removeAgent(w1);
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.AgentNotRegistered.selector, w1));
        swarm.renew(id);
        // A removed agent may still hand the unit back with a reason.
        vm.prank(w1);
        swarm.release(id, ProofSwarm.ReleaseReason.MissingLemma, bytes32(0));
        assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
    }

    function test_UnitCannotBeLeasedTwice() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.prank(w3);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Leased));
        swarm.lease(id);
        vm.prank(w1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Leased));
        swarm.lease(id);
    }

    function test_FiveLeasesPerAccountAcrossItsAgents() public {
        for (uint256 n = 1; n <= 7; ++n) {
            _post(n);
        }
        _lease(w1, 1);
        _lease(w2, 2);
        _lease(w1, 3);
        _lease(w2, 4);
        _lease(w1, 5);
        assertEq(swarm.accountOf(ACC_A).activeLeases, 5);
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLimitReached.selector, ACC_A));
        swarm.lease(_id(6));
        vm.prank(w2);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLimitReached.selector, ACC_A));
        swarm.lease(_id(6));
        // Another account is not affected.
        _lease(w3, 6);
        // Releasing one frees one slot, and only one.
        vm.prank(w2);
        swarm.release(_id(2), ProofSwarm.ReleaseReason.MissingLemma, bytes32(0));
        _lease(w1, 7);
        vm.prank(w2);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLimitReached.selector, ACC_A));
        swarm.lease(_id(2));
    }

    function test_RenewWithinFortyFiveMinutes() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.warp(T0 + 45 minutes);
        vm.expectEmit();
        emit ProofSwarm.LeaseRenewed(id, w1, T0 + 90 minutes);
        vm.prank(w1);
        swarm.renew(id);
        assertEq(swarm.leaseDeadline(id), T0 + 90 minutes);
    }

    function test_RenewOneSecondLateFails() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.warp(T0 + 45 minutes + 1);
        assertFalse(swarm.isLeaseLive(id));
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLapsed.selector, T0 + 45 minutes));
        swarm.renew(id);
    }

    function test_RenewByAnotherAgentFails() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.prank(w2);
        vm.expectRevert(ProofSwarm.NotLeaseHolder.selector);
        swarm.renew(id);
        vm.prank(r1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.IndependentReviewer));
        swarm.renew(id);
    }

    function test_LeaseEndsAtSixHoursHoweverOftenRenewed() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        for (uint256 i = 1; i <= 8; ++i) {
            vm.warp(T0 + i * 40 minutes);
            vm.prank(w1);
            swarm.renew(id);
        }
        // Last renewal at 5h20m: 45 more minutes would be 6h05m, but the lease ends at 6h.
        assertEq(swarm.leaseDeadline(id), T0 + 6 hours);
        vm.warp(T0 + 6 hours);
        vm.prank(w1);
        swarm.renew(id);
        assertEq(swarm.leaseDeadline(id), T0 + 6 hours);
        vm.warp(T0 + 6 hours + 1);
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLapsed.selector, T0 + 6 hours));
        swarm.renew(id);
        swarm.expireLease(id);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Open));
    }

    function test_ExpireLease() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseStillLive.selector, T0 + 45 minutes));
        swarm.expireLease(id);
        vm.warp(T0 + 45 minutes + 1);
        vm.expectEmit();
        emit ProofSwarm.LeaseExpired(id, w1, ACC_A);
        vm.prank(stranger);
        swarm.expireLease(id);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Open));
        assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
        assertEq(swarm.accountOf(ACC_A).expired, 1);
        assertEq(swarm.report().expiries, 1);
        assertEq(swarm.leaseDeadline(id), 0);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Open));
        swarm.expireLease(id);
    }

    function test_LapsedLeaseIsTakenOverDirectly() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.warp(T0 + 46 minutes);
        _lease(w3, 1);
        assertEq(swarm.leaseOf(id).agent, w3);
        assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
        assertEq(swarm.accountOf(ACC_A).expired, 1);
        assertEq(swarm.accountOf(ACC_B).activeLeases, 1);
    }

    function test_ReleaseWithReason() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.expectEmit();
        emit ProofSwarm.UnitReleased(id, w1, ACC_A, ProofSwarm.ReleaseReason.StatementSeemsFalse, bytes32(0));
        vm.prank(w1);
        swarm.release(id, ProofSwarm.ReleaseReason.StatementSeemsFalse, bytes32(0));
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Open));
        assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
        assertEq(swarm.accountOf(ACC_A).released, 1);
        assertEq(swarm.report().releases, 1);
        // No waiting time after this reason.
        _lease(w1, 1);
    }

    function test_ReleaseFailures() public {
        bytes32 id = _post(1);
        vm.prank(w1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Open));
        swarm.release(id, ProofSwarm.ReleaseReason.Other, bytes32(0));
        _lease(w1, 1);
        vm.prank(w2);
        vm.expectRevert(ProofSwarm.NotLeaseHolder.selector);
        swarm.release(id, ProofSwarm.ReleaseReason.Other, bytes32(0));
        vm.startPrank(w1);
        vm.expectRevert(ProofSwarm.InvalidReleaseReason.selector);
        swarm.release(id, ProofSwarm.ReleaseReason.None, bytes32(0));
        vm.expectRevert(ProofSwarm.InvalidReleaseReason.selector);
        swarm.release(id, ProofSwarm.ReleaseReason.Submitted, bytes32(0));
        // This unit is a plain proof: it was not a search and is not open to reductions.
        vm.expectRevert(ProofSwarm.ReasonNotApplicable.selector);
        swarm.release(id, ProofSwarm.ReleaseReason.Exhausted, keccak256("program"));
        vm.expectRevert(ProofSwarm.ReasonNotApplicable.selector);
        swarm.release(id, ProofSwarm.ReleaseReason.Reduced, bytes32(0));
        vm.stopPrank();
    }

    function test_ExhaustedNeedsASearchUnitAndTheProgramHash() public {
        ProofSwarm.UnitSpec memory spec = _spec(1, 100);
        spec.kind = ProofSwarm.Kind.Search;
        bytes32 id = _postSpec(1, spec);
        _lease(w1, 1);
        vm.startPrank(w1);
        vm.expectRevert(ProofSwarm.MissingEvidence.selector);
        swarm.release(id, ProofSwarm.ReleaseReason.Exhausted, bytes32(0));
        swarm.release(id, ProofSwarm.ReleaseReason.Exhausted, sha256("search program"));
        vm.stopPrank();
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Open));
    }

    function test_ReducedNeedsAUnitOpenToReductions() public {
        ProofSwarm.UnitSpec memory spec = _spec(1, 100);
        spec.reductions = true;
        _postSpec(1, spec);
        spec = _spec(2, 100);
        spec.kind = ProofSwarm.Kind.Cut;
        _postSpec(2, spec);
        _lease(w1, 1);
        _lease(w1, 2);
        vm.startPrank(w1);
        swarm.release(_id(1), ProofSwarm.ReleaseReason.Reduced, bytes32(0));
        swarm.release(_id(2), ProofSwarm.ReleaseReason.Reduced, bytes32(0));
        vm.stopPrank();
        assertEq(swarm.accountOf(ACC_A).released, 2);
    }

    function test_CooldownAfterOutOfTimeOrOtherAppliesToTheAccount() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.prank(w1);
        swarm.release(id, ProofSwarm.ReleaseReason.OutOfTime, bytes32(0));
        // The same account, through either of its agents, waits an hour for this unit.
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.ReleaseCooldownActive.selector, T0 + 1 hours));
        swarm.lease(id);
        vm.prank(w2);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.ReleaseCooldownActive.selector, T0 + 1 hours));
        swarm.lease(id);
        // It may take another unit, and another account may take this one.
        _post(2);
        _lease(w1, 2);
        _lease(w3, 1);
        vm.prank(w3);
        swarm.release(id, ProofSwarm.ReleaseReason.Other, bytes32(0));
        vm.warp(T0 + 1 hours - 1);
        vm.prank(w2);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.ReleaseCooldownActive.selector, T0 + 1 hours));
        swarm.lease(id);
        vm.warp(T0 + 1 hours);
        _lease(w2, 1);
    }

    function test_HolderMayReleaseALapsedLeaseWithItsReason() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.warp(T0 + 2 hours);
        vm.prank(w1);
        swarm.release(id, ProofSwarm.ReleaseReason.OutOfTime, bytes32(0));
        assertEq(swarm.accountOf(ACC_A).released, 1);
        assertEq(swarm.accountOf(ACC_A).expired, 0);
    }

    /// @dev Replays renewals at fuzzed intervals against the rule: live until 45 minutes after the last
    ///      renewal and until six hours after the lease was taken, whichever comes first.
    function testFuzz_LeaseLivenessFollowsTheRule(uint16[12] memory gaps) public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        uint256 lastBeat = T0;
        uint256 nowTs = T0;
        for (uint256 i = 0; i < gaps.length; ++i) {
            nowTs += bound(gaps[i], 1, 50 minutes);
            vm.warp(nowTs);
            uint256 byBeat = lastBeat + 45 minutes;
            uint256 byAge = T0 + 6 hours;
            uint256 deadline = byBeat < byAge ? byBeat : byAge;
            assertEq(swarm.leaseDeadline(id), deadline);
            bool live = nowTs <= deadline;
            assertEq(swarm.isLeaseLive(id), live);
            vm.prank(w1);
            if (live) {
                swarm.renew(id);
                lastBeat = nowTs;
            } else {
                vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLapsed.selector, deadline));
                swarm.renew(id);
                swarm.expireLease(id);
                assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
                return;
            }
        }
        assertLe(swarm.leaseDeadline(id), T0 + 6 hours);
    }

    /// @dev Two agents of one account take and return units in a fuzzed order; the account never holds
    ///      more than five, and a refusal happens exactly when it holds five.
    function testFuzz_AccountNeverHoldsMoreThanFive(uint256 seed) public {
        uint256 units = 9;
        bool[] memory held = new bool[](units);
        address[] memory holder = new address[](units);
        for (uint256 n = 0; n < units; ++n) {
            _post(n);
        }
        uint256 active;
        for (uint256 step = 0; step < 40; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 n = seed % units;
            address who = (seed >> 8) % 2 == 0 ? w1 : w2;
            if (held[n]) {
                vm.prank(holder[n]);
                swarm.release(_id(n), ProofSwarm.ReleaseReason.MissingLemma, bytes32(0));
                held[n] = false;
                active -= 1;
            } else if (active == 5) {
                vm.prank(who);
                vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLimitReached.selector, ACC_A));
                swarm.lease(_id(n));
            } else {
                vm.prank(who);
                swarm.lease(_id(n));
                held[n] = true;
                holder[n] = who;
                active += 1;
            }
            assertEq(swarm.accountOf(ACC_A).activeLeases, active);
            assertLe(active, 5);
        }
    }
}

contract ProofSwarmPreferenceTest is SwarmFixture {
    address internal preferred = makeAddr("imd-agent-1927");
    bytes32 internal constant ACC_P = keccak256("preferred-account");

    function setUp() public override {
        super.setUp();
        vm.startPrank(owner);
        swarm.authorizeAccount(ACC_P);
        swarm.registerAgent(preferred, ProofSwarm.Role.ProofDevelopment, ACC_P);
        vm.stopPrank();
    }

    function test_NoReservationUntilThePreferredAgentIsSet() public {
        bytes32 id = _post(1);
        assertEq(swarm.reservedUntil(id), 0);
        _lease(w1, 1);
    }

    function test_NewUnitIsReservedForThePreferredAgent() public {
        vm.prank(owner);
        swarm.setPreferredAgent(preferred);
        bytes32 id = _post(1);
        assertEq(swarm.reservedUntil(id), T0 + 5 minutes);
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.ReservedForPreferredAgent.selector, T0 + 5 minutes));
        swarm.lease(id);
        vm.warp(T0 + 5 minutes - 1);
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.ReservedForPreferredAgent.selector, T0 + 5 minutes));
        swarm.lease(id);
        _lease(preferred, 1);
        assertEq(swarm.leaseOf(id).agent, preferred);
    }

    function test_OthersTakeTheUnitAfterTheWindow() public {
        vm.prank(owner);
        swarm.setPreferredAgent(preferred);
        _post(1);
        vm.warp(T0 + 5 minutes);
        _lease(w1, 1);
    }

    function test_NoReservationWhenThePreferredAgentIsNotAvailable() public {
        vm.prank(owner);
        swarm.setPreferredAgent(preferred);
        for (uint256 n = 1; n <= 6; ++n) {
            _post(n);
        }
        for (uint256 n = 1; n <= 5; ++n) {
            _lease(preferred, n);
        }
        // Its account holds five: unit 6 is free for everyone at once.
        assertEq(swarm.reservedUntil(_id(6)), 0);
        _lease(w1, 6);
    }

    function test_NoReservationWhenUnregisteredRevokedOrAReviewer() public {
        vm.startPrank(owner);
        swarm.setPreferredAgent(stranger);
        vm.stopPrank();
        bytes32 id = _post(1);
        assertEq(swarm.reservedUntil(id), 0);

        vm.prank(owner);
        swarm.setPreferredAgent(r1);
        assertEq(swarm.reservedUntil(id), 0);

        vm.startPrank(owner);
        swarm.setPreferredAgent(preferred);
        assertEq(swarm.reservedUntil(id), T0 + 5 minutes);
        swarm.revokeAccount(ACC_P);
        assertEq(swarm.reservedUntil(id), 0);
        swarm.authorizeAccount(ACC_P);
        swarm.setPreferenceWindow(0);
        assertEq(swarm.reservedUntil(id), 0);
        swarm.setPreferenceWindow(10 minutes);
        assertEq(swarm.reservedUntil(id), T0 + 10 minutes);
        swarm.clearPreferredAgent();
        vm.stopPrank();
        assertEq(swarm.reservedUntil(id), 0);
        _lease(w1, 1);
    }

    function test_UnitThePreferredAgentHandedBackIsNotReservedForItAgain() public {
        vm.prank(owner);
        swarm.setPreferredAgent(preferred);
        bytes32 id = _post(1);
        _lease(preferred, 1);
        vm.prank(preferred);
        swarm.release(id, ProofSwarm.ReleaseReason.MissingLemma, bytes32(0));
        assertEq(swarm.reservedUntil(id), 0);
        _lease(w1, 1);
    }
}

contract ProofSwarmProofTest is SwarmFixture {
    bytes32 internal id;
    bytes32 internal file;

    function setUp() public override {
        super.setUp();
        id = _post(1);
        file = _file(1);
        _lease(w1, 1);
    }

    function test_SubmitForReview() public {
        vm.expectEmit();
        emit ProofSwarm.ProofSubmittedForReview(id, file, w1, 1);
        _submit(w1, 1, file);
        ProofSwarm.Submission memory s = swarm.submissionOf(id);
        assertEq(s.fileHash, file);
        assertEq(s.author, w1);
        assertEq(s.account, ACC_A);
        assertEq(s.price, 100);
        assertEq(s.approvals, 0);
        assertTrue(swarm.fileUsed(file));
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.InReview));
        // Still one of the account's live leases.
        assertEq(swarm.accountOf(ACC_A).activeLeases, 1);
    }

    function test_SubmitRefusedUntilPinsAreConfigured() public {
        ProofSwarm fresh = new ProofSwarm(owner);
        vm.startPrank(owner);
        fresh.authorizeAccount(ACC_A);
        fresh.authorizeAccount(ACC_C);
        fresh.registerAgent(w1, ProofSwarm.Role.ProofDevelopment, ACC_A);
        fresh.registerAgent(c1, ProofSwarm.Role.Coordinator, ACC_C);
        fresh.setApprovedBudget(10);
        vm.stopPrank();
        vm.prank(c1);
        fresh.postUnit(id, _spec(1, 100));
        vm.startPrank(w1);
        fresh.lease(id);
        vm.expectRevert(ProofSwarm.PinsNotConfigured.selector);
        fresh.submitForReview(id, file, _statement(1), _target(1), _imports(1), PIN);
        vm.stopPrank();
        vm.prank(owner);
        fresh.setPinnedDependencies(PIN);
        vm.prank(w1);
        fresh.submitForReview(id, file, _statement(1), _target(1), _imports(1), PIN);
        assertEq(fresh.submissionOf(id).fileHash, file);
    }

    function test_SubmitRefusesAnAlteredStatement() public {
        vm.prank(w1);
        vm.expectRevert(ProofSwarm.AlteredStatement.selector);
        swarm.submitForReview(id, file, keccak256("a weaker statement"), _target(1), _imports(1), PIN);
    }

    function test_SubmitRefusesAnotherPathOrTheoremName() public {
        vm.prank(w1);
        vm.expectRevert(ProofSwarm.WrongTheoremOrPath.selector);
        swarm.submitForReview(id, file, _statement(1), _target(2), _imports(1), PIN);
    }

    function test_SubmitRefusesOtherImports() public {
        vm.prank(w1);
        vm.expectRevert(ProofSwarm.ForbiddenImports.selector);
        swarm.submitForReview(id, file, _statement(1), _target(1), _imports(2), PIN);
    }

    function test_SubmitRefusesAnotherDependencyPin() public {
        vm.prank(w1);
        vm.expectRevert(ProofSwarm.DependencyPinMismatch.selector);
        swarm.submitForReview(id, file, _statement(1), _target(1), _imports(1), keccak256("mathlib master"));
    }

    function test_SubmitFailuresByCallerAndState() public {
        vm.prank(w2);
        vm.expectRevert(ProofSwarm.NotLeaseHolder.selector);
        swarm.submitForReview(id, file, _statement(1), _target(1), _imports(1), PIN);
        vm.prank(r1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.IndependentReviewer));
        swarm.submitForReview(id, file, _statement(1), _target(1), _imports(1), PIN);
        vm.prank(w1);
        vm.expectRevert(ProofSwarm.ZeroValue.selector);
        swarm.submitForReview(id, bytes32(0), _statement(1), _target(1), _imports(1), PIN);
        _submit(w1, 1, file);
        // A second file while the first is under review.
        vm.prank(w1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.InReview));
        swarm.submitForReview(id, _file(2), _statement(1), _target(1), _imports(1), PIN);
    }

    function test_SubmitRefusedOnALapsedLease() public {
        vm.warp(T0 + 46 minutes);
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLapsed.selector, T0 + 45 minutes));
        swarm.submitForReview(id, file, _statement(1), _target(1), _imports(1), PIN);
    }

    function test_SameFileCannotBeSubmittedTwice() public {
        _submit(w1, 1, file);
        _post(2);
        _lease(w3, 2);
        vm.prank(w3);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.DuplicateProofFile.selector, file));
        swarm.submitForReview(_id(2), file, _statement(2), _target(2), _imports(2), PIN);
    }

    function test_TwoIndependentApprovalsValidate() public {
        _submit(w1, 1, file);
        vm.expectEmit();
        emit ProofSwarm.ProofApproved(id, file, r1, RUN);
        vm.prank(r1);
        swarm.approve(id, file, RUN);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.InReview));
        assertEq(swarm.report().validatedProofs, 0);
        vm.expectEmit();
        emit ProofSwarm.ProofValidated(id, file, 2);
        vm.prank(r2);
        swarm.approve(id, file, RUN);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Validated));
        assertEq(swarm.report().validatedProofs, 1);
        assertEq(swarm.accountOf(ACC_A).validated, 1);
    }

    function test_QuorumOfOneValidatesAtOnce() public {
        vm.prank(owner);
        swarm.setReviewQuorum(1);
        _submit(w1, 1, file);
        vm.prank(r1);
        swarm.approve(id, file, RUN);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Validated));
    }

    function test_ApproveFailures() public {
        vm.prank(r1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Leased));
        swarm.approve(id, file, RUN);
        _submit(w1, 1, file);
        // Only independent reviewers review.
        vm.prank(w3);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.LeanVerification));
        swarm.approve(id, file, RUN);
        vm.prank(c1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.Coordinator));
        swarm.approve(id, file, RUN);
        vm.prank(w1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.ProofDevelopment));
        swarm.approve(id, file, RUN);
        // A reviewer on the author's account is not independent.
        vm.prank(rA);
        vm.expectRevert(ProofSwarm.ReviewerNotIndependent.selector);
        swarm.approve(id, file, RUN);
        // The reviewer must name the file under review and bring the checker's run.
        vm.prank(r1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.StaleReview.selector, file));
        swarm.approve(id, _file(2), RUN);
        vm.prank(r1);
        vm.expectRevert(ProofSwarm.MissingEvidence.selector);
        swarm.approve(id, file, bytes32(0));
        // One approval per reviewer account.
        vm.prank(r1);
        swarm.approve(id, file, RUN);
        vm.prank(r1);
        vm.expectRevert(ProofSwarm.AlreadyReviewed.selector);
        swarm.approve(id, file, RUN);
        vm.prank(r1);
        vm.expectRevert(ProofSwarm.AlreadyReviewed.selector);
        swarm.reject(id, file, ProofSwarm.RejectReason.Other, bytes32(0));
    }

    function test_TwoReviewersOnOneAccountCountOnce() public {
        address r1b = makeAddr("second reviewer on reviewer-one");
        vm.prank(owner);
        swarm.registerAgent(r1b, ProofSwarm.Role.IndependentReviewer, ACC_R1);
        _submit(w1, 1, file);
        vm.prank(r1);
        swarm.approve(id, file, RUN);
        vm.prank(r1b);
        vm.expectRevert(ProofSwarm.AlreadyReviewed.selector);
        swarm.approve(id, file, RUN);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.InReview));
    }

    function test_ReviewRefusedOnALapsedLease() public {
        _submit(w1, 1, file);
        vm.warp(T0 + 46 minutes);
        vm.prank(r1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLapsed.selector, T0 + 45 minutes));
        swarm.approve(id, file, RUN);
    }

    function test_RejectForSorryBurnsTheFileAndReturnsTheUnit() public {
        _submit(w1, 1, file);
        vm.prank(r1);
        swarm.approve(id, file, RUN);
        bytes32 log = keccak256("REJECTED (sorry)");
        vm.expectEmit();
        emit ProofSwarm.ProofRejected(id, file, r2, ProofSwarm.RejectReason.ContainsSorry, log);
        vm.prank(r2);
        swarm.reject(id, file, ProofSwarm.RejectReason.ContainsSorry, log);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Leased));
        assertEq(swarm.submissionOf(id).fileHash, bytes32(0));
        assertEq(swarm.accountOf(ACC_A).reviewRejections, 1);
        assertEq(swarm.report().validatedProofs, 0);
        // The rejected file is never accepted again, on this unit or another.
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.DuplicateProofFile.selector, file));
        swarm.submitForReview(id, file, _statement(1), _target(1), _imports(1), PIN);
        // A repaired file starts review from nothing: the earlier approval does not carry over.
        _submit(w1, 1, _file(2));
        assertEq(swarm.submissionOf(id).approvals, 0);
        _approveBoth(1, _file(2));
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Validated));
    }

    function test_EveryRejectReasonIsRecorded() public {
        for (uint8 reason = 1; reason <= uint8(ProofSwarm.RejectReason.Other); ++reason) {
            bytes32 f = _file(100 + reason);
            _submit(w1, 1, f);
            vm.prank(r1);
            swarm.reject(id, f, ProofSwarm.RejectReason(reason), bytes32(0));
        }
        assertEq(swarm.accountOf(ACC_A).reviewRejections, 8);
        assertEq(uint8(ProofSwarm.RejectReason.NativeDecide), 2);
        assertEq(uint8(ProofSwarm.RejectReason.UnauthorizedAxiom), 3);
        assertEq(uint8(ProofSwarm.RejectReason.AlteredStatement), 4);
    }

    function test_RejectFailures() public {
        _submit(w1, 1, file);
        vm.prank(r1);
        vm.expectRevert(ProofSwarm.InvalidRejectReason.selector);
        swarm.reject(id, file, ProofSwarm.RejectReason.None, bytes32(0));
        vm.prank(rA);
        vm.expectRevert(ProofSwarm.ReviewerNotIndependent.selector);
        swarm.reject(id, file, ProofSwarm.RejectReason.Other, bytes32(0));
        vm.prank(w3);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.LeanVerification));
        swarm.reject(id, file, ProofSwarm.RejectReason.Other, bytes32(0));
        vm.prank(r1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.StaleReview.selector, file));
        swarm.reject(id, _file(2), ProofSwarm.RejectReason.Other, bytes32(0));
    }

    function test_RecordPullRequestEndsTheLeaseAsSubmitted() public {
        _submit(w1, 1, file);
        _approveBoth(1, file);
        vm.expectEmit();
        emit ProofSwarm.PullRequestRecorded(id, 4321, file);
        vm.expectEmit();
        emit ProofSwarm.UnitReleased(id, w1, ACC_A, ProofSwarm.ReleaseReason.Submitted, bytes32(uint256(4321)));
        vm.prank(w1);
        swarm.recordPullRequest(id, 4321);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Submitted));
        assertEq(swarm.submissionOf(id).pullRequest, 4321);
        assertTrue(swarm.pullRequestUsed(4321));
        assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
        assertEq(swarm.accountOf(ACC_A).pullRequests, 1);
        assertEq(swarm.report().pullRequests, 1);
        assertEq(swarm.leaseOf(id).agent, address(0));
    }

    function test_PullRequestRefusedBeforeValidation() public {
        vm.prank(w1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Leased));
        swarm.recordPullRequest(id, 1);
        _submit(w1, 1, file);
        vm.prank(r1);
        swarm.approve(id, file, RUN);
        vm.prank(w1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.InReview));
        swarm.recordPullRequest(id, 1);
    }

    function test_PullRequestFailures() public {
        _submit(w1, 1, file);
        _approveBoth(1, file);
        vm.prank(w2);
        vm.expectRevert(ProofSwarm.NotLeaseHolder.selector);
        swarm.recordPullRequest(id, 1);
        vm.prank(w1);
        vm.expectRevert(ProofSwarm.ZeroValue.selector);
        swarm.recordPullRequest(id, 0);
        vm.warp(T0 + 46 minutes);
        vm.prank(w1);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.LeaseLapsed.selector, T0 + 45 minutes));
        swarm.recordPullRequest(id, 1);
    }

    function test_OneProofFilePerPullRequest() public {
        _submit(w1, 1, file);
        _approveBoth(1, file);
        vm.prank(w1);
        swarm.recordPullRequest(id, 77);
        _post(2);
        _lease(w3, 2);
        _submit(w3, 2, _file(2));
        _approveBoth(2, _file(2));
        vm.prank(w3);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.PullRequestAlreadyUsed.selector, uint64(77)));
        swarm.recordPullRequest(_id(2), 77);
        vm.prank(w3);
        swarm.recordPullRequest(_id(2), 78);
    }

    function test_LapseDuringReviewFreesTheFile() public {
        _submit(w1, 1, file);
        _approveBoth(1, file);
        vm.warp(T0 + 46 minutes);
        swarm.expireLease(id);
        assertFalse(swarm.fileUsed(file));
        assertEq(swarm.submissionOf(id).fileHash, bytes32(0));
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Open));
        // Taken again, the same file is reviewed from nothing, by the same reviewers.
        _lease(w3, 1);
        _submit(w3, 1, file);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.InReview));
        _approveBoth(1, file);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Validated));
    }

    function test_ReleaseDuringReviewFreesTheFile() public {
        _submit(w1, 1, file);
        vm.prank(w1);
        swarm.release(id, ProofSwarm.ReleaseReason.HypothesisTooWeak, bytes32(0));
        assertFalse(swarm.fileUsed(file));
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Open));
        assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
    }
}

contract ProofSwarmVerdictTest is SwarmFixture {
    bytes32 internal constant MERGE = keccak256("merge commit");

    function test_AcceptedVerdictCreditsTheLeasePrice() public {
        bytes32 id = _post(1);
        vm.prank(c1);
        swarm.repriceUnit(id, 640);
        _lease(w1, 1);
        _submit(w1, 1, _file(1));
        _approveBoth(1, _file(1));
        vm.prank(w1);
        swarm.recordPullRequest(id, 9);
        vm.expectEmit();
        emit ProofSwarm.VerdictRecorded(id, c1, true, 640, MERGE);
        vm.prank(c1);
        swarm.recordVerdict(id, true, MERGE);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Accepted));
        ProofSwarm.AccountStats memory a = swarm.accountOf(ACC_A);
        assertEq(a.points, 640);
        assertEq(a.accepted, 1);
        assertEq(a.rejected, 0);
        ProofSwarm.SwarmReport memory r = swarm.report();
        assertEq(r.acceptedContributions, 1);
        assertEq(r.points, 640);
        // An accepted unit is final.
        vm.prank(c1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Accepted));
        swarm.recordVerdict(id, false, MERGE);
        vm.prank(w3);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Accepted));
        swarm.lease(id);
        vm.prank(c1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Accepted));
        swarm.withdrawUnit(id, MERGE);
    }

    function test_RejectedVerdictReopensTheUnitAndCreditsNothing() public {
        bytes32 id = _toSubmitted(w1, 1, 9);
        vm.warp(T0 + 3 hours);
        vm.prank(c1);
        swarm.recordVerdict(id, false, keccak256("REJECTED (axioms)"));
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Open));
        assertEq(swarm.unitOf(id).openedAt, T0 + 3 hours);
        assertEq(swarm.accountOf(ACC_A).points, 0);
        assertEq(swarm.accountOf(ACC_A).rejected, 1);
        assertEq(swarm.report().rejectedContributions, 1);
        assertEq(swarm.report().points, 0);
        // Neither the refused file nor its pull request can be used again.
        assertTrue(swarm.fileUsed(_file(1)));
        assertTrue(swarm.pullRequestUsed(9));
        _lease(w3, 1);
        vm.prank(w3);
        vm.expectRevert(abi.encodeWithSelector(ProofSwarm.DuplicateProofFile.selector, _file(1)));
        swarm.submitForReview(id, _file(1), _statement(1), _target(1), _imports(1), PIN);
    }

    function test_VerdictFailures() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        vm.prank(c1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Leased));
        swarm.recordVerdict(id, true, MERGE);
        _submit(w1, 1, _file(1));
        _approveBoth(1, _file(1));
        // Validated by the swarm's reviewers is not accepted by the official checker.
        vm.prank(c1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Validated));
        swarm.recordVerdict(id, true, MERGE);
        vm.prank(w1);
        swarm.recordPullRequest(id, 9);
        vm.prank(w1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.ProofDevelopment));
        swarm.recordVerdict(id, true, MERGE);
        vm.prank(r1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.IndependentReviewer));
        swarm.recordVerdict(id, true, MERGE);
        vm.prank(c1);
        vm.expectRevert(ProofSwarm.MissingEvidence.selector);
        swarm.recordVerdict(id, true, bytes32(0));
        // A coordinator on the author's account cannot credit that account.
        vm.prank(cA);
        vm.expectRevert(ProofSwarm.ReviewerNotIndependent.selector);
        swarm.recordVerdict(id, true, MERGE);
        assertEq(swarm.report().points, 0);
    }

    function test_WithdrawClearsALeaseAndIsFinal() public {
        bytes32 id = _post(1);
        _lease(w1, 1);
        _submit(w1, 1, _file(1));
        bytes32 why = keccak256("desk answered 410 withdrawn");
        vm.prank(w1);
        vm.expectRevert(_wrongRole(ProofSwarm.Role.ProofDevelopment));
        swarm.withdrawUnit(id, why);
        vm.prank(c1);
        vm.expectRevert(ProofSwarm.MissingEvidence.selector);
        swarm.withdrawUnit(id, bytes32(0));
        vm.expectEmit();
        emit ProofSwarm.UnitWithdrawn(id, c1, why);
        vm.prank(c1);
        swarm.withdrawUnit(id, why);
        assertEq(uint8(_status(id)), uint8(ProofSwarm.UnitStatus.Withdrawn));
        assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
        assertFalse(swarm.fileUsed(_file(1)));
        vm.prank(w1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Withdrawn));
        swarm.lease(id);
        vm.prank(c1);
        vm.expectRevert(_notInState(id, ProofSwarm.UnitStatus.Withdrawn));
        swarm.withdrawUnit(id, why);
        vm.prank(c1);
        vm.expectRevert(_notInState(_id(5), ProofSwarm.UnitStatus.None));
        swarm.withdrawUnit(_id(5), why);
    }

    function test_WithdrawOfOpenAndSubmittedUnits() public {
        bytes32 open = _post(1);
        bytes32 submitted = _toSubmitted(w1, 2, 9);
        vm.startPrank(c1);
        swarm.withdrawUnit(open, MERGE);
        swarm.withdrawUnit(submitted, MERGE);
        vm.expectRevert(_notInState(submitted, ProofSwarm.UnitStatus.Withdrawn));
        swarm.recordVerdict(submitted, true, MERGE);
        vm.stopPrank();
        assertEq(swarm.report().points, 0);
        assertEq(swarm.accountOf(ACC_A).activeLeases, 0);
    }

    function test_ReportAddsUp() public {
        // Unit 1 accepted, unit 2 refused by the checker, unit 3 released, unit 4 lapsed, unit 5 held.
        bytes32 u1 = _toSubmitted(w1, 1, 11);
        bytes32 u2 = _toSubmitted(w3, 2, 12);
        vm.startPrank(c1);
        swarm.recordVerdict(u1, true, MERGE);
        swarm.recordVerdict(u2, false, MERGE);
        vm.stopPrank();
        _post(3);
        _lease(w2, 3);
        vm.prank(w2);
        swarm.release(_id(3), ProofSwarm.ReleaseReason.MissingLemma, bytes32(0));
        _post(4);
        _lease(w2, 4);
        vm.warp(T0 + 1 hours);
        swarm.expireLease(_id(4));
        _post(5);
        _lease(w3, 5);
        vm.prank(w1);
        swarm.reportCost(300);
        vm.prank(r1);
        swarm.reportCost(25);

        ProofSwarm.SwarmReport memory r = swarm.report();
        assertEq(r.registeredAgents, 8);
        // w1, w2, w3, r1, r2 and c1 acted; rA and cA never did.
        assertEq(r.participatingAgents, 6);
        assertEq(r.unitsPosted, 5);
        assertEq(r.leasesTaken, 5);
        assertEq(r.releases, 1);
        assertEq(r.expiries, 1);
        assertEq(r.validatedProofs, 2);
        assertEq(r.pullRequests, 2);
        assertEq(r.acceptedContributions, 1);
        assertEq(r.rejectedContributions, 1);
        assertEq(r.points, 100);
        assertEq(r.totalCost, 325);
        assertEq(r.approvedBudget, BUDGET);
        assertEq(swarm.accountOf(ACC_A).points, 100);
        assertEq(swarm.accountOf(ACC_B).points, 0);
        assertEq(swarm.accountOf(ACC_B).activeLeases, 1);
        assertFalse(swarm.agentOf(rA).participated);
        assertTrue(swarm.agentOf(r2).participated);
    }
}
