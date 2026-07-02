// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6 } from "@equilibria/root/number/types/UFixed6.sol";
import { IAaveV3Pool } from "@emptyset/reserve/contracts/interfaces/strategy/IAaveV3FiatReserve.sol";
import { MockERC20 } from "./MockERC20.sol";

contract MockAaveV3Pool is IAaveV3Pool {
    using SafeERC20 for IERC20;

    Token6 public immutable asset;
    MockERC20 public immutable aToken;

    constructor(Token6 asset_) {
        asset = asset_;
        aToken = new MockERC20("Mock Aave USDC", "aUSDC", 6);
    }

    function deposit(Token6 asset_, UFixed6 amount, address onBehalfOf, uint16) external {
        require(Token6.unwrap(asset_) == Token6.unwrap(asset), "invalid asset");

        IERC20(Token6.unwrap(asset)).safeTransferFrom(msg.sender, address(this), UFixed6.unwrap(amount));
        aToken.mint(onBehalfOf, UFixed6.unwrap(amount));
    }

    function withdraw(Token6 asset_, UFixed6 amount, address to) external {
        require(Token6.unwrap(asset_) == Token6.unwrap(asset), "invalid asset");

        aToken.burn(msg.sender, UFixed6.unwrap(amount));
        IERC20(Token6.unwrap(asset)).safeTransfer(to, UFixed6.unwrap(amount));
    }

    function getReserveData(address asset_) external view returns (ReserveData memory data) {
        if (asset_ == Token6.unwrap(asset)) data.aTokenAddress = address(aToken);
    }
}
