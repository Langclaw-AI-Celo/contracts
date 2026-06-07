// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LangclawUsageVault} from "../src/LangclawUsageVault.sol";

contract DeployLangclawUsageVaultScript is Script {
    function run() external returns (LangclawUsageVault vault) {
        address owner = vm.envAddress("LANGCLAW_USAGE_VAULT_OWNER");
        address withdrawalAuthority = vm.envAddress("LANGCLAW_USAGE_VAULT_WITHDRAWAL_AUTHORITY");
        address depositToken = vm.envOr("LANGCLAW_USAGE_VAULT_DEPOSIT_TOKEN", address(0));

        vm.startBroadcast();
        vault = new LangclawUsageVault(owner, withdrawalAuthority, depositToken);
        vm.stopBroadcast();
    }
}
