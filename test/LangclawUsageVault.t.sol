// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test} from "forge-std/Test.sol";
import {LangclawUsageVault} from "../src/LangclawUsageVault.sol";

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

contract ReentrantWithdrawalReceiver {
    LangclawUsageVault internal immutable vault;

    bool public reentryBlocked;
    bytes4 public lastRevertSelector;

    constructor(LangclawUsageVault vault_) {
        vault = vault_;
    }

    receive() external payable {
        try vault.withdraw(1 wei) {
            reentryBlocked = false;
        } catch (bytes memory reason) {
            reentryBlocked = true;
            if (reason.length >= 4) {
                bytes4 selector;
                assembly {
                    selector := mload(add(reason, 0x20))
                }
                lastRevertSelector = selector;
            }
        }
    }

    function attack(uint256 amount) external {
        vault.withdraw(amount);
    }
}

contract RevertingWithdrawalReceiver {
    LangclawUsageVault internal immutable vault;

    constructor(LangclawUsageVault vault_) {
        vault = vault_;
    }

    receive() external payable {
        revert("native-transfer-rejected");
    }

    function withdrawFromVault(uint256 amount) external {
        vault.withdraw(amount);
    }
}

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
}

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FailingTransferToken is ERC20 {
    bool internal transferFails;

    constructor() ERC20("Failing Token", "FAIL") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTransferFailure(bool shouldFail) external {
        transferFails = shouldFail;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (transferFails) {
            return false;
        }

        return super.transfer(to, amount);
    }
}

contract FailingTransferFromToken is ERC20 {
    constructor() ERC20("Failing TransferFrom Token", "FAIL_FROM") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}

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
