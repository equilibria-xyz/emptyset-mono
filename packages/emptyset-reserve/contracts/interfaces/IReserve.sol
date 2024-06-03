// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@equilibria/root/number/types/UFixed18.sol";
import "@equilibria/root/token/types/Token18.sol";
import "@equilibria/root/token/types/Token6.sol";

/**
 * @title IReserve
 * @notice Interface for the protocol reserve
 */
interface IReserve {
    event Mint(address indexed account, UFixed18 mintAmount, UFixed18 costAmount);
    event Redeem(address indexed account, UFixed18 costAmount, UFixed18 redeemAmount);
    event Issue(address indexed account, UFixed18 amount);

    function dsu() external view returns (Token18);
    function assets() external view returns (UFixed18);
    function mintPrice() external view returns (UFixed18);
    function redeemPrice() external view returns (UFixed18);
    function mint(UFixed18 amount) external returns (UFixed18 mintAmount);
    function redeem(UFixed18 amount) external returns (UFixed18 redemptionAmount);
    function issue(UFixed18 amount) external;
}
