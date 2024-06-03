// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { UFixed6 } from "@equilibria/root/number/types/UFixed6.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { IReserveBase } from "../IReserveBase.sol";

/// @title ICompoundV3USDCReserve
/// @notice Interface for the CompoundV3USDCReserve
interface ICompoundV3USDCReserve is IReserveBase {
    function usdc() external view returns (Token6);
    function compound() external view returns (ICompoundV3Market);
    function initialize() external;
}

interface ICompoundV3Market {
    function supply(Token6 asset, UFixed6 amount) external;
    function withdraw(Token6 asset, UFixed6 amount) external;
    function balanceOf(address account) external view returns (UFixed6);
}