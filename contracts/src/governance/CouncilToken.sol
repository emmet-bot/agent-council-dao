// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title CouncilToken
 * @notice ERC20 governance token for the Agent Council (P9).
 *
 *  Name:    "Agent Council Token"
 *  Symbol:  "COUNCIL"
 *  Supply:  1,000,000 (18 decimals) — minted equally to the two council members:
 *
 *    agents[0] → 50% (500,000 COUNCIL)
 *    agents[1] → 50% (500,000 COUNCIL)
 *
 *  Voting weight uses OpenZeppelin ERC20Votes (checkpoint-based).
 *
 * @dev LSP7VotesInitAbstract does not exist in the current lsp-smart-contracts
 *      library, so this contract uses the standard OZ ERC20Votes base.
 *      If/when a LUKSO-native voting-weight LSP7 becomes available, a wrapper
 *      or migration path can be added.
 */
contract CouncilToken is ERC20, ERC20Permit, ERC20Votes {
    uint256 public constant TOTAL_SUPPLY = 1_000_000 ether; // 18 decimals

    uint256 public constant SHARE_AGENT_0 = TOTAL_SUPPLY / 2; // 500,000
    uint256 public constant SHARE_AGENT_1 = TOTAL_SUPPLY / 2; // 500,000

    /**
     * @param agents Array of exactly 2 council agent addresses.
     *               Each receives 50% of total supply.
     */
    constructor(address[2] memory agents)
        ERC20("Agent Council Token", "COUNCIL")
        ERC20Permit("Agent Council Token")
    {
        require(agents[0] != address(0), "CouncilToken: zero address agent[0]");
        require(agents[1] != address(0), "CouncilToken: zero address agent[1]");
        require(agents[0] != agents[1], "CouncilToken: duplicate agent");

        _mint(agents[0], SHARE_AGENT_0);
        _mint(agents[1], SHARE_AGENT_1);
    }

    // ──────────────────────── Required overrides ────────────────────────

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
