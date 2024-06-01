// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6, UFixed6Lib } from "@equilibria/root/number/types/UFixed6.sol";
import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { ReserveBase } from "../ReserveBase.sol";

contract AaveV3USDCReserve is ReserveBase {
    Token6 public immutable usdc;
    IAavePool public immutable aave;
    Token6 public immutable aToken;

    constructor(Token18 dsu_, Token6 usdc_, IAavePool aave_) ReserveBase(dsu_) {
        usdc = usdc_;
        aave = aave_;
        aToken = Token6.wrap(aave_.getReserveData(Token6.unwrap((usdc_))).aTokenAddress);
    }

    function initialize() public virtual initializer(2) {
        __ReserveBase__initialize();

        usdc.approve(address(aave));
        // TODO: sanity checks on configuration (is there a market?)
    }

    function _pull(UFixed18 amount) internal override {
        usdc.pull(msg.sender, UFixed6Lib.from(amount, true));
    }

    function _push(UFixed18 amount) internal override {
        usdc.push(msg.sender, UFixed6Lib.from(amount));
    }

    function _collateral() internal override view returns (UFixed18) {
        return UFixed18Lib.from(aToken.balanceOf(address(this)));
    }

    function _assets() internal override view returns (UFixed18) {
        return UFixed18Lib.from(usdc.balanceOf(address(this)));
    }

    function _update(UFixed18 collateral, UFixed18 target) internal virtual override {
        if (collateral.gt(target))
            aave.withdraw(usdc, UFixed6Lib.from(collateral.sub(target)), address(this));
        if (target.gt(collateral))
            aave.deposit(usdc, UFixed6Lib.from(target.sub(collateral)), address(this), 0);
    }
}

interface IAavePool {
    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }

    function deposit(Token6 asset, UFixed6 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(Token6 asset, UFixed6 amount, address to) external;
    function getReserveData(address asset) external view returns (ReserveData memory);
}
