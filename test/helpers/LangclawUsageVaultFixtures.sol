// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LangclawUsageVault} from "../../src/LangclawUsageVault.sol";

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

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("Fee-on-Transfer Token", "FEE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, _msgSender(), amount);

        uint256 fee = amount / 10;
        _transfer(from, to, amount - fee);
        _burn(from, fee);

        return true;
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
