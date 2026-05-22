// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LangclawUsageVault is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event Deposit(address indexed payer, uint256 amount, bytes32 indexed depositReference);
    event Withdrawal(address indexed payer, uint256 amount);
    event VaultPaused(address indexed owner);
    event VaultUnpaused(address indexed owner);
    event WithdrawalAuthorized(address indexed payer, uint256 amount, bytes32 indexed withdrawalId);
    event WithdrawalAuthorityUpdated(address indexed previousAuthority, address indexed newAuthority);

    error ZeroAmount();
    error InvalidPayer();
    error InvalidWithdrawalAuthority();
    error UnauthorizedWithdrawal(address payer, uint256 requested, uint256 authorized);
    error WithdrawalIdAlreadyUsed(bytes32 withdrawalId);
    error InsufficientVaultBalance(uint256 requestedTotalAuthorization, uint256 availableBalance);
    error NativeTransferFailed(address recipient, uint256 amount);
    error OwnershipRenounceDisabled();
    error UnsupportedNativeDeposit();
    error UnsupportedTokenDeposit();

    address public immutable depositToken;
    address public withdrawalAuthority;
    uint256 public totalAuthorizedWithdrawals;
    uint256 public totalWithdrawn;

    mapping(address payer => uint256 amount) public authorizedWithdrawals;
    mapping(bytes32 withdrawalId => bool used) public usedWithdrawalIds;

    modifier onlyWithdrawalAuthority() {
        if (msg.sender != withdrawalAuthority) {
            revert InvalidWithdrawalAuthority();
        }
        _;
    }

    constructor(address initialOwner, address initialWithdrawalAuthority, address initialDepositToken) Ownable(initialOwner) {
        if (initialWithdrawalAuthority == address(0)) {
            revert InvalidWithdrawalAuthority();
        }

        depositToken = initialDepositToken;
        withdrawalAuthority = initialWithdrawalAuthority;
        emit WithdrawalAuthorityUpdated(address(0), initialWithdrawalAuthority);
    }

    receive() external payable whenNotPaused {
        if (depositToken != address(0)) {
            revert UnsupportedNativeDeposit();
        }

        _depositNative(bytes32(0));
    }

    function deposit(bytes32 depositReference) external payable whenNotPaused {
        if (depositToken != address(0)) {
            revert UnsupportedNativeDeposit();
        }

        _depositNative(depositReference);
    }

    function depositTokenAmount(bytes32 depositReference, uint256 amount) external whenNotPaused nonReentrant {
        if (depositToken == address(0)) {
            revert UnsupportedTokenDeposit();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        IERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount, depositReference);
    }

    function authorizeWithdrawal(address payer, uint256 amount, bytes32 withdrawalId) external onlyWithdrawalAuthority {
        if (payer == address(0)) {
            revert InvalidPayer();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (usedWithdrawalIds[withdrawalId]) {
            revert WithdrawalIdAlreadyUsed(withdrawalId);
        }

        uint256 nextTotalAuthorization = totalAuthorizedWithdrawals + amount;
        uint256 availableBalance = vaultBalance();
        if (nextTotalAuthorization > availableBalance) {
            revert InsufficientVaultBalance(nextTotalAuthorization, availableBalance);
        }

        usedWithdrawalIds[withdrawalId] = true;
        authorizedWithdrawals[payer] += amount;
        totalAuthorizedWithdrawals = nextTotalAuthorization;

        emit WithdrawalAuthorized(payer, amount, withdrawalId);
    }

    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 authorizedAmount = authorizedWithdrawals[msg.sender];
        if (amount > authorizedAmount) {
            revert UnauthorizedWithdrawal(msg.sender, amount, authorizedAmount);
        }

        unchecked {
            authorizedWithdrawals[msg.sender] = authorizedAmount - amount;
            totalAuthorizedWithdrawals -= amount;
            totalWithdrawn += amount;
        }

        if (depositToken == address(0)) {
            (bool success,) = msg.sender.call{value: amount}("");
            if (!success) {
                revert NativeTransferFailed(msg.sender, amount);
            }
        } else {
            IERC20(depositToken).safeTransfer(msg.sender, amount);
        }

        emit Withdrawal(msg.sender, amount);
    }

    function vaultBalance() public view returns (uint256) {
        if (depositToken == address(0)) {
            return address(this).balance;
        }

        return IERC20(depositToken).balanceOf(address(this));
    }

    function pause() external onlyOwner {
        _pause();
        emit VaultPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit VaultUnpaused(msg.sender);
    }

    function setWithdrawalAuthority(address newWithdrawalAuthority) external onlyOwner {
        if (newWithdrawalAuthority == address(0)) {
            revert InvalidWithdrawalAuthority();
        }

        address previousWithdrawalAuthority = withdrawalAuthority;
        withdrawalAuthority = newWithdrawalAuthority;

        emit WithdrawalAuthorityUpdated(previousWithdrawalAuthority, newWithdrawalAuthority);
    }

    function renounceOwnership() public view override onlyOwner {
        revert OwnershipRenounceDisabled();
    }

    function _depositNative(bytes32 depositReference) private {
        if (msg.value == 0) {
            revert ZeroAmount();
        }

        emit Deposit(msg.sender, msg.value, depositReference);
    }
}
