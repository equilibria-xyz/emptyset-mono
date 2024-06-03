// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { ICompoundV3USDCReserve, ICompoundV3Market } from "../../interfaces/strategy/ICompoundV3USDCReserve.sol";
import { ReserveBase } from "../ReserveBase.sol";

/// @title CompoundV3USDCReserve
/// @notice A reserve strategy that uses Compound V3 to manage the underlying asset USDC
contract CompoundV3USDCReserve is ICompoundV3USDCReserve, ReserveBase {
    /// @dev The USDC token
    Token6 public immutable usdc;
    /// @dev The Compound V3 contract which supports supplying USDC
    ICompoundV3Market public immutable compound;

    /// @notice Constructs a new CompoundV3USDCReserve
    /// @param dsu_ The DSU token
    /// @param usdc_ The USDC token
    /// @param compound_ The Compound V3 contract which supports supplying USDC
    constructor(Token18 dsu_, Token6 usdc_, ICompoundV3Market compound_) ReserveBase(dsu_) {
        usdc = usdc_;
        compound = compound_;

        if (!compound.baseToken().eq(usdc)) revert CompoundV3USDCReserveInvalidMarketError();
    }

    /// @notice Initializes the new CompoundV3USDCReserve
    function initialize() public virtual initializer(2) {
        __ReserveBase__initialize();

        usdc.approve(address(compound));
    }

    /// @inheritdoc ReserveBase
    function _pull(UFixed18 amount) internal override {
        usdc.pull(msg.sender, UFixed6Lib.from(amount, true));
    }

    /// @inheritdoc ReserveBase
    function _push(UFixed18 amount) internal override {
        usdc.push(msg.sender, UFixed6Lib.from(amount));
    }

    /// @inheritdoc ReserveBase
    function _unallocated() internal override view returns (UFixed18) {
        return UFixed18Lib.from(usdc.balanceOf(address(this)));
    }

    /// @inheritdoc ReserveBase
    function _allocated() internal override view returns (UFixed18) {
        return UFixed18Lib.from(compound.balanceOf(address(this)));
    }

    /// @inheritdoc ReserveBase
    function _update(UFixed18 collateral, UFixed18 target) internal override {
        if (collateral.gt(target))
            compound.withdraw(usdc, UFixed6Lib.from(collateral.sub(target)));
        if (target.gt(collateral))
            compound.supply(usdc, UFixed6Lib.from(target.sub(collateral)));
    }
}
