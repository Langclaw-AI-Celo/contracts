// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {LangclawTradingJournal} from "../src/LangclawTradingJournal.sol";

contract DeployLangclawTradingJournalScript is Script {
    function run() external returns (LangclawTradingJournal journal) {
        vm.startBroadcast();
        journal = new LangclawTradingJournal();
        vm.stopBroadcast();
    }
}
