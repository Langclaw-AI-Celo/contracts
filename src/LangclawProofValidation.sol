// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library LangclawProofValidation {
    function isEmpty(string calldata value) internal pure returns (bool) {
        return bytes(value).length == 0;
    }

    function isEmpty(bytes32 value) internal pure returns (bool) {
        return value == bytes32(0);
    }
}
