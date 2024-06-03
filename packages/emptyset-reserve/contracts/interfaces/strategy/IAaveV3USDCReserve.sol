// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { UFixed6 } from "@equilibria/root/number/types/UFixed6.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { IReserveBase } from "../IReserveBase.sol";

/// @title IAaveV3USDCReserve
/// @notice Interface for the AaveV3USDCReserve
interface IAaveV3USDCReserve is IReserveBase {
    function usdc() external view returns (Token6);
    function aave() external view returns (IAaveV3Pool);
    function aToken() external view returns (Token6);
    function initialize() external;
}

interface IAaveV3Pool {
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
