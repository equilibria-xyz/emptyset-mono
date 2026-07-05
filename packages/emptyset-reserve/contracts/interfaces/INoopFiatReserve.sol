// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { IReserve } from "./IReserve.sol";

/// @title INoopFiatReserve
/// @notice Interface for the NoopFiatReserve
interface INoopFiatReserve is IReserve {
    function fiat() external view returns (Token6);
}
