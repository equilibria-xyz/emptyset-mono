// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { IReserve } from "./IReserve.sol";


/// @title IReserveBase
/// @notice Interface for the ReserveBase
interface IReserveBase is IReserve {
    /// @dev The caller is not the coordinator
    /// sig: 0x59186a30
    error ReserveBaseNotCoordinatorError();

    /// @dev The allocation amount is not between 0 and 1 inclusive
    /// sig: 0x4144f277
    error ReserveBaseInvalidAllocationError();

    /// @dev The coordinator of the reserve has been updated to `newCoordinator`
    event CoordinatorUpdated(address newCoordinator);

    /// @dev The allocation of the reserve has been updated to `newAllocation`
    event AllocationUpdated(UFixed18 newAllocation);

    function coordinator() external view returns (address);
    function allocation() external view returns (UFixed18);
    function updateCoordinator(address newCoordinator) external;
    function updateAllocation(UFixed18 newAllocation) external;
}
