// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test} from "forge-std/Test.sol";
import {LangclawUsageVault} from "../src/LangclawUsageVault.sol";
import {FailingTransferFromToken, FailingTransferToken, MockUSDT} from "./helpers/LangclawUsageVaultFixtures.sol";

contract LangclawUsageVaultTokenTest is Test {
    LangclawUsageVault internal vault;
    MockUSDT internal usdt;

    address internal owner = makeAddr("tokenOwner");
    address internal withdrawalAuthority = makeAddr("tokenWithdrawalAuthority");
    address internal payer = makeAddr("tokenPayer");
    address internal stranger = makeAddr("tokenStranger");

    event Deposit(address indexed payer, uint256 amount, bytes32 indexed depositReference);
    event Withdrawal(address indexed payer, uint256 amount);

    function setUp() public {
        usdt = new MockUSDT();
        vault = new LangclawUsageVault(owner, withdrawalAuthority, address(usdt));
        usdt.mint(payer, 1_000e6);
    }

    function test_DepositTokenAmountTransfersUSDTAndEmitsReference() public {
        bytes32 depositReference = keccak256("usdt-deposit");
        uint256 amount = 25e6;

        vm.prank(payer);
        usdt.approve(address(vault), amount);

        vm.expectEmit(true, false, true, true, address(vault));
        emit Deposit(payer, amount, depositReference);

        vm.prank(payer);
        vault.depositTokenAmount(depositReference, amount);

        assertEq(usdt.balanceOf(address(vault)), amount);
        assertEq(vault.vaultBalance(), amount);
    }

    function test_FailedTokenDepositPreservesPayerFundsAndAllowance() public {
        FailingTransferFromToken token = new FailingTransferFromToken();
        LangclawUsageVault failingVault = new LangclawUsageVault(owner, withdrawalAuthority, address(token));
        uint256 amount = 25e6;

        token.mint(payer, amount);
        vm.prank(payer);
        token.approve(address(failingVault), amount);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        vm.prank(payer);
        failingVault.depositTokenAmount(keccak256("failed-token-deposit"), amount);

        assertEq(token.balanceOf(payer), amount);
        assertEq(token.balanceOf(address(failingVault)), 0);
        assertEq(token.allowance(payer, address(failingVault)), amount);
        assertEq(failingVault.vaultBalance(), 0);
    }

    function test_TokenDepositAcceptsErc8021TaggedCalldata() public {
        bytes32 depositReference = keccak256("tagged-usdt-deposit");
        uint256 amount = 25e6;
        bytes memory payload = abi.encodeCall(vault.depositTokenAmount, (depositReference, amount));
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.prank(payer);
        usdt.approve(address(vault), amount);

        vm.expectEmit(true, false, true, true, address(vault));
        emit Deposit(payer, amount, depositReference);

        vm.prank(payer);
        (bool success,) = address(vault).call(bytes.concat(payload, suffix));

        assertTrue(success);
        assertEq(usdt.balanceOf(address(vault)), amount);
        assertEq(vault.vaultBalance(), amount);
    }

    function test_TokenDepositRejectsZeroAmount() public {
        vm.expectRevert(LangclawUsageVault.ZeroAmount.selector);

        vm.prank(payer);
        vault.depositTokenAmount(keccak256("usdt-zero"), 0);
    }

    function test_TokenVaultRejectsNativeDeposit() public {
        vm.deal(payer, 1 ether);

        vm.expectRevert(LangclawUsageVault.UnsupportedNativeDeposit.selector);

        vm.prank(payer);
        vault.deposit{value: 1 ether}(keccak256("native"));
    }

    function test_NativeVaultRejectsTokenDepositFunction() public {
        LangclawUsageVault nativeVault = new LangclawUsageVault(owner, withdrawalAuthority, address(0));

        vm.expectRevert(LangclawUsageVault.UnsupportedTokenDeposit.selector);

        nativeVault.depositTokenAmount(keccak256("token"), 1);
    }

    function test_TokenWithdrawalTransfersUSDT() public {
        uint256 depositAmount = 100e6;
        uint256 withdrawalAmount = 40e6;

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, keccak256("withdrawal"));

        uint256 payerBalanceBefore = usdt.balanceOf(payer);

        vm.expectEmit(true, false, false, true, address(vault));
        emit Withdrawal(payer, withdrawalAmount);

        vm.prank(payer);
        vault.withdraw(withdrawalAmount);

        assertEq(usdt.balanceOf(payer), payerBalanceBefore + withdrawalAmount);
        assertEq(usdt.balanceOf(address(vault)), depositAmount - withdrawalAmount);
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
    }

    function test_FailedTokenTransferPreservesWithdrawalState() public {
        FailingTransferToken token = new FailingTransferToken();
        LangclawUsageVault failingVault = new LangclawUsageVault(owner, withdrawalAuthority, address(token));
        uint256 amount = 25e6;

        token.mint(payer, amount);
        vm.startPrank(payer);
        token.approve(address(failingVault), amount);
        failingVault.depositTokenAmount(keccak256("failing-token-deposit"), amount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        failingVault.authorizeWithdrawal(payer, amount, keccak256("failing-token-withdrawal"));
        token.setTransferFailure(true);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        vm.prank(payer);
        failingVault.withdraw(amount);

        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(address(failingVault)), amount);
        assertEq(failingVault.authorizedWithdrawals(payer), amount);
        assertEq(failingVault.totalAuthorizedWithdrawals(), amount);
        assertEq(failingVault.totalWithdrawn(), 0);
    }

    function testFuzz_TokenPartialWithdrawalAccounting(
        uint96 rawDepositAmount,
        uint96 rawAuthorizationAmount,
        uint96 rawWithdrawalAmount
    ) public {
        uint256 depositAmount = bound(uint256(rawDepositAmount), 1, 1_000e6);
        uint256 authorizationAmount = bound(uint256(rawAuthorizationAmount), 1, depositAmount);
        uint256 withdrawalAmount = bound(uint256(rawWithdrawalAmount), 1, authorizationAmount);

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("fuzz-token-deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(
            payer, authorizationAmount, keccak256(abi.encode("fuzz-token-withdrawal", authorizationAmount))
        );

        uint256 payerBalanceBefore = usdt.balanceOf(payer);

        vm.prank(payer);
        vault.withdraw(withdrawalAmount);

        assertEq(usdt.balanceOf(payer), payerBalanceBefore + withdrawalAmount);
        assertEq(usdt.balanceOf(address(vault)), depositAmount - withdrawalAmount);
        assertEq(vault.authorizedWithdrawals(payer), authorizationAmount - withdrawalAmount);
        assertEq(vault.totalAuthorizedWithdrawals(), authorizationAmount - withdrawalAmount);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
    }

    function test_TokenWithdrawalAcceptsErc8021TaggedCalldata() public {
        uint256 depositAmount = 100e6;
        uint256 withdrawalAmount = 40e6;

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("tagged-withdrawal-deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, keccak256("tagged-withdrawal"));

        uint256 payerBalanceBefore = usdt.balanceOf(payer);
        bytes memory payload = abi.encodeCall(vault.withdraw, (withdrawalAmount));
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.expectEmit(true, false, false, true, address(vault));
        emit Withdrawal(payer, withdrawalAmount);

        vm.prank(payer);
        (bool success,) = address(vault).call(bytes.concat(payload, suffix));

        assertTrue(success);
        assertEq(usdt.balanceOf(payer), payerBalanceBefore + withdrawalAmount);
        assertEq(usdt.balanceOf(address(vault)), depositAmount - withdrawalAmount);
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
    }

    function test_TokenAuthorizationCannotExceedTokenBalance() public {
        uint256 depositAmount = 10e6;
        bytes32 withdrawalId = keccak256("too-large");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("deposit"), depositAmount);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                LangclawUsageVault.InsufficientVaultBalance.selector, depositAmount + 1, depositAmount
            )
        );

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(stranger, depositAmount + 1, withdrawalId);

        assertFalse(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(stranger), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);

        vm.startPrank(payer);
        usdt.approve(address(vault), 1);
        vault.depositTokenAmount(keccak256("deposit-retry"), 1);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(stranger, depositAmount + 1, withdrawalId);

        assertTrue(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(stranger), depositAmount + 1);
        assertEq(vault.totalAuthorizedWithdrawals(), depositAmount + 1);
    }

    function test_TokenAuthorizationsReserveCapacityAcrossPayers() public {
        uint256 depositAmount = 10e6;
        uint256 firstAuthorization = 7e6;
        uint256 secondAuthorization = 4e6;
        bytes32 secondWithdrawalId = keccak256("token-capacity-second-payer");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-capacity-deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, firstAuthorization, keccak256("token-capacity-first-payer"));

        vm.expectRevert(
            abi.encodeWithSelector(
                LangclawUsageVault.InsufficientVaultBalance.selector,
                firstAuthorization + secondAuthorization,
                depositAmount
            )
        );
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(stranger, secondAuthorization, secondWithdrawalId);

        assertFalse(vault.usedWithdrawalIds(secondWithdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), firstAuthorization);
        assertEq(vault.authorizedWithdrawals(stranger), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), firstAuthorization);

        vm.startPrank(payer);
        usdt.approve(address(vault), 1e6);
        vault.depositTokenAmount(keccak256("token-capacity-top-up"), 1e6);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(stranger, secondAuthorization, secondWithdrawalId);

        assertTrue(vault.usedWithdrawalIds(secondWithdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), firstAuthorization);
        assertEq(vault.authorizedWithdrawals(stranger), secondAuthorization);
        assertEq(vault.totalAuthorizedWithdrawals(), firstAuthorization + secondAuthorization);
        assertEq(vault.vaultBalance(), depositAmount + 1e6);
    }

    function test_TokenVaultRejectsPlainNativeTransfer() public {
        vm.deal(payer, 1 ether);

        vm.prank(payer);
        (bool success, bytes memory reason) = address(vault).call{value: 1 ether}("");

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 0x20))
        }

        assertFalse(success);
        assertEq(selector, LangclawUsageVault.UnsupportedNativeDeposit.selector);
    }

    function test_PausedTokenVaultBlocksDepositAndWithdraw() public {
        uint256 depositAmount = 20e6;
        uint256 withdrawalAmount = 5e6;
        bytes32 withdrawalId = keccak256("token-paused-withdrawal");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-before-pause"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, withdrawalId);

        vm.prank(owner);
        vault.pause();

        vm.startPrank(payer);
        usdt.approve(address(vault), withdrawalAmount);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.depositTokenAmount(keccak256("token-paused-deposit"), withdrawalAmount);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.withdraw(withdrawalAmount);
        vm.stopPrank();

        assertEq(usdt.balanceOf(payer), 1_000e6 - depositAmount);
        assertEq(usdt.balanceOf(address(vault)), depositAmount);
        assertEq(vault.authorizedWithdrawals(payer), withdrawalAmount);
        assertEq(vault.totalAuthorizedWithdrawals(), withdrawalAmount);
        assertEq(vault.totalWithdrawn(), 0);
        assertTrue(vault.usedWithdrawalIds(withdrawalId));
    }

    function test_PausedTokenVaultAllowsAuthorizationForRecovery() public {
        uint256 depositAmount = 20e6;
        uint256 withdrawalAmount = 5e6;
        bytes32 withdrawalId = keccak256("token-paused-recovery");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-recovery-deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(owner);
        vault.pause();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, withdrawalId);

        assertTrue(vault.paused());
        assertTrue(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), withdrawalAmount);
        assertEq(vault.totalAuthorizedWithdrawals(), withdrawalAmount);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(payer);
        vault.withdraw(withdrawalAmount);

        vm.prank(owner);
        vault.unpause();

        uint256 payerBalanceBefore = usdt.balanceOf(payer);
        vm.prank(payer);
        vault.withdraw(withdrawalAmount);

        assertEq(usdt.balanceOf(payer), payerBalanceBefore + withdrawalAmount);
        assertEq(usdt.balanceOf(address(vault)), depositAmount - withdrawalAmount);
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
    }

    function test_TokenAuthorizationRequiresConfiguredAuthority() public {
        uint256 depositAmount = 10e6;
        uint256 withdrawalAmount = 4e6;
        bytes32 withdrawalId = keccak256("token-unauthorized-authority");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-authority-deposit"), depositAmount);
        vm.stopPrank();

        vm.expectRevert(LangclawUsageVault.InvalidWithdrawalAuthority.selector);
        vm.prank(stranger);
        vault.authorizeWithdrawal(payer, withdrawalAmount, withdrawalId);

        assertFalse(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.vaultBalance(), depositAmount);
    }

    function test_TokenAuthorizationRejectsZeroPayerWithoutChangingState() public {
        uint256 depositAmount = 10e6;
        bytes32 withdrawalId = keccak256("token-zero-payer");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-zero-payer-deposit"), depositAmount);
        vm.stopPrank();

        vm.expectRevert(LangclawUsageVault.InvalidPayer.selector);
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(address(0), 1e6, withdrawalId);

        assertFalse(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.vaultBalance(), depositAmount);
    }

    function test_TokenAuthorizationRejectsZeroAmountWithoutChangingState() public {
        uint256 depositAmount = 10e6;
        bytes32 withdrawalId = keccak256("token-zero-authorization");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-zero-authorization-deposit"), depositAmount);
        vm.stopPrank();

        vm.expectRevert(LangclawUsageVault.ZeroAmount.selector);
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 0, withdrawalId);

        assertFalse(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.vaultBalance(), depositAmount);
    }

    function test_TokenWithdrawalRejectsZeroAmountWithoutChangingAuthorization() public {
        uint256 depositAmount = 10e6;
        uint256 withdrawalAmount = 4e6;

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-zero-withdrawal-deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, keccak256("token-zero-withdrawal"));

        vm.expectRevert(LangclawUsageVault.ZeroAmount.selector);
        vm.prank(payer);
        vault.withdraw(0);

        assertEq(vault.authorizedWithdrawals(payer), withdrawalAmount);
        assertEq(vault.totalAuthorizedWithdrawals(), withdrawalAmount);
        assertEq(vault.totalWithdrawn(), 0);
        assertEq(vault.vaultBalance(), depositAmount);
    }

    function test_TokenWithdrawalRejectsUnauthorizedPayerWithoutChangingBalances() public {
        uint256 depositAmount = 10e6;
        uint256 withdrawalAmount = 1e6;

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-unauthorized-withdrawal-deposit"), depositAmount);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(LangclawUsageVault.UnauthorizedWithdrawal.selector, stranger, withdrawalAmount, 0)
        );
        vm.prank(stranger);
        vault.withdraw(withdrawalAmount);

        assertEq(usdt.balanceOf(stranger), 0);
        assertEq(vault.authorizedWithdrawals(stranger), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), 0);
        assertEq(vault.vaultBalance(), depositAmount);
    }

    function test_TokenWithdrawalIdCannotReplayAcrossPayers() public {
        uint256 depositAmount = 10e6;
        uint256 firstAuthorization = 3e6;
        bytes32 withdrawalId = keccak256("token-cross-payer-replay");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-cross-payer-deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, firstAuthorization, withdrawalId);

        vm.expectRevert(abi.encodeWithSelector(LangclawUsageVault.WithdrawalIdAlreadyUsed.selector, withdrawalId));
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(stranger, 1e6, withdrawalId);

        assertTrue(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), firstAuthorization);
        assertEq(vault.authorizedWithdrawals(stranger), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), firstAuthorization);
        assertEq(vault.vaultBalance(), depositAmount);
    }

    function test_RepeatedTokenAuthorizationsAccumulateAndClearAfterWithdrawal() public {
        uint256 depositAmount = 10e6;
        uint256 firstAuthorization = 3e6;
        uint256 secondAuthorization = 2e6;
        uint256 totalAuthorization = firstAuthorization + secondAuthorization;

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-repeat-deposit"), depositAmount);
        vm.stopPrank();

        vm.startPrank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, firstAuthorization, keccak256("token-repeat-first"));
        vault.authorizeWithdrawal(payer, secondAuthorization, keccak256("token-repeat-second"));
        vm.stopPrank();

        assertEq(vault.authorizedWithdrawals(payer), totalAuthorization);
        assertEq(vault.totalAuthorizedWithdrawals(), totalAuthorization);

        uint256 payerBalanceBefore = usdt.balanceOf(payer);
        vm.prank(payer);
        vault.withdraw(totalAuthorization);

        assertEq(usdt.balanceOf(payer), payerBalanceBefore + totalAuthorization);
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), totalAuthorization);
        assertEq(vault.vaultBalance(), depositAmount - totalAuthorization);
    }

    function test_ConsumedTokenWithdrawalIdRemainsUsedAfterFullWithdrawal() public {
        uint256 depositAmount = 10e6;
        uint256 withdrawalAmount = 4e6;
        bytes32 withdrawalId = keccak256("token-consumed-withdrawal-id");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-consumed-id-deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, withdrawalId);

        vm.prank(payer);
        vault.withdraw(withdrawalAmount);

        vm.expectRevert(abi.encodeWithSelector(LangclawUsageVault.WithdrawalIdAlreadyUsed.selector, withdrawalId));
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1e6, withdrawalId);

        assertTrue(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
        assertEq(vault.vaultBalance(), depositAmount - withdrawalAmount);
    }

    function test_TokenAuthorizationRemainsWithdrawableAfterAuthorityRotation() public {
        uint256 depositAmount = 10e6;
        uint256 withdrawalAmount = 4e6;
        address newAuthority = makeAddr("rotatedTokenAuthority");

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-rotation-deposit"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, keccak256("token-before-rotation"));

        vm.prank(owner);
        vault.setWithdrawalAuthority(newAuthority);

        vm.expectRevert(LangclawUsageVault.InvalidWithdrawalAuthority.selector);
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1e6, keccak256("token-old-authority"));

        uint256 payerBalanceBefore = usdt.balanceOf(payer);
        vm.prank(payer);
        vault.withdraw(withdrawalAmount);

        assertEq(vault.withdrawalAuthority(), newAuthority);
        assertEq(usdt.balanceOf(payer), payerBalanceBefore + withdrawalAmount);
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
        assertEq(vault.vaultBalance(), depositAmount - withdrawalAmount);
    }

    function test_AcceptedTokenVaultOwnerControlsAuthorityRotation() public {
        address newOwner = makeAddr("newTokenVaultOwner");
        address newAuthority = makeAddr("newTokenVaultAuthority");

        vm.prank(owner);
        vault.transferOwnership(newOwner);

        vm.prank(newOwner);
        vault.acceptOwnership();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        vault.setWithdrawalAuthority(newAuthority);

        vm.prank(newOwner);
        vault.setWithdrawalAuthority(newAuthority);

        assertEq(vault.owner(), newOwner);
        assertEq(vault.pendingOwner(), address(0));
        assertEq(vault.withdrawalAuthority(), newAuthority);
    }
}
