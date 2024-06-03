// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { UFixed18 } from "@equilibria/root/number/types/UFixed18.sol";
import { Token18 } from "@equilibria/root/token/types/Token18.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";


/// @title IReserve
/// @notice Interface for the protocol reserve
interface IReserve {
    /// @dev The reserve has decreased its collateralization ratio during the coarse of the state execution
    /// sig: 0x34d1fc21
    error ReserveBaseInsufficientAssetsError();

    /// @dev `account` has minted `mintAmount` DSU for `costAmount` underlying assets
    event Mint(address indexed account, UFixed18 mintAmount, UFixed18 costAmount);

    /// @dev `account` has redeemed `redeemAmount` DSU for `costAmount` underlying assets
    event Redeem(address indexed account, UFixed18 costAmount, UFixed18 redeemAmount);

    /// @dev `account` has issued `amount` DSU
    event Issue(address indexed account, UFixed18 amount);

    function dsu() external view returns (Token18);
    function assets() external view returns (UFixed18);
    function mintPrice() external view returns (UFixed18);
    function redeemPrice() external view returns (UFixed18);
    function mint(UFixed18 amount) external returns (UFixed18 mintAmount);
    function redeem(UFixed18 amount) external returns (UFixed18 redemptionAmount);
    function issue(UFixed18 amount) external;
}
