// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/governance/SimpleAuditRegistry.sol";

contract DeploySimpleAuditRegistry is Script {
    function run() external {
        uint256 chainId = block.chainid;
        if (chainId != 8453) {
            revert("This script must run on Base Mainnet (chainId 8453)");
        }

        address councilUP = 0x888033b1492161B5F867573d675d178FA56854Ae;
        address owner = vm.envOr("AUDIT_REGISTRY_OWNER", councilUP);

        vm.startBroadcast();
        new SimpleAuditRegistry(owner);
        vm.stopBroadcast();
    }
}
