// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library LangclawProofValidation {
    function isBlank(string calldata value) internal pure returns (bool) {
        bytes calldata characters = bytes(value);

        for (uint256 index; index < characters.length; ++index) {
            bytes1 character = characters[index];
            bool isWhitespace = character == 0x20 || (character >= 0x09 && character <= 0x0d);

            if (!isWhitespace) {
                return false;
            }
        }

        return true;
    }

    function isEmpty(bytes32 value) internal pure returns (bool) {
        return value == bytes32(0);
    }
}
