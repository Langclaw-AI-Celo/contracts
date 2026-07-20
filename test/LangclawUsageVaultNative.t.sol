// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Test} from "forge-std/Test.sol";
import {LangclawUsageVault} from "../src/LangclawUsageVault.sol";
import {
    MockUSDT,
    ReentrantWithdrawalReceiver,
    RevertingWithdrawalReceiver
} from "./helpers/LangclawUsageVaultFixtures.sol";

contract LangclawUsageVaultTest is Test {
    LangclawUsageVault internal vault;

    address internal owner = makeAddr("owner");
    address internal withdrawalAuthority = makeAddr("withdrawalAuthority");
    address internal payer = makeAddr("payer");
    address internal stranger = makeAddr("stranger");

    event Deposit(address indexed payer, uint256 amount, bytes32 indexed depositReference);
    event Withdrawal(address indexed payer, uint256 amount);
    event VaultPaused(address indexed owner);
    event VaultUnpaused(address indexed owner);
    event WithdrawalAuthorized(address indexed payer, uint256 amount, bytes32 indexed withdrawalId);
    event WithdrawalAuthorityUpdated(address indexed previousAuthority, address indexed newAuthority);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        vault = new LangclawUsageVault(owner, withdrawalAuthority, address(0));
        vm.deal(payer, 100 ether);
        vm.deal(stranger, 100 ether);
    }

    function test_RevertZeroConstructorAuthority() public {
        vm.expectRevert(LangclawUsageVault.InvalidWithdrawalAuthority.selector);
        new LangclawUsageVault(owner, address(0), address(0));
    }

    function test_NativeAndTokenConstructorState() public {
        MockUSDT token = new MockUSDT();
        LangclawUsageVault tokenVault = new LangclawUsageVault(owner, withdrawalAuthority, address(token));

        assertEq(vault.owner(), owner);
        assertEq(vault.withdrawalAuthority(), withdrawalAuthority);
        assertEq(vault.depositToken(), address(0));
        assertEq(vault.vaultBalance(), 0);

        assertEq(tokenVault.owner(), owner);
        assertEq(tokenVault.withdrawalAuthority(), withdrawalAuthority);
        assertEq(tokenVault.depositToken(), address(token));
        assertEq(tokenVault.vaultBalance(), 0);
    }

    function test_DepositEmitsReference() public {
        bytes32 depositReference = keccak256("top-up-request-1");
        uint256 amount = 1.5 ether;

        vm.expectEmit(true, false, true, true, address(vault));
        emit Deposit(payer, amount, depositReference);

        vm.prank(payer);
        vault.deposit{value: amount}(depositReference);

        assertEq(address(vault).balance, amount);
        assertEq(vault.vaultBalance(), amount);
    }

    function test_NativeDepositAcceptsErc8021TaggedCalldata() public {
        bytes32 depositReference = keccak256("tagged-native-deposit");
        uint256 amount = 1 ether;
        bytes memory payload = abi.encodeCall(vault.deposit, (depositReference));
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.expectEmit(true, false, true, true, address(vault));
        emit Deposit(payer, amount, depositReference);

        vm.prank(payer);
        (bool success,) = address(vault).call{value: amount}(bytes.concat(payload, suffix));

        assertTrue(success);
        assertEq(address(vault).balance, amount);
        assertEq(vault.vaultBalance(), amount);
    }

    function test_ReceiveEmitsEmptyReference() public {
        uint256 amount = 2 ether;

        vm.expectEmit(true, false, true, true, address(vault));
        emit Deposit(payer, amount, bytes32(0));

        vm.prank(payer);
        (bool success,) = address(vault).call{value: amount}("");

        assertTrue(success);
        assertEq(address(vault).balance, amount);
    }

    function test_RevertZeroDeposit() public {
        vm.expectRevert(LangclawUsageVault.ZeroAmount.selector);

        vm.prank(payer);
        vault.deposit{value: 0}(keccak256("zero"));
    }

    function test_RevertZeroReceiveDeposit() public {
        vm.prank(payer);
        (bool success, bytes memory reason) = address(vault).call{value: 0}("");

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 0x20))
        }

        assertFalse(success);
        assertEq(selector, LangclawUsageVault.ZeroAmount.selector);
    }

    function test_PauseBlocksDepositAndUnpauseRestoresIt() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit Paused(owner);
        vm.expectEmit(true, false, false, true, address(vault));
        emit VaultPaused(owner);

        vm.prank(owner);
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(payer);
        vault.deposit{value: 1 ether}(keccak256("paused"));

        vm.expectEmit(false, false, false, true, address(vault));
        emit Unpaused(owner);
        vm.expectEmit(true, false, false, true, address(vault));
        emit VaultUnpaused(owner);

        vm.prank(owner);
        vault.unpause();

        vm.prank(payer);
        vault.deposit{value: 1 ether}(keccak256("open"));

        assertEq(address(vault).balance, 1 ether);
    }

    function test_PauseAndUnpauseAcceptErc8021TaggedCalldata() public {
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.expectEmit(false, false, false, true, address(vault));
        emit Paused(owner);
        vm.expectEmit(true, false, false, true, address(vault));
        emit VaultPaused(owner);

        vm.prank(owner);
        (bool pauseSuccess,) = address(vault).call(bytes.concat(abi.encodeCall(vault.pause, ()), suffix));

        assertTrue(pauseSuccess);
        assertTrue(vault.paused());

        vm.expectEmit(false, false, false, true, address(vault));
        emit Unpaused(owner);
        vm.expectEmit(true, false, false, true, address(vault));
        emit VaultUnpaused(owner);

        vm.prank(owner);
        (bool unpauseSuccess,) = address(vault).call(bytes.concat(abi.encodeCall(vault.unpause, ()), suffix));

        assertTrue(unpauseSuccess);
        assertFalse(vault.paused());
    }

    function test_RepeatedPauseTransitionsRevertWithoutChangingState() public {
        vm.prank(owner);
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        vault.pause();

        assertTrue(vault.paused());

        vm.prank(owner);
        vault.unpause();

        vm.expectRevert(Pausable.ExpectedPause.selector);
        vm.prank(owner);
        vault.unpause();

        assertFalse(vault.paused());
    }

    function test_PauseBlocksDirectNativeTransfersWithoutMovingFunds() public {
        vm.prank(owner);
        vault.pause();

        uint256 payerBalanceBefore = payer.balance;
        uint256 vaultBalanceBefore = address(vault).balance;

        vm.prank(payer);
        (bool success, bytes memory reason) = address(vault).call{value: 1 ether}("");

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 0x20))
        }

        assertFalse(success);
        assertEq(selector, Pausable.EnforcedPause.selector);
        assertEq(payer.balance, payerBalanceBefore);
        assertEq(address(vault).balance, vaultBalanceBefore);
    }

    function test_OnlyOwnerCanPause() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));

        vm.prank(stranger);
        vault.pause();
    }

    function test_TwoStepOwnershipTransfer() public {
        address newOwner = makeAddr("new-owner");

        vm.prank(owner);
        vault.transferOwnership(newOwner);

        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), newOwner);

        vm.prank(newOwner);
        vault.acceptOwnership();

        assertEq(vault.owner(), newOwner);
        assertEq(vault.pendingOwner(), address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        vault.pause();

        vm.prank(newOwner);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_TwoStepOwnershipTransferAcceptsErc8021TaggedCalldata() public {
        address newOwner = makeAddr("tagged-new-owner");
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.prank(owner);
        (bool transferSuccess,) =
            address(vault).call(bytes.concat(abi.encodeCall(vault.transferOwnership, (newOwner)), suffix));

        assertTrue(transferSuccess);
        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), newOwner);

        vm.prank(newOwner);
        (bool acceptSuccess,) = address(vault).call(bytes.concat(abi.encodeCall(vault.acceptOwnership, ()), suffix));

        assertTrue(acceptSuccess);
        assertEq(vault.owner(), newOwner);
        assertEq(vault.pendingOwner(), address(0));
    }

    function test_AcceptedOwnerControlsRecoveryFromPausedState() public {
        address newOwner = makeAddr("paused-new-owner");

        vm.startPrank(owner);
        vault.pause();
        vault.transferOwnership(newOwner);
        vm.stopPrank();

        vm.prank(newOwner);
        vault.acceptOwnership();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        vault.unpause();

        assertTrue(vault.paused());

        vm.prank(newOwner);
        vault.unpause();

        assertFalse(vault.paused());
        assertEq(vault.owner(), newOwner);
    }

    function test_AcceptedOwnerControlsWithdrawalAuthorityRotation() public {
        address newOwner = makeAddr("authority-new-owner");
        address newAuthority = makeAddr("authority-from-new-owner");

        vm.prank(owner);
        vault.transferOwnership(newOwner);

        vm.prank(newOwner);
        vault.acceptOwnership();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        vault.setWithdrawalAuthority(newAuthority);

        assertEq(vault.withdrawalAuthority(), withdrawalAuthority);

        vm.prank(newOwner);
        vault.setWithdrawalAuthority(newAuthority);

        assertEq(vault.owner(), newOwner);
        assertEq(vault.withdrawalAuthority(), newAuthority);
    }

    function test_PendingOwnerCannotManageVaultBeforeAcceptance() public {
        address pendingOwner = makeAddr("pending-owner");

        vm.prank(owner);
        vault.transferOwnership(pendingOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pendingOwner));
        vm.prank(pendingOwner);
        vault.pause();

        assertFalse(vault.paused());
        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), pendingOwner);

        vm.prank(owner);
        vault.pause();

        assertTrue(vault.paused());
    }

    function test_PendingOwnerCannotUnpauseVaultBeforeAcceptance() public {
        address pendingOwner = makeAddr("pending-recovery-owner");

        vm.startPrank(owner);
        vault.pause();
        vault.transferOwnership(pendingOwner);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pendingOwner));
        vm.prank(pendingOwner);
        vault.unpause();

        assertTrue(vault.paused());
        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), pendingOwner);
    }

    function test_OwnerCanCancelPendingOwnershipTransfer() public {
        address canceledOwner = makeAddr("canceled-owner");

        vm.startPrank(owner);
        vault.transferOwnership(canceledOwner);
        vault.transferOwnership(address(0));
        vm.stopPrank();

        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, canceledOwner));
        vm.prank(canceledOwner);
        vault.acceptOwnership();

        assertEq(vault.owner(), owner);

        vm.prank(owner);
        vault.pause();

        assertTrue(vault.paused());
    }

    function test_ReplacedPendingOwnerCannotAcceptOwnership() public {
        address replacedOwner = makeAddr("replaced-pending-owner");
        address replacementOwner = makeAddr("replacement-pending-owner");

        vm.startPrank(owner);
        vault.transferOwnership(replacedOwner);
        vault.transferOwnership(replacementOwner);
        vm.stopPrank();

        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), replacementOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, replacedOwner));
        vm.prank(replacedOwner);
        vault.acceptOwnership();

        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), replacementOwner);

        vm.prank(replacementOwner);
        vault.acceptOwnership();

        assertEq(vault.owner(), replacementOwner);
        assertEq(vault.pendingOwner(), address(0));
    }

    function test_RevertZeroWithdrawal() public {
        vm.expectRevert(LangclawUsageVault.ZeroAmount.selector);

        vm.prank(payer);
        vault.withdraw(0);
    }

    function test_RevertWithdrawalWithoutAuthorization() public {
        vm.expectRevert(abi.encodeWithSelector(LangclawUsageVault.UnauthorizedWithdrawal.selector, payer, 1 ether, 0));

        vm.prank(payer);
        vault.withdraw(1 ether);
    }

    function test_AuthorizeWithdrawalRequiresAuthority() public {
        vm.expectRevert(LangclawUsageVault.InvalidWithdrawalAuthority.selector);

        vm.prank(stranger);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("withdrawal-unauthorized"));
    }

    function test_AuthorizeWithdrawalRejectsInvalidPayer() public {
        _depositFrom(payer, 1 ether);

        vm.expectRevert(LangclawUsageVault.InvalidPayer.selector);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(address(0), 1 ether, keccak256("withdrawal-invalid-payer"));
    }

    function test_AuthorizeWithdrawalRejectsZeroAmount() public {
        vm.expectRevert(LangclawUsageVault.ZeroAmount.selector);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 0, keccak256("withdrawal-zero"));
    }

    function test_AuthorizeWithdrawalAcceptsErc8021TaggedCalldata() public {
        uint256 amount = 1 ether;
        bytes32 withdrawalId = keccak256("tagged-authorization");

        _depositFrom(payer, amount);

        bytes memory payload = abi.encodeCall(vault.authorizeWithdrawal, (payer, amount, withdrawalId));
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.expectEmit(true, false, true, true, address(vault));
        emit WithdrawalAuthorized(payer, amount, withdrawalId);

        vm.prank(withdrawalAuthority);
        (bool success,) = address(vault).call(bytes.concat(payload, suffix));

        assertTrue(success);
        assertTrue(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), amount);
        assertEq(vault.totalAuthorizedWithdrawals(), amount);
    }

    function test_AuthorizeWithdrawalRejectsReplayId() public {
        bytes32 withdrawalId = keccak256("withdrawal-id");

        _depositFrom(payer, 2 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);

        vm.expectRevert(abi.encodeWithSelector(LangclawUsageVault.WithdrawalIdAlreadyUsed.selector, withdrawalId));

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);
    }

    function test_AuthorizeWithdrawalRejectsReplayIdAcrossPayers() public {
        address secondPayer = makeAddr("replay-second-payer");
        bytes32 withdrawalId = keccak256("global-withdrawal-id");

        _depositFrom(payer, 2 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);

        vm.expectRevert(abi.encodeWithSelector(LangclawUsageVault.WithdrawalIdAlreadyUsed.selector, withdrawalId));

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(secondPayer, 1 ether, withdrawalId);

        assertEq(vault.authorizedWithdrawals(secondPayer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 1 ether);
    }

    function test_RejectedAuthorizationDoesNotConsumeWithdrawalId() public {
        bytes32 withdrawalId = keccak256("withdrawal-too-large");

        _depositFrom(payer, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(LangclawUsageVault.InsufficientVaultBalance.selector, 1 ether + 1 wei, 1 ether)
        );

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether + 1 wei, withdrawalId);

        assertFalse(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);

        _depositFrom(stranger, 1 wei);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether + 1 wei, withdrawalId);

        assertTrue(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), 1 ether + 1 wei);
        assertEq(vault.totalAuthorizedWithdrawals(), 1 ether + 1 wei);
    }

    function test_ExistingAuthorizationsReserveCapacityAcrossPayers() public {
        address secondPayer = makeAddr("capacity-second-payer");
        bytes32 secondWithdrawalId = keccak256("capacity-second-withdrawal");

        _depositFrom(payer, 5 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 4 ether, keccak256("capacity-first-withdrawal"));

        vm.expectRevert(abi.encodeWithSelector(LangclawUsageVault.InsufficientVaultBalance.selector, 6 ether, 5 ether));
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(secondPayer, 2 ether, secondWithdrawalId);

        assertFalse(vault.usedWithdrawalIds(secondWithdrawalId));
        assertEq(vault.authorizedWithdrawals(secondPayer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 4 ether);

        _depositFrom(stranger, 1 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(secondPayer, 2 ether, secondWithdrawalId);

        assertTrue(vault.usedWithdrawalIds(secondWithdrawalId));
        assertEq(vault.authorizedWithdrawals(secondPayer), 2 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 6 ether);
    }

    function test_AuthorizedWithdrawalTransfersAndReducesAllowance() public {
        uint256 depositAmount = 5 ether;
        uint256 withdrawalAmount = 2 ether;
        bytes32 withdrawalId = keccak256("withdrawal-happy");

        _depositFrom(payer, depositAmount);

        vm.expectEmit(true, false, true, true, address(vault));
        emit WithdrawalAuthorized(payer, withdrawalAmount, withdrawalId);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, withdrawalId);

        uint256 payerBalanceBefore = payer.balance;

        vm.expectEmit(true, false, false, true, address(vault));
        emit Withdrawal(payer, withdrawalAmount);

        vm.prank(payer);
        vault.withdraw(withdrawalAmount);

        assertEq(payer.balance, payerBalanceBefore + withdrawalAmount);
        assertEq(address(vault).balance, depositAmount - withdrawalAmount);
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
    }

    function test_NativeWithdrawalAcceptsErc8021TaggedCalldata() public {
        uint256 depositAmount = 3 ether;
        uint256 withdrawalAmount = 1 ether;

        _depositFrom(payer, depositAmount);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, keccak256("tagged-native-withdrawal"));

        uint256 payerBalanceBefore = payer.balance;
        bytes memory payload = abi.encodeCall(vault.withdraw, (withdrawalAmount));
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.expectEmit(true, false, false, true, address(vault));
        emit Withdrawal(payer, withdrawalAmount);

        vm.prank(payer);
        (bool success,) = address(vault).call(bytes.concat(payload, suffix));

        assertTrue(success);
        assertEq(payer.balance, payerBalanceBefore + withdrawalAmount);
        assertEq(address(vault).balance, depositAmount - withdrawalAmount);
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
    }

    function test_RepeatedAuthorizationsAccumulateForSamePayer() public {
        _depositFrom(payer, 5 ether);

        vm.startPrank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("same-payer-first"));
        vault.authorizeWithdrawal(payer, 2 ether, keccak256("same-payer-second"));
        vm.stopPrank();

        assertEq(vault.authorizedWithdrawals(payer), 3 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 3 ether);

        vm.prank(payer);
        vault.withdraw(3 ether);

        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), 3 ether);
    }

    function test_ConsumedWithdrawalIdRemainsUsedAfterFullWithdrawal() public {
        bytes32 withdrawalId = keccak256("consumed-after-withdrawal");

        _depositFrom(payer, 2 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);

        vm.prank(payer);
        vault.withdraw(1 ether);

        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertTrue(vault.usedWithdrawalIds(withdrawalId));

        vm.expectRevert(abi.encodeWithSelector(LangclawUsageVault.WithdrawalIdAlreadyUsed.selector, withdrawalId));
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);

        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
    }

    function test_MultiPayerPartialWithdrawalAccounting() public {
        address secondPayer = makeAddr("second-payer");
        _depositFrom(payer, 10 ether);

        vm.startPrank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 4 ether, keccak256("payer-one-authorization"));
        vault.authorizeWithdrawal(secondPayer, 3 ether, keccak256("payer-two-authorization"));
        vm.stopPrank();

        vm.prank(payer);
        vault.withdraw(1.5 ether);

        vm.prank(secondPayer);
        vault.withdraw(1 ether);

        assertEq(vault.authorizedWithdrawals(payer), 2.5 ether);
        assertEq(vault.authorizedWithdrawals(secondPayer), 2 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 4.5 ether);
        assertEq(vault.totalWithdrawn(), 2.5 ether);
        assertEq(vault.vaultBalance(), 7.5 ether);
        assertEq(payer.balance, 1.5 ether);
        assertEq(secondPayer.balance, 1 ether);
    }

    function test_WithdrawalCannotExceedAllowance() public {
        _depositFrom(payer, 3 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("withdrawal-partial"));

        uint256 payerBalanceBefore = payer.balance;
        uint256 vaultBalanceBefore = address(vault).balance;

        vm.expectRevert(
            abi.encodeWithSelector(LangclawUsageVault.UnauthorizedWithdrawal.selector, payer, 1 ether + 1 wei, 1 ether)
        );

        vm.prank(payer);
        vault.withdraw(1 ether + 1 wei);

        assertEq(payer.balance, payerBalanceBefore);
        assertEq(address(vault).balance, vaultBalanceBefore);
        assertEq(vault.authorizedWithdrawals(payer), 1 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 1 ether);
        assertEq(vault.totalWithdrawn(), 0);
    }

    function test_PausedWithdrawalPreservesAuthorizationState() public {
        bytes32 withdrawalId = keccak256("withdrawal-paused");

        _depositFrom(payer, 3 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);

        vm.prank(owner);
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);

        vm.prank(payer);
        vault.withdraw(1 ether);

        assertEq(payer.balance, 0);
        assertEq(address(vault).balance, 3 ether);
        assertEq(vault.authorizedWithdrawals(payer), 1 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 1 ether);
        assertEq(vault.totalWithdrawn(), 0);
        assertTrue(vault.usedWithdrawalIds(withdrawalId));
    }

    function test_PauseAllowsAuthorizationForWithdrawalAfterRecovery() public {
        bytes32 withdrawalId = keccak256("authorization-during-pause");

        _depositFrom(payer, 2 ether);

        vm.prank(owner);
        vault.pause();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);

        assertEq(vault.authorizedWithdrawals(payer), 1 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 1 ether);
        assertTrue(vault.usedWithdrawalIds(withdrawalId));

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(payer);
        vault.withdraw(1 ether);

        vm.prank(owner);
        vault.unpause();

        vm.prank(payer);
        vault.withdraw(1 ether);

        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), 1 ether);
        assertEq(payer.balance, 1 ether);
    }

    function test_OwnerCanRotateWithdrawalAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.expectEmit(true, true, false, true, address(vault));
        emit WithdrawalAuthorityUpdated(withdrawalAuthority, newAuthority);

        vm.prank(owner);
        vault.setWithdrawalAuthority(newAuthority);

        assertEq(vault.withdrawalAuthority(), newAuthority);
    }

    function test_WithdrawalAuthorityRotationAcceptsErc8021TaggedCalldata() public {
        address newAuthority = makeAddr("tagged-new-authority");
        bytes memory payload = abi.encodeCall(vault.setWithdrawalAuthority, (newAuthority));
        bytes memory suffix = hex"63656c6f5f316139383733383633366462110080218021802180218021802180218021";

        vm.expectEmit(true, true, false, true, address(vault));
        emit WithdrawalAuthorityUpdated(withdrawalAuthority, newAuthority);

        vm.prank(owner);
        (bool success,) = address(vault).call(bytes.concat(payload, suffix));

        assertTrue(success);
        assertEq(vault.withdrawalAuthority(), newAuthority);
    }

    function test_OwnerCanRotateWithdrawalAuthorityWhilePaused() public {
        address newAuthority = makeAddr("paused-rotation-authority");
        bytes32 withdrawalId = keccak256("paused-rotation-authorization");

        _depositFrom(payer, 2 ether);

        vm.startPrank(owner);
        vault.pause();
        vault.setWithdrawalAuthority(newAuthority);
        vm.stopPrank();

        vm.expectRevert(LangclawUsageVault.InvalidWithdrawalAuthority.selector);
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("retired-paused-authority"));

        vm.prank(newAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);

        assertTrue(vault.paused());
        assertEq(vault.withdrawalAuthority(), newAuthority);
        assertTrue(vault.usedWithdrawalIds(withdrawalId));
        assertEq(vault.authorizedWithdrawals(payer), 1 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 1 ether);
    }

    function test_OnlyOwnerCanRotateWithdrawalAuthority() public {
        address newAuthority = makeAddr("unauthorized-new-authority");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));

        vm.prank(stranger);
        vault.setWithdrawalAuthority(newAuthority);

        assertEq(vault.withdrawalAuthority(), withdrawalAuthority);
    }

    function test_RotatedAuthorityControlsWithdrawalAccess() public {
        address newAuthority = makeAddr("rotated-authority");
        _depositFrom(payer, 2 ether);

        vm.prank(owner);
        vault.setWithdrawalAuthority(newAuthority);

        vm.expectRevert(LangclawUsageVault.InvalidWithdrawalAuthority.selector);
        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("old-authority"));

        vm.prank(newAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("new-authority"));

        assertEq(vault.authorizedWithdrawals(payer), 1 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 1 ether);
    }

    function test_AuthorizationRemainsWithdrawableAfterAuthorityRotation() public {
        address newAuthority = makeAddr("allowance-rotation-authority");

        _depositFrom(payer, 2 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("allowance-before-rotation"));

        vm.prank(owner);
        vault.setWithdrawalAuthority(newAuthority);

        vm.prank(payer);
        vault.withdraw(1 ether);

        assertEq(vault.withdrawalAuthority(), newAuthority);
        assertEq(vault.authorizedWithdrawals(payer), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), 1 ether);
        assertEq(payer.balance, 1 ether);
    }

    function test_RevertInvalidWithdrawalAuthorityRotation() public {
        vm.expectRevert(LangclawUsageVault.InvalidWithdrawalAuthority.selector);

        vm.prank(owner);
        vault.setWithdrawalAuthority(address(0));

        assertEq(vault.withdrawalAuthority(), withdrawalAuthority);

        _depositFrom(payer, 1 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("authorization-after-rejected-rotation"));

        assertEq(vault.authorizedWithdrawals(payer), 1 ether);
        assertEq(vault.totalAuthorizedWithdrawals(), 1 ether);
    }

    function test_RenounceOwnershipIsDisabled() public {
        vm.expectRevert(LangclawUsageVault.OwnershipRenounceDisabled.selector);

        vm.prank(owner);
        vault.renounceOwnership();
    }

    function test_NonOwnerCannotReachDisabledRenouncePath() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));

        vm.prank(stranger);
        vault.renounceOwnership();

        assertEq(vault.owner(), owner);
        assertEq(vault.pendingOwner(), address(0));
    }

    function test_ReentrancyIsBlockedDuringWithdrawal() public {
        ReentrantWithdrawalReceiver receiver = new ReentrantWithdrawalReceiver(vault);
        uint256 amount = 1 ether;

        _depositFrom(payer, amount);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(address(receiver), amount, keccak256("withdrawal-reentrant"));

        receiver.attack(amount);

        assertTrue(receiver.reentryBlocked());
        assertEq(receiver.lastRevertSelector(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(address(receiver).balance, amount);
        assertEq(address(vault).balance, 0);
        assertEq(vault.authorizedWithdrawals(address(receiver)), 0);
        assertEq(vault.totalAuthorizedWithdrawals(), 0);
        assertEq(vault.totalWithdrawn(), amount);
    }

    function test_RevertWhenNativeTransferFails() public {
        RevertingWithdrawalReceiver receiver = new RevertingWithdrawalReceiver(vault);
        uint256 amount = 1 ether;

        _depositFrom(payer, amount);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(address(receiver), amount, keccak256("withdrawal-transfer-fails"));

        vm.expectRevert(
            abi.encodeWithSelector(LangclawUsageVault.NativeTransferFailed.selector, address(receiver), amount)
        );

        receiver.withdrawFromVault(amount);

        assertEq(address(receiver).balance, 0);
        assertEq(address(vault).balance, amount);
        assertEq(vault.authorizedWithdrawals(address(receiver)), amount);
        assertEq(vault.totalAuthorizedWithdrawals(), amount);
        assertEq(vault.totalWithdrawn(), 0);
    }

    function testFuzz_Deposit(bytes32 depositReference, uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1 wei, 100 ether);
        vm.deal(payer, amount);

        vm.expectEmit(true, false, true, true, address(vault));
        emit Deposit(payer, amount, depositReference);

        vm.prank(payer);
        vault.deposit{value: amount}(depositReference);

        assertEq(address(vault).balance, amount);
    }

    function testFuzz_AuthorizedWithdrawal(uint96 rawDepositAmount, uint96 rawWithdrawalAmount) public {
        uint256 depositAmount = bound(uint256(rawDepositAmount), 1 wei, 100 ether);
        uint256 withdrawalAmount = bound(uint256(rawWithdrawalAmount), 1 wei, depositAmount);

        vm.deal(payer, depositAmount);
        vm.prank(payer);
        vault.deposit{value: depositAmount}(keccak256("fuzz-deposit"));

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, keccak256(abi.encode("fuzz-withdrawal", withdrawalAmount)));

        uint256 payerBalanceBefore = payer.balance;

        vm.prank(payer);
        vault.withdraw(withdrawalAmount);

        assertEq(payer.balance, payerBalanceBefore + withdrawalAmount);
        assertEq(address(vault).balance, depositAmount - withdrawalAmount);
        assertEq(vault.totalWithdrawn(), withdrawalAmount);
    }

    function _depositFrom(address depositor, uint256 amount) private {
        vm.deal(depositor, amount);
        vm.prank(depositor);
        vault.deposit{value: amount}(keccak256("deposit"));
    }
}
