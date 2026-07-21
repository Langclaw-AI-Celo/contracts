// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployLangclawUsageVaultScript} from "../script/DeployLangclawUsageVault.s.sol";
import {LangclawUsageVault} from "../src/LangclawUsageVault.sol";
import {MockUSDT} from "./helpers/LangclawUsageVaultFixtures.sol";

contract DeployLangclawUsageVaultScriptTest is Test {
    DeployLangclawUsageVaultScript internal deployment;

    address internal owner = makeAddr("deploymentOwner");
    address internal withdrawalAuthority = makeAddr("deploymentWithdrawalAuthority");

    function setUp() public {
        deployment = new DeployLangclawUsageVaultScript();
        vm.setEnv("LANGCLAW_USAGE_VAULT_OWNER", vm.toString(owner));
        vm.setEnv("LANGCLAW_USAGE_VAULT_WITHDRAWAL_AUTHORITY", vm.toString(withdrawalAuthority));
    }

    function test_RevertWhenDepositTokenHasNoCode() public {
        address invalidToken = makeAddr("invalidDepositToken");
        vm.setEnv("LANGCLAW_USAGE_VAULT_DEPOSIT_TOKEN", vm.toString(invalidToken));

        vm.expectRevert(
            abi.encodeWithSelector(DeployLangclawUsageVaultScript.InvalidDepositToken.selector, invalidToken)
        );
        deployment.run();
    }

    function test_DeploysNativeVaultWhenDepositTokenIsZero() public {
        vm.setEnv("LANGCLAW_USAGE_VAULT_DEPOSIT_TOKEN", vm.toString(address(0)));

        LangclawUsageVault vault = deployment.run();

        assertEq(vault.owner(), owner);
        assertEq(vault.withdrawalAuthority(), withdrawalAuthority);
        assertEq(vault.depositToken(), address(0));
    }

    function test_DeploysVaultWithContractDepositToken() public {
        MockUSDT token = new MockUSDT();
        vm.setEnv("LANGCLAW_USAGE_VAULT_DEPOSIT_TOKEN", vm.toString(address(token)));

        LangclawUsageVault vault = deployment.run();

        assertEq(vault.owner(), owner);
        assertEq(vault.withdrawalAuthority(), withdrawalAuthority);
        assertEq(vault.depositToken(), address(token));
    }
}
