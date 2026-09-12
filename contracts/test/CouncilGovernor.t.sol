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
 * @notice Full propose → vote → queue → execute flow test for Agent Council governance.
 */
contract CouncilGovernorTest is Test {
    CouncilToken public token;
    CouncilTimelock public timelock;
    CouncilGovernor public governor;

    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");

    // Target contract for governance action
    address public target = makeAddr("target");

    function setUp() public {
        // 1. Deploy token — mints equally to 2 agents
        token = new CouncilToken([agent1, agent2]);

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

        // 7. Mine one block so delegation checkpoints are active
        vm.roll(block.number + 1);
    }

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

        // ── Advance past voting delay (75 blocks) ──
        vm.roll(block.number + 76);

        // Verify proposal is Active
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // ── Vote — both council members vote For ──
        vm.prank(agent1);
        governor.castVote(proposalId, 1); // For
        vm.prank(agent2);
        governor.castVote(proposalId, 1); // For

        // ── Advance past voting period (50400 blocks) ──
        vm.roll(block.number + 50401);

        // Verify proposal succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // ── Queue ──
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // ── Advance past timelock delay (1 day) ──
        vm.warp(block.timestamp + 3 days + 1);

        // ── Execute ──
        uint256 balanceBefore = target.balance;
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(target.balance, balanceBefore + 0.5 ether);
    }

    function test_proposalThreshold() public view {
        assertEq(governor.proposalThreshold(), 0);
    }

    function test_votingDelay() public view {
        assertEq(governor.votingDelay(), 75);
    }

    function test_votingPeriod() public view {
        assertEq(governor.votingPeriod(), 50400); // ~7 days at 12s/block
    }

    function test_quorum() public view {
        // 100% of 1,000,000 tokens = both 500,000-token members
        uint256 q = governor.quorum(block.number - 1);
        assertEq(q, 1_000_000 ether);
    }

    // Tests that a proposal with zero votes is defeated (no participation at all)
    function test_proposalDefeatedWithZeroVotes() public {
        vm.deal(address(timelock), 1 ether);

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "Zero votes test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 76);
        // No votes cast
        vm.roll(block.number + 50401);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // One 50% member cannot approve a council proposal alone.
    function test_oneMemberAloneCannotPassProposal() public {
        vm.deal(address(timelock), 1 ether);

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "One-member solo vote test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 76);

        // Only one member votes FOR (50% < 100% quorum)
        vm.prank(agent1);
        governor.castVote(proposalId, 1); // FOR

        vm.roll(block.number + 50401);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_oneYesAndOneAbstainCannotPassProposal() public {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Unanimous affirmative vote test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 76);
        vm.prank(agent1);
        governor.castVote(proposalId, 1); // For
        vm.prank(agent2);
        governor.castVote(proposalId, 2); // Abstain
        vm.roll(block.number + 50401);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_zeroTokenAddressCanProposeAtZeroThreshold() public {
        address nobody = makeAddr("nobody");

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(nobody);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Zero-threshold proposal");
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    }

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

        vm.roll(block.number + 76);

        // Vote
        vm.prank(agent1);
        governor.castVote(proposalId, 1);
        vm.prank(agent2);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 50401);

        // Queue
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // Try to execute immediately — should revert (timelock not ready)
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descHash);

        // After delay — should succeed
        vm.warp(block.timestamp + 3 days + 1);
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }
}
