// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { UFixed18, UFixed18Lib } from "@equilibria/root/number/types/UFixed18.sol";
import { Ownable } from "@equilibria/root/attribute/Ownable.sol";

abstract contract PartialAllocation is Ownable {
    error PartialAllocationNotCoordinatorError();
    error PartialAllocationInvalidAllocationError();

    event CoorindatorUpdated(address newCoordinator);
    event AllocationUpdated(UFixed18 newAllocation);

    address public coordinator;
    UFixed18 public allocation;

    function __PartialAllocation__initialize() internal onlyInitializer {
        if (owner() == address(0)) __Ownable__initialize();
    }

    function updateCoordinator(address newCoordinator) external onlyOwner {
        coordinator = newCoordinator;
        emit CoorindatorUpdated(newCoordinator);
    }

    function updateAllocation(UFixed18 newAllocation) external {
        if (msg.sender != coordinator && msg.sender != owner()) revert PartialAllocationNotCoordinatorError();
        if (newAllocation.gt(UFixed18Lib.ONE)) revert PartialAllocationInvalidAllocationError();

        allocation = newAllocation;
        emit AllocationUpdated(newAllocation);
    }
}
