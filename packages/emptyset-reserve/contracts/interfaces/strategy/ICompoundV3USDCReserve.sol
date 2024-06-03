// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { UFixed6 } from "@equilibria/root/number/types/UFixed6.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { IReserveBase } from "../IReserveBase.sol";

/// @title ICompoundV3USDCReserve
/// @notice Interface for the CompoundV3USDCReserve
interface ICompoundV3USDCReserve is IReserveBase {
    /// @dev The base token of the supplied market is not USDC
    /// sig: 0x9f071dd0
    error CompoundV3USDCReserveInvalidMarketError();

    function usdc() external view returns (Token6);
    function compound() external view returns (ICompoundV3Market);
    function initialize() external;
}

interface ICompoundV3Market {
    function baseToken() external view returns (Token6);
    function supply(Token6 asset, UFixed6 amount) external;
    function withdraw(Token6 asset, UFixed6 amount) external;
    function balanceOf(address account) external view returns (UFixed6);
}