// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6, Token6Lib } from "@equilibria/root/token/types/Token6.sol";
import { Fixed6, Fixed6Lib } from "@equilibria/root/number/types/Fixed6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { IAaveV3FiatReserve, IAaveV3Pool } from "../../interfaces/strategy/IAaveV3FiatReserve.sol";
import { ReserveBase } from "../ReserveBase.sol";

/// @title AaveV3FiatReserve
/// @notice A reserve with the following configuration:
///         - Its underlying asset is a 6-decimal fiat token (ex. USDC, USDT)
///         - Its strategy uses Aave V3 to manage the underlying asset
contract AaveV3FiatReserve is IAaveV3FiatReserve, ReserveBase {
    /// @dev The fiat token
    Token6 public immutable fiat;

    /// @dev The Aave pool contract which supports supplying the fiat token
    IAaveV3Pool public immutable aave;

    /// @dev The aToken representing the fiat token in the Aave pool
    Token6 public immutable aToken;

    /// @notice Constructs a new AaveV3FiatReserve
    /// @param dsu_ The DSU token
    /// @param fiat_ The fiat token
    /// @param aave_ The Aave pool contract which supports supplying Fiat
    constructor(Token18 dsu_, Token6 fiat_, IAaveV3Pool aave_) ReserveBase(dsu_) {
        fiat = fiat_;
        aave = aave_;
        aToken = Token6.wrap(aave_.getReserveData(Token6.unwrap((fiat_))).aTokenAddress);

        if (aToken.eq(Token6Lib.ZERO)) revert AaveV3FiatReserveInvalidPoolError();
    }

    /// @notice Initializes the new AaveV3FiatReserve
    function initialize() public virtual initializer(2) {
        __ReserveBase__initialize();

        fiat.approve(address(aave));
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
        return UFixed18Lib.from(aToken.balanceOf(address(this)));
    }

    /// @inheritdoc ReserveBase
    function _update(UFixed18 collateral, UFixed18 target) internal virtual override {
        UFixed6 delta = UFixed6Lib.from(collateral.gt(target) ? collateral.sub(target) : target.sub(collateral));

        // Aave will revert if the amount is zero
        if (delta.isZero()) return;
        if (collateral.gt(target)) aave.withdraw(fiat, delta, address(this));
        if (target.gt(collateral)) aave.deposit(fiat, delta, address(this), 0);
    }
}

