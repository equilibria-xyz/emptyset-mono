// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @dev An 18-decimal ERC20Votes governance token for exercising the Claim2Step delegation flow.
contract MockGovToken is ERC20Votes {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC20Permit(name_) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
