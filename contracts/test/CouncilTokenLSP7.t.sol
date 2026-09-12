// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CouncilTokenLSP7} from "../src/governance/CouncilTokenLSP7.sol";
import {CouncilTimelock} from "../src/governance/CouncilTimelock.sol";
import {CouncilGovernor} from "../src/governance/CouncilGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

/**
 * @title CouncilTokenLSP7Test
 * @notice Tests for the P11 LSP7-compatible governance token and its integration
 *         with the existing OZ Governor stack.
 *
 * Updated to cover BART audit fixes (2026-03-30):
 *  - H-04: operator mapping is now [tokenOwner][operator] — tests verify correct reads/writes
 *  - H-07: revokeOperator only callable by tokenOwner — operator self-revoke now reverts
 */
contract CouncilTokenLSP7Test is Test {
    CouncilTokenLSP7 public token;
    CouncilTimelock public timelock;
    CouncilGovernor public governor;

    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    address public recipient = makeAddr("recipient");
    address public operatorAccount = makeAddr("operator");

    address public target = makeAddr("target");

    function setUp() public {
        // 1. Deploy LSP7 token
        token = new CouncilTokenLSP7([agent1, agent2]);

        // 2. Deploy timelock
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute
        timelock = new CouncilTimelock(proposers, executors, address(this));

        // 3. Deploy governor with LSP7 token as IVotes
        governor = new CouncilGovernor(
            IVotes(address(token)),
            TimelockController(payable(address(timelock)))
        );

        // 4. Grant roles
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // 5. Mine one block so delegation checkpoints are active
        //    (auto-delegated in constructor via H-01)
        vm.roll(block.number + 1);
    }

    // ══════════════════════════════════════════════════════════
    //  Token Properties
    // ══════════════════════════════════════════════════════════

    function test_name() public view {
        assertEq(token.name(), "Agent Council Token");
    }

    function test_symbol() public view {
        assertEq(token.symbol(), "COUNCIL");
    }

    function test_decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_totalSupply() public view {
        assertEq(token.totalSupply(), 1_000_000 ether);
    }

    function test_tokenType() public view {
        assertEq(token.tokenType(), 0);
    }

    function test_equalTwoMemberDistribution() public view {
        assertEq(token.balanceOf(agent1), 500_000 ether);
        assertEq(token.balanceOf(agent2), 500_000 ether);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(operatorAccount), 0);
    }

    // ══════════════════════════════════════════════════════════
    //  ERC165 Interface Detection
    // ══════════════════════════════════════════════════════════

    function test_supportsLSP7Interface() public view {
        assertTrue(token.supportsInterface(0x05519512)); // LSP7
    }

    function test_supportsERC165Interface() public view {
        assertTrue(token.supportsInterface(type(IERC165).interfaceId));
    }

    function test_supportsIERC5805Interface() public view {
        assertTrue(token.supportsInterface(type(IERC5805).interfaceId));
    }

    function test_doesNotSupportRandomInterface() public view {
        assertFalse(token.supportsInterface(0xdeadbeef));
    }

    // ══════════════════════════════════════════════════════════
    //  Voting Power (IVotes/IERC5805)
    // ══════════════════════════════════════════════════════════

    function test_autoSelfDelegation() public view {
        // H-01: agents should be auto-delegated in constructor
        assertEq(token.delegates(agent1), agent1);
        assertEq(token.delegates(agent2), agent2);
    }

    function test_votingPowerMatchesBalance() public view {
        assertEq(token.getVotes(agent1), 500_000 ether);
        assertEq(token.getVotes(agent2), 500_000 ether);
    }

    function test_delegationMovesVotingPower() public {
        vm.prank(agent2);
        token.delegate(agent1);

        assertEq(token.getVotes(agent1), 1_000_000 ether);
        assertEq(token.getVotes(agent2), 0);
        assertEq(token.balanceOf(agent2), 500_000 ether); // balance unchanged
    }

    function test_getPastVotes() public {
        // Transfer some tokens
        vm.prank(agent1);
        token.transfer(agent1, agent2, 100_000 ether, true, "");
        vm.roll(block.number + 2);

        // Past votes at the checkpoint block should reflect pre-transfer state
        assertEq(token.getPastVotes(agent1, block.number - 3), 500_000 ether);
    }

    // ══════════════════════════════════════════════════════════
    //  LSP7 Transfer
    // ══════════════════════════════════════════════════════════

    function test_transferMovesBalanceAndVotes() public {
        vm.prank(agent1);
        token.transfer(agent1, agent2, 50_000 ether, true, "");

        assertEq(token.balanceOf(agent1), 450_000 ether);
        assertEq(token.balanceOf(agent2), 550_000 ether);

        // Voting power follows balance (both self-delegated)
        assertEq(token.getVotes(agent1), 450_000 ether);
        assertEq(token.getVotes(agent2), 550_000 ether);
    }

    function test_transferRevertsOnSelf() public {
        vm.prank(agent1);
        vm.expectRevert(CouncilTokenLSP7.LSP7CannotSendToSelf.selector);
        token.transfer(agent1, agent1, 100 ether, true, "");
    }

    function test_transferRevertsOnZeroAddress() public {
        vm.prank(agent1);
        vm.expectRevert(CouncilTokenLSP7.LSP7CannotSendToAddressZero.selector);
        token.transfer(agent1, address(0), 100 ether, true, "");
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(recipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                CouncilTokenLSP7.LSP7AmountExceedsBalance.selector,
                0,
                recipient,
                1 ether
            )
        );
        token.transfer(recipient, agent1, 1 ether, true, "");
    }

    // ══════════════════════════════════════════════════════════
    //  LSP7 transferBatch
    // ══════════════════════════════════════════════════════════

    function test_transferBatch() public {
        address[] memory from = new address[](2);
        from[0] = agent1;
        from[1] = agent1;

        address[] memory to = new address[](2);
        to[0] = agent2;
        to[1] = recipient;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10_000 ether;
        amounts[1] = 20_000 ether;

        bool[] memory force = new bool[](2);
        force[0] = true;
        force[1] = true;

        bytes[] memory data = new bytes[](2);
        data[0] = "";
        data[1] = "";

        vm.prank(agent1);
        token.transferBatch(from, to, amounts, force, data);

        assertEq(token.balanceOf(agent1), 470_000 ether);
        assertEq(token.balanceOf(agent2), 510_000 ether);
        assertEq(token.balanceOf(recipient), 20_000 ether);
    }

    function test_transferBatchRevertsOnLengthMismatch() public {
        address[] memory from = new address[](1);
        from[0] = agent1;

        address[] memory to = new address[](2);
        to[0] = agent2;
        to[1] = recipient;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        bool[] memory force = new bool[](1);
        force[0] = true;

        bytes[] memory data = new bytes[](1);
        data[0] = "";

        vm.prank(agent1);
        vm.expectRevert(CouncilTokenLSP7.LSP7InvalidTransferBatch.selector);
        token.transferBatch(from, to, amounts, force, data);
    }

    // ══════════════════════════════════════════════════════════
    //  Operator Model (H-04 corrected mapping order tests)
    // ══════════════════════════════════════════════════════════

    function test_authorizeAndTransferAsOperator() public {
        vm.prank(agent1);
        token.authorizeOperator(agent2, 50_000 ether, "");

        // H-04: authorizedAmountFor reads [tokenOwner][operator]
        assertEq(token.authorizedAmountFor(agent2, agent1), 50_000 ether);

        vm.prank(agent2);
        token.transfer(agent1, recipient, 50_000 ether, true, "");

        assertEq(token.balanceOf(agent1), 450_000 ether);
        assertEq(token.balanceOf(recipient), 50_000 ether);
        assertEq(token.authorizedAmountFor(agent2, agent1), 0);
    }

    function test_revokeOperator() public {
        vm.prank(agent1);
        token.authorizeOperator(agent2, 50_000 ether, "");

        // Only tokenOwner (agent1) can revoke
        vm.prank(agent1);
        token.revokeOperator(agent2, agent1, false, "");

        assertEq(token.authorizedAmountFor(agent2, agent1), 0);
    }

    /**
     * @dev H-07: operator CANNOT unilaterally revoke themselves.
     *      This was previously allowed; now only tokenOwner can revoke.
     */
    function test_operatorCannotSelfRevoke() public {
        vm.prank(agent1);
        token.authorizeOperator(agent2, 50_000 ether, "");

        // agent2 (operator) tries to revoke itself — should revert
        vm.prank(agent2);
        vm.expectRevert("LSP7: only tokenOwner can revoke operator");
        token.revokeOperator(agent2, agent1, false, "");

        // Authorization should still be intact
        assertEq(token.authorizedAmountFor(agent2, agent1), 50_000 ether);
    }

    function test_getOperatorsOf() public {
        vm.prank(agent1);
        token.authorizeOperator(agent2, 100 ether, "");
        vm.prank(agent1);
        token.authorizeOperator(operatorAccount, 200 ether, "");

        address[] memory ops = token.getOperatorsOf(agent1);
        assertEq(ops.length, 2);
    }

    function test_increaseAllowance() public {
        vm.prank(agent1);
        token.authorizeOperator(agent2, 100 ether, "");

        vm.prank(agent1);
        token.increaseAllowance(agent2, 50 ether, "");

        assertEq(token.authorizedAmountFor(agent2, agent1), 150 ether);
    }

    function test_decreaseAllowance() public {
        vm.prank(agent1);
        token.authorizeOperator(agent2, 100 ether, "");

        vm.prank(agent1);
        token.decreaseAllowance(agent2, 30 ether, "");

        assertEq(token.authorizedAmountFor(agent2, agent1), 70 ether);
    }

    function test_decreaseAllowanceToZeroRemovesOperator() public {
        vm.prank(agent1);
        token.authorizeOperator(agent2, 100 ether, "");

        vm.prank(agent1);
        token.decreaseAllowance(agent2, 100 ether, "");

        address[] memory ops = token.getOperatorsOf(agent1);
        assertEq(ops.length, 0);
    }

    function test_authorizeZeroAddressReverts() public {
        vm.prank(agent1);
        vm.expectRevert(CouncilTokenLSP7.LSP7CannotUseAddressZeroAsOperator.selector);
        token.authorizeOperator(address(0), 100 ether, "");
    }

    function test_authorizeSelfReverts() public {
        vm.prank(agent1);
        vm.expectRevert(CouncilTokenLSP7.LSP7TokenOwnerCannotBeOperator.selector);
        token.authorizeOperator(agent1, 100 ether, "");
    }

    // ══════════════════════════════════════════════════════════
    //  Constructor Guards
    // ══════════════════════════════════════════════════════════

    function test_duplicateAgentReverts() public {
        vm.expectRevert(CouncilTokenLSP7.DuplicateAgentAddress.selector);
        new CouncilTokenLSP7([agent1, agent1]);
    }

    function test_zeroAddressAgentReverts() public {
        vm.expectRevert("CouncilToken: zero address agent");
        new CouncilTokenLSP7([address(0), agent2]);
    }

    // ══════════════════════════════════════════════════════════
    //  Full Governor Integration (propose → vote → queue → execute)
    // ══════════════════════════════════════════════════════════

    function test_fullGovernanceFlowWithLSP7() public {
        vm.deal(address(timelock), 1 ether);

        // ── Propose ──
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 0.5 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "P11: Send 0.5 ETH to target via LSP7 governance";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Verify Pending
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // ── Advance past voting delay ──
        vm.roll(block.number + 76);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // ── Vote ──
        vm.prank(agent1);
        governor.castVote(proposalId, 1); // For
        vm.prank(agent2);
        governor.castVote(proposalId, 1); // For
        // ── Advance past voting period ──
        vm.roll(block.number + 50401);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // ── Queue ──
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // ── Advance past timelock ──
        vm.warp(block.timestamp + 3 days + 1);

        // ── Execute ──
        uint256 balanceBefore = target.balance;
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(target.balance, balanceBefore + 0.5 ether);
    }

    function test_proposalThresholdWithLSP7() public view {
        assertEq(governor.proposalThreshold(), 0);
    }

    function test_quorumWithLSP7() public view {
        // 100% of 1,000,000 = both 500,000-token members
        uint256 q = governor.quorum(block.number - 1);
        assertEq(q, 1_000_000 ether);
    }

    function test_proposalDefeatedWithZeroVotes() public {
        vm.deal(address(timelock), 1 ether);

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "Zero votes defeat test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 76);
        vm.roll(block.number + 50401);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_oneMemberAloneCannotMeetQuorum() public {
        vm.deal(address(timelock), 1 ether);

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "One-member solo quorum test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 76);

        vm.prank(agent1);
        governor.castVote(proposalId, 1); // FOR — 500k is below 100% quorum

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

    function test_timelockEnforcedWithLSP7() public {
        vm.deal(address(timelock), 1 ether);

        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 0.1 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";
        string memory description = "Timelock enforcement test";

        vm.prank(agent1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + 76);

        vm.prank(agent1);
        governor.castVote(proposalId, 1);
        vm.prank(agent2);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + 50401);

        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // Execute before delay should revert
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descHash);

        // After delay should succeed
        vm.warp(block.timestamp + 3 days + 1);
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    // ══════════════════════════════════════════════════════════
    //  Voting Power Movement on Transfer
    // ══════════════════════════════════════════════════════════

    function test_votingPowerMovesWithTransfer() public {
        uint256 preVotesAgent1 = token.getVotes(agent1);
        uint256 preVotesAgent2 = token.getVotes(agent2);

        vm.prank(agent1);
        token.transfer(agent1, agent2, 100_000 ether, true, "");

        assertEq(token.getVotes(agent1), preVotesAgent1 - 100_000 ether);
        assertEq(token.getVotes(agent2), preVotesAgent2 + 100_000 ether);
    }

    function test_votingPowerSnapshotAfterTransfer() public {
        vm.prank(agent1);
        token.transfer(agent1, agent2, 100_000 ether, true, "");

        vm.roll(block.number + 2);

        // Past votes should reflect the PRE-transfer state
        assertEq(token.getPastVotes(agent1, block.number - 3), 500_000 ether);
        assertEq(token.getPastVotes(agent2, block.number - 3), 500_000 ether);
    }

    function test_delegatedVotingThroughGovernor() public {
        // agent2 delegates to agent1
        vm.prank(agent2);
        token.delegate(agent1);

        vm.roll(block.number + 1);

        // agent1 now has all votes, agent2 has 0
        assertEq(token.getVotes(agent1), 1_000_000 ether);
        assertEq(token.getVotes(agent2), 0);

        // But agent2 still holds the tokens
        assertEq(token.balanceOf(agent2), 500_000 ether);

        // The Governor has a zero proposal threshold, so a delegated-away member may still propose.
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(agent2);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Zero-threshold delegated proposal");
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    }
}
