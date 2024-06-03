// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { IReserveBase } from "../IReserveBase.sol";

/// @title INoopFiatReserve
/// @notice Interface for the NoopFiatReserve
interface INoopFiatReserve is IReserveBase {
    function fiat() external view returns (Token6);
    function initialize() external;
}
