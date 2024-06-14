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

    /// @notice Returns the DSU stablecoin that the reserve has authorit to issue
    /// @return The DSU stablecoin
    function dsu() external view returns (Token18);

    /// @notice Returns the quantity of assets, both allocated and unallocated, held by the reserve
    /// @return The quantity of assets held by the reserve
    function assets() external view returns (UFixed18);

    /// @notice Returns the price in the underlying assets to mint a single DSU
    /// @dev Underlying assets amounts are scaled to 18 decimal places
    /// @return The price to mint a single DSU
    function mintPrice() external view returns (UFixed18);

    /// @notice Returns the price in DSU to redeem a single underlying asset
    /// @dev Underlying assets amounts are scaled to 18 decimal places
    /// @return The price to mint a single DSU
    function redeemPrice() external view returns (UFixed18);

    /// @notice Mints new DSU by wrapping the underlying asset
    /// @param amount The quantity of the underlying assets to wrap
    /// @return mintAmount The quantity of DSU minted
    function mint(UFixed18 amount) external returns (UFixed18 mintAmount);

    /// @notice Redeems underlying assets by burning DSU
    /// @param amount The quantity of DSU to burn
    /// @return redemptionAmount The quantity of underlying assets redeemed
    function redeem(UFixed18 amount) external returns (UFixed18 redemptionAmount);

    /// @notice Issues new DSU
    /// @dev Can only be called by the owner
    ///      The reserve must have sufficient assets to issue the DSU
    /// @param amount The quantity of DSU to issue
    function issue(UFixed18 amount) external;
}
