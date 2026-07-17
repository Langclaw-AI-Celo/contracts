// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

    function test_OnlyOwnerCanPause() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));

        vm.prank(stranger);
        vault.pause();
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

    function test_AuthorizeWithdrawalRejectsReplayId() public {
        bytes32 withdrawalId = keccak256("withdrawal-id");

        _depositFrom(payer, 2 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);

        vm.expectRevert(abi.encodeWithSelector(LangclawUsageVault.WithdrawalIdAlreadyUsed.selector, withdrawalId));

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, withdrawalId);
    }

    function test_AuthorizeWithdrawalCannotExceedVaultBalance() public {
        _depositFrom(payer, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(LangclawUsageVault.InsufficientVaultBalance.selector, 1 ether + 1 wei, 1 ether)
        );

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether + 1 wei, keccak256("withdrawal-too-large"));
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

    function test_WithdrawalCannotExceedAllowance() public {
        _depositFrom(payer, 3 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("withdrawal-partial"));

        vm.expectRevert(
            abi.encodeWithSelector(LangclawUsageVault.UnauthorizedWithdrawal.selector, payer, 1 ether + 1 wei, 1 ether)
        );

        vm.prank(payer);
        vault.withdraw(1 ether + 1 wei);
    }

    function test_PauseBlocksWithdrawal() public {
        _depositFrom(payer, 3 ether);

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, 1 ether, keccak256("withdrawal-paused"));

        vm.prank(owner);
        vault.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);

        vm.prank(payer);
        vault.withdraw(1 ether);
    }

    function test_OwnerCanRotateWithdrawalAuthority() public {
        address newAuthority = makeAddr("newAuthority");

        vm.expectEmit(true, true, false, true, address(vault));
        emit WithdrawalAuthorityUpdated(withdrawalAuthority, newAuthority);

        vm.prank(owner);
        vault.setWithdrawalAuthority(newAuthority);

        assertEq(vault.withdrawalAuthority(), newAuthority);
    }

    function test_RevertInvalidWithdrawalAuthorityRotation() public {
        vm.expectRevert(LangclawUsageVault.InvalidWithdrawalAuthority.selector);

        vm.prank(owner);
        vault.setWithdrawalAuthority(address(0));
    }

    function test_RenounceOwnershipIsDisabled() public {
        vm.expectRevert(LangclawUsageVault.OwnershipRenounceDisabled.selector);

        vm.prank(owner);
        vault.renounceOwnership();
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
        assertEq(vault.authorizedWithdrawals(address(receiver)), 0);
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

    function test_TokenAuthorizationCannotExceedTokenBalance() public {
        uint256 depositAmount = 10e6;

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
        vault.authorizeWithdrawal(stranger, depositAmount + 1, keccak256("too-large"));
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

        vm.startPrank(payer);
        usdt.approve(address(vault), depositAmount);
        vault.depositTokenAmount(keccak256("token-before-pause"), depositAmount);
        vm.stopPrank();

        vm.prank(withdrawalAuthority);
        vault.authorizeWithdrawal(payer, withdrawalAmount, keccak256("token-paused-withdrawal"));

        vm.prank(owner);
        vault.pause();

        vm.startPrank(payer);
        usdt.approve(address(vault), withdrawalAmount);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.depositTokenAmount(keccak256("token-paused-deposit"), withdrawalAmount);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.withdraw(withdrawalAmount);
        vm.stopPrank();
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

    function invariant_TotalWithdrawnNeverExceedsBackendAuthorization() public view {
        assertLe(vault.totalWithdrawn(), handler.totalAuthorizedAmount());
    }

    function invariant_VaultBalancePlusWithdrawalsEqualsDeposits() public view {
        assertEq(address(vault).balance + vault.totalWithdrawn(), handler.totalDeposited());
    }
}
