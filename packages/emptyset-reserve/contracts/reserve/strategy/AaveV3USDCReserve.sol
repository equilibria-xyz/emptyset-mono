// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { IAaveV3USDCReserve, IAaveV3Pool } from "../../interfaces/strategy/IAaveV3USDCReserve.sol";
import { ReserveBase } from "../ReserveBase.sol";

/// @title AaveV3USDCReserve
/// @notice A reserve strategy that uses Aave V3 to manage the underlying asset USDC
contract AaveV3USDCReserve is ReserveBase {
    /// @dev The USDC token
    Token6 public immutable usdc;

    /// @dev The Aave pool contract which supports supplying USDC
    IAaveV3Pool public immutable aave;

    /// @dev The aToken representing the USDC in the Aave pool
    Token6 public immutable aToken;

    /// @notice Constructs a new AaveV3USDCReserve
    /// @param dsu_ The DSU token
    /// @param usdc_ The USDC token
    /// @param aave_ The Aave pool contract which supports supplying USDC
    constructor(Token18 dsu_, Token6 usdc_, IAaveV3Pool aave_) ReserveBase(dsu_) {
        usdc = usdc_;
        aave = aave_;
        aToken = Token6.wrap(aave_.getReserveData(Token6.unwrap((usdc_))).aTokenAddress);
    }

    /// @notice Initializes the new AaveV3USDCReserve
    function initialize() public virtual initializer(2) {
        __ReserveBase__initialize();

        usdc.approve(address(aave));
        // TODO: sanity checks on configuration (is there a market?)
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
        return UFixed18Lib.from(aToken.balanceOf(address(this)));
    }

    /// @inheritdoc ReserveBase
    function _update(UFixed18 collateral, UFixed18 target) internal virtual override {
        if (collateral.gt(target))
            aave.withdraw(usdc, UFixed6Lib.from(collateral.sub(target)), address(this));
        if (target.gt(collateral))
            aave.deposit(usdc, UFixed6Lib.from(target.sub(collateral)), address(this), 0);
    }
}

