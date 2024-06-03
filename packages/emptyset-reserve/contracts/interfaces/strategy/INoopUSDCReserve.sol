// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { IReserveBase } from "../IReserveBase.sol";

/// @title INoopUSDCReserve
/// @notice Interface for the NoopUSDCReserve
interface INoopUSDCReserve is IReserveBase {
    function usdc() external view returns (Token6);
    function initialize() external;
}
