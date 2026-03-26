// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CouncilToken} from "../src/governance/CouncilToken.sol";
import {CouncilTimelock} from "../src/governance/CouncilTimelock.sol";
import {CouncilGovernor} from "../src/governance/CouncilGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title CouncilGovernorTest
 * @notice Full test suite for Agent Council governance with LSP7-compatible token.
 *
 *  Tests cover:
 *   1. Full governance flow (propose → vote → queue → execute)
 *   2. Proposal threshold
 *   3. Voting delay
 *   4. Voting period (updated to 21600)
 *   5. Quorum (10% of 1M)
 *   6. Proposal defeat (no quorum)
 *   7. Cannot propose without enough tokens
 *   8. Timelock delay enforcement
 *   9. Skewed token distribution (40/30/20/10%)
 *  10. LSP7 transfer + delegation
 *  11. LSP7 operator authorization
 */
contract CouncilGovernorTest is Test {
    CouncilToken public token;
    CouncilTimelock public timelock;
    CouncilGovernor public governor;

    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    address public agent3 = makeAddr("agent3");
    address public agent4 = makeAddr("agent4");

    // Target contract for governance action
    address public target = makeAddr("target");

    function setUp() public {
        // 1. Deploy token — mints to 4 agents with skewed distribution
        token = new CouncilToken([agent1, agent2, agent3, agent4]);

        // 2. Deploy timelock — deployer as temp admin
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute
        timelock = new CouncilTimelock(proposers, executors, address(this));

        // 3. Deploy governor
        governor = new CouncilGovernor(
            IVotes(address(token)),
            TimelockController(payable(address(timelock)))
        );

        // 4. Grant Governor proposer + canceller roles
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // 5. Revoke deployer admin
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // 6. Agents delegate to themselves (activate voting power)
        vm.prank(agent1);
        token.delegate(agent1);
        vm.prank(agent2);
        token.delegate(agent2);
        vm.prank(agent3);
        token.delegate(agent3);
        vm.prank(agent4);
        token.delegate(agent4);

        // 7. Mine one block so delegation checkpoints are active
        vm.roll(block.number + 1);
    }

    // ──────────────────────── Test 1: Full Governance Flow ────────────────────────

    function test_fullGovernanceFlow() public {
        // Fund the timelock so it can send ETH
        vm.deal(address(timelock), 1 ether);

        // ── Propose ──
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 0.5 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = ""; // just send ETH
        string memory description = "Send 0.5 ETH to target";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Verify proposal is Pending
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // ── Advance past voting delay (1 block) ──
        vm.roll(block.number + 2);

        // Verify proposal is Active
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // ── Vote — agent1 (40%) + agent2 (30%) vote For ──
        vm.prank(agent1);
        governor.castVote(proposalId, 1); // For
        vm.prank(agent2);
        governor.castVote(proposalId, 1); // For

        // ── Advance past voting period (21600 blocks) ──
        vm.roll(block.number + 21601);

        // Verify proposal succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // ── Queue ──
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // ── Advance past timelock delay (1 day) ──
        vm.warp(block.timestamp + 1 days + 1);

        // ── Execute ──
        uint256 balanceBefore = target.balance;
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(target.balance, balanceBefore + 0.5 ether);
    }

    // ──────────────────────── Test 2: Proposal Threshold ────────────────────────

    function test_proposalThreshold() public view {
        assertEq(governor.proposalThreshold(), 1e18);
    }

    // ──────────────────────── Test 3: Voting Delay ────────────────────────

    function test_votingDelay() public view {
        assertEq(governor.votingDelay(), 1);
    }

    // ──────────────────────── Test 4: Voting Period ────────────────────────

    function test_votingPeriod() public view {
        assertEq(governor.votingPeriod(), 21600);
    }

    // ──────────────────────── Test 5: Quorum ────────────────────────

    function test_quorum() public view {
        // 10% of 1,000,000 tokens = 100,000
        uint256 q = governor.quorum(block.number - 1);
        assertEq(q, 100_000 ether);
    }

    // ──────────────────────── Test 6: Defeat Without Quorum ────────────────────────

    function test_proposalFailsWithoutQuorum() public {
        vm.deal(address(timelock), 1 ether);

        // Propose
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "No quorum test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Advance past voting delay
        vm.roll(block.number + 2);

        // Nobody votes

        // Advance past voting period
        vm.roll(block.number + 21601);

        // Proposal should be defeated (no votes)
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ──────────────────────── Test 7: Cannot Propose Without Tokens ────────────────────────

    function test_cannotProposeWithoutEnoughTokens() public {
        address nobody = makeAddr("nobody");

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(nobody);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");
    }

    // ──────────────────────── Test 8: Timelock Delay Enforced ────────────────────────

    function test_timelockDelayEnforced() public {
        vm.deal(address(timelock), 1 ether);

        // Propose
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 0.1 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "Timelock delay test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 2);

        // Vote — agent1 (40%) alone is enough for quorum (10%)
        vm.prank(agent1);
        governor.castVote(proposalId, 1);
        vm.prank(agent2);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 21601);

        // Queue
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // Try to execute immediately — should revert (timelock not ready)
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descHash);

        // After delay — should succeed
        vm.warp(block.timestamp + 1 days + 1);
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    // ──────────────────────── Test 9: Skewed Token Distribution ────────────────────────

    function test_skewedDistribution() public view {
        assertEq(token.balanceOf(agent1), 400_000 ether, "Agent1 should have 40%");
        assertEq(token.balanceOf(agent2), 300_000 ether, "Agent2 should have 30%");
        assertEq(token.balanceOf(agent3), 200_000 ether, "Agent3 should have 20%");
        assertEq(token.balanceOf(agent4), 100_000 ether, "Agent4 should have 10%");
        assertEq(token.totalSupply(), 1_000_000 ether, "Total supply should be 1M");
    }

    // ──────────────────────── Test 10: LSP7 Transfer + Delegation ────────────────────────

    function test_lsp7TransferAndDelegation() public {
        // Agent1 transfers 100k tokens to agent4 via LSP7 transfer
        vm.prank(agent1);
        token.transfer(agent1, agent4, 100_000 ether, true, "");

        // Verify balances
        assertEq(token.balanceOf(agent1), 300_000 ether);
        assertEq(token.balanceOf(agent4), 200_000 ether);

        // Re-delegate to update voting power checkpoints
        vm.prank(agent1);
        token.delegate(agent1);
        vm.prank(agent4);
        token.delegate(agent4);

        // Mine a block for checkpoints
        vm.roll(block.number + 1);

        // Verify voting power updated
        assertEq(token.getVotes(agent1), 300_000 ether);
        assertEq(token.getVotes(agent4), 200_000 ether);
    }

    // ──────────────────────── Test 11: LSP7 Operator Authorization ────────────────────────

    function test_lsp7OperatorAuthorization() public {
        address operator = makeAddr("operator");

        // Agent1 authorizes operator for 50k tokens
        vm.prank(agent1);
        token.authorizeOperator(operator, 50_000 ether, "");

        assertEq(token.authorizedAmountFor(operator, agent1), 50_000 ether);

        // Operator transfers 30k from agent1 to agent3
        vm.prank(operator);
        token.transfer(agent1, agent3, 30_000 ether, true, "");

        assertEq(token.balanceOf(agent1), 370_000 ether);
        assertEq(token.balanceOf(agent3), 230_000 ether);
        assertEq(token.authorizedAmountFor(operator, agent1), 20_000 ether);

        // Revoke operator
        vm.prank(agent1);
        token.revokeOperator(operator, agent1, false, "");
        assertEq(token.authorizedAmountFor(operator, agent1), 0);
    }

    // ──────────────────────── Test 12: Proposal Defeated by Against Votes ────────────────────────

    function test_proposalDefeatedByAgainstVotes() public {
        vm.deal(address(timelock), 1 ether);

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 0.1 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "Defeated proposal test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 2);

        // Agent4 (10%) votes For, Agents 1+2+3 (90%) vote Against
        vm.prank(agent4);
        governor.castVote(proposalId, 1); // For
        vm.prank(agent1);
        governor.castVote(proposalId, 0); // Against
        vm.prank(agent2);
        governor.castVote(proposalId, 0); // Against
        vm.prank(agent3);
        governor.castVote(proposalId, 0); // Against

        vm.roll(block.number + 21601);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }
}
