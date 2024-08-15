// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { ICompoundV3FiatReserve, ICompoundV3Market } from "../../interfaces/strategy/ICompoundV3FiatReserve.sol";
import { ReserveBase } from "../ReserveBase.sol";

/// @title CompoundV3FiatReserve
/// @notice A reserve with the following configuration:
///         - Its underlying asset is a 6-decimal fiat token (ex. USDC, USDT)
///         - Its strategy uses Compound V3 to manage the underlying asset
contract CompoundV3FiatReserve is ICompoundV3FiatReserve, ReserveBase {
    /// @dev The fiat token
    Token6 public immutable fiat;
    /// @dev The Compound V3 contract which supports supplying the fiat token
    ICompoundV3Market public immutable compound;

    /// @notice Constructs a new CompoundV3FiatReserve
    /// @param dsu_ The DSU token
    /// @param fiat_ The fiat token
    /// @param compound_ The Compound V3 contract which supports supplying the fiat token
    constructor(Token18 dsu_, Token6 fiat_, ICompoundV3Market compound_) ReserveBase(dsu_) {
        fiat = fiat_;
        compound = compound_;

        if (!compound.baseToken().eq(fiat_)) revert CompoundV3FiatReserveInvalidMarketError();
    }

    /// @notice Initializes the new CompoundV3FiatReserve
    function initialize() public virtual initializer(2) {
        __ReserveBase__initialize();

        fiat.approve(address(compound));
    }

    /// @inheritdoc ReserveBase
    function _pull(UFixed18 amount) internal override {
        fiat.pull(msg.sender, UFixed6Lib.from(amount, true));
    }

    /// @inheritdoc ReserveBase
    function _push(UFixed18 amount) internal override {
        fiat.push(msg.sender, UFixed6Lib.from(amount));
    }

    /// @inheritdoc ReserveBase
    function _unallocated() internal override view returns (UFixed18) {
        return UFixed18Lib.from(fiat.balanceOf(address(this)));
    }

    /// @inheritdoc ReserveBase
    function _allocated() internal override view returns (UFixed18) {
        return UFixed18Lib.from(compound.balanceOf(address(this)));
    }

    /// @inheritdoc ReserveBase
    function _update(UFixed18 collateral, UFixed18 target) internal override {
        if (collateral.gt(target))
            compound.withdraw(fiat, UFixed6Lib.from(collateral.sub(target)));
        if (target.gt(collateral))
            compound.supply(fiat, UFixed6Lib.from(target.sub(collateral)));
    }
}
