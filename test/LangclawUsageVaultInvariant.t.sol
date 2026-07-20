// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LangclawUsageVault} from "../src/LangclawUsageVault.sol";

contract LangclawUsageVaultHandler is Test {
    LangclawUsageVault internal immutable vault;
    address internal immutable withdrawalAuthority;

    address[] internal payers;

    uint256 public totalDeposited;
    uint256 public totalAuthorizedAmount;

    constructor(LangclawUsageVault vault_, address withdrawalAuthority_) {
        vault = vault_;
        withdrawalAuthority = withdrawalAuthority_;

        payers.push(address(0x1001));
        payers.push(address(0x1002));
        payers.push(address(0x1003));
        payers.push(address(0x1004));
    }

    function deposit(uint256 payerSeed, uint96 rawAmount, bytes32 depositReference) public {
        address payer = _payer(payerSeed);
        uint256 amount = bound(uint256(rawAmount), 1 wei, 10 ether);

        vm.deal(payer, amount);
        vm.prank(payer);
        vault.deposit{value: amount}(depositReference);

        totalDeposited += amount;
    }

    function authorizeWithdrawal(uint256 payerSeed, uint96 rawAmount, uint256 withdrawalSeed) public {
        uint256 availableBalance = address(vault).balance - vault.totalAuthorizedWithdrawals();
        if (availableBalance == 0) {
            return;
        }

        address payer = _payer(payerSeed);
        uint256 amount = bound(uint256(rawAmount), 1 wei, availableBalance);
        bytes32 withdrawalId = keccak256(abi.encode("invariant-withdrawal", withdrawalSeed, totalAuthorizedAmount));

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, amount, withdrawalId);

        totalAuthorizedAmount += amount;
    }

    function withdraw(uint256 payerSeed, uint96 rawAmount) public {
        address payer = _payer(payerSeed);
        uint256 authorizedAmount = vault.authorizedWithdrawals(payer);
        if (authorizedAmount == 0) {
            return;
        }

        uint256 amount = bound(uint256(rawAmount), 1 wei, authorizedAmount);

        vm.prank(payer);
        vault.withdraw(amount);
    }

    function payerAt(uint256 index) external view returns (address) {
        return payers[index];
    }

    function payerCount() external view returns (uint256) {
        return payers.length;
    }

    function _payer(uint256 payerSeed) private view returns (address) {
        return payers[payerSeed % payers.length];
    }
}

contract LangclawUsageVaultInvariantTest is Test {
    LangclawUsageVault internal vault;
    LangclawUsageVaultHandler internal handler;

    address internal owner = makeAddr("invariantOwner");
    address internal withdrawalAuthority = makeAddr("invariantWithdrawalAuthority");

    function setUp() public {
        vault = new LangclawUsageVault(owner, withdrawalAuthority, address(0));
        handler = new LangclawUsageVaultHandler(vault, withdrawalAuthority);

        targetContract(address(handler));
    }

    function invariant_TotalAuthorizedWithdrawalsStaySolvent() public view {
        assertLe(vault.totalAuthorizedWithdrawals(), address(vault).balance);
    }

    function invariant_TotalAuthorizationEqualsPayerAllowances() public view {
        uint256 allowanceTotal;

        for (uint256 index; index < handler.payerCount(); ++index) {
            allowanceTotal += vault.authorizedWithdrawals(handler.payerAt(index));
        }

        assertEq(vault.totalAuthorizedWithdrawals(), allowanceTotal);
    }

    function invariant_TotalWithdrawnNeverExceedsBackendAuthorization() public view {
        assertLe(vault.totalWithdrawn(), handler.totalAuthorizedAmount());
    }

    function invariant_VaultBalancePlusWithdrawalsEqualsDeposits() public view {
        assertEq(address(vault).balance + vault.totalWithdrawn(), handler.totalDeposited());
    }
}
