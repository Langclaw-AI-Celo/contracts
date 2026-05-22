// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {LangclawRegistry} from "../src/LangclawRegistry.sol";

contract DeployLangclawRegistryScript is Script {
    function run() external returns (LangclawRegistry registry) {
        vm.startBroadcast();
        registry = new LangclawRegistry();
        vm.stopBroadcast();
    }
}
