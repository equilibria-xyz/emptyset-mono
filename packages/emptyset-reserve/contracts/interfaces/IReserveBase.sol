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

    /// @notice Returns the address of the reserve's coordinator, who has the ability to update the reserve's allocation
    /// @return The reserve's coordinator
    function coordinator() external view returns (address);

    /// @notice Returns the allocation percentage of the reserve's assets to the underlying strategy
    /// @return The reserve's allocation
    function allocation() external view returns (UFixed18);

    /// @notice Update the reserve's coordinator to `newCoordinator`
    /// @dev Can only be called by the owner
    /// @param newCoordinator The new coordinator of the reserve
    function updateCoordinator(address newCoordinator) external;

    /// @notice Update the reserve's allocation to `newAllocation`
    /// @dev Can only be called by the coordinator
    /// @param newAllocation The new allocation of the reserve
    function updateAllocation(UFixed18 newAllocation) external;
}
