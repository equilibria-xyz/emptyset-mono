// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Token6 } from "@equilibria/root/token/types/Token6.sol";
import { UFixed6 } from "@equilibria/root/number/types/UFixed6.sol";
import { ICompoundV3Market } from "@emptyset/reserve/contracts/interfaces/strategy/ICompoundV3FiatReserve.sol";

contract MockCompoundV3Market is ICompoundV3Market {
    using SafeERC20 for IERC20;

    Token6 private immutable _baseToken;
    mapping(address => uint256) private _balances;

    constructor(Token6 baseToken_) {
        _baseToken = baseToken_;
    }

    function baseToken() external view returns (Token6) {
        return _baseToken;
    }

    function supply(Token6 asset, UFixed6 amount) external {
        require(Token6.unwrap(asset) == Token6.unwrap(_baseToken), "invalid asset");

        IERC20(Token6.unwrap(_baseToken)).safeTransferFrom(msg.sender, address(this), UFixed6.unwrap(amount));
        _balances[msg.sender] += UFixed6.unwrap(amount);
    }

    function withdraw(Token6 asset, UFixed6 amount) external {
        require(Token6.unwrap(asset) == Token6.unwrap(_baseToken), "invalid asset");

        _balances[msg.sender] -= UFixed6.unwrap(amount);
        IERC20(Token6.unwrap(_baseToken)).safeTransfer(msg.sender, UFixed6.unwrap(amount));
    }

    function balanceOf(address account) external view returns (UFixed6) {
        return UFixed6.wrap(_balances[account]);
    }
}
