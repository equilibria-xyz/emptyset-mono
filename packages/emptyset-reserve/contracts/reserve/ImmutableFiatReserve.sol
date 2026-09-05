// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.35;

import { ERC1967Upgrade } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { OwnableStub } from "../utils/OwnableStub.sol";
import { NoopFiatReserve } from "./NoopFiatReserve.sol";

/// @title ImmutableFiatReserve
/// @notice An ownerless fiat reserve that supports DSU redemption but permanently disables DSU minting
contract ImmutableFiatReserve is NoopFiatReserve, ERC1967Upgrade {
    /// @notice Constructs a new ImmutableFiatReserve
    /// @param dsu_ The DSU token
    /// @param fiat_ The fiat token
    constructor(Token18 dsu_, Token6 fiat_) NoopFiatReserve(dsu_, fiat_) { }

    /// @notice Finalizes the reserve, permanently disabling future upgrades
    function finalize() external {
        if (_getAdmin().codehash == keccak256(type(OwnableStub).runtimeCode)) return;
        _changeAdmin(address(new OwnableStub()));
    }

    /// @inheritdoc NoopFiatReserve
    function mint(UFixed18) external pure override returns (UFixed18) {
        revert NotImplementedError();
    }
}
