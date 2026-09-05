// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.35;

import { Ownable } from "@equilibria/root/attribute/Ownable.sol";

/// @title OwnableStub
/// @notice A terminal owner that may accept ownership but cannot exercise owner-only functionality
contract OwnableStub {
    /// @notice Accepts ownership of an Ownable contract
    /// @param ownable The contract whose ownership to accept
    function acceptOwner(address ownable) external {
        Ownable(ownable).acceptOwner();
    }
}
